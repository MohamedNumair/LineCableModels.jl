"""
    LineCableModels.Core

The [`Core`](@ref) module provides the main functionalities of the [`LineCableModels.jl`](index.md) package. This module implements data structures, methods and functions for calculating frequency-dependent electrical parameters (Z/Y matrices) of line and cable systems with uncertainty quantification. 

# Overview

- Calculation of frequency-dependent series impedance (Z) and shunt admittance (Y) matrices.
- Uncertainty propagation for geometric and material parameters using `Measurements.jl`.
- Internal impedance computation for solid, tubular and multi-layered coaxial conductors.
- Earth return impedances/admittances for overhead lines and underground cables (valid up to 10 MHz).
- Support for frequency-dependent soil properties.
- Handling of arbitrary polyphase systems with multiple conductors per phase.
- Phase and sequence domain calculations with uncertainty quantification.
- Novel N-layer concentric cable formulation with semiconductor modeling.

# Dependencies

$(IMPORTS)

# Exports

$(EXPORTS)
"""
module Core

# Load common dependencies
include("common_deps.jl")
using ..Utils
using ..Materials
using ..EarthProps
using ..DataModel
import ..LineCableModels: FormulationSet, _get_description

# Module-specific dependencies
using Measurements
using LinearAlgebra
using SpecialFunctions

# Export public API
export LineParametersProblem, LineParameters
export AbstractFormulationSet, AbstractImpedanceFormulation, AbstractAdmittanceFormulation,
    FormulationOptions

"""
$(TYPEDEF)

Abstract base type for all problem definitions in the [`LineCableModels.jl`](index.md) computation framework.
"""
abstract type ProblemDefinition end

# Formulation abstract types
abstract type AbstractFormulationSet end
abstract type AbstractImpedanceFormulation <: AbstractFormulationSet end
abstract type AbstractAdmittanceFormulation <: AbstractFormulationSet end
abstract type InternalImpedanceFormulation <: AbstractImpedanceFormulation end
abstract type EarthImpedanceFormulation <: AbstractImpedanceFormulation end
abstract type InternalAdmittanceFormulation <: AbstractAdmittanceFormulation end
abstract type EarthAdmittanceFormulation <: AbstractAdmittanceFormulation end

"""
$(TYPEDEF)

Represents a line parameters computation problem for a given physical cable system.

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

"""
$(TYPEDEF)

Formulation base type for defining solver options in the computation framework.
Solver options define execution-related parameters such as output options,
solver command line arguments, and post-processing settings.

Concrete implementations should define how the solution process is controlled,
including file handling, previewing options, and external tool integration.
"""
abstract type FormulationOptions end

struct LineParameters{T<:Union{Complex{Float64},Complex{Measurement{Float64}}}}
    "Series impedance matrices [Ω/m]"
    Z::Array{T,3}
    "Shunt admittance matrices [S/m]"
    Y::Array{T,3}

    # Inner constructor with validation
    function LineParameters(Z::Array{T,3}, Y::Array{T,3}) where {T<:Union{Complex{Float64},Complex{Measurement{Float64}}}}
        # Validate dimensions
        size(Z, 1) == size(Z, 2) || throw(DimensionMismatch("Z matrix must be square"))
        size(Y, 1) == size(Y, 2) || throw(DimensionMismatch("Y matrix must be square"))
        size(Z) == size(Y) || throw(DimensionMismatch("Z and Y must have same dimensions"))

        new{T}(Z, Y)
    end
end

struct EMTFormulation <: AbstractFormulationSet
    internal_impedance::InternalImpedanceFormulation
    earth_impedance::EarthImpedanceFormulation
    internal_admittance::InternalAdmittanceFormulation
    earth_admittance::EarthAdmittanceFormulation

    function EMTFormulation(;
        internal_impedance::InternalImpedanceFormulation=nothing,
        earth_impedance::EarthImpedanceFormulation=nothing,
        internal_admittance::InternalAdmittanceFormulation=nothing,
        earth_admittance::EarthAdmittanceFormulation=nothing
    )
        return new(
            internal_impedance, earth_impedance,
            internal_admittance, earth_admittance
        )
    end
end

function FormulationSet(; internal_impedance::InternalImpedanceFormulation,
    earth_impedance::EarthImpedanceFormulation,
    internal_admittance::InternalAdmittanceFormulation,
    earth_admittance::EarthAdmittanceFormulation)
    return EMTFormulation(; internal_impedance, earth_impedance,
        internal_admittance, earth_admittance)
end

# Pretty printing with uncertainty information if present
function Base.show(io::IO, params::LineParameters{T}) where {T}
    n_cond, _, n_freq = size(params.Z)
    print(io, "LineParameters with $(n_cond) conductors at $(n_freq) frequencies")
    if T <: Complex{Measurement{Float64}}
        print(io, " (with uncertainties)")
    end
end

end # module Core