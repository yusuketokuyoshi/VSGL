#ifndef SG_LIGHT_HLSLI
#define SG_LIGHT_HLSLI

struct SGLight
{
	float3 position;
	float  variance;
	float3 intensity;
	float  sharpness;
	float3 axis;
	uint   pad;
};

#endif
