#include "NormalMapUtility.hlsli"
#include "NormalizedDeviceCoordinate.hlsli"
#include "SmithGGXBRDF.hlsli"
#include "AnisotropicSphericalGaussian.hlsli"
#include "SGLight.hlsli"

Texture2D<float3>      diffuseMap     : register(t0);
Texture2D<float4>      specularMap    : register(t1);
Texture2D<float2>      normalMap      : register(t3);
Texture2D<float>       shadowMap      : register(t4);
SamplerState           textureSampler : register(s0);
SamplerComparisonState shadowSampler  : register(s1);

cbuffer cb0 : register(b0)
{
	float4x4 g_lightViewProjection;
	float3   g_cameraPosition;
	float3   g_lightPosition;
	float    g_lightIntensity;
};

static const uint SG_LIGHT_COUNT = 2;

cbuffer cb1 : register(b1)
{
	SGLight sgLightBuffer[SG_LIGHT_COUNT];
};

struct Input
{
	float4 position : SV_Position;
	float3 worldPosition : POSITION1;
	float2 texcoord : TEXCOORD;
	float3 normal : NORMAL;
	float3 tangent : TANGENT;
	nointerpolation float bitangentSign : BITANGENT_SIGN;
#if defined(ALPHA_CUTOUT)
	bool isFrontFace : SV_IsFrontFace;
#endif
};

// Compute lighting from spherical Gaussian (SG) light sources.
// [Tokuyoshi 2015 "Fast Indirect Illumination Using Two Virtual Spherical Gaussian Lights"]
// [Tokuyoshi 2015 "Virtual Spherical Gaussian Lights for Real-Time Glossy Indirect Illumination"]
float3 SGLighting(const float3 viewDir, const float3 position, const float3 normal, const float3 diffuse, const float3 specular, const float squaredRoughness)
{
	const SGLobe diffuseLobe = { normal, SG_CUT_COSINE_SHARPNESS, 0.0 };
	const ASGLobe specularLobe = ASGReflectionLobe(viewDir, normal, squaredRoughness);
	const float3 specularVec = specularLobe.z * ASGSharpnessToSGSharpness(specularLobe.sharpness);
	float3 result = 0.0;

	[unroll]
	for (uint i = 0; i < SG_LIGHT_COUNT; ++i)
	{
		// Load an SG light.
		const SGLight sgLight = sgLightBuffer[i];
		const float3 lightVec = sgLight.position - position;
		const float squaredDistance = dot(lightVec, lightVec);
		const float3 lightDir = lightVec * rsqrt(squaredDistance);

		// Compute SG sharpness for a light distribution viewed from the shading point.
		const float SHARPNESS_MAX = 0x1.0p+28; // We clamp the SG sharpness with SHARPNESS_MAX for the numerical stability.
		const float lightSharpness = min(squaredDistance * sgLight.varianceInv, SHARPNESS_MAX);

		// Light lobe given by the product of the light distribution viewed from the shading point and the directional distribution of the SG light.
		const SGLobe lightLobe = SGProduct(sgLight.axis, sgLight.sharpness, lightDir, lightSharpness);

		// Diffuse lighting: the product integral of the diffuse lobe and light lobe.
		// The coefficient of the diffuse lobe is the BRDF i.e. diffuse/pi for the Lambert model.
#if defined(HSG_CONVOLUTION)
		// Product integral of an SG and clamped cosine alleviates light leaks, though it is more expensive than the product integral of two SGs.
		const float3 diffuseIllumination = diffuse * HSGCosineProductIntegralOverPi(lightLobe, normal);
#else
		// Fast approximation using a product integral of two SG lobes.
		const float3 diffuseIllumination = diffuse * SGApproxProductIntegralOverPi(lightLobe, diffuseLobe);
#endif
		// Specular lighting: the product integral of the specular lobe and light lobe.
		// Since we approximate an unnormalized NDF (whose peak = 1) into a specular ASG lobe, the coefficient of the specular ASG lobe is given as follows:
		// coefficient = BRDF*cosine/(unnormalized NDF).
		// We approximate this coefficient function with the value at the dominant direction.
		// The dominant direction is given by the product of the specular lobe and light lobe in SG basis.
		const float3 dominantDir = normalize(specularVec + lightLobe.axis * lightLobe.sharpness); // Axis of the SG product lobe.
		const float coefficient = SmithGGXLobeOverUnnormalizedNDF(viewDir, dominantDir, normal, squaredRoughness); // Fresnel = 1 in this implementation.
		const float3 specularIllumination = specular * (coefficient * ASGProductIntegral(specularLobe, lightLobe));

		// Finally, we multiply the common SG-light coefficient.
		result += sgLight.coefficient * (diffuseIllumination + specularIllumination);
	}

	return result;
}

[earlydepthstencil]
float3 main(const Input input) : SV_Target
{
#if defined(ALPHA_CUTOUT)
	const float3x3 tangentFrame = BuildTangentFrame(normalize(input.isFrontFace ? input.normal : -input.normal), input.tangent, input.bitangentSign);
#else
	const float3x3 tangentFrame = BuildTangentFrame(normalize(input.normal), input.tangent, input.bitangentSign);
#endif
	const float3 diffuse = diffuseMap.Sample(textureSampler, input.texcoord);
	const float4 specular = specularMap.Sample(textureSampler, input.texcoord);
	const float3 normalTS = DecodeNormalMap(normalMap.Sample(textureSampler, input.texcoord));
	const float3 normal = mul(normalTS, tangentFrame);
	const float3 viewDir = normalize(g_cameraPosition - input.worldPosition);
	const float squaredRoughness = PerceptualRoughnessToSquaredRoughness(specular.w);

	// Direct illumination.
	const float3 lightVec = g_lightPosition - input.worldPosition;
	const float lightSquaredDistance = dot(lightVec, lightVec);
	const float3 lightDir = lightVec * rsqrt(lightSquaredDistance);
	const float3 shadowNDC = NDCTransform(input.worldPosition, g_lightViewProjection);
	const float2 shadowTexcoord = NDCToTexcoord(shadowNDC.xy);
	const float visibility = shadowMap.SampleCmpLevelZero(shadowSampler, shadowTexcoord, saturate(shadowNDC.z));
	const float3 brdf = diffuse / M_PI + specular.xyz * SmithGGXBRDF(viewDir, lightDir, normal, squaredRoughness); // Fresnel = 1 in this implementation.
	const float3 directIllumination = brdf * g_lightIntensity * (visibility * saturate(dot(normal, lightDir)) / lightSquaredDistance);

	// Indirect illumination using VSGLs.
	const float3 indirectIllumination = SGLighting(viewDir, input.worldPosition, normal, diffuse, specular.xyz, squaredRoughness);

	return directIllumination + indirectIllumination;
}
