struct Lossless <: InsulationAdmittanceFormulation end
get_description(::Lossless) = "Lossless insulation (ideal dielectric)"

@inline function (f::Lossless)(r_in::T, r_ex::T, epsr_i::T, freq::T
) where {T <: REALSCALAR}

	if r_ex == r_in
		# TODO: Implement consistent handling of admittance for bare conductors
		# Issue URL: https://github.com/Electa-Git/LineCableModels.jl/issues/17
		return zero(Complex{T})
	end

	# Constants
	# ω = 2π * freq
	eps_i = T(ε₀) * epsr_i


	return Complex{T}(log(r_ex / r_in) / (2π * eps_i))
end
