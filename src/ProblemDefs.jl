"""
$(TYPEDEF)

Abstract base type for all problem definitions in the LineCableModels.jl computation framework.
"""
abstract type ProblemDefinition end

"""
$(TYPEDEF)

Represents a line parameters computation problem using a physical cable system.

$(TYPEDFIELDS)
"""
struct LineParametersProblem <: ProblemDefinition
    "The physical cable system to analyze."
    system::LineCableSystem
    "Operating temperature [°C]."
    temperature::Number
    "Earth properties model."
    earth_props::EarthModel
    "Frequencies at which to perform the analysis [Hz]."
    frequencies::Vector{Float64}

    function LineParametersProblem(
        system::LineCableSystem;
        temperature::Number=T₀,
        earth_props::EarthModel,
        frequencies::Vector{Float64}=[f₀]
    )
        return new(system, temperature, earth_props, frequencies)
    end
end

# Base abstract types
abstract type AbstractFormulation end
abstract type AbstractImpedanceFormulation <: AbstractFormulation end
abstract type AbstractAdmittanceFormulation <: AbstractFormulation end

abstract type InternalImpedanceFormulation <: AbstractImpedanceFormulation end
abstract type EarthImpedanceFormulation <: AbstractImpedanceFormulation end
abstract type EarthAdmittanceFormulation <: AbstractAdmittanceFormulation end

"""
$(TYPEDEF)

Formulation base type for defining solver options in the computation framework.
Solver options define execution-related parameters such as mesh generation options,
solver configuration, and post-processing settings.

Concrete implementations should define how the solution process is controlled,
including file handling, previewing options, and external tool integration.
"""
abstract type FormulationOptions end

"""
$(TYPEDEF)

Abstract base type for workspace containers in the FEM simulation framework.
Workspace containers maintain the complete state of a simulation, including 
intermediate data structures, identification mappings, and results.

Concrete implementations should provide state tracking for all phases of the 
simulation process from geometry creation through results analysis.
"""
abstract type AbstractWorkspace end