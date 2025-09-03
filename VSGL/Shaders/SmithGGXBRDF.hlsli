#ifndef SMITH_GGX_BRDF_HLSLI
#define SMITH_GGX_BRDF_HLSLI

#include "GGX.hlsli"

// Microfacet BRDF using the axis-aligned anisotropic GGX NDF with the Smith height-correlated masking-shadowing function.
float SmithGGXBRDF(const float3 wi, const float3 wo, const float2 roughness)
{
	const float3 m = normalize(wi + wo);
	const float ndf = GGX(m, roughness);
	const float si = length(float3(wi.xy * roughness, wi.z));
	const float so = length(float3(wo.xy * roughness, wo.z));

	return min(ndf / (2.0 * (si * abs(wo.z) + so * abs(wi.z))), FLT_MAX);
}

// BRDF*cosine/(unnormalized NDF), where the peak of the unnormalized NDF is 1.
float SmithGGXLobeOverUnnormalizedNDF(const float3 incomingDir, const float3 outgoingDir, const float3 normal, const float roughness2)
{
	const float zi = dot(normal, incomingDir);
	const float zo = dot(normal, outgoingDir);
	const float si = sqrt(roughness2 + (1.0 - roughness2) * (zi * zi));
	const float so = sqrt(roughness2 + (1.0 - roughness2) * (zo * zo));

	return saturate(zo) / max(2.0 * M_PI * roughness2 * (si * abs(zo) + so * abs(zi)), FLT_MIN);
}

// Convert from perceptual roughness to GGX/Beckmann alpha roughness.
// In this implementation, we use the square mapping similar to many game engines.
float PerceptualRoughnessToAlpha(const float perceptualRoughness)
{
	return perceptualRoughness * perceptualRoughness;
}

#endif
