#ifndef MICROFACET_BRDF_HLSLI
#define MICROFACET_BRDF_HLSLI

#include "NumericLimits.hlsli"
#include "MathConstants.hlsli"

// Isotropic GGX NDF.
float GGX(const float z, const float squaredRoughness)
{
	const float a = (squaredRoughness - 1.0) * (z * z) + 1.0;

	return (z > 0.0) ? squaredRoughness / (M_PI * (a * a)) : 0.0;
}

// Microfacet BRDF using the isotropic GGX NDF with the Smith height-correlated masking-shadowing function.
float SmithGGXBRDF(const float3 incomingDir, const float3 outgoingDir, const float3 normal, const float squaredRoughness)
{
	const float3 halfvec = normalize(incomingDir + outgoingDir);
	const float  ndf = GGX(dot(normal, halfvec), squaredRoughness);
	const float  zi = abs(dot(normal, incomingDir));
	const float  zo = abs(dot(normal, outgoingDir));
	const float  si = sqrt(squaredRoughness + (1.0 - squaredRoughness) * (zi * zi));
	const float  so = sqrt(squaredRoughness + (1.0 - squaredRoughness) * (zo * zo));

	return min(ndf / (2.0 * (si * zo + so * zi)), FLT_MAX);
}

// BRDF*dot(o,n)/PDF for VNDF importance sampling, where PDF = D/(4*(projected area)).
float SmithGGXLobeOverPDF(const float3 incomingDir, const float3 outgoingDir, const float3 normal, const float squaredRoughness)
{
	const float zi = dot(normal, incomingDir);
	const float zo = dot(normal, outgoingDir);
	const float si = sqrt(squaredRoughness + (1.0 - squaredRoughness) * (zi * zi));
	const float so = sqrt(squaredRoughness + (1.0 - squaredRoughness) * (zo * zo));

	return saturate(zo) * (si + zi) / max(si * abs(zo) + so * abs(zi), FLT_MIN);
}

// BRDF*cosine/(unnormalized NDF), where the peak of the unnormalized NDF is 1.
float SmithGGXLobeOverUnnormalizedNDF(const float3 incomingDir, const float3 outgoingDir, const float3 normal, const float squaredRoughness)
{
	const float zi = dot(normal, incomingDir);
	const float zo = dot(normal, outgoingDir);
	const float si = sqrt(squaredRoughness + (1.0 - squaredRoughness) * (zi * zi));
	const float so = sqrt(squaredRoughness + (1.0 - squaredRoughness) * (zo * zo));

	return saturate(zo) / max(2.0 * M_PI * squaredRoughness * (si * abs(zo) + so * abs(zi)), FLT_MIN);
}

// Convert from perceptual roughness to GGX/Beckmann alpha roughness.
// In this implementation, we use the square mapping similar to many game engines.
float PerceptualRoughnessToSquaredRoughness(const float perceptualRoughness)
{
	const float roughness = perceptualRoughness * perceptualRoughness;
	return roughness * roughness;
}

#endif
