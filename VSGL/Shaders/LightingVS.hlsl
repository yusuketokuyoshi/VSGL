cbuffer cb : register(b0)
{
	float4x4 g_viewProj;
};

struct Input
{
	float3 pos : POSITION;
	float2 texcoord : TEXCOORD;
	float3 normal : NORMAL;
	float3 tangent : TANGENT;
	float3 bitangent : BITANGENT;
};

struct Output
{
	float4 pos : SV_Position;
	float3 wpos : POSITION1;
	float2 texcoord : TEXCOORD;
	float3 normal : NORMAL;
	float3 tangent : TANGENT;
	nointerpolation float bitangentSign : BITANGENT_SIGN;
};

Output main(const Input input)
{
	Output output;
	output.pos = mul(g_viewProj, float4(input.pos, 1.0));
	output.wpos = input.pos;
	output.texcoord = input.texcoord;
	output.normal = input.normal;
	output.tangent = input.tangent;
	output.bitangentSign = asfloat((asuint(dot(input.bitangent, cross(input.normal, input.tangent))) & 0x80000000) ^ asuint(1.0)); // TODO: Precompute bitangentSign.

	return output;
}
