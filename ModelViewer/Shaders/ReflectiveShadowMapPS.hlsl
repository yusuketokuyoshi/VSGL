#include "NormalMapUtility.hlsli"
#include "OctahedralMapping.hlsli"

#if defined(ALPHA_CUTOUT)
Texture2D<float4> diffuseMap     : register(t0);
#else
Texture2D<float3> diffuseMap     : register(t0);
#endif
Texture2D<float4> specularMap    : register(t1);
Texture2D<float2> normalMap      : register(t3);
SamplerState      textureSampler : register(s0);

struct Input
{
	float4 position : SV_Position;
	float2 texcoord : TEXCOORD;
	float3 normal : NORMAL;
	float3 tangent : TANGENT;
	nointerpolation float bitangentSign : BITANGENT_SIGN;
#if defined(ALPHA_CUTOUT)
	bool isFrontFace : SV_IsFrontFace;
#endif
};

struct Output
{
	float2 normal : SV_Target0;
	float3 diffuse : SV_Target1;
	float4 specular : SV_Target2;
};

#if !defined(ALPHA_CUTOUT)
[earlydepthstencil]
#endif
Output main(const Input input)
{
#if defined(ALPHA_CUTOUT)
	const float4 diffuse = diffuseMap.Sample(textureSampler, input.texcoord);

	if (diffuse.w < 0.5)
	{
		discard;
	}

	const float3x3 tangentFrame = BuildTangentFrame(normalize(input.isFrontFace ? input.normal : -input.normal), input.tangent, input.bitangentSign);
#else
	const float3 diffuse = diffuseMap.Sample(textureSampler, input.texcoord);
	const float3x3 tangentFrame = BuildTangentFrame(normalize(input.normal), input.tangent, input.bitangentSign);
#endif
	const float3 normalTS = DecodeNormalMap(normalMap.Sample(textureSampler, input.texcoord));
	const float3 normal = mul(normalTS, tangentFrame);
	Output output;
	output.normal = EncodeOct(normal);
	output.diffuse = diffuse.xyz;
	output.specular = specularMap.Sample(textureSampler, input.texcoord);

	return output;
}
