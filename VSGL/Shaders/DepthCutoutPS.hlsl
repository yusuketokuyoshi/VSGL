Texture2D<float4> diffuseMap : register(t0);
SamplerState      textureSampler : register(s0);

struct Input
{
	float4 pos : SV_Position;
	float2 texcoord : TEXCOORD;
};

void main(const Input input)
{
	if (diffuseMap.Sample(textureSampler, input.texcoord).a < 0.5)
	{
		discard;
	}
}
