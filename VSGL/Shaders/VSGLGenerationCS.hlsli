#include "VSGLGenerationSetting.h"
#include "SphericalGaussian.hlsli"
#include "SGLight.hlsli"
#include "SmithGGXBRDF.hlsli"
#include "OctahedralMapping.hlsli"
#include "NormalizedDeviceCoordinate.hlsli"

RWStructuredBuffer<SGLight> sgLightBuffer  : register(u0);
Texture2D<float>            depthBuffer    : register(t0);
Texture2D<float2>           normalBuffer   : register(t1);
#if defined(DIFFUSE_VSGL)
Texture2D<float3>           diffuseBuffer  : register(t2);
#elif defined(SPECULAR_VSGL)
Texture2D<float4>           specularBuffer : register(t2);
#else
#error
#endif

cbuffer cb0 : register(b0)
{
	float4x4 g_lightViewProjInv;
	float3   g_lightPosition;
	float3   g_lightAxis;
	float    g_photonPower;
};

cbuffer cb1 : register(b1)
{
	uint g_outputIndex;
};

// Static constants and group shared memory.
// The usage of the group shared memory depends on the minimum wave lane count specified by WAVE_LANE_COUNT_MIN.
// The default setting is WAVE_LANE_COUNT_MIN = 4, since WaveGetLaneCount() >= 4 for Shader Model 6.0.
// Please set WAVE_LANE_COUNT_MIN as large as possible to reduce the size of the group shared memory storage.
// You can obtain the lane count on your hardware by using ID3D12Device::CheckFeatureSupport with D3D12_FEATURE_DATA_D3D12_OPTIONS1.
static const uint WAVE_LANE_COUNT_MIN = 4;
static const uint THREAD_GROUP_SIZE = THREAD_GROUP_WIDTH * THREAD_GROUP_WIDTH;
static const uint SHARED_MEMORY_SIZE = (THREAD_GROUP_SIZE + WAVE_LANE_COUNT_MIN - 1) / WAVE_LANE_COUNT_MIN;
groupshared float4 sharedPositions[SHARED_MEMORY_SIZE];
groupshared float3 sharedAxes[SHARED_MEMORY_SIZE];
groupshared float3 sharedPowers[SHARED_MEMORY_SIZE];

// Parallel summation in a work group.
// The total value is stored in the first element of the group shared memory.
void ThreadGroupSum(const uint groupIndex, const float4 position, const float3 axis, const float3 power)
{
	// Bottom-level reduction. Summation in each wave.
	const float4 positionSum = WaveActiveSum(position);
	const float3 axisSum = WaveActiveSum(axis);
	const float3 powerSum = WaveActiveSum(power);
	const uint laneCount = WaveGetLaneCount();

	// Store the total for each wave into group shared memory.
	if (WaveIsFirstLane())
	{
		const uint index = groupIndex / laneCount;
		sharedPositions[index] = positionSum;
		sharedAxes[index] = axisSum;
		sharedPowers[index] = powerSum;
	}

	GroupMemoryBarrierWithGroupSync();

	// Middle-level reduction. Summation using the group shared memory.
	uint i = (THREAD_GROUP_SIZE / 2) / laneCount;

	for (; i > laneCount; i >>= 1)
	{
		if (groupIndex < i)
		{
			sharedPositions[groupIndex] += sharedPositions[groupIndex + i];
			sharedAxes[groupIndex] += sharedAxes[groupIndex + i];
			sharedPowers[groupIndex] += sharedPowers[groupIndex + i];
		}

		GroupMemoryBarrierWithGroupSync();
	}

	// Top-level reduction. Summation in a wave.
	if (groupIndex < i)
	{
		for (; i > 0; i >>= 1)
		{
			sharedPositions[groupIndex] += sharedPositions[groupIndex + i];
			sharedAxes[groupIndex] += sharedAxes[groupIndex + i];
			sharedPowers[groupIndex] += sharedPowers[groupIndex + i];
		}
	}
}

SGLight GenerateVSGL(const float4 positionAvg, const float3 axisAvg, const float3 power)
{
	// Normalize the axis.
	const float axisLength = length(axisAvg);
	const float3 axis = axisLength != 0.0 ? axisAvg / axisLength : float3(0.0, 0.0, 1.0);

	// Estimate the SG sharpness using the Banerjee's method [2005].
	const float sharpness = min(VMFAxisLengthToSharpness(saturate(axisLength)), SGLIGHT_SHARPNESS_MAX);

	// Approximate the distribution of VPL positions with a Gaussian.
	// Since we assume that the VPLs are distributed on a 2D plane, we divide the total variance by two.
	const float variance = (positionAvg.w - dot(positionAvg.xyz, positionAvg.xyz)) / 2.0;

	// Normalization of the 2D Gaussian distribution and SG.
	const float3 intensity = power * g_photonPower / (2.0 * M_PI * SGIntegral(sharpness)); // Will be divided by variance at the shading pass in our implementation.

	SGLight sgLight;
	sgLight.position = positionAvg.xyz;
	sgLight.variance = variance;
	sgLight.intensity = intensity;
	sgLight.sharpness = sharpness;
	sgLight.axis = -axis;
	sgLight.pad = 0;

	return sgLight;
}

// This shader generates one VSGL from an RSM for each work group.
// Unlike the previous work [Tokuyoshi 2015 "Fast Indirect Illumination Using Two Virtual Spherical Gaussian Lights"],
// this implementation is single pass and does not use global temporary buffers.
// In addition, we employ Banerjee's sharpness estimation, while the previous work used the Toksvig's estimation.
// [Banerjee et al. 2005 "Clustering on the Unit Hypersphere using von Mises-Fisher Distributions"]
// [Toksvig 2005 "Mipmapping Normal Maps"]
// For the detail of the calculation of VSGL parameters, please refer to our paper
// [Tokuyoshi 2015 "Virtual Spherical Gaussian Lights for Real-time Glossy Indirect Illumination"].
[numthreads(THREAD_GROUP_WIDTH, THREAD_GROUP_WIDTH, 1)]
void main(const uint2 threadID : SV_DispatchThreadID, const uint groupIndex : SV_GroupIndex)
{
	float4 positionSum = 0.0;
	float3 axisSum = 0.0;
	float3 powerSum = 0.0;

	// Serial reduction.
	for (uint y = 0; y < RSM_WIDTH; y += THREAD_GROUP_WIDTH)
	{
		for (uint x = 0; x < RSM_WIDTH; x += THREAD_GROUP_WIDTH)
		{
			// Read the RSM.
			const uint2 texelID = threadID + uint2(x, y);
			const float depth = depthBuffer[texelID];
			const float3 normal = DecodeOct(normalBuffer[texelID]);

			// Reconstruct the VPL.
			const float2 texcoord = (texelID + 0.5) / RSM_WIDTH;
			const float3 position = GetWorldPosition(texcoord, depth, g_lightViewProjInv);
			const float3 direction = normalize(position - g_lightPosition);
			const float c = dot(direction, g_lightAxis);
			const float jacobian = c * c * c; // Jacobian for the transformation from the image plane to the directional space.
#if defined(DIFFUSE_VSGL)
			const float3 diffuse = diffuseBuffer[texelID];

			// For the diffuse lobe, we approximate the PDF = cosine/pi into a normalized SG (a.k.a. vMF distribution) whose axis is the surface normal.
			// Then, we convert the vMF into an average of directions [Banerjee et al. 2005].
			const float3 axis = normal;
			const float axisLength = 0.5; // Average axis length for the cut cosine.
			const float3 power = diffuse * jacobian;
#elif defined(SPECULAR_VSGL)
			const float4 specular = specularBuffer[texelID];
			const float roughness = PerceptualRoughnessToAlpha(specular.w);
			const float roughness2 = roughness * roughness;

			// Tangent frame assuming an isotropic roughness.
			// TODO: Use the same tangent frame as lighting to support ansiotropic roughness.
			const float3x3 tangentFrame = BuildONBDuff(normal);

			// We approximate the normalized specular lobe into a normalized SG (a.k.a. vMF distribution).
			// Then, we convert the vMF into an average of directions [Banerjee et al. 2005].
			// If you prefer the performance more than the quality, you can use the Toksvig's method [2005] instead of the Banerjee et al.'s method.
			const float3 wi = mul(tangentFrame, -direction);
			const SGLobe sg = SGReflectionLobe(wi, roughness2);
			const float3 axis = mul(sg.axis, tangentFrame);
			const float axisLength = VMFSharpnessToAxisLength(sg.sharpness);
			const float3 power = specular.xyz * jacobian;
#else
#error
#endif
			// Position and axis are weighted by the power to compute the weighted average.
			const float weight = power.x + power.y + power.z;
			positionSum += float4(position, dot(position, position)) * weight;
			axisSum += axis * (axisLength * weight);
			powerSum += power;
		}
	}

	// Parallel summation in the work group.
	// The total value is stored in the first element of the local shared memory.
	ThreadGroupSum(groupIndex, positionSum, axisSum, powerSum);

	// Only the first thread in the work group outputs a VSGL.
	if (groupIndex == 0)
	{
		const float4 positionSum = sharedPositions[0];
		const float3 axisSum = sharedAxes[0];
		const float3 powerSum = sharedPowers[0];
		const float weightSum = max(powerSum.x + powerSum.y + powerSum.z, FLT_MIN);

		sgLightBuffer[g_outputIndex] = GenerateVSGL(positionSum / weightSum, axisSum / weightSum, powerSum);
	}
}
