cbuffer cb : register(b0)
{
	float4x4 g_viewProjection;
};

float4 main(const float3 position : POSITION) : SV_Position
{
	return mul(g_viewProjection, float4(position, 1.0));
}
