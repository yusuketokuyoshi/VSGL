#ifndef SPHERICAL_GAUSSIAN_HLSLI
#define SPHERICAL_GAUSSIAN_HLSLI

#include "NumericLimits.hlsli"
#include "MathConstants.hlsli"

static const float SG_CUT_COSINE_SHARPNESS = 2.0;

struct SGLobe
{
	float3 axis;
	float  sharpness;
	float  logCoefficient;
};

float expm1(const float x)
{
	if (abs(x) > 0.5)
	{
		return exp(x) - 1.0;
	}
	else
	{
		// To improve the numerical stability for a small x, we approximate exp(x) - 1 using Taylor series.
		// This approximation error is smaller than the numerical error of the exact form.
		return ((((((((1.0 / 362880.0 * x + 1.0 / 40320.0) * x + 1.0 / 5040.0) * x + 1.0 / 720.0) * x + 1.0 / 120.0) * x + 1.0 / 24.0) * x + 1.0 / 6.0) * x + 1.0 / 2.0) * x + 1.0) * x;
	}
}

float SGEvaluate(const float3 dir, const float3 axis, const float sharpness, const float logCoefficient = 0.0)
{
	return exp(logCoefficient + sharpness * (dot(dir, axis) - 1.0));
}

// Exact solution of an SG integral.
float SGIntegral(const float sharpness)
{
	if (sharpness > 0.125)
	{
		return 2.0 * M_PI * (1.0 - exp(-2.0 * sharpness)) / sharpness;
	}
	else
	{
		// To improve the numerical stability for small sharpness, we approximate (1 - exp(-2*sharpness))/sharpness using Taylor series.
		// This approximation error is smaller than the numerical error of the exact form.
		return 2.0 * M_PI * ((((((-4.0 / 45.0) * sharpness + 4.0 / 15.0) * sharpness - 2.0 / 3.0) * sharpness + 4.0 / 3.0) * sharpness - 2.0) * sharpness + 2.0);
	}
}

// Approximate solution for an SG integral.
// This approximation assumes sharpness is not small.
// Don't input sharpness smaller than 0.5 to avoid the approximate solution larger than 4pi.
float SGApproxIntegral(const float sharpness)
{
	return 2.0 * M_PI / sharpness;
}

// Product of two SGs which is closed in SG basis
SGLobe SGProduct(const float3 axis1, const float sharpness1, const float3 axis2, const float sharpness2)
{
	const float3 axis = axis1 * sharpness1 + axis2 * sharpness2;
	const float sharpness = length(axis);

	// Compute logCoefficient = sharpness - sharpness1 - sharpness2 in a numerically stable form.
	const float cosine = clamp(dot(axis1, axis2), -1.0, 1.0);
	const float sharpnessMin = min(sharpness1, sharpness2);
	const float sharpnessRatio = sharpnessMin / max(sharpness1, sharpness2);
	const float logCoefficient = 2.0 * sharpnessMin * (cosine - 1.0) / (sqrt(2.0 * sharpnessRatio * cosine + sharpnessRatio * sharpnessRatio + 1.0) + sharpnessRatio + 1.0);

	const SGLobe result = { axis / max(sharpness, FLT_MIN), sharpness, logCoefficient };

	return result;
}

// Exact product integral
// [Tsai and Shih. 2006, "All-Frequency Precomputed Radiance Transfer using Spherical Radial Basis Functions and Clustered Tensor Approximation"].
float SGProductIntegral(const SGLobe sg1, const SGLobe sg2)
{
	const SGLobe lobe = SGProduct(sg1.axis, sg1.sharpness, sg2.axis, sg2.sharpness);

	return exp(sg1.logCoefficient + sg2.logCoefficient + lobe.logCoefficient) * SGIntegral(lobe.sharpness);
}

// Approximate product integral / pi.
// [Iwasaki et al. 12, "Interactive Bi-scale Editing of Highly Glossy Materials"].
float SGApproxProductIntegralOverPi(const SGLobe sg1, const SGLobe sg2)
{
	const float sharpnessSum = sg1.sharpness + sg2.sharpness;
	const float sharpness = sg1.sharpness * sg2.sharpness / sharpnessSum;

	return 2.0 * SGEvaluate(sg1.axis, sg2.axis, sharpness, sg1.logCoefficient + sg2.logCoefficient) / sharpnessSum;
}

// Approximate product integral.
float SGApproxProductIntegral(const SGLobe sg1, const SGLobe sg2)
{
	return M_PI * SGApproxProductIntegralOverPi(sg1, sg2);
}

// Approximate hemispherical integral of an SG / 2pi.
// The parameter "cosine" is the cosine of the angle between the SG axis and pole axis of the hemisphere.
// [Meder and Bruderlin 2018 "Hemispherical Gausians for Accurate Lighting Integration"]
float HSGIntegralOverTwoPi(const float sharpness, const float cosine)
{
	// This function approximately computes the integral using an interpolation between the upper hemispherical integral and lower hemispherical integral.
	// First we compute the interpolation factor.
	// Unlike the paper, we use reciprocals of exponential functions obtained by negative exponents for the numerical stability.
	const float t = sqrt(sharpness) * sharpness * (-1.6988 * sharpness - 10.8438) / ((sharpness + 6.2201) * sharpness + 10.2415);
	const float u = t * clamp(cosine, -1.0, 1.0);
	const float lerpFactor = saturate(expm1(t + u) / (expm1(t) * (1.0 + exp(u))));

	// Interpolation between the upper hemispherical integral and lower hemispherical integral.
	// Upper hemispherical integral: 2pi*(1 - e)/sharpness.
	// Lower hemispherical integral: 2pi*e*(1 - e)/sharpness.
	// Since this function returns the integral divided by 2pi, 2pi is eliminated from the code.
	const float e = exp(-sharpness);
	const float w = lerp(e, 1.0, lerpFactor); // (1 - e)/sharpness will be multiplied later.

	if (sharpness > 0.5)
	{
		return w * (1.0 - e) / sharpness;
	}
	else
	{
		// To improve the numerical stability for small sharpness, we approximate (1 - exp(-sharpness))/sharpness using Taylor series.
		// This approximation error is smaller than the numerical error of the exact form.
		return w * ((((((((1.0 / 362880.0 * sharpness - 1.0 / 40320.0) * sharpness + 1.0 / 5040.0) * sharpness - 1.0 / 720.0) * sharpness + 1.0 / 120.0) * sharpness - 1.0 / 24.0) * sharpness + 1.0 / 6.0) * sharpness - 1.0 / 2.0) * sharpness + 1.0);
	}
}

// Approximate hemispherical integral of an SG.
float HSGIntegral(const float sharpness, const float cosine)
{
	return 2.0 * M_PI * HSGIntegralOverTwoPi(sharpness, cosine);
}

// Approximate product integral of an SG and clamped cosine / pi.
// [Meder and Bruderlin 2018 "Hemispherical Gausians for Accurate Lighting Integration"]
float HSGCosineProductIntegralOverPi(const SGLobe sg1, const float3 normal)
{
	const SGLobe lobe = SGProduct(sg1.axis, sg1.sharpness, normal, 0.0315);
	const float integral0 = (32.7080 * 2.0) * HSGIntegralOverTwoPi(lobe.sharpness, dot(lobe.axis, normal)) * exp(sg1.logCoefficient + lobe.logCoefficient);
	const float integral1 = (31.7003 * 2.0) * HSGIntegralOverTwoPi(sg1.sharpness, dot(sg1.axis, normal)) * exp(sg1.logCoefficient);

	return max(integral0 - integral1, 0.0);
}

// Approximate product integral of an SG and clamped cosine.
float HSGCosineProductIntegral(const SGLobe sg1, const float3 normal)
{
	return M_PI * HSGCosineProductIntegralOverPi(sg1, normal);
}

// Approximate the reflection lobe with an SG lobe for microfacet BRDFs.
// [Wang et al. 2009 "All-Frequency Rendering with Dynamic, Spatially-Varying Reflectance"]
SGLobe SGReflectionLobe(const float3 direction, const float3 normal, const float squaredRoughness)
{
	// Compute SG sharpness for the NDF.
	// Unlike Wang et al. [2009], we use the following equation based on the Appendix of [Tokuyoshi and Harada 2019 "Hierarchical Russian Roulette for Vertex Connections"].
	const float sharpnessNDF = 2.0 / squaredRoughness - 2.0;

	// Approximate the reflection lobe axis using the peak of the NDF (i.e., the perfectly specular reflection direction).
	const float3 axis = reflect(-direction, normal);

	// Jacobian of the transformation from halfvectors to reflection vectors.
	const float jacobian = 4.0 * abs(dot(direction, normal));

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
