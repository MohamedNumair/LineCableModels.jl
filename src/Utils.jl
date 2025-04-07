"""
	LineCableModels.Utils

The [`Utils`](@ref) module provides utility functions and constants for the  [`LineCableModels.jl`](index.md) package. This module includes functions for handling measurements, numerical comparisons, and other common tasks.

# Overview

- Provides general constants used throughout the package.
- Includes utility functions for numerical comparisons and handling measurements.
- Contains functions to compute uncertainties and bounds for measurements.

# Dependencies

$(IMPORTS)

# Exports

$(EXPORTS)
"""
module Utils

# Load common dependencies
include("CommonDeps.jl")

# Module-specific dependencies
using Measurements
using Statistics

# General constants
"Base power system frequency, f₀ = 50 [Hz]."
const f₀ = 50
"Magnetic constant (vacuum permeability), μ₀ = 4π * 1e-7 [H/m]."
const μ₀ = 4π * 1e-7
"Electric constant (vacuum permittivity), ε₀ = 8.8541878128e-12 [F/m]."
const ε₀ = 8.8541878128e-12
"Annealed copper reference resistivity, ρ₀ = 1.724e-08 [Ω·m]."
const ρ₀ = 1.724e-08
"Base temperature for conductor properties, T₀ = 20 [°C]."
const T₀ = 20
"Default tolerance for floating-point comparisons, TOL = 1e-6."
const TOL = 1e-6
export f₀, μ₀, ε₀, ρ₀, T₀, TOL

"""
$(TYPEDSIGNATURES)

Checks if two numerical values are approximately equal within a given tolerance.

# Arguments

- `x`: First numeric value.
- `y`: Second numeric value.
- `atol`: Absolute tolerance for comparison (default: `TOL`).

# Returns

- `true` if `x` and `y` are approximately equal within the given tolerance.
- `false` otherwise.

# Examples

```julia
$(FUNCTIONNAME)(1.00001, 1.0, atol=1e-4) # Output: true
$(FUNCTIONNAME)(1.0001, 1.0, atol=1e-5)  # Output: false
```
"""
function equals(x, y; atol = TOL)
	return isapprox(x, y, atol = atol)
end

"""
$(TYPEDSIGNATURES)

Extracts the nominal value from a measurement or returns the original value.

# Arguments

- `x`: Input value which can be a `Measurement` type or any other type.

# Returns

- The nominal value if `x` is a `Measurement`, otherwise returns `x` unchanged.

# Examples

```julia
using Measurements

$(FUNCTIONNAME)(1.0)  # Output: 1.0
$(FUNCTIONNAME)(5.2 ± 0.3)  # Output: 5.2
```
"""
function to_nominal(x)
	return x isa Measurement ? Measurements.value(x) : x
end

"""
$(TYPEDSIGNATURES)

Converts a measurement to a value with zero uncertainty, retaining the numeric type `Measurement`.

# Arguments

- `value`: Input value that may be a `Measurement` type or another type.

# Returns

- If input is a `Measurement`, returns the same value with zero uncertainty; otherwise returns the original value unchanged.

# Examples

```julia
x = 5.0 ± 0.1
result = $(FUNCTIONNAME)(x)  # Output: 5.0 ± 0.0

y = 10.0
result = $(FUNCTIONNAME)(y)  # Output: 10.0
```
"""
function strip_uncertainty(value)
	return value isa Measurement ? (Measurements.value(value) ± 0.0) : value
end

"""
$(TYPEDSIGNATURES)

Converts a value to a measurement with uncertainty based on percentage.

# Arguments

- `val`: The nominal value.
- `perc`: The percentage uncertainty (0 to 100).

# Returns

- A `Measurement` type with the given value and calculated uncertainty.

# Examples

```julia
using Measurements

$(FUNCTIONNAME)(100.0, 5)  # Output: 100.0 ± 5.0
$(FUNCTIONNAME)(10.0, 10)  # Output: 10.0 ± 1.0
```
"""
function percent_to_uncertain(val, perc) #perc from 0 to 100
	measurement(val, (perc * val) / 100)
end

"""
$(TYPEDSIGNATURES)

Computes the uncertainty of a measurement by incorporating systematic bias.

# Arguments

- `nominal`: The deterministic nominal value (Float64).
- `measurements`: A vector of `Measurement` values from the `Measurements.jl` package.

# Returns

- A new `Measurement` object representing the mean measurement value with an uncertainty that accounts for both statistical variation and systematic bias.

# Notes

- Computes the mean value and its associated uncertainty from the given `measurements`.
- Determines the **bias** as the absolute difference between the deterministic `nominal` value and the mean measurement.
- The final uncertainty is the sum of the standard uncertainty (`sigma_mean`) and the systematic bias.

# Examples
```julia
using Measurements

nominal = 10.0
measurements = [10.2 ± 0.1, 9.8 ± 0.2, 10.1 ± 0.15]
result = $(FUNCTIONNAME)(nominal, measurements)
println(result)  # Output: Measurement with adjusted uncertainty
```
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
$(TYPEDSIGNATURES)

Computes the upper bound of a measurement value.

# Arguments

- `m`: A numerical value, expected to be of type `Measurement` from the `Measurements.jl` package.

# Returns

- The upper bound of `m`, computed as `value(m) + uncertainty(m)` if `m` is a `Measurement`.
- `NaN` if `m` is not a `Measurement`.

# Examples

```julia
using Measurements

m = 10.0 ± 2.0
upper = $(FUNCTIONNAME)(m)  # Output: 12.0

not_a_measurement = 5.0
upper_invalid = $(FUNCTIONNAME)(not_a_measurement)  # Output: NaN
```
"""
function to_upper(m::Number)
	if m isa Measurement
		return Measurements.value(m) + Measurements.uncertainty(m)
	else
		return NaN
	end
end

"""
$(TYPEDSIGNATURES)

Computes the lower bound of a measurement value.

# Arguments

- `m`: A numerical value, expected to be of type `Measurement` from the `Measurements.jl` package.

# Returns

- The lower bound, computed as `value(m) - uncertainty(m)` if `m` is a `Measurement`.
- `NaN` if `m` is not a `Measurement`.

# Examples

```julia
using Measurements

m = 10.0 ± 2.0
lower = $(FUNCTIONNAME)(m)  # Output: 8.0

not_a_measurement = 5.0
lower_invalid = $(FUNCTIONNAME)(not_a_measurement)  # Output: NaN
```
"""
function to_lower(m::Number)
	if m isa Measurement
		return Measurements.value(m) - Measurements.uncertainty(m)
	else
		return NaN
	end
end

"""
$(TYPEDSIGNATURES)

Computes the percentage uncertainty of a measurement.

# Arguments

- `m`: A numerical value, expected to be of type `Measurement` from the `Measurements.jl` package.

# Returns

- The percentage uncertainty, computed as `100 * uncertainty(m) / value(m)`, if `m` is a `Measurement`.
- `NaN` if `m` is not a `Measurement`.

# Examples

```julia
using Measurements

m = 10.0 ± 2.0
percent_err = $(FUNCTIONNAME)(m)  # Output: 20.0

not_a_measurement = 5.0
percent_err_invalid = $(FUNCTIONNAME)(not_a_measurement)  # Output: NaN
```
"""
function percent_error(m::Number)
	if m isa Measurement
		return 100 * Measurements.uncertainty(m) / Measurements.value(m)
	else
		return NaN
	end
end

"""
$(TYPEDSIGNATURES)

Automatically exports public functions, types, and modules from a module.

# Arguments

- None.

# Returns

- An `export` expression containing all public symbols that should be exported.

# Notes

This macro scans the current module for all defined symbols and automatically generates an `export` statement for public functions, types, and submodules, excluding built-in and private names. Private names are considered those starting with an underscore ('_'), as per standard Julia conventions.
	
# Examples

```julia
@_autoexport
```
```julia
using ..Utils
# ...
Utils.@_autoexport
```
"""
macro _autoexport()
	mod = __module__

	# Get all names defined in the module, including unexported ones
	all_names = names(mod; all = true)

	# List of names to explicitly exclude
	excluded_names = Set([:eval, :include, :using, :import, :export, :require])

	# Filter out private names (starting with '_'), module name, built-in functions, and auto-generated method symbols
	public_names = Symbol[]
	for name in all_names
		str_name = string(name)

		startswith(str_name, "@_") && continue  # Skip private macros
		startswith(str_name, "_") && continue  # Skip private names
		name === nameof(mod) && continue  # Skip the module's own name
		name in excluded_names && continue  # Skip built-in functions
		startswith(str_name, "#") && continue  # Skip generated method symbols (e.g., #eval, #include)

		if isdefined(mod, name)
			val = getfield(mod, name)
			if val isa Function || val isa Type || val isa Module
				push!(public_names, name)
			end
		end
	end

	return esc(Expr(:export, public_names...))
end

@_autoexport

end
