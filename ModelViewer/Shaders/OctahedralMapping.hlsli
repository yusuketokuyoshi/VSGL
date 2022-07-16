#ifndef OCTAHEDRAL_MAPPING_HLSLI
#define OCTAHEDRAL_MAPPING_HLSLI

#include "Math.hlsli"

float2 EncodeOct(const float3 dir)
{
	// Project the sphere onto the octahedron, and then project onto the x-y plane.
	const float2 s = dir.xy / (abs(dir.x) + abs(dir.y) + abs(dir.z));

	// Reflect the folds of the lower hemisphere over the diagonals.
	return (dir.z < 0.0) ? mulsign(1.0 - abs(s.yx), s) : s;
}

float3 DecodeOct(const float2 p)
{
	const float z = 1.0 - abs(p.x) - abs(p.y);
	const float3 n = { p.xy - mulsign(saturate(-z), p.xy), z };

	return normalize(n);
}

#endif
