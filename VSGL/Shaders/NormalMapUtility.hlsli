#ifndef NORMAL_MAP_UTILITY_HLSLI
#define NORMAL_MAP_UTILITY_HLSLI

// Reconstruct a unit normal vector from a texel value of two-channel normal maps.
float3 DecodeNormalMap(const float2 n)
{
	return float3(n.x, n.y, sqrt(saturate(1.0 - dot(n, n))));
}

float3x3 BuildTangentFrame(const float3 normal, const float3 tangent, const float bitangentSign = 1.0)
{
	const float3 bitangent = normalize(cross(normal, tangent));
	return float3x3(cross(bitangent, normal), bitangentSign * bitangent, normal);
}

#endif
