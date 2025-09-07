
struct ScaledBessel <: InternalImpedanceFormulation end
get_description(::ScaledBessel) = "Scaled Bessel (Schelkunoff)"


@inline function (f::ScaledBessel)(
	form::Symbol, r_in::T, r_ex::T, rho_c::T, mur_c::T, freq::T,
) where {T <: REALSCALAR}
	Base.@nospecialize form
	return form === :inner  ? f(Val(:inner), r_in, r_ex, rho_c, mur_c, freq)  :
		   form === :outer  ? f(Val(:outer), r_in, r_ex, rho_c, mur_c, freq)  :
		   form === :mutual ? f(Val(:mutual), r_in, r_ex, rho_c, mur_c, freq) :
		   throw(ArgumentError("Unknown ScaledBessel form: $form"))
end

@inline function (f::ScaledBessel)(
	::Val{:inner}, r_in::T, r_ex::T, rho_c::T, mur_c::T, freq::T,
) where {T <: REALSCALAR}
	# Constants
	mu_c = T(μ₀) * mur_c
	ω = 2π * freq
	sigma_c = 1/rho_c

	# Calculate the reciprocal of the skin depth
	m = sqrt(im * ω * mu_c * sigma_c)
	w_ex = m * r_ex

	if r_in > 0

		w_in = m * r_in

		s_in = exp(abs(real(w_in)) - w_ex)
		s_ex = exp(abs(real(w_ex)) - w_in)
		sc = s_in / s_ex

		# Bessel function terms with uncertainty handling
		N = (besselix(1, w_ex)) * (besselkx(0, w_in))
		+ sc *
		(besselix(0, w_in)) * (besselkx(1, w_ex))

		D = (besselix(1, w_ex)) * (besselkx(1, w_in))
		- sc *
		(besselix(1, w_in)) * (besselkx(1, w_ex))

	else
		return zero(Complex{T}) # not physical, but consistent with :outer - algorithmic shortcut for solids/tubular blending
	end

	return Complex{T}((im * ω * mu_c / (2π * w_in)) * (N / D))
end

@inline function (f::ScaledBessel)(
	::Val{:outer}, r_in::T, r_ex::T, rho_c::T, mur_c::T, freq::T,
) where {T <: REALSCALAR}
	# Constants
	mu_c = T(μ₀) * mur_c
	ω = 2π * freq
	sigma_c = 1/rho_c

	# Calculate the reciprocal of the skin depth
	m = sqrt(im * ω * mu_c * sigma_c)
	w_ex = m * r_ex

	if r_in > 0

		w_in = m * r_in

		s_in = exp(abs(real(w_in)) - w_ex)
		s_ex = exp(abs(real(w_ex)) - w_in)
		sc = s_in / s_ex

		# Bessel function terms with uncertainty handling
		N = (besselix(0, w_ex)) * (besselkx(1, w_in))
		+ sc *
		(besselix(1, w_in)) * (besselkx(0, w_ex))

		D = (besselix(1, w_ex)) * (besselkx(1, w_in))
		- sc *
		(besselix(1, w_in)) * (besselkx(1, w_ex))

	else
		N = besselix(0, w_ex)
		D = besselix(1, w_ex)
	end

	return Complex{T}((im * ω * mu_c / (2π * w_ex)) * (N / D))
end

@inline function (f::ScaledBessel)(
	::Val{:mutual}, r_in::T, r_ex::T, rho_c::T, mur_c::T, freq::T,
) where {T <: REALSCALAR}
	# Constants
	mu_c = T(μ₀) * mur_c
	ω = 2π * freq
	sigma_c = 1/rho_c

	# Calculate the reciprocal of the skin depth
	m = sqrt(im * ω * mu_c * sigma_c)
	w_ex = m * r_ex

	if r_in > 0

		w_in = m * r_in

		s_in = exp(abs(real(w_in)) - w_ex)
		s_ex = exp(abs(real(w_ex)) - w_in)
		sc = s_in / s_ex

		# Bessel function terms with uncertainty handling
		N = 1.0 / s_ex

		D = (besselix(1, w_ex)) * (besselkx(1, w_in))
		- sc *
		(besselix(1, w_in)) * (besselkx(1, w_ex))

	else
		return zero(Complex{T}) # not physical, but consistent with :outer - algorithmic shortcut for solids/tubular blending
	end

	return Complex{T}((1.0 / (2π * r_in * r_ex * sigma_c)) * (N / D))
end
