"""
    SimpleCarson

Simplified Carson earth return impedance (frequency-dependent logarithmic term only).
Self: Z_e ≈ ω μ₀ /8 + j (ω μ₀ / (2π)) * log( K * sqrt(ρ/f) ) with K≈658.5 (legacy constant)
Mutual: j (ω μ₀ /(2π)) log(D'/D)
"""
struct SimpleCarson <: EarthImpedanceFormulation end
get_description(::SimpleCarson) = "Simple Carson Earth"

@inline function (f::SimpleCarson)(form::Symbol, h::AbstractVector{T}, yij::T, rho_g::AbstractVector{T}, eps_g::AbstractVector{T}, mu_g::AbstractVector{T}, freq::T) where {T<:REALSCALAR}
    Base.@nospecialize form
    return form === :self ? f(Val(:self), h, yij, rho_g, eps_g, mu_g, freq) :
           form === :mutual ? f(Val(:mutual), h, yij, rho_g, eps_g, mu_g, freq) :
           throw(ArgumentError("Unknown SimpleCarson form: $form"))
end

@inline function (f::SimpleCarson)(::Val{:self}, h::AbstractVector{T}, yij::T, rho_g::AbstractVector{T}, eps_g::AbstractVector{T}, mu_g::AbstractVector{T}, freq::T) where {T<:REALSCALAR}
    ω = 2π*freq
    μ0 = T(μ₀)
    ρ = last(rho_g) # assume last layer earth
    return Complex{T}(ω*μ0/8) + im*(ω*μ0/(2π))*log(T(658.5)*sqrt(ρ/freq))
end

@inline function (f::SimpleCarson)(::Val{:mutual}, h::AbstractVector{T}, yij::T, rho_g::AbstractVector{T}, eps_g::AbstractVector{T}, mu_g::AbstractVector{T}, freq::T) where {T<:REALSCALAR}
    ω = 2π*freq
    μ0 = T(μ₀)
    hi, hj = abs(h[1]), abs(h[2])
    d  = hypot(yij, hi - hj)
    d′ = hypot(yij, hi + hj)
    return im*(ω*μ0/(2π))*log(d′/d)
end
