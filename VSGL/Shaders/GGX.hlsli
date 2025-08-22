#ifndef GGX_HLSLI
#define GGX_HLSLI

#include "MathConstants.hlsli"
#include "NumericLimits.hlsli"

// Symmetric GGX using anisotropic alpha roughness.
float SGGX(const float3 m, const float2 roughness)
{
	const float3 stretched = float3(m.xy / roughness, m.z);
	const float length2 = dot(stretched, stretched);

	return 1.0 / (M_PI * (roughness.x * roughness.y) * (length2 * length2));
}

// Symmetric GGX using a 2x2 roughness matrix (i.e., Non-axis-aligned GGX w/o the Heaviside function).
float SGGX(const float3 m, const float2x2 roughnessMat)
{
	const float det = max(determinant(roughnessMat), FLT_MIN); // TODO: Use Kahan's algorithm for precise determinant [https://pharr.org/matt/blog/2019/11/03/difference-of-floats].
	const float2x2 roughnessMatAdj = { roughnessMat._22, -roughnessMat._12, -roughnessMat._21, roughnessMat._11 };
	const float length2 = dot(m.xy, mul(roughnessMatAdj, m.xy)) / det + m.z * m.z; // TODO: Use Kahan's algorithm for precise mul and dot [https://pharr.org/matt/blog/2019/11/03/difference-of-floatshttps://pharr.org/matt/blog/2019/11/03/difference-of-floats].

	return 1.0 / (M_PI * sqrt(det) * (length2 * length2));
}

// Axis-aligned anisotropic GGX.
float GGX(const float3 m, const float2 roughness)
{
	return (m.z > 0.0) ? SGGX(m, roughness) : 0.0;
}

// Non-axis-aligned anisotropic GGX.
// [Tokuyoshi and Kaplanyan 2021 "Stable Geometric Specular Antialiasing with Projected-Space NDF Filtering", Eq. 1]
float GGX(const float3 m, const float2x2 roughnessMat)
{
	return (m.z > 0.0) ? SGGX(m, roughnessMat) : 0.0;
}

// A dominant visible mirocafet normal for the GGX NDF.
// This normal vector is given by sampling the center of the spherical-cap VNDF [Dupuy and Benyoub 2023 "Sampling Visible GGX Normals with Spherical Caps"].
float3 GGXDominantVisibleNormal(const float3 wi, const float2 roughness)
{
	return normalize(float3(roughness * roughness * wi.xy, wi.z + length(float3(roughness * wi.xy, wi.z))));
}

// Reflection lobe based on the symmetric GGX VNDF.
// [Tokuyoshi et al. 2024 "Hierarchical Light Sampling with Accurate Spherical Gaussian Lighting", Section 5.2]
float SGGXReflectionPDF(const float3 wi, const float3 m, const float2x2 roughnessMat)
{
	return SGGX(m, roughnessMat) / (4.0 * sqrt(dot(wi.xy, mul(roughnessMat, wi.xy)) + wi.z * wi.z)); // TODO: Use Kahan's algorithm for precise mul and dot. [https://pharr.org/matt/blog/2019/11/03/difference-of-floats]
}

#endif
