#ifndef SPHERICAL_GAUSSIAN_HLSLI
#define SPHERICAL_GAUSSIAN_HLSLI

#include "Math.hlsli"
#include "NumericLimits.hlsli"
#include "MathConstants.hlsli"

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

// Approximate product integral.
// [Iwasaki et al. 2012, "Interactive Bi-scale Editing of Highly Glossy Materials"].
float SGApproxProductIntegral(const SGLobe sg1, const SGLobe sg2)
{
	const float sharpnessSum = sg1.sharpness + sg2.sharpness;
	const float sharpness = sg1.sharpness * sg2.sharpness / sharpnessSum;

	return 2.0 * M_PI * SGEvaluate(sg1.axis, sg2.axis, sharpness, sg1.logAmplitude + sg2.logAmplitude) / sharpnessSum;
}

// Approximate hemispherical integral of an SG / 2pi.
// The parameter "cosine" is the cosine of the angle between the SG axis and the pole axis of the hemisphere.
// [Tokuyoshi 2022 "Accurate Diffuse Lighting from Spherical Gaussian Lights"]
float SGHemisphericalIntegralOverTwoPi(const float cosine, const float sharpness)
{
	// This function approximately computes the integral using an interpolation between the upper hemispherical integral and lower hemispherical integral.
	// First we compute the sigmoid-form interpolation factor.
	// Instead of a logistic approximation [Meder and Bruderlin 2018 "Hemispherical Gausians for Accurate Lighting Integration"],
	// we approximate the interpolation factor using the CDF of a Gaussian (i.e. normalized error function).

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
// The parameter "cosine" is the cosine of the angle between the SG axis and the pole axis of the hemisphere.
float SGHemisphericalIntegral(const float cosine, const float sharpness)
{
	return 2.0 * M_PI * SGHemisphericalIntegralOverTwoPi(cosine, sharpness);
}

// Approximate hemispherical integral for a vMF distribution (i.e. normalized SG).
// The parameter "cosine" is the cosine of the angle between the SG axis and the pole axis of the hemisphere.
// [Tokuyoshi et al. 2024 "Hierarchical Light Sampling with Accurate Spherical Gaussian Lighting (Supplementary Document)" Listing. 4]
float VMFHemisphericalIntegral(const float cosine, const float sharpness)
{
	// Interpolation factor [Tokuyoshi 2022].
	const float A = 0.6517328826907056171791055021459;
	const float B = 1.3418280033141287699294252888649;
	const float C = 7.2216687798956709087860872386955;
	const float steepness = sharpness * sqrt((0.5 * sharpness + A) / ((sharpness + B) * sharpness + C));
	const float lerpFactor = saturate(0.5 + 0.5 * (erf(steepness * clamp(cosine, -1.0, 1.0)) / erf(steepness)));

	// Interpolation between upper and lower hemispherical integrals .
	const float e = exp(-sharpness);

	return lerp(e, 1.0, lerpFactor) / (e + 1.0);
}

// Approximate product integral of an SG and clamped cosine / pi.
// [Tokuyoshi 2022 "Accurate Diffuse Lighting from Spherical Gaussian Lights"]
// This implementation is slower and less accurate than SGClampedCosineProductIntegralOverPi2024.
// Use SGClampedCosineProductIntegralOverPi2024 instead of this function.
float SGClampedCosineProductIntegralOverPi2022(const SGLobe sg, const float3 normal)
{
	const float LAMBDA = 0.00084560872241480124;
	const float ALPHA = 1182.2467339678153;
	const SGLobe prodLobe = SGProduct(sg.axis, sg.sharpness, normal, LAMBDA);
	const float integral0 = SGHemisphericalIntegralOverTwoPi(dot(prodLobe.axis, normal), prodLobe.sharpness) * exp(prodLobe.logAmplitude + LAMBDA);
	const float integral1 = SGHemisphericalIntegralOverTwoPi(dot(sg.axis, normal), sg.sharpness);

	return exp(sg.logAmplitude) * max(2.0 * ALPHA * (integral0 - integral1), 0.0);
}

// Approximate product integral of an SG and clamped cosine.
// This implementation is slower and less accurate than SGClampedCosineProductIntegral2024.
// Use SGClampedCosineProductIntegral2024 instead of this function.
float SGClampedCosineProductIntegral2022(const SGLobe sg, const float3 normal)
{
	return M_PI * SGClampedCosineProductIntegralOverPi2022(sg, normal);
}

// [Tokuyoshi et al. 2024 "Hierarchical Light Sampling with Accurate Spherical Gaussian Lighting (Supplementary Document)" Listing. 5]
float UpperSGClampedCosineIntegralOverTwoPi(const float sharpness)
{
	if (sharpness <= 0.5)
	{
		// Taylor-series approximation for the numerical stability.
		// TODO: Derive a faster polynomial approximation.
		return (((((((-1.0 / 362880.0) * sharpness + 1.0 / 40320.0) * sharpness - 1.0 / 5040.0) * sharpness + 1.0 / 720.0) * sharpness - 1.0 / 120.0) * sharpness + 1.0 / 24.0) * sharpness - 1.0 / 6.0) * sharpness + 0.5;
	}

	return (expm1(-sharpness) + sharpness) / (sharpness * sharpness);
}

// [Tokuyoshi et al. 2024 "Hierarchical Light Sampling with Accurate Spherical Gaussian Lighting (Supplementary Document)" Listing. 6]
float LowerSGClampedCosineIntegralOverTwoPi(const float sharpness)
{
	const float e = exp(-sharpness);

	if (sharpness <= 0.5)
	{
		// Taylor-series approximation for the numerical stability.
		// TODO: Derive a faster polynomial approximation.
		return e * (((((((((1.0 / 403200.0) * sharpness - 1.0 / 45360.0) * sharpness + 1.0 / 5760.0) * sharpness - 1.0 / 840.0) * sharpness + 1.0 / 144.0) * sharpness - 1.0 / 30.0) * sharpness + 1.0 / 8.0) * sharpness - 1.0 / 3.0) * sharpness + 0.5);
	}

	return e * (-expm1(-sharpness) - sharpness * e) / (sharpness * sharpness);
}

// Approximate product integral of an SG and clamped cosine / pi.
// [Tokuyoshi et al. 2024 "Hierarchical Light Sampling with Accurate Spherical Gaussian Lighting (Supplementary Document)" Listing. 7]
float SGClampedCosineProductIntegralOverPi2024(const float cosine, const float sharpness)
{
	// Fitted approximation for t(sharpness).
	const float A = 2.7360831611272558028247203765204;
	const float B = 17.02129778174187535455530451145;
	const float C = 4.0100826728510421403939290030394;
	const float D = 15.219156263147210594866010069381;
	const float E = 76.087896272360737270901154261082;
	const float t = sharpness * sqrt(0.5 * ((sharpness + A) * sharpness + B) / (((sharpness + C) * sharpness + D) * sharpness + E));
	const float tz = t * cosine;

	// In this HLSL implementation, we roughly implement erfc(x) = 1 - erf(x) which can have a numerical error for large x.
	// Therefore, unlike the original impelemntation [Tokuyoshi et al. 2024], we clamp the lerp factor with the machine epsilon / 2 for a conservative approximation.
	// This clamping is unnecessary for languages that have a precise erfc function (e.g., C++).
	// The original implementation [Tokuyoshi et al. 2024] uses a precise erfc function and does not clamp the lerp factor.
	const float INV_SQRTPI = 0.56418958354775628694807945156077; // = 1/sqrt(pi).
	const float CLAMPING_THRESHOLD = 0.5 * FLT_EPSILON; // Set zero if a precise erfc function is available.
	const float lerpFactor = saturate(max(0.5 * (cosine * erfc(-tz) + erfc(t)) - 0.5 * INV_SQRTPI * exp(-tz * tz) * expm1(t * t * (cosine * cosine - 1.0)) / t, CLAMPING_THRESHOLD));

	// Interpolation between lower and upper hemispherical integrals.
	const float lowerIntegral = LowerSGClampedCosineIntegralOverTwoPi(sharpness);
	const float upperIntegral = UpperSGClampedCosineIntegralOverTwoPi(sharpness);

	return 2.0 * lerp(lowerIntegral, upperIntegral, lerpFactor);
}

// Approximate product integral of an SG and clamped cosine.
// [Tokuyoshi et al. 2024 "Hierarchical Light Sampling with Accurate Spherical Gaussian Lighting (Supplementary Document)" Listing. 7]
float SGClampedCosineProductIntegral2024(const float cosine, const float sharpness)
{
	return M_PI * SGClampedCosineProductIntegralOverPi2024(cosine, sharpness);
}

// Approximate the reflection lobe with an SG lobe for microfacet BRDFs.
// [Wang et al. 2009 "All-Frequency Rendering with Dynamic, Spatially-Varying Reflectance"]
SGLobe SGReflectionLobe(const float3 dir, const float3 normal, const float roughness2)
{
	// Compute SG sharpness for the NDF.
	// Unlike Wang et al. [2009], we use the following equation based on the Appendix of [Tokuyoshi and Harada 2019 "Hierarchical Russian Roulette for Vertex Connections"].
	const float sharpnessNDF = 2.0 / roughness2 - 2.0;

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
	const float SQRT3 = 1.7320508075688772935274463415059; // = sqrt(3).
	const float d = sin(theta) * SQRT3 - cos(theta);

	return (sharpness > 0x1.0p25) ? 1.0 : sqrt(1.0 + a * a) * d + a;
}

#endif
