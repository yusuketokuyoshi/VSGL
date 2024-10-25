#ifndef MATH_HLSLI
#define MATH_HLSLI

float mulsign(const float x, const float y)
{
	return asfloat((asuint(y) & 0x80000000) ^ asuint(x));
}

float2 mulsign(const float2 x, const float2 y)
{
	return asfloat((asuint(y) & 0x80000000) ^ asuint(x));
}

// exp(x) - 1 with cancellation of rounding errors.
// [Nicholas J. Higham "Accuracy and Stability of Numerical Algorithms", Section 1.14.1, p.19]
float expm1(const float x)
{
	const float u = exp(x);

	if (u == 1.0)
	{
		return x;
	}

	const float y = u - 1.0;

	if (abs(x) < 1.0)
	{
		return y * x / log(u);
	}

	return y;
}

// (exp(x) - 1)/x with cancellation of rounding errors.
// [Nicholas J. Higham "Accuracy and Stability of Numerical Algorithms", Section 1.14.1, p. 19]
float expm1_over_x(const float x)
{
	const float u = exp(x);

	if (u == 1.0)
	{
		return 1.0;
	}

	const float y = u - 1.0;

	if (abs(x) < 1.0)
	{
		return y / log(u);
	}

	return y / x;
}

float erf(const float x)
{
	// Early return for large |x|.
	if (abs(x) >= 4.0)
	{
		return mulsign(1.0, x);
	}

	// Polynomial approximation based on the approximation posted in https://forums.developer.nvidia.com/t/optimized-version-of-single-precision-error-function-erff/40977
	if (abs(x) > 1.0)
	{
		// The maximum error is smaller than the approximation described in Abramowitz and Stegun [1964 "Handbook of Mathematical Functions with Formulas, Graphs, and Mathematical Tables", 7.1.26, p.299].
		const float A1 = 1.628459513;
		const float A2 = 9.15674746e-1;
		const float A3 = 1.54329389e-1;
		const float A4 = -3.51759829e-2;
		const float A5 = 5.66795561e-3;
		const float A6 = -5.64874616e-4;
		const float A7 = 2.58907676e-5;
		const float a = abs(x);
		const float y = 1.0 - exp2(-(((((((A7 * a + A6) * a + A5) * a + A4) * a + A3) * a + A2) * a + A1) * a));

		return mulsign(y, x);
	}

	// The maximum error is smaller than the 6th order Taylor polynomial.
	const float A1 = 1.128379121;
	const float A2 = -3.76123011e-1;
	const float A3 = 1.12799220e-1;
	const float A4 = -2.67030653e-2;
	const float A5 = 4.90735564e-3;
	const float A6 = -5.58853149e-4;
	const float x2 = x * x;

	return (((((A6 * x2 + A5) * x2 + A4) * x2 + A3) * x2 + A2) * x2 + A1) * x;
}

// Complementary error function erfc(x) = 1 - erf(x).
// This implementation can have a numerical error for large x.
// TODO: Precise implementation.
float erfc(const float x)
{
	return 1.0 - erf(x);
}

#endif
