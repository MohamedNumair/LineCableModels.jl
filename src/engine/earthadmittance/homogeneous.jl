abstract type Homogeneous <: EarthAdmittanceFormulation end

struct Kernel{Tγ1, Tγ2, Tμ2}
	"Layer where the source conductor is placed."
	s::Int
	"Layer where the target conductor is placed."
	t::Int
	"Primary field propagation constant (0 = lossless, 1 = air, 2 = earth)."
	Γx::Int
	"Air propagation constant γ₁(ω, μ, σ, ε)."
	γ1::Tγ1
	"Earth propagation constant γ₂(ω, μ, σ, ε)."
	γ2::Tγ2
	"Earth magnetic-constant assumption μ₂(μ)."
	μ2::Tμ2
end

struct Papadopoulos{Tγ1, Tγ2, Tμ2} <: Homogeneous
	kernel::Kernel{Tγ1, Tγ2, Tμ2}
end

Papadopoulos(; s::Int = 2, t::Int = 2, Γx::Int = 2,
	γ1 = (ω, μ, σ, ε) -> sqrt(1im * ω * μ * (σ + 1im*ω*ε)),
	γ2 = (ω, μ, σ, ε) -> sqrt(1im * ω * μ * (σ + 1im*ω*ε)),
	μ2 = μ -> μ) =
	Papadopoulos(
		Kernel{typeof(γ1), typeof(γ2), typeof(μ2)}(s, t, Γx, γ1, γ2, μ2),
	)

get_description(::Papadopoulos) = "Papadopoulos"
from_kernel(f::Papadopoulos) = f.kernel


struct Pollaczek{Tγ1, Tγ2, Tμ2} <: Homogeneous
	kernel::Kernel{Tγ1, Tγ2, Tμ2}
end

Pollaczek(; s::Int = 2, t::Int = 2, Γx::Int = 0,
	γ1 = (ω, μ, σ, ε) -> 1im * ω * sqrt(μ * ε),
	γ2 = (ω, μ, σ, ε) -> zero(1im * ω),
	μ2 = μ -> oftype(μ, μ₀)) =
	Pollaczek(
		Kernel{typeof(γ1), typeof(γ2), typeof(μ2)}(s, t, Γx, γ1, γ2, μ2),
	)

get_description(::Pollaczek) = "Pollaczek"
from_kernel(f::Pollaczek) = f.kernel

struct Images{Tγ1, Tγ2, Tμ2} <: Homogeneous
	kernel::Kernel{Tγ1, Tγ2, Tμ2}
end

Images(; s::Int = 1, t::Int = 1, Γx::Int = 0,
	γ1 = (ω, μ, σ, ε) -> 1im * ω * sqrt(μ * ε),
	γ2 = (ω, μ, σ, ε) -> zero(1im * ω),
	μ2 = μ -> oftype(μ, μ₀)) =
	Images(
		Kernel{typeof(γ1), typeof(γ2), typeof(μ2)}(s, t, Γx, γ1, γ2, μ2),
	)

get_description(::Images) = "Electrostatic images"
from_kernel(f::Images) = f.kernel

# ρ, ε, μ = ws.rho_g, ws.eps_g, ws.mu_g
#     f(h, d, @view(ρ[:,k]), @view(ε[:,k]), @view(μ[:,k]), ws.freq[k])

# Functor implementation for all homogeneous earth impedance formulations.
function (f::Homogeneous)(
	form::Symbol,
	h::AbstractVector{T},
	yij::T,
	rho_g::AbstractVector{T},
	eps_g::AbstractVector{T},
	mu_g::AbstractVector{T},
	freq::T,
) where {T <: REALSCALAR}
	Base.@nospecialize form
	return form === :self ? f(Val(:self), h, yij, rho_g, eps_g, mu_g, freq) :
		   form === :mutual ? f(Val(:mutual), h, yij, rho_g, eps_g, mu_g, freq) :
		   throw(ArgumentError("Unknown earth admittance form: $form"))
end

function (f::Homogeneous)(
	h::AbstractVector{T},
	yij::T,
	rho_g::AbstractVector{T},
	eps_g::AbstractVector{T},
	mu_g::AbstractVector{T},
	freq::T,
) where {T <: REALSCALAR}
	return f(Val(:mutual), h, yij, rho_g, eps_g, mu_g, freq)
end

@inline _to_σ(ρ) = isinf(ρ) ? zero(ρ) : (iszero(ρ) ? inv(zero(ρ)) : inv(ρ))
@inline _not(s::Int) =
	(s == 1 || s == 2) ? (3 - s) :
	throw(ArgumentError("s must be 1 or 2"))

@inline _get_layer(z) =
	z > 0 ? 1 :
	(z < 0 ? 2 : throw(ArgumentError("Conductor at interface (h=0) is invalid")))

@noinline function _layer_mismatch(which::AbstractString, got::Int, expected::Int)
	throw(
		ArgumentError(
			"conductor $which is in layer $got but formulation expects layer $expected",
		),
	)
end

@inline function validate_layers!(f::Homogeneous, h)
	@boundscheck length(h) == 2 || throw(ArgumentError("h must have length 2"))
	ℓ1 = _get_layer(h[1])
	ℓ2 = _get_layer(h[2])
	(ℓ1 == f.s) || _layer_mismatch("i (h[1])", ℓ1, f.s)
	(ℓ2 == f.t) || _layer_mismatch("j (h[2])", ℓ2, f.t)
	return nothing
end

@inline function _bessel_diff(γs, d::T, D::T) where {T}
	zmax = max(abs(γs)*d, abs(γs)*D)
	zmax < T(1e-6) ? log(D/d) : (besselk(0, γs*d) - besselk(0, γs*D))
end



@inline function (f::Homogeneous)(
	::Val{:mutual},
	h::AbstractVector{T},
	yij::T,
	rho_g::AbstractVector{T},
	eps_g::AbstractVector{T},
	mu_g::AbstractVector{T},
	freq::T,
) where {T <: REALSCALAR}

	validate_layers!(f, h)

	s = f.s # index of source layer
	o = _not(s) # the other layer
	ω = 2π*freq
	nL = length(rho_g)
	μ = similar(mu_g);
	σ = similar(rho_g);
	@inbounds for i in 1:nL
		μ[i] = (i == 1) ? mu_g[i] : f.μ2(mu_g[i]) # μ₂ for earth layers
		σ[i] = _to_σ(rho_g[i])
	end

	# construct propagation constants according to formulation assumptions
	γ = Vector{Complex{T}}(undef, nL)
	@inbounds for i in 1:nL
		γ[i] = (i == 1 ? f.γ1 : f.γ2)(ω, μ[i], σ[i], eps_g[i])
	end
	γ_s = γ[s];
	γ_o = γ[o]
	γs_2 = γ_s^2
	γo_2 = γ_o^2

	# kx from struct: 0:none, 1:air, 2:source layer
	kx_2 = if f.Γx == 0 # precalc squared
		zero(γs_2)
	else
		ℓ = (f.Γx == 1) ? 1 : s
		oftype(γs_2, (ω^2) * μ[ℓ] * eps_g[ℓ])
	end

	# --- Underground,"no capacitive coupling" ---
	# physics: source in EARTH (s=t=2), kx = 0, γ_earth ≈ 0
	# ⇒ Pe = 0
	if f.s == 2 && f.t == 2 && isapprox(γ_s, zero(γ_s))
		return zero(Complex{T})
	end

	# unpack geometry
	@inbounds hi, hj = abs(h[1]), abs(h[2])
	dij = hypot(yij, hi - hj)          # √(y^2 + (hi - hj)^2) - conductor-conductor
	Dij = hypot(yij, hi + hj)          # √(y^2 + (hi + hj)^2) - conductor-image

	# perfectly conducting earth term in Bessel form
	Λij = _bessel_diff(γ_s, dij, Dij)

	# --- Overhead special case ---
	# physics: source in AIR (s=t=1), kx = 0, σ_air ≈ 0,
	#          earth propagation constant negligible γ_earth ≈ 0
	# ⇒ Sij = Tij = 0, Pe = (jω)/(2π(σ_air+jωε_air)) * Λ ≡ (1/(2π ε0)) * Λ
	if f.s == 1 && f.Γx == 0 && isapprox(γ_o, zero(γ_o))
		return (1im*ω) / (2π*eps_g[1]) * Λij
	end

	# precompute scalars for integrand
	a_s = (λ::T) -> sqrt(λ^2 + γs_2 + kx_2)
	a_o = (λ::T) -> sqrt(λ^2 + γo_2 + kx_2)
	μ_s = μ[s]
	μ_o = μ[o]
	H = hi + hj

	# earth correction term
	Fij = (λ) -> begin
		as = a_s(λ);
		ao = a_o(λ)
		μ_o * exp(-as * H) / (as*μ_o + ao*μ_s)
	end

	# G_ij(λ) 
	# G = μ0 μ1 α1 (γ1² - γ0²) e^{-α1 H} / [ (α1 μ0 + α0 μ1)(α1 γ0² μ1 + α0 γ1² μ0) ]
	# here: 0→other (o), 1→source (s)
	Gij = (λ) -> begin
		as = a_s(λ);
		ao = a_o(λ)
		num = μ_o * μ_s * as * (γs_2 - γo_2) * exp(-as * H)
		den = (as*μ_o + ao*μ_s) * (as*γo_2*μ_s + ao*γs_2*μ_o)
		num / den
	end

	# S_ij + T_ij in one go: 2∫₀^∞ (Fij+Gij) cos(yij λ) dλ
	integrand = (λ) -> (Fij(λ) + Gij(λ)) * cos(yij * λ)
	Iij, _ = quadgk(integrand, 0.0, Inf; rtol = 1e-8)
	Iij *= 2

	_σ_s = σ[s] + 1im*ω*eps_g[s] # complex conductivity of source layer

	return (1im * ω / (2π * _σ_s)) * (Λij + Iij)

end
