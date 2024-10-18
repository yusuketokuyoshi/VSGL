#ifndef SMITH_GGX_BRDF_HLSLI
#define SMITH_GGX_BRDF_HLSLI

#include "GGX.hlsli"

// Microfacet BRDF using the isotropic GGX NDF with the Smith height-correlated masking-shadowing function.
float SmithGGXBRDF(const float3 incomingDir, const float3 outgoingDir, const float3 normal, const float roughness2)
{
	const float3 halfvec = normalize(incomingDir + outgoingDir);
	const float ndf = GGX(dot(normal, halfvec), roughness2);
	const float zi = abs(dot(normal, incomingDir));
	const float zo = abs(dot(normal, outgoingDir));
	const float si = sqrt(roughness2 + (1.0 - roughness2) * (zi * zi));
	const float so = sqrt(roughness2 + (1.0 - roughness2) * (zo * zo));

	return min(ndf / (2.0 * (si * zo + so * zi)), FLT_MAX);
}

// BRDF*dot(o,n)/PDF for VNDF importance sampling, where PDF = D/(4*(projected area)).
float SmithGGXLobeOverPDF(const float3 incomingDir, const float3 outgoingDir, const float3 normal, const float roughness2)
{
	const float zi = dot(normal, incomingDir);
	const float zo = dot(normal, outgoingDir);
	const float si = sqrt(roughness2 + (1.0 - roughness2) * (zi * zi));
	const float so = sqrt(roughness2 + (1.0 - roughness2) * (zo * zo));

	return saturate(zo) * (si + zi) / max(si * abs(zo) + so * abs(zi), FLT_MIN);
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
