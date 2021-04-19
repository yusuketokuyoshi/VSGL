cbuffer cb : register(b0)
{
	float4x4 g_viewProj;
};

struct Input
{
	float3 pos : POSITION;
	float2 texcoord : TEXCOORD;
};

struct Output
{
	float4 pos : SV_Position;
	float2 texcoord : TEXCOORD;
};

Output main(const Input input)
{
	Output output;
	output.pos = mul(g_viewProj, float4(input.pos, 1.0));
	output.texcoord = input.texcoord;

	return output;
}
