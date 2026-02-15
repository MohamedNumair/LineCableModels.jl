"""
$(TYPEDEF)

Represents an ampacity calculation problem.

$(TYPEDFIELDS)
"""
struct AmpacityProblem{T <: REALSCALAR} <: ProblemDefinition
	"The physical cable system to analyze."
	system::LineCableSystem{T}
	"Earth environment with thermal properties."
	environment::EarthModel{T}

	@doc """
	$(TYPEDSIGNATURES)

	Constructs an [`AmpacityProblem`](@ref) instance.

	# Arguments
	- `system`: The cable system to analyze.
	- `environment`: The earth model (including thermal properties).
	"""
	function AmpacityProblem(system::LineCableSystem{T}, environment::EarthModel{T}) where {T <: REALSCALAR}
		return new{T}(system, environment)
	end
end

"""
$(TYPEDEF)

Formulation for IEC 60287 based ampacity calculation.

$(TYPEDFIELDS)
"""
struct IEC60287Formulation <: AbstractFormulationSet
	"Bonding configuration of the sheaths/screens (:solid, :single_point, :cross_bonded)."
	bonding_type::Symbol
	"Whether to include solar radiation (for cables in air)."
	solar_radiation::Bool

	function IEC60287Formulation(; bonding_type::Symbol = :solid, solar_radiation::Bool = false)
		@assert bonding_type in (:solid, :single_point, :cross_bonded) "Invalid bonding type"
		return new(bonding_type, solar_radiation)
	end
end
