#ifndef SG_LIGHT_HLSLI
#define SG_LIGHT_HLSLI

static const float SGLIGHT_SHARPNESS_MAX = 0x1.0p41; // Clamping threshold to avoid overflow.

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
