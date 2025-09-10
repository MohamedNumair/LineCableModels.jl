"""
    FullCarson

Series expansion form of Carson's earth return impedance (self & mutual) using classic coefficients.
Implementation adapted for quick analytical comparisons; assumes homogeneous earth (use last layer resistivity).
"""
struct FullCarson <: EarthImpedanceFormulation end
get_description(::FullCarson) = "Full Carson Earth"

@inline function (f::FullCarson)(form::Symbol, h::AbstractVector{T}, yij::T, rho_g::AbstractVector{T}, eps_g::AbstractVector{T}, mu_g::AbstractVector{T}, freq::T) where {T<:REALSCALAR}
    Base.@nospecialize form
    return form === :self ? f(Val(:self), h, yij, rho_g, eps_g, mu_g, freq) :
           form === :mutual ? f(Val(:mutual), h, yij, rho_g, eps_g, mu_g, freq) :
           throw(ArgumentError("Unknown FullCarson form: $form"))
end

@inline function (f::FullCarson)(::Val{:self}, h::AbstractVector{T}, yij::T, rho_g::AbstractVector{T}, eps_g::AbstractVector{T}, mu_g::AbstractVector{T}, freq::T) where {T<:REALSCALAR}
    ω = 2π*freq; μ0 = T(μ₀); ρ = last(rho_g)
    # geometry
    dij = 2abs(h[1])
    m = (sqrt(T(2))/T(503))*dij*sqrt(freq/ρ)  # classic Carson m
    b1 = 1/(3*sqrt(T(2))); b2 = 1/16; b3 = b1/(15); b4 = b2/(24); d2 = b2*π/4; d4 = b4*π/4
    c2 = T(1.3659315); c4 = c2 + 1/4 + 1/6
    re = π/8 - b1*m + b2*m^2*(log(exp(c2)/m)) + b3*m^3 - d4*m^4
    im_part = 0.5*log(1.85138/m) + b1*m - d2*m^2 + b3*m^3 - b4*m^4*(log(exp(c4)/m))
    im_part += 0.5*log(dij)
    return (ω*μ0/π)*(re + im*im_part)
end

@inline function (f::FullCarson)(::Val{:mutual}, h::AbstractVector{T}, yij::T, rho_g::AbstractVector{T}, eps_g::AbstractVector{T}, mu_g::AbstractVector{T}, freq::T) where {T<:REALSCALAR}
    # Use simple Carson mutual (can refine with series terms if needed)
    ω = 2π*freq; μ0 = T(μ₀)
    hi, hj = abs(h[1]), abs(h[2])
    d  = hypot(yij, hi - hj)
    d′ = hypot(yij, hi + hj)
    return im*(ω*μ0/(2π))*log(d′/d)
end
