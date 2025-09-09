abstract type Homogeneous <: EarthImpedanceFormulation end

get_description(::Homogeneous) = "Homogeneous earth (general model)"

Base.@kwdef struct Papadopoulos <: Homogeneous
	"Layer where the source conductor is placed."
	s::Int = 2
	"Layer where the target conductor is placed."
	t::Int = 2
	"Source propagation constant (0 = lossless, 1 = air, 2 = earth)."
	source_kx::Int = 2
	"Earth displacement current assumption."
	use_earth_eps::Bool = true
end
get_description(::Papadopoulos) = "Papadopoulos"

# ρ, ε, μ = ws.rho_g, ws.eps_g, ws.mu_g
#     f(h, d, @view(ρ[:,k]), @view(ε[:,k]), @view(μ[:,k]), ws.freq[k])

function (f::Homogeneous)(
	form::Symbol,
	h::AbstractVector{T},
	d::AbstractVector{T},
	rho_g::AbstractVector{T},
	eps_g::AbstractVector{T},
	mu_g::AbstractVector{T},
	freq::T,
) where {T <: REALSCALAR}
	Base.@nospecialize form
	return form === :self ? f(Val(:self), h, d, rho_g, eps_g, mu_g, freq) :
		   form === :mutual ? f(Val(:mutual), h, d, rho_g, eps_g, mu_g, freq) :
		   throw(ArgumentError("Unknown earth impedance form: $form"))
end

@inline _jT(::Type{T}) where {T} = complex(zero(T), one(T))          # 0+1im in Complex{T}
@inline _ω(f::T) where {T} = T(2π) * f
@inline _σ(ρ::T) where {T} =
	isinf(ρ) ? zero(T) : (iszero(ρ) ? (one(T)/zero(T)) : inv(ρ)) # ∞→0, 0→∞
@inline _ε_eff(f::Homogeneous, ℓ::Int, ε::AbstractVector{T}) where {T} =
	(ℓ == 1) ? ε[ℓ] : (f.use_earth_eps ? ε[ℓ] : zero(T)) # keep air ε, toggle earth ε

@inline function _γ(f::Homogeneous, ℓ::Int,
	μ::AbstractVector{T}, ε::AbstractVector{T}, ρ::AbstractVector{T}, ω::T) where {T}
	j = _jT(T)
	σ = _σ(ρ[ℓ])
	εeff = _ε_eff(f, ℓ, ε)
	return sqrt(j * ω * μ[ℓ] * (σ + j*ω*εeff))
end

@inline function _kx(f::Homogeneous,
	ρ::AbstractVector{T}, ε::AbstractVector{T},
	μ::AbstractVector{T}, ω::T) where {T}
	j = _jT(T)
	if f.source_kx == 0 # lossless
		return complex(zero(T), zero(T))
	end
	ℓ = (f.source_kx == 1) ? 1 : f.s                    # 1=air, 2=(source layer)
	σℓ = _σ(ρ[ℓ])
	εℓ = _ε_eff(f, ℓ, ε)
	return ω * sqrt(μ[ℓ] * (εℓ - j*(σℓ/ω)))  # Complex{T}
end

@inline _a(λ::T, γ::T, kx::Complex{T}) where {T} = sqrt(λ^2 + γ^2 + kx^2)

@inline function (f::Homogeneous)(
	::Val{:mutual}, h::AbstractVector{T},
	d::AbstractVector{T},
	rho_g::AbstractVector{T},
	eps_g::AbstractVector{T},
	mu_g::AbstractVector{T},
	freq::T,
) where {T <: REALSCALAR}

end