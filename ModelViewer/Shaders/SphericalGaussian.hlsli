#ifndef SPHERICAL_GAUSSIAN_HLSLI
#define SPHERICAL_GAUSSIAN_HLSLI

#include "Math.hlsli"
#include "NumericLimits.hlsli"
#include "MathConstants.hlsli"

static const float SG_CUT_COSINE_SHARPNESS = 2.0;

struct SGLobe
{
	float3 axis;
	float  sharpness;
	float  logAmplitude;
};

float SGEvaluate(const float3 dir, const float3 axis, const float sharpness, const float logAmplitude = 0.0)
{
	return exp(logAmplitude + sharpness * (dot(dir, axis) - 1.0));
}

// Exact solution of an SG integral.
float SGIntegral(const float sharpness)
{
	return 4.0 * M_PI * expm1_over_x(-2.0 * sharpness);
}

// Approximate solution for an SG integral.
// This approximation assumes sharpness is not small.
// Don't input sharpness smaller than 0.5 to avoid the approximate solution larger than 4pi.
float SGApproxIntegral(const float sharpness)
{
	return 2.0 * M_PI / sharpness;
}

// Product of two SGs.
SGLobe SGProduct(const float3 axis1, const float sharpness1, const float3 axis2, const float sharpness2)
{
	const float3 axis = axis1 * sharpness1 + axis2 * sharpness2;
	const float sharpness = length(axis);

	// Compute logAmplitude = sharpness - sharpness1 - sharpness2 using a numerically stable form.
	const float cosine = clamp(dot(axis1, axis2), -1.0, 1.0);
	const float sharpnessMin = min(sharpness1, sharpness2);
	const float sharpnessRatio = sharpnessMin / max(max(sharpness1, sharpness2), FLT_MIN);
	const float logAmplitude = 2.0 * sharpnessMin * (cosine - 1.0) / (sqrt(2.0 * sharpnessRatio * cosine + sharpnessRatio * sharpnessRatio + 1.0) + sharpnessRatio + 1.0);

	const SGLobe result = { axis / max(sharpness, FLT_MIN), sharpness, logAmplitude };

	return result;
}

// Exact product integral
// [Tsai and Shih. 2006, "All-Frequency Precomputed Radiance Transfer using Spherical Radial Basis Functions and Clustered Tensor Approximation"].
float SGProductIntegral(const SGLobe sg1, const SGLobe sg2)
{
	const SGLobe lobe = SGProduct(sg1.axis, sg1.sharpness, sg2.axis, sg2.sharpness);

	return exp(sg1.logAmplitude + sg2.logAmplitude + lobe.logAmplitude) * SGIntegral(lobe.sharpness);
}

// Approximate product integral / pi.
// [Iwasaki et al. 12, "Interactive Bi-scale Editing of Highly Glossy Materials"].
float SGApproxProductIntegralOverPi(const SGLobe sg1, const SGLobe sg2)
{
	const float sharpnessSum = sg1.sharpness + sg2.sharpness;
	const float sharpness = sg1.sharpness * sg2.sharpness / sharpnessSum;

	return 2.0 * SGEvaluate(sg1.axis, sg2.axis, sharpness, sg1.logAmplitude + sg2.logAmplitude) / sharpnessSum;
}

// Approximate product integral.
float SGApproxProductIntegral(const SGLobe sg1, const SGLobe sg2)
{
	return M_PI * SGApproxProductIntegralOverPi(sg1, sg2);
}

// Approximate hemispherical integral of an SG / 2pi.
// The parameter "cosine" is the cosine of the angle between the SG axis and pole axis of the hemisphere.
// [Tokuyoshi 2022 "Accurate Diffuse Lighting from Spherical Gaussian Lights"]
float HSGIntegralOverTwoPi(const float cosine, const float sharpness)
{
	// This function approximately computes the integral using an interpolation between the upper hemispherical integral and lower hemispherical integral.
	// First we compute the sigmoid-form interpolation factor.
	// Instead of a logistic approximation [Meder and Bruderlin 2018 "Hemispherical Gausians for Accurate Lighting Integration"],
	// we approxiamte the interpolation factor using the CDF of a Gaussian (i.e. normalized error function).

	// Our fitted steepness for the CDF.
	const float A = 0.6517328826907056171791055021459;
	const float B = 1.3418280033141287699294252888649;
	const float C = 7.2216687798956709087860872386955;
	const float steepness = sharpness * sqrt((0.5 * sharpness + A) / ((sharpness + B) * sharpness + C));

	// Our approximation for the normalized hemispherical integral.
	const float lerpFactor = 0.5 + 0.5 * (erf(steepness * clamp(cosine, -1.0, 1.0)) / erf(steepness));

	// Interpolation between the upper hemispherical integral and lower hemispherical integral.
	// Upper hemispherical integral: 2pi*(1 - e)/sharpness.
	// Lower hemispherical integral: 2pi*e*(1 - e)/sharpness.
	// Since this function returns the integral divided by 2pi, 2pi is eliminated from the code.
	const float e = exp(-sharpness);

	return lerp(e, 1.0, lerpFactor) * expm1_over_x(-sharpness);
}

// Approximate hemispherical integral of an SG.
float HSGIntegral(const float cosine, const float sharpness)
{
	return 2.0 * M_PI * HSGIntegralOverTwoPi(cosine, sharpness);
}

// Approximate product integral of an SG and clamped cosine / pi.
// [Tokuyoshi 2022 "Accurate Diffuse Lighting from Spherical Gaussian Lights"]
float HSGCosineProductIntegralOverPi(const SGLobe sg, const float3 normal)
{
	const float LAMBDA = 0.00084560872241480124;
	const float ALPHA = 1182.2467339678153;
	const SGLobe prodLobe = SGProduct(sg.axis, sg.sharpness, normal, LAMBDA);
	const float integral0 = HSGIntegralOverTwoPi(dot(prodLobe.axis, normal), prodLobe.sharpness) * exp(prodLobe.logAmplitude + LAMBDA);
	const float integral1 = HSGIntegralOverTwoPi(dot(sg.axis, normal), sg.sharpness);

	return exp(sg.logAmplitude) * max(2.0 * ALPHA * (integral0 - integral1), 0.0);
}

// Approximate product integral of an SG and clamped cosine.
float HSGCosineProductIntegral(const SGLobe sg, const float3 normal)
{
	return M_PI * HSGCosineProductIntegralOverPi(sg, normal);
}

// Approximate the reflection lobe with an SG lobe for microfacet BRDFs.
// [Wang et al. 2009 "All-Frequency Rendering with Dynamic, Spatially-Varying Reflectance"]
SGLobe SGReflectionLobe(const float3 dir, const float3 normal, const float squaredRoughness)
{
	// Compute SG sharpness for the NDF.
	// Unlike Wang et al. [2009], we use the following equation based on the Appendix of [Tokuyoshi and Harada 2019 "Hierarchical Russian Roulette for Vertex Connections"].
	const float sharpnessNDF = 2.0 / squaredRoughness - 2.0;

	// Approximate the reflection lobe axis using the peak of the NDF (i.e., the perfectly specular reflection direction).
	const float3 axis = reflect(-dir, normal);

	// Jacobian of the transformation from halfvectors to reflection vectors.
	const float jacobian = 4.0 * abs(dot(dir, normal));

	// Compute sharpness for the reflection lobe.
	const float sharpness = sharpnessNDF / jacobian;

	const SGLobe result = { axis, sharpness, 0.0 };
	return result;
}

// Estimation of vMF sharpness (i.e., SG sharpness) from the average of directions in R^3.
// [Banerjee et al. 2005 "Clustering on the Unit Hypersphere using von Mises-Fisher Distributions"]
float VMFAxisLengthToSharpness(const float axisLength)
{
	return axisLength * (3.0 - axisLength * axisLength) / (1.0 - axisLength * axisLength);
}

// Inverse of VMFAxisLengthToSharpness.
float VMFSharpnessToAxisLength(const float sharpness)
{
	// Solve x^3 - sx^2 - 3x + s = 0, where s = sharpness.
	// For x in [0, 1] and s in [0, infty), this equation has only a single solution.
	// [Xu and Wang 2015 "Realtime Rendering Glossy to Glossy Reflections in Screen Space"]
	// We solve this cubic equation in a numerically stable manner.
	// [Peters, C. 2016. "How to solve a cubic equation, revisited". http://momentsingraphics.de/?p=105]
	const float a = sharpness / 3.0;
	const float b = a * a * a;
	const float c = sqrt(1.0 + 3.0 * (a * a) * (1.0 + a * a));
	const float theta = atan2(c, b) / 3.0;
	const float SQRT3 = 1.7320508075688772935274463415059;
	const float d = sin(theta) * SQRT3 - cos(theta);

	return (sharpness > 0x1.0p25) ? 1.0 : sqrt(1.0 + a * a) * d + a;
}

#endif
