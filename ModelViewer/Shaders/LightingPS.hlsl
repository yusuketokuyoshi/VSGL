#include "NormalMapUtility.hlsli"
#include "NormalizedDeviceCoordinate.hlsli"
#include "NDFFiltering.hlsli"
#include "SmithGGXBRDF.hlsli"
#include "SGLight.hlsli"
#if defined(PREVIOUS_SG_LIGHTING)
#include "AnisotropicSphericalGaussian.hlsli"
#else
#include "SphericalGaussian.hlsli"
#endif

Texture2D<float3>      diffuseMap     : register(t0);
Texture2D<float4>      specularMap    : register(t1);
Texture2D<float2>      normalMap      : register(t3);
Texture2D<float>       shadowMap      : register(t4);
SamplerState           textureSampler : register(s0);
SamplerComparisonState shadowSampler  : register(s1);

cbuffer cb0 : register(b0)
{
	float4x4 g_lightViewProj;
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
	float4 pos : SV_Position;
	float3 wpos : POSITION1;
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
// The previous implementation (that can be enabled by "PREVIOUS_SG_LIGHTING") used ASGs [Xu et al. 2013].
// The current implementation uses a new SG lighting method based on NDF filtering.
// [Tokuyoshi et al. 2024 "Hierarchical Light Sampling with Accurate Spherical Gaussian Lighting"]
float3 SGLighting(const float3 viewDir, const float3x3 tangentFrame, const float3 position, const float3 normal, const float3 diffuse, const float3 specular, const float2 roughness)
{
#if defined(PREVIOUS_SG_LIGHTING)
	const ASGLobe specularLobe = ASGReflectionLobe(viewDir, normal, roughness.x * roughness.y); // Assume roughness.x == roughness.y
	const float3 reflecVec = specularLobe.z * ASGSharpnessToSGSharpness(specularLobe.sharpness);
#else
	// Convert the roughness parameter from slope space to the orthographically projected space.
	// [Tokuyoshi and Kaplanyan 2021 "Stable Geometric Specular Antialiasing with Projected-Space NDF Filtering", Eq. 4]
	const float2 roughness2 = roughness * roughness;
	const float2 projRoughness2 = roughness2 / max(1.0 - roughness2, FLT_MIN);

	// Compute the Jacobian matrix J for the transformation between halfvetors and reflection vectors at halfvector = normal.
	// TODO: Investigate a more dominant halfvector for rough surfaces than the normal.
	const float3 wi = mul(tangentFrame, viewDir);
	const float vlen = length(wi.xy);
	const float2 v = (vlen != 0.0) ? (wi.xy / vlen) : float2(1.0, 0.0);
	const float2x2 jacobianMat = mul(float2x2(v.x, -v.y, v.y, v.x), float2x2(0.5, 0.0, 0.0, 0.5 / wi.z)); // Omit abs() unlike the paper since it doesn't affect JJ^T.

	// Compute JJ^T for NDF filtering.
	const float2x2 jjMat = mul(jacobianMat, transpose(jacobianMat));

	// Compute the determinant of JJ^T without catastrophic cancellation.
	const float detJJ4 = 1.0 / (4.0 * wi.z * wi.z); // = 4 * determiant(JJ^T).

	// Preprocess for the lobe visibility.
	// Approximate the reflection lobe with an SG whose axis is the perfect specular reflection vector.
	// We use a conservative SG sharpness to filter the visibility as mentioned in the last paragraph "Filtered Visibility" of Section 5.2 of the paper.
	// [Tokuyoshi et al. 2024 "Hierarchical Light Sampling with Accurate Spherical Gaussian Lighting"]
	// TODO: Investigate a more dominant reflection vector for rough surfaces than the perfect specular reflection vector.
	const float roughnessMax2 = max(roughness2.x, roughness2.y);
	const float reflecSharpness = (1.0 - roughnessMax2) / max(2.0f * roughnessMax2, FLT_MIN);
	const float3 reflecVec = reflect(-viewDir, normal) * reflecSharpness;
#endif

	float3 result = 0.0;

	[unroll]
	for (uint i = 0; i < SG_LIGHT_COUNT; ++i)
	{
		// Load an SG light.
		const SGLight sgLight = sgLightBuffer[i];
		const float3 lightVec = sgLight.position - position;
		const float squaredDistance = dot(lightVec, lightVec);
		const float3 lightDir = lightVec * rsqrt(squaredDistance);

		// Clamp the variance for the numerical stability.
		const float VARIANCE_THRESHOLD = 0x1.0p-31;
		const float variance = max(sgLight.variance, VARIANCE_THRESHOLD * squaredDistance);

		// Compute the maximum emissive radiance of the SG light.
		// (maximum radiant intensity)/(2*pi*variance) where (maximum radiant intensity)/(2*pi) is given by sgLight.intensity.
		// This value can be precomputed in the SG light generation if we don't clamp the variance.
		const float3 emissive = sgLight.intensity / variance;

		// Compute SG sharpness for a light distribution viewed from the shading point.
		const float lightSharpness = squaredDistance / variance;

		// Light lobe given by the product of the light distribution viewed from the shading point and the directional distribution of the SG light.
		const SGLobe lightLobe = SGProduct(sgLight.axis, sgLight.sharpness, lightDir, lightSharpness);

#if defined(PREVIOUS_SG_LIGHTING)
		// Diffuse lighting: the product integral of the diffuse lobe and light lobe.
		// The coefficient of the diffuse lobe is the BRDF i.e. diffuse/pi for the Lambert model.
		const float diffuseIllumination = SGClampedCosineProductIntegralOverPi2022(lightLobe, normal);

		// Specular lighting: the product integral of the specular lobe and light lobe.
		// Since we approximate an unnormalized NDF (whose peak = 1) into a specular ASG lobe, the coefficient of the specular ASG lobe is given as follows:
		// coefficient = BRDF*cosine/(unnormalized NDF).
		// We approximate this coefficient function with the value at the dominant direction.
		// The dominant direction is given by the product of the specular lobe and light lobe in SG basis.
		const float3 dominantDir = normalize(reflecVec + lightLobe.axis * lightLobe.sharpness); // Axis of the SG product lobe.
		const float coefficient = SmithGGXLobeOverUnnormalizedNDF(viewDir, dominantDir, normal, roughness.x * roughness.y); // Fresnel = 1 in this implementation.
		const float specularIllumination = coefficient * ASGProductIntegral(specularLobe, lightLobe);
#else
		// Diffuse SG lighting.
		// [Tokuyoshi et al. 2024 "Hierarchical Light Sampling with Accurate Spherical Gaussian Lighting", Section 4]
		const float amplitude = exp(lightLobe.logAmplitude);
		const float cosine = clamp(dot(lightLobe.axis, normal), -1.0, 1.0);
		const float diffuseIllumination = amplitude * SGClampedCosineProductIntegralOverPi2024(cosine, lightLobe.sharpness);

		// Glossy SG lighting.
		// [Tokuyoshi et al. 2024 "Hierarchical Light Sampling with Accurate Spherical Gaussian Lighting", Section 5]
		const float3 prodVec = reflecVec + lightLobe.axis * lightLobe.sharpness; // Axis of the SG product lobe.
		const float prodSharpness = length(prodVec);
		const float3 prodDir = prodVec / prodSharpness;
		const float lightLobeVariance = 1.0 / lightLobe.sharpness;
		const float2x2 filteredProjRoughnessMat = float2x2(projRoughness2.x, 0.0, 0.0, projRoughness2.y) + 2.0 * lightLobeVariance * jjMat;

		// Compute the determinant of filteredProjRoughnessMat in a numerically stable manner.
		// See the supplementary document (Section 5.2) of the paper for the derivation.
		const float det = projRoughness2.x * projRoughness2.y + 2.0 * lightLobeVariance * (projRoughness2.x * jjMat._11 + projRoughness2.y * jjMat._22) + lightLobeVariance * lightLobeVariance * detJJ4;

		// NDF filtering in a numerically stable manner.
		// See the supplementary document (Section 5.2) of the paper for the derivation.
		const float tr = filteredProjRoughnessMat._11 + filteredProjRoughnessMat._22;
		const float2x2 filteredRoughnessMat = select(isfinite(1.0 + tr + det), min(filteredProjRoughnessMat + float2x2(det, 0.0, 0.0, det), FLT_MAX) / (1.0 + tr + det), float2x2(min(filteredProjRoughnessMat._11, FLT_MAX) / min(filteredProjRoughnessMat._11 + 1.0, FLT_MAX), 0.0, 0.0, min(filteredProjRoughnessMat._22, FLT_MAX) / min(filteredProjRoughnessMat._22 + 1.0, FLT_MAX)));

		// Evaluate the filtered reflection lobe.
		const float3 halfvecUnormalized = wi + mul(tangentFrame, lightLobe.axis);
		const float3 halfvec = halfvecUnormalized / max(length(halfvecUnormalized), FLT_MIN);
		const float lobe = SGGXReflectionPDF(wi, halfvec, filteredRoughnessMat);

		// Visibility of the SG light in the upper hemisphere.
		const float visibility = VMFHemisphericalIntegral(dot(prodDir, normal), prodSharpness);

		// Eq. 12 of the paper.
		const float specularIllumination = amplitude * visibility * lobe * SGIntegral(lightLobe.sharpness);
#endif

		// Finally, we multiply the common SG-light coefficient.
		result += emissive * (diffuse * diffuseIllumination + specular * specularIllumination);
	}

	return result;
}

[earlydepthstencil]
float3 main(const Input input) : SV_Target
{
#if defined(ALPHA_CUTOUT)
	const float3 baseNormal = normalize(input.isFrontFace ? input.normal : -input.normal);
#else
	const float3 baseNormal = normalize(input.normal);
#endif
	const float3x3 baseTangentFrame = BuildTangentFrame(baseNormal, input.tangent, input.bitangentSign);
	const float3 diffuse = diffuseMap.Sample(textureSampler, input.texcoord);
	const float4 specular = specularMap.Sample(textureSampler, input.texcoord);
	const float3 normalTS = DecodeNormalMap(normalMap.Sample(textureSampler, input.texcoord));
	const float3 normal = mul(normalTS, baseTangentFrame);
	const float3x3 tangentFrame = BuildTangentFrame(normal, input.tangent, input.bitangentSign);
	const float3 viewDir = normalize(g_cameraPosition - input.wpos);
	const float3 wi = mul(tangentFrame, viewDir);
	const float2 roughness = PerceptualRoughnessToAlpha(specular.w);

	// Geometric specular antialiasing with NDF filtering.
	const float2 effectiveRoughness = IsotropicNDFFiltering(ddx(baseNormal), ddy(baseNormal), roughness);

	// Direct illumination.
	const float3 lightVec = g_lightPosition - input.wpos;
	const float lightDistance2 = dot(lightVec, lightVec);
	const float3 lightDir = lightVec * rsqrt(lightDistance2);
	const float3 wo = mul(tangentFrame, lightDir);
	const float3 brdf = diffuse / M_PI + specular.xyz * SmithGGXBRDF(wi, wo, effectiveRoughness); // Fresnel = 1 in this implementation.
	const float3 shadowNDC = NDCTransform(input.wpos, g_lightViewProj);
	const float2 shadowTexcoord = NDCToTexcoord(shadowNDC.xy);
	const float visibility = shadowMap.SampleCmpLevelZero(shadowSampler, shadowTexcoord, saturate(shadowNDC.z));
	const float3 directIllumination = brdf * (g_lightIntensity * visibility * saturate(wo.z) / lightDistance2);

	// Indirect illumination using VSGLs.
	const float3 indirectIllumination = SGLighting(viewDir, tangentFrame, input.wpos, normal, diffuse, specular.xyz, effectiveRoughness);

	return directIllumination + indirectIllumination;
}
