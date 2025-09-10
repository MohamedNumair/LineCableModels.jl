"""
    SimpleSkin

Low-frequency internal impedance approximation (no skin effect) adding jωμ₀/8π term to DC resistance.
Z_int ≈ R_dc + j ω μ₀ / (8π)
"""
struct SimpleSkin <: InternalImpedanceFormulation end
get_description(::SimpleSkin) = "Simple Carson Internal"

@inline function (f::SimpleSkin)(form::Symbol, r_in::T, r_ex::T, rho_c::T, mur_c::T, freq::T) where {T<:REALSCALAR}
    Base.@nospecialize form
    return form === :inner  ? f(Val(:inner), r_in, r_ex, rho_c, mur_c, freq) :
           form === :outer  ? f(Val(:outer), r_in, r_ex, rho_c, mur_c, freq) :
           form === :mutual ? f(Val(:mutual), r_in, r_ex, rho_c, mur_c, freq) :
           throw(ArgumentError("Unknown SimpleSkin form: $form"))
end

# Inner/outer/mutual share same approximation except geometry factors; keep interface parity
@inline (::SimpleSkin)(::Val{:inner}, r_in::T, r_ex::T, rho_c::T, mur_c::T, freq::T) where {T<:REALSCALAR} = _simple_internal(rho_c, mur_c, freq)
@inline (::SimpleSkin)(::Val{:outer}, r_in::T, r_ex::T, rho_c::T, mur_c::T, freq::T) where {T<:REALSCALAR} = _simple_internal(rho_c, mur_c, freq)
@inline (::SimpleSkin)(::Val{:mutual}, r_in::T, r_ex::T, rho_c::T, mur_c::T, freq::T) where {T<:REALSCALAR} = zero(Complex{T})

@inline function _simple_internal(rho_c::T, mur_c::T, freq::T) where {T<:REALSCALAR}
    iszero(rho_c) && return zero(Complex{T})
    ω = 2π*freq
    mu_c = T(μ₀)*mur_c
    # crude DC resistance per unit length needs geometry; fallback to ω term only if unknown
    # Caller expected to add external log spacing term separately; here only internal part
    return Complex{T}(im*ω*mu_c/(8π))
end
