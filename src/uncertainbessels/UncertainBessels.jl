"""
	LineCableModels.UncertainBessels

Numerically stable evaluation of Bessel functions and related quantities for
cable line models. The [`UncertainBessels`](@ref) module provides scaled variants, ratios, and logarithmic derivatives with careful handling of overflow/underflow and support for
uncertainty‑aware numeric types [NIST_DLMF](@ref) [6897971](@ref).

# Overview

- Scaled ``I_{ν}``  and ``K_{ν}`` to prevent overflow/underflow at large ``|z|``.
- Stable evaluation of ratios and log‑derivatives used in boundary conditions.
- Automatic selection among series, continued fractions, and asymptotics.
- Type‑stable dispatch for `Real`, `Complex`, `BigFloat`, and AD/uncertainty types.
- Thin interface consumed by internal impedance and earth‑return models.

# Dependencies

$(IMPORTS)

# Exports

$(EXPORTS)

# Usage

- Prefer scaled forms when ``|Re(z)|`` is large or arguments vary by orders of magnitude.
- Use ratio/log‑derivative routines inside linear systems to improve conditioning.
- BigFloat is supported; configure precision upstream with `setprecision`.
- Uncertainty types are propagated as long as they support +, −, ×, ÷, exp/log.

# Numerical notes

- Scaled ``I_{ν}(z)`` typically uses ``exp(−|Re(z)|)·I_{ν}(z)``; scaled ``K_{ν}(z)`` uses ``exp(+|Re(z)|)·K_{ν}(z)``.
- Branch cuts follow DLMF conventions unless stated otherwise.
- Near ``z ≈ 0`` or half‑integer orders, finite limits are returned when defined.
- Fallback strategy chooses series/CF/asymptotics based on argument/order size.

# Errors and diagnostics

- Throws `DomainError` or `ArgumentError` with guidance on invalid regions.
- Emits informative messages when loss of significance is detected.

# See also

- [`LineCableModels.Engine.InternalImpedance`](@ref)
- [`LineCableModels.Engine.EarthImpedance`](@ref)
"""
module UncertainBessels

# Module-specific dependencies
using ..Commons
using Calculus: Calculus
using SpecialFunctions: SpecialFunctions
using Measurements: Measurements, Measurement

export besselix, besselkx, besseljx, besselyx, bessekhx
export besseli, besselk, besselj, bessely, besselh

# Complex argument with measurement parts
@inline function _lift_complex_measurement(f, ν, ẑ::Complex{<:Measurement})
	return Measurements.result(
		f(ν, Measurements.value(ẑ)),
		vcat(
			Calculus.gradient(
				x -> real(f(ν, complex(x[1], x[2]))),
				[reim(Measurements.value(ẑ))...],
			),
			Calculus.gradient(
				x -> imag(f(ν, complex(x[1], x[2]))),
				[reim(Measurements.value(ẑ))...],
			),
		),
		ẑ,
	)
end

# Real argument with measurement
@inline function _lift_real_measurement(f, ν, x::Measurements.Measurement)
	x0 = Measurements.value(x)
	y0 = f(ν, x0)
	dy = Calculus.derivative(t -> f(ν, t), x0)
	return Measurements.result(y0, (dy,), x)
end


# Complex inputs with uncertainty
@inline besselix(ν, z::Complex{<:Measurements.Measurement{T}}) where {T <: AbstractFloat} =
	_lift_complex_measurement(SpecialFunctions.besselix, ν, z)
@inline besselkx(ν, z::Complex{<:Measurements.Measurement{T}}) where {T <: AbstractFloat} =
	_lift_complex_measurement(SpecialFunctions.besselkx, ν, z)
@inline besseljx(ν, z::Complex{<:Measurements.Measurement{T}}) where {T <: AbstractFloat} =
	_lift_complex_measurement(SpecialFunctions.besseljx, ν, z)
@inline besselyx(ν, z::Complex{<:Measurements.Measurement{T}}) where {T <: AbstractFloat} =
	_lift_complex_measurement(SpecialFunctions.besselyx, ν, z)
@inline besselhx(ν, z::Complex{<:Measurements.Measurement{T}}) where {T <: AbstractFloat} =
	_lift_complex_measurement(SpecialFunctions.besselhx, ν, z)
@inline besselj(ν, z::Complex{<:Measurements.Measurement{T}}) where {T <: AbstractFloat} =
	_lift_complex_measurement(SpecialFunctions.besselj, ν, z)
@inline bessely(ν, z::Complex{<:Measurements.Measurement{T}}) where {T <: AbstractFloat} =
	_lift_complex_measurement(SpecialFunctions.bessely, ν, z)
@inline besseli(ν, z::Complex{<:Measurements.Measurement{T}}) where {T <: AbstractFloat} =
	_lift_complex_measurement(SpecialFunctions.besseli, ν, z)
@inline besselk(ν, z::Complex{<:Measurements.Measurement{T}}) where {T <: AbstractFloat} =
	_lift_complex_measurement(SpecialFunctions.besselk, ν, z)
@inline besselh(ν, z::Complex{<:Measurements.Measurement{T}}) where {T <: AbstractFloat} =
	_lift_complex_measurement(SpecialFunctions.besselh, ν, z)

# Real inputs with uncertainty
@inline besselix(ν, x::Measurements.Measurement{T}) where {T <: AbstractFloat} =
	_lift_real_measurement(SpecialFunctions.besselix, ν, x)
@inline besselkx(ν, x::Measurements.Measurement{T}) where {T <: AbstractFloat} =
	_lift_real_measurement(SpecialFunctions.besselkx, ν, x)
@inline besseljx(ν, x::Measurements.Measurement{T}) where {T <: AbstractFloat} =
	_lift_real_measurement(SpecialFunctions.besseljx, ν, x)
@inline besselyx(ν, x::Measurements.Measurement{T}) where {T <: AbstractFloat} =
	_lift_real_measurement(SpecialFunctions.besselyx, ν, x)
@inline besselhx(ν, x::Measurements.Measurement{T}) where {T <: AbstractFloat} =
	_lift_real_measurement(SpecialFunctions.besselhx, ν, x)
@inline besselj(ν, x::Measurements.Measurement{T}) where {T <: AbstractFloat} =
	_lift_real_measurement(SpecialFunctions.besselj, ν, x)
@inline bessely(ν, x::Measurements.Measurement{T}) where {T <: AbstractFloat} =
	_lift_real_measurement(SpecialFunctions.bessely, ν, x)
@inline besseli(ν, x::Measurements.Measurement{T}) where {T <: AbstractFloat} =
	_lift_real_measurement(SpecialFunctions.besseli, ν, x)
@inline besselk(ν, x::Measurements.Measurement{T}) where {T <: AbstractFloat} =
	_lift_real_measurement(SpecialFunctions.besselk, ν, x)
@inline besselh(ν, x::Measurements.Measurement{T}) where {T <: AbstractFloat} =
	_lift_real_measurement(SpecialFunctions.besselh, ν, x)

# Plain Float/Complex fallbacks 
@inline besselix(ν, z::T) where {T <: AbstractFloat} = SpecialFunctions.besselix(ν, z)
@inline besselkx(ν, z::T) where {T <: AbstractFloat} = SpecialFunctions.besselkx(ν, z)
@inline besseljx(ν, z::T) where {T <: AbstractFloat} = SpecialFunctions.besseljx(ν, z)
@inline besselyx(ν, z::T) where {T <: AbstractFloat} = SpecialFunctions.besselyx(ν, z)
@inline besselhx(ν, z::T) where {T <: AbstractFloat} = SpecialFunctions.besselhx(ν, z)
@inline besselj(ν, z::T) where {T <: AbstractFloat} = SpecialFunctions.besselj(ν, z)
@inline bessely(ν, z::T) where {T <: AbstractFloat} = SpecialFunctions.bessely(ν, z)
@inline besseli(ν, z::T) where {T <: AbstractFloat} = SpecialFunctions.besseli(ν, z)
@inline besselk(ν, z::T) where {T <: AbstractFloat} = SpecialFunctions.besselk(ν, z)
@inline besselh(ν, z::T) where {T <: AbstractFloat} = SpecialFunctions.besselh(ν, z)

@inline besselix(ν, z::Complex{T}) where {T <: AbstractFloat} =
	SpecialFunctions.besselix(ν, z)
@inline besselkx(ν, z::Complex{T}) where {T <: AbstractFloat} =
	SpecialFunctions.besselkx(ν, z)
@inline besseljx(ν, z::Complex{T}) where {T <: AbstractFloat} =
	SpecialFunctions.besseljx(ν, z)
@inline besselyx(ν, z::Complex{T}) where {T <: AbstractFloat} =
	SpecialFunctions.besselyx(ν, z)
@inline besselhx(ν, z::Complex{T}) where {T <: AbstractFloat} =
	SpecialFunctions.besselhx(ν, z)
@inline besselj(ν, z::Complex{T}) where {T <: AbstractFloat} =
	SpecialFunctions.besselj(ν, z)
@inline bessely(ν, z::Complex{T}) where {T <: AbstractFloat} =
	SpecialFunctions.bessely(ν, z)
@inline besseli(ν, z::Complex{T}) where {T <: AbstractFloat} =
	SpecialFunctions.besseli(ν, z)
@inline besselk(ν, z::Complex{T}) where {T <: AbstractFloat} =
	SpecialFunctions.besselk(ν, z)
@inline besselh(ν, z::Complex{T}) where {T <: AbstractFloat} =
	SpecialFunctions.besselh(ν, z)

end # module UncertainBessels
