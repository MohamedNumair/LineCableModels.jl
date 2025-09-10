"""
	LineCableModels.Engine.InternalImpedance

# Dependencies

$(IMPORTS)

# Exports

$(EXPORTS)
"""
module InternalImpedance

# Export public API
export ScaledBessel, SimpleSkin, DeriSkin

# Module-specific dependencies
using ...Commons
import ...Commons: get_description
import ..Engine: InternalImpedanceFormulation
using Measurements
using LinearAlgebra
using ...UncertainBessels: besselix, besselkx

include("scaledbessel.jl")
include("simpleskin.jl")
include("deriskin.jl")

function loop_to_phase(
	Z::Matrix{Complex{T}},
) where {T <: REALSCALAR}
	# Check the size of the Z matrix (assuming Z is NxN)
	N = size(Z, 1)

	# Build the voltage transformation matrix T_V
	T_V = Matrix{T}(I, N, N + 1)  # Start with an identity matrix
	for i ∈ 1:N
		T_V[i, i+1] = -1  # Set the -1 in the next column
	end
	T_V = T_V[:, 1:N]  # Remove the last column

	# Build the current transformation matrix T_I
	T_I = tril(ones(T, N, N))  # Lower triangular matrix of ones

	# Compute the new impedance matrix Z_prime
	Z_prime = T_V \ Z * T_I

	return Z_prime
end

end # module InternalImpedance

