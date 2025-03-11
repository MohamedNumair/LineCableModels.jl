"""
_equals: Checks if two numerical values are approximately equal within a given tolerance.

# Arguments
- `x`: First numeric value.
- `y`: Second numeric value.
- `atol`: Absolute tolerance for comparison (default: `TOL`).

# Returns
- `true` if `x` and `y` are approximately equal within the given tolerance.
- `false` otherwise.

# Dependencies
- Uses `isapprox` from Base Julia for numerical approximation checks.

# Examples
```julia
_equals(1.00001, 1.0, atol=1e-4) # Output: true
_equals(1.0001, 1.0, atol=1e-5)  # Output: false
```

# Notes
Wrapper around `isapprox` to handle floating-point comparison.
Use this instead of `==` for all numerical comparisons to avoid
precision errors that shouldn't require explanation.

# References
- None.
"""
function _equals(x, y; atol = TOL)
	return isapprox(x, y, atol = atol)
end

"""
_to_nominal: Extracts the nominal value from a measurement or returns the original value.

# Arguments
- `x`: Input value which can be a `Measurement` type or any other type.

# Returns
- The nominal value if `x` is a `Measurement`, otherwise returns `x` unchanged.

# Dependencies
- Uses `Measurements.value` to extract the nominal value from measurements.

# Examples
```julia
using Measurements

_to_nominal(1.0)  # Output: 1.0
_to_nominal(5.2 ± 0.3)  # Output: 5.2
```

# Notes
Utility function for handling both deterministic values and measurements
in calculations where only the central value is needed.

# References
- None.
"""
function _to_nominal(x)
	return x isa Measurement ? Measurements.value(x) : x
end

"""
percent_to_uncertain: Converts a value to a measurement with uncertainty based on percentage.

# Arguments
- `val`: The nominal value.
- `perc`: The percentage uncertainty (0 to 100).

# Returns
- A `Measurement` type with the given value and calculated uncertainty.

# Dependencies
- Uses `measurement` function from the `Measurements.jl` package.

# Examples
```julia
using Measurements

percent_to_uncertain(100.0, 5)  # Output: 100.0 ± 5.0
percent_to_uncertain(10.0, 10)  # Output: 10.0 ± 1.0
```

# Notes
Convenient way to specify uncertainty as a percentage rather than absolute value.
The uncertainty is calculated as val × (perc/100).

# References
- None.
"""
function percent_to_uncertain(val, perc) #perc from 0 to 100
	measurement(val, (perc * val) / 100)
end

"""
bias_to_uncertain: Computes the uncertainty of a measurement by incorporating systematic bias.

# Arguments
- `nominal`: The deterministic nominal value (Float64).
- `measurements`: A vector of `Measurement` values from the `Measurements.jl` package.

# Returns
- A new `Measurement` object representing the mean measurement value with an uncertainty that accounts for both statistical variation and systematic bias.

# Methodology
- Computes the mean value and its associated uncertainty from the given `measurements`.
- Determines the **bias** as the absolute difference between the deterministic `nominal` value and the mean measurement.
- The final uncertainty is the sum of the standard uncertainty (`sigma_mean`) and the systematic bias.

# Dependencies
- Requires the `Measurements.jl` package for handling uncertain values.

# Examples
```julia
using Measurements

nominal = 10.0
measurements = [10.2 ± 0.1, 9.8 ± 0.2, 10.1 ± 0.15]
result = bias_to_uncertain(nominal, measurements)
println(result)  # Output: Measurement with adjusted uncertainty
```

# References
- None.
"""
function bias_to_uncertain(nominal::Float64, measurements::Vector{<:Measurement})
	# Compute the mean value and uncertainty from the measurements
	mean_measurement = mean(measurements)
	mean_value = Measurements.value(mean_measurement)  # Central value
	sigma_mean = Measurements.uncertainty(mean_measurement)  # Uncertainty of the mean
	# Compute the bias (deterministic nominal value minus mean measurement)
	bias = abs(nominal - mean_value)
	return mean_value ± (sigma_mean + bias)
end

"""
_to_upper: Computes the upper bound of a measurement value.

# Arguments
- `m`: A numerical value, expected to be of type `Measurement` from the `Measurements.jl` package.

# Returns
- The upper bound of `m`, computed as `value(m) + uncertainty(m)` if `m` is a `Measurement`.
- `NaN` if `m` is not a `Measurement`.

# Dependencies
- Requires the `Measurements.jl` package for handling uncertain values.

# Examples
```julia
using Measurements

m = 10.0 ± 2.0
upper = _to_upper(m)  # Output: 12.0

not_a_measurement = 5.0
upper_invalid = _to_upper(not_a_measurement)  # Output: NaN
```

# References
- None.
"""
function _to_upper(m::Number)
	if m isa Measurement
		return Measurements.value(m) + Measurements.uncertainty(m)
	else
		return NaN
	end
end

"""
_to_upper and _to_lower: Compute the upper and lower bounds of a measurement value.

# Arguments
- `m`: A numerical value, expected to be of type `Measurement` from the `Measurements.jl` package.

# Returns
- `_to_upper(m)`: The upper bound, computed as `value(m) + uncertainty(m)` if `m` is a `Measurement`.
- `_to_lower(m)`: The lower bound, computed as `value(m) - uncertainty(m)` if `m` is a `Measurement`.
- `NaN` if `m` is not a `Measurement`.

# Dependencies
- Requires the `Measurements.jl` package for handling uncertain values.

# Examples
```julia
using Measurements

m = 10.0 ± 2.0
upper = _to_upper(m)  # Output: 12.0
lower = _to_lower(m)  # Output: 8.0

not_a_measurement = 5.0
upper_invalid = _to_upper(not_a_measurement)  # Output: NaN
lower_invalid = _to_lower(not_a_measurement)  # Output: NaN
```

# References
- None.
"""
function _to_lower(m::Number)
	if m isa Measurement
		return Measurements.value(m) - Measurements.uncertainty(m)
	else
		return NaN
	end
end

"""
_percent_error: Computes the percentage uncertainty of a measurement.

# Arguments
- `m`: A numerical value, expected to be of type `Measurement` from the `Measurements.jl` package.

# Returns
- The percentage uncertainty, computed as `100 * uncertainty(m) / value(m)`, if `m` is a `Measurement`.
- `NaN` if `m` is not a `Measurement`.

# Dependencies
- Requires the `Measurements.jl` package for handling uncertain values.

# Examples
```julia
using Measurements

m = 10.0 ± 2.0
percent_err = _percent_error(m)  # Output: 20.0

not_a_measurement = 5.0
percent_err_invalid = _percent_error(not_a_measurement)  # Output: NaN
```

# References
- None.
"""
function _percent_error(m::Number)
	if m isa Measurement
		return 100 * Measurements.uncertainty(m) / Measurements.value(m)
	else
		return NaN
	end
end