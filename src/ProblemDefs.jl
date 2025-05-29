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

# abstract type InternalImpedanceFormulation <: AbstractImpedanceFormulation end
# abstract type EarthImpedanceFormulation <: AbstractImpedanceFormulation end
# abstract type EarthAdmittanceFormulation <: AbstractAdmittanceFormulation end

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

# Convenience constructor for single frequency
# function LineParameters(Z::Matrix{T}, Y::Matrix{T}) where {T<:Union{Complex{Float64},Complex{Measurement{Float64}}}}
#     Z3D = reshape(Z, (size(Z, 1), size(Z, 2), 1))
#     Y3D = reshape(Y, (size(Y, 1), size(Y, 2), 1))
#     LineParameters(Z3D, Y3D)
# end

# Pretty printing with uncertainty information if present
function Base.show(io::IO, params::LineParameters{T}) where {T}
    n_cond, _, n_freq = size(params.Z)
    print(io, "LineParameters with $(n_cond) conductors at $(n_freq) frequencies")
    if T <: Complex{Measurement{Float64}}
        print(io, " (with uncertainties)")
    end
end