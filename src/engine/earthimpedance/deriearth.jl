"""
    DeriEarth

Deri model earth return impedance using complex penetration depth.
Self: Z_e = j ω μ₀ /(2π) * log(2(h + 1/p)) with p = sqrt(j ω μ₀ / ρ).
Mutual: replace 2h with H = h_i + h_j + 2/p and include horizontal separation.
"""
struct DeriEarth <: EarthImpedanceFormulation end
get_description(::DeriEarth) = "Deri Earth"

@inline function (f::DeriEarth)(form::Symbol, h::AbstractVector{T}, yij::T, rho_g::AbstractVector{T}, eps_g::AbstractVector{T}, mu_g::AbstractVector{T}, freq::T) where {T<:REALSCALAR}
    Base.@nospecialize form
    return form === :self ? f(Val(:self), h, yij, rho_g, eps_g, mu_g, freq) :
           form === :mutual ? f(Val(:mutual), h, yij, rho_g, eps_g, mu_g, freq) :
           throw(ArgumentError("Unknown DeriEarth form: $form"))
end

@inline function (f::DeriEarth)(::Val{:self}, h::AbstractVector{T}, yij::T, rho_g::AbstractVector{T}, eps_g::AbstractVector{T}, mu_g::AbstractVector{T}, freq::T) where {T<:REALSCALAR}
    ω = 2π*freq; μ0 = T(μ₀); ρ = last(rho_g)
    p = sqrt(im*ω*μ0/ρ)
    hi = abs(h[1])
    return (im*ω*μ0/(2π))*log(2*(hi + 1/p))
end

@inline function (f::DeriEarth)(::Val{:mutual}, h::AbstractVector{T}, yij::T, rho_g::AbstractVector{T}, eps_g::AbstractVector{T}, mu_g::AbstractVector{T}, freq::T) where {T<:REALSCALAR}
    ω = 2π*freq; μ0 = T(μ₀); ρ = last(rho_g)
    p = sqrt(im*ω*μ0/ρ)
    hi, hj = abs(h[1]), abs(h[2])
    H = hi + hj + 2/p
    return (im*ω*μ0/(2π))*log(hypot(yij, H))
end
