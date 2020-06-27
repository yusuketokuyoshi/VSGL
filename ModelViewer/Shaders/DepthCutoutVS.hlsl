cbuffer cb : register(b0)
{
	float4x4 g_viewProjection;
};

struct Input
{
	float3 position : POSITION;
	float2 texcoord : TEXCOORD;
};

struct Output
{
	float4 position : SV_Position;
	float2 texcoord : TEXCOORD;
};

Output main(const Input input)
{
	Output output;
	output.position = mul(g_viewProjection, float4(input.position, 1.0));
	output.texcoord = input.texcoord;

	return output;
}
