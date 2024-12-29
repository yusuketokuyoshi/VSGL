#ifndef NDF_FILTERING_HLSLI
#define NDF_FILTERING_HLSLI

// NDF filtering using an isotropic fitler kernel based on normal derivatives.
// [Tokuyoshi and Kaplanyan 2021 "Stable Geometric Specular Antialiasing with Projected-Space NDF Filtering", Listing 5. https://www.jcgt.org/published/0010/02/02/]
// @param dndu, dndv  Screen-space derivatives of interpolated vertex normals.
// @param roughness   GGX (or Beckmann) alpha roughness.
// @return            Filtered alpha roughness.
float2 IsotropicNDFFiltering(const float3 dndu, const float3 dndv, const float2 roughness)
{
    const float SIGMA2 = 0.15915494; // Variance of pixel filter kernel (1/(2pi)).
    const float KAPPA = 0.18; // User-specified clamping threshold.
    const float kernelRoughness2 = SIGMA2 * (dot(dndu, dndu) + dot(dndv, dndv)); // Eq. 14 in the paper.
    const float clampedKernelRoughness2 = min(kernelRoughness2, KAPPA);
    const float2 filteredRoughness2 = saturate(roughness * roughness + clampedKernelRoughness2);
    return sqrt(filteredRoughness2);
}

#endif
