#ifndef MATH_HLSLI
#define MATH_HLSLI

// (exp(x) - 1)/x with cancellation of rounding errors.
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

#endif
