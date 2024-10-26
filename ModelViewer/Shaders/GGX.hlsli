#ifndef GGX_HLSLI
#define GGX_HLSLI

#include "MathConstants.hlsli"
#include "NumericLimits.hlsli"

// Isotropic GGX.
float GGX(const float z, const float roughness2)
{
	const float a = (roughness2 - 1.0) * (z * z) + 1.0;

	return (z > 0) ? roughness2 / (M_PI * (a * a)) : 0.0;
}

// Symmetry GGX using a 2x2 roughness matrix (i.e., Non-axis-aligned GGX w/o the Heaviside function).
float SGGX(const float3 m, const float2x2 roughnessMat)
{
	const float det = max(determinant(roughnessMat), FLT_MIN); // TODO: Use Kahan's algorithm for precise determinant. [https://pharr.org/matt/blog/2019/11/03/difference-of-floats]
	const float2x2 roughnessMatAdj = { roughnessMat._22, -roughnessMat._12, -roughnessMat._21, roughnessMat._11 };
	const float length2 = dot(m.xy, mul(roughnessMatAdj, m.xy)) / det + m.z * m.z; // TODO: Use Kahan's algorithm for precise mul and dot. [https://pharr.org/matt/blog/2019/11/03/difference-of-floatshttps://pharr.org/matt/blog/2019/11/03/difference-of-floats]

	return 1.0 / (M_PI * sqrt(det) * (length2 * length2));
}

// Non-axis-aligned GGX.
// [Tokuyoshi and Kaplanyan 2021 "Stable Geometric Specular Antialiasing with Projected-Space NDF Filtering", Eq. 1]
float GGX(const float3 m, const float2x2 roughnessMat)
{
	return (m.z > 0.0) ? SGGX(m, roughnessMat) : 0.0;
}

// Reflection lobe based on the symmetric GGX VNDF.
// [Tokuyoshi et al. 2024 "Hierarchical Light Sampling with Accurate Spherical Gaussian Lighting", Section 5.2]
float SGGXReflectionPDF(const float3 wi, const float3 m, const float2x2 roughnessMat)
{
	return SGGX(m, roughnessMat) / (4.0 * sqrt(dot(wi.xy, mul(roughnessMat, wi.xy)) + wi.z * wi.z)); // TODO: Use Kahan's algorithm for precise mul and dot. [https://pharr.org/matt/blog/2019/11/03/difference-of-floats]
}

#endif
