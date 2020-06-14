cbuffer cb : register(b0)
{
	float4x4 g_viewProjection;
};

struct Input
{
	float3 position : POSITION;
	float2 texcoord : TEXCOORD;
	float3 normal : NORMAL;
	float3 tangent : TANGENT;
	float3 bitangent : BITANGENT;
};

struct Output
{
	float4 position : SV_Position;
	float2 texcoord : TEXCOORD;
	float3 normal : NORMAL;
	float3 tangent : TANGENT;
	nointerpolation float bitangentSign : BITANGENT_SIGN;
};

Output main(const Input input)
{
	Output output;
	output.position = mul(g_viewProjection, float4(input.position, 1.0));
	output.texcoord = input.texcoord;
	output.normal = input.normal;
	output.tangent = input.tangent;
	output.bitangentSign = asfloat((asuint(dot(input.bitangent, cross(input.normal, input.tangent))) & 0x80000000) ^ asuint(1.0)); // TODO: Precompute bitangentSign.

	return output;
}
