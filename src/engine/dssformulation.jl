
using DocStringExtensions

# Define abstract types for earth models
abstract type DSSEarthModel end
struct SimpleCarson <: DSSEarthModel end
struct FullCarson <: DSSEarthModel end
struct DeriModel <: DSSEarthModel end
struct Saad <: DSSEarthModel end

"""
$(TYPEDEF)

Options for the DSS formulation.

$(TYPEDFIELDS)
"""
@kwdef struct DSSOptions <: AbstractFormulationOptions
    "Common options"
    common::LineParamOptions = LineParamOptions()
    "Reduce bundle conductors to equivalent single conductor"
	reduce_bundle::Bool = true
	"Eliminate grounded conductors from the system (Kron reduction)"
	kron_reduction::Bool = true
    "Temperature correction"
	temperature_correction::Bool = true
end

"""
$(TYPEDEF)

Represents the DSS formulation set for cable or line systems.

$(TYPEDFIELDS)
"""
struct DSSFormulation <: AbstractFormulationSet
    "Internal impedance formulation."
	internal_impedance::DSSEarthModel
	"Earth impedance formulation."
	earth_impedance::DSSEarthModel
    "Solver options for DSS-type computations."
	options::DSSOptions

    @doc """
	$(TYPEDSIGNATURES)

	Constructs a [`DSSFormulation`](@ref) instance.
	"""
    function DSSFormulation(;
        internal_impedance::DSSEarthModel,
        earth_impedance::DSSEarthModel,
        options::DSSOptions,
    )
        return new(
            internal_impedance,
            earth_impedance,
            options,
        )
    end
end
