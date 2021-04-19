#ifndef NORMALIZED_DEVICE_COORDINATE_HLSLI
#define NORMALIZED_DEVICE_COORDINATE_HLSLI

float2 NDCToTexcoord(const float2 ndc)
{
	return float2(ndc.x, -ndc.y) * 0.5 + 0.5;
}

float3 NDCTransform(const float3 position, const float4x4 viewProj)
{
	const float4 p = mul(viewProj, float4(position, 1.0));
	return p.xyz / p.w;
}

float3 GetWorldPosition(const float2 texcoord, const float depth, const float4x4 viewProjInv)
{
	const float2 s = texcoord * 2.0 - 1.0;
	const float4 p = mul(viewProjInv, float4(s.x, -s.y, depth, 1.0));
	return p.xyz / p.w;
}

#endif
