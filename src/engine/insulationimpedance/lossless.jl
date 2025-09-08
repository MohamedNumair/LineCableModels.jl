
struct Lossless <: InsulationImpedanceFormulation end
get_description(::Lossless) = "Lossless insulation (ideal dielectric)"

@inline function (f::Lossless)(r_in::T, r_ex::T, mur_i::T, freq::T
) where {T <: REALSCALAR}

	if r_ex == r_in
		# TODO: Implement consistent handling of admittance for bare conductors
		# Issue URL: https://github.com/Electa-Git/LineCableModels.jl/issues/18
		return zero(Complex{T})
	end

	# Constants
	mu_i = T(μ₀) * mur_i
	ω = 2π * freq

	return Complex{T}(im * ω * mu_i * log(r_ex / r_in) / 2π)
end