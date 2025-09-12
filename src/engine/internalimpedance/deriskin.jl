using ...UncertainBessels
"""
    DeriSkin

Skin-effect internal impedance using Deri approximation with modified Bessel ratio I0/I1.
Z_int ≈ R_dc + (α R_dc / 2) * (I0(α)/I1(α)) where α = sqrt(j ω μ / (π R_dc)).
For large |α|, I0/I1 → 1.
"""
struct DeriSkin <: InternalImpedanceFormulation end
get_description(::DeriSkin) = "Deri Skin Internal"

@inline function (f::DeriSkin)(form::Symbol, r_in::T, r_ex::T, rho_c::T, mur_c::T, freq::T) where {T<:REALSCALAR}
    Base.@nospecialize form
    return form === :inner  ? f(Val(:inner), r_in, r_ex, rho_c, mur_c, freq) :
           form === :outer  ? f(Val(:outer), r_in, r_ex, rho_c, mur_c, freq) :
           form === :mutual ? f(Val(:mutual), r_in, r_ex, rho_c, mur_c, freq) :
           throw(ArgumentError("Unknown DeriSkin form: $form"))
end

@inline (::DeriSkin)(::Val{:inner}, r_in::T, r_ex::T, rho_c::T, mur_c::T, freq::T) where {T<:REALSCALAR} = _deri_internal(r_in, r_ex, rho_c, mur_c, freq)
@inline (::DeriSkin)(::Val{:outer}, r_in::T, r_ex::T, rho_c::T, mur_c::T, freq::T) where {T<:REALSCALAR} = _deri_internal(r_in, r_ex, rho_c, mur_c, freq)
@inline (::DeriSkin)(::Val{:mutual}, r_in::T, r_ex::T, rho_c::T, mur_c::T, freq::T) where {T<:REALSCALAR} = zero(Complex{T})

@inline function _deri_internal(r_in::T, r_ex::T, rho_c::T, mur_c::T, freq::T) where {T<:REALSCALAR}
    iszero(rho_c) && return zero(Complex{T})
    # Estimate R_dc per unit length from solid/tubular geometry (Ω/m)
    # If hollow (r_in>0) use annulus area
    A = r_in > 0 ? (π*(r_ex^2 - r_in^2)) : (π*r_ex^2)
    Rdc = rho_c / A
    ω = 2π*freq
    mu_c = T(μ₀)*mur_c
    α = sqrt((im*ω*mu_c)/(π*Rdc))
    ratio = if abs(α) > 35
        one(α)
    else
        i0 = besseli(0, α); i1 = besseli(1, α)
        iszero(i1) ? one(α) : (i0/i1)
    end
    return Complex{T}(Rdc) + (α*Rdc*ratio)/2
end
