#ifndef ANISOTROPIC_SPHERICAL_GAUSSIAN_HLSLI
#define ANISOTROPIC_SPHERICAL_GAUSSIAN_HLSLI

#include "SphericalGaussian.hlsli"

struct ASGLobe
{
	float3 x;
	float3 y;
	float3 z;
	float2 sharpness;
	float  logAmplitude;
};

float ASGSharpnessToSGSharpness(const float2 sharpness)
{
	return 2.0 * sqrt(sharpness.x * sharpness.y);
}

float SGSharpnessToASGSharpness(const float sharpness)
{
	return 0.5 * sharpness;
}

float ASGEvaluate(const float3 dir, const ASGLobe asg)
{
	const float smoothing = saturate(dot(dir, asg.z));
	const float2 v = { dot(dir, asg.x), dot(dir, asg.y) };

	return smoothing * exp(asg.logAmplitude - dot(asg.sharpness, v * v));
}

// Rough approximation for the integral of an ASG.
float ASGApproxIntegral(const float2 sharpness)
{
	return M_PI * rsqrt(sharpness.x * sharpness.y);
}

// Approximate product integral of an ASG and SG.
float ASGProductIntegral(const ASGLobe asg, const SGLobe sg)
{
	const float sharpness = SGSharpnessToASGSharpness(sg.sharpness);
	const float2 sharpnessSum = asg.sharpness + sharpness;
	const ASGLobe lobe = { asg.x, asg.y, asg.z, asg.sharpness * sharpness / sharpnessSum, sg.logAmplitude };

	return M_PI * ASGEvaluate(sg.axis, lobe) * rsqrt(sharpnessSum.x * sharpnessSum.y);
}

// Approximate the reflection lobe with an ASG lobe for microfacet BRDFs.
// This implementation is specialized for isotropic NDFs.
// For a general form for anisotropic NDFs, please see [Xu et al. 2012 "Anisotropic Spherical Gaussians"].
ASGLobe ASGReflectionLobe(const float3 dir, const float3 normal, const float roughness2)
{
	// Compute ASG sharpness for the NDF.
	// Unlike Xu et al. [2012], we use the following equation based on the Appendix of [Tokuyoshi and Harada 2019 "Hierarchical Russian Roulette for Vertex Connections"].
	const float sharpnessNDF = 1.0 / roughness2 - 1.0;

	// Compute a 2x2 Jacobian matrix for the transformation from halfvectors to reflection vectors.
	// Since this matrix is diagonal at the perfect reflection vector, we use only diagonal entries.
	const float2 jacobianDiag = { 2.0 * dot(dir, normal), 2.0 };

	// Compute the sharpness and axes for the reflection lobe.
	const float2 sharpness = sharpnessNDF / (jacobianDiag * jacobianDiag);
	const float3 axisX = normalize(cross(dir, normal));
	const float3 axisZ = reflect(-dir, normal);
	const float3 axisY = cross(axisZ, axisX);

	const ASGLobe result = { axisX, axisY, axisZ, sharpness, 0.0 };
	return result;
}

#endif
