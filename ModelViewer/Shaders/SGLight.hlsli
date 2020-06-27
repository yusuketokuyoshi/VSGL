#ifndef SG_LIGHT_HLSLI
#define SG_LIGHT_HLSLI

struct SGLight
{
	float3 position;
	float  varianceInv;
	float3 coefficient;
	float  sharpness;
	float3 axis;
	uint   pad;
};

#endif
