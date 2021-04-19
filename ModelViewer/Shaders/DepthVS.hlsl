cbuffer cb : register(b0)
{
	float4x4 g_viewProj;
};

float4 main(const float3 pos : POSITION) : SV_Position
{
	return mul(g_viewProj, float4(pos, 1.0));
}
