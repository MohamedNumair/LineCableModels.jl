struct SeriesImpedance{T} <: AbstractArray{T, 3}
	values::Array{T, 3}   # n×n×nfreq, units: Ω/m
end

struct ShuntAdmittance{T} <: AbstractArray{T, 3}
	values::Array{T, 3}   # n×n×nfreq, units: S/m
end

"""
$(TYPEDEF)

Represents the frequency-dependent line parameters (series impedance and shunt admittance matrices) for a cable or line system.

$(TYPEDFIELDS)
"""
struct LineParameters{T <: REALSCALAR}
	"Series impedance matrices \\[Ω/m\\]."
	Z::SeriesImpedance{Complex{T}}
	"Shunt admittance matrices \\[S/m\\]."
	Y::ShuntAdmittance{Complex{T}}
	"Frequencies \\[Hz\\]."
	f::Vector{T}

	@doc """
	$(TYPEDSIGNATURES)

	Constructs a [`LineParameters`](@ref) instance.

	# Arguments

	- `Z`: Series impedance matrices \\[Ω/m\\].
	- `Y`: Shunt admittance matrices \\[S/m\\].
	- `f`: Frequencies \\[Hz\\].

	# Returns

	- A [`LineParameters`](@ref) object with prelocated impedance and admittance matrices for a given frequency range.

	# Examples

	```julia
	params = $(FUNCTIONNAME)(Z, Y, f)
	```
	"""
	function LineParameters(
		Z::SeriesImpedance{Complex{T}},
		Y::ShuntAdmittance{Complex{T}},
		f::Vector{T},
	) where {T <: REALSCALAR}
		size(Z, 1) == size(Z, 2) || throw(DimensionMismatch("Z must be square"))
		size(Y, 1) == size(Y, 2) || throw(DimensionMismatch("Y must be square"))
		size(Z, 3) == size(Y, 3) == length(f) ||
			throw(DimensionMismatch("Z and Y must have same dimensions (n×n×nfreq)"))
		new{T}(Z, Y, f)
	end
end

SeriesImpedance(A::AbstractArray{T, 3}) where {T} = SeriesImpedance{T}(Array(A))
ShuntAdmittance(A::AbstractArray{T, 3}) where {T} = ShuntAdmittance{T}(Array(A))

# Convenience ctor for LineParameters from raw arrays
function LineParameters(
	Z::Array{T, 3},
	Y::Array{T, 3},
	f::AbstractVector{<:Real},
) where {T <: COMPLEXSCALAR}
	size(Z) == size(Y) || throw(DimensionMismatch("Z and Y must have same dims"))
	Fr = typeof(real(zero(T)))
	fr = if Fr === BASE_FLOAT
		Vector{Fr}(f)
	else
		eltype(f) <: Measurement ? Vector{Fr}(f) : measurement.(f, zero.(f))
	end
	return LineParameters{T}(
		SeriesImpedance{T}(Z),
		ShuntAdmittance{T}(Y),
		fr,
	)
end


