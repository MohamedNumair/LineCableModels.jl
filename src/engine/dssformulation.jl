
using DocStringExtensions

# Define abstract types for DSS analytical formulations
abstract type DSSFormulation end
struct SimpleCarson <: DSSFormulation end
struct FullCarson <: DSSFormulation end
struct DeriModel <: DSSFormulation end
struct Saad <: DSSFormulation end

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
struct DSSFormulationSet <: AbstractFormulationSet
    "Internal impedance formulation."
	internal_impedance::DSSFormulation
	"Earth impedance formulation."
	earth_impedance::DSSFormulation
    "Solver options for DSS-type computations."
	options::DSSOptions

    @doc """
	$(TYPEDSIGNATURES)

	Constructs a [`DSSFormulationSet`](@ref) instance.
	"""
    function DSSFormulationSet(;
        internal_impedance::DSSFormulation,
        earth_impedance::DSSFormulation,
        options::DSSOptions,
    )
        return new(
            internal_impedance,
            earth_impedance,
            options,
        )
    end
end
