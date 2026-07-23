#ifndef NDF_FILTERING_HLSLI
#define NDF_FILTERING_HLSLI

// NDF filtering using an isotropic fitler kernel based on normal derivatives.
// [Tokuyoshi and Kaplanyan 2021 "Stable Geometric Specular Antialiasing with Projected-Space NDF Filtering", Listing 5. https://www.jcgt.org/published/0010/02/02/]
// @param dndu, dndv  Screen-space derivatives of interpolated vertex normals.
// @param alpha       GGX (or Beckmann) alpha roughness.
// @return            Filtered alpha roughness.
float2 IsotropicNDFFiltering(const float3 dndu, const float3 dndv, const float2 alpha)
{
	const float SIGMA2 = 0.15915494; // Variance of pixel filter kernel (1/(2pi)).
	const float KAPPA = 0.18; // User-specified clamping threshold.
	const float kernelAlpha2 = SIGMA2 * (dot(dndu, dndu) + dot(dndv, dndv)); // Eq. 14 in the paper.
	const float clampedKernelAlpha2 = min(kernelAlpha2, KAPPA);
	const float2 filteredAlpha2 = saturate(alpha * alpha + clampedKernelAlpha2);
	return sqrt(filteredAlpha2);
}

#endif
