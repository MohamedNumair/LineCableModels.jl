"""
    LineCableModels.Engine

The [`Engine`](@ref) module provides the main functionalities of the [`LineCableModels.jl`](index.md) package. This module implements data structures, methods and functions for calculating frequency-dependent electrical parameters (Z/Y matrices) of line and cable systems with uncertainty quantification. 

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
module Engine

# Load common dependencies
include("common_deps.jl")
using ..Utils
using ..Materials
using ..EarthProps
using ..DataModel
using ..LineCableModels # For physical constants (f₀, μ₀, ε₀, ρ₀, T₀, TOL, ΔTmax)
import ..LineCableModels: FormulationSet, _get_description

# Module-specific dependencies
using Measurements
using LinearAlgebra
using SpecialFunctions

# Export public API
export LineParametersProblem, LineParameters
export AbstractFormulationSet, AbstractImpedanceFormulation, AbstractAdmittanceFormulation

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
struct LineParametersProblem{T<:Union{Float64,Measurement{Float64}}} <: ProblemDefinition
    "The physical cable system to analyze."
    system::LineCableSystem
    "Operating temperature [°C]."
    temperature::T
    "Earth properties model."
    earth_props::EarthModel{T}
    "Frequencies at which to perform the analysis [Hz]."
    frequencies::Vector{Float64}

    function LineParametersProblem(
        system::LineCableSystem;
        temperature::T=T(T₀),
        earth_props::EarthModel{T},
        frequencies::Vector{Float64}=[f₀]
    ) where {T<:Union{Float64,Measurement{Float64}}}

        # 1. System structure validation
        @assert !isempty(system.cables) "LineCableSystem must contain at least one cable"

        # 2. Phase assignment validation
        phase_numbers = unique(vcat([cable.conn for cable in system.cables]...))
        @assert !isempty(filter(x -> x > 0, phase_numbers)) "At least one conductor must be assigned to a phase (>0)"
        @assert maximum(phase_numbers) <= system.num_phases "Invalid phase number detected"

        # 3. Cable components validation
        for (i, cable) in enumerate(system.cables)
            @assert !isempty(cable.design_data.components) "Cable $i has no components defined"

            # Validate conductor-insulator pairs
            for (j, comp) in enumerate(cable.design_data.components)
                @assert !isempty(comp.conductor_group.layers) "Component $j in cable $i has no conductor layers"
                @assert !isempty(comp.insulator_group.layers) "Component $j in cable $i has no insulator layers"

                # Validate monotonic increase of radii
                @assert comp.conductor_group.radius_ext > comp.conductor_group.radius_in "Component $j in cable $i: conductor outer radius must be larger than inner radius"
                @assert comp.insulator_group.radius_ext > comp.insulator_group.radius_in "Component $j in cable $i: insulator outer radius must be larger than inner radius"

                # Validate geometric continuity between conductor and insulator
                r_ext_cond = comp.conductor_group.radius_ext
                r_in_ins = comp.insulator_group.radius_in
                @assert abs(r_ext_cond - r_in_ins) < 1e-10 "Geometric mismatch in cable $i component $j: conductor outer radius ≠ insulator inner radius"

                # Validate electromagnetic properties
                # Conductor properties
                @assert comp.conductor_props.rho > 0 "Component $j in cable $i: conductor resistivity must be positive"
                @assert comp.conductor_props.mu_r > 0 "Component $j in cable $i: conductor relative permeability must be positive"
                @assert comp.conductor_props.eps_r >= 0 "Component $j in cable $i: conductor relative permittivity grater than or equal to zero"

                # Insulator properties
                @assert comp.insulator_props.rho > 0 "Component $j in cable $i: insulator resistivity must be positive"
                @assert comp.insulator_props.mu_r > 0 "Component $j in cable $i: insulator relative permeability must be positive"
                @assert comp.insulator_props.eps_r > 0 "Component $j in cable $i: insulator relative permittivity must be positive"
            end
        end

        # 4. Temperature range validation
        @assert abs(temperature - T₀) < ΔTmax """
        Temperature is outside the valid range for linear resistivity model:
        T = $T
        T₀ = $T₀
        ΔTmax = $ΔTmax
        |T - T₀| = $(abs(T - T₀))"""

        # 5. Frequency range validation
        @assert !isempty(frequencies) "Frequency vector cannot be empty"
        @assert all(f -> f > 0, frequencies) "All frequencies must be positive"
        @assert issorted(frequencies) "Frequency vector must be monotonically increasing"
        if maximum(frequencies) > 1e8
            @warn "Frequencies above 100 MHz exceed quasi-TEM validity limit. High-frequency results should be interpreted with caution." maxfreq = maximum(frequencies)
        end

        # 6. Earth model validation
        @assert length(earth_props.layers[end].rho_g) == length(frequencies) """Earth model frequencies must match analysis frequencies
        Earth model frequencies = $(length(earth_props.layers[end].rho_g))
        Analysis frequencies = $(length(frequencies))
        """

        # 7. Geometric validation
        positions = [(cable.horz, cable.vert, maximum(comp.insulator_group.radius_ext
                                                      for comp in cable.design_data.components))
                     for cable in system.cables]

        for i in eachindex(positions)
            for j in (i+1):lastindex(positions)
                # Calculate center-to-center distance
                dist = sqrt((positions[i][1] - positions[j][1])^2 +
                            (positions[i][2] - positions[j][2])^2)

                # Get outermost radii for both cables
                r_outer_i = positions[i][3]
                r_outer_j = positions[j][3]

                # Check if cables overlap
                min_allowed_dist = r_outer_i + r_outer_j

                @assert dist > min_allowed_dist """
                    Cables $i and $j overlap!
                    Center-to-center distance: $(dist) m
                    Minimum required distance: $(min_allowed_dist) m
                    Cable $i outer radius: $(r_outer_i) m
                    Cable $j outer radius: $(r_outer_j) m"""
            end
        end

        return new{T}(system, temperature, earth_props, frequencies)
    end
end

# """
# $(TYPEDEF)

# Formulation base type for defining solver options in the computation framework.
# Solver options define execution-related parameters such as output options,
# solver command line arguments, and post-processing settings.

# Concrete implementations should define how the solution process is controlled,
# including file handling, previewing options, and external tool integration.
# """
# abstract type FormulationOptions end

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

function FormulationSet(::Val{:EMT}; internal_impedance::InternalImpedanceFormulation,
    earth_impedance::EarthImpedanceFormulation,
    internal_admittance::InternalAdmittanceFormulation,
    earth_admittance::EarthAdmittanceFormulation)
    return EMTFormulation(; internal_impedance, earth_impedance,
        internal_admittance, earth_admittance)
end

function flatten_cablesystem(system::LineCableSystem)
    # Count total components
    n_components = sum(length(cable.design_data.components) for cable in system.cables)

    # Determine type based on first numeric value
    T = typeof(system.cables[1].horz)

    # Pre-allocate 1D arrays
    horz = Vector{T}(undef, n_components)
    vert = Vector{T}(undef, n_components)
    r_in = Vector{T}(undef, n_components)
    r_ext = Vector{T}(undef, n_components)
    r_ins_in = Vector{T}(undef, n_components)
    r_ins_ext = Vector{T}(undef, n_components)
    rho_cond = Vector{T}(undef, n_components)
    mu_cond = Vector{T}(undef, n_components)
    eps_cond = Vector{T}(undef, n_components)
    rho_ins = Vector{T}(undef, n_components)
    mu_ins = Vector{T}(undef, n_components)
    eps_ins = Vector{T}(undef, n_components)
    tan_ins = Vector{T}(undef, n_components)   # Loss tangent for insulator
    phase_map = Vector{Int}(undef, n_components)
    cable_map = Vector{Int}(undef, n_components)

    # Fill arrays
    idx = 1
    for (cable_idx, cable) in enumerate(system.cables)
        for (comp_idx, component) in enumerate(cable.design_data.components)
            # Geometric properties
            horz[idx] = cable.horz
            vert[idx] = cable.vert
            r_in[idx] = component.conductor_group.radius_in
            r_ext[idx] = component.conductor_group.radius_ext
            r_ins_in[idx] = component.insulator_group.radius_in
            r_ins_ext[idx] = component.insulator_group.radius_ext

            # Material properties
            rho_cond[idx] = component.conductor_props.rho
            mu_cond[idx] = component.conductor_props.mu_r
            eps_cond[idx] = component.conductor_props.eps_r
            rho_ins[idx] = component.insulator_props.rho
            mu_ins[idx] = component.insulator_props.mu_r
            eps_ins[idx] = component.insulator_props.eps_r

            # Calculate loss factor from resistivity
            ω = 2 * π * f₀  # Using default frequency
            C_eq = component.insulator_group.shunt_capacitance
            G_eq = component.insulator_group.shunt_conductance
            tan_ins[idx] = G_eq / (ω * C_eq)

            # Mapping
            phase_map[idx] = cable.conn[comp_idx]
            cable_map[idx] = cable_idx

            idx += 1
        end
    end

    return (
        horz=horz, vert=vert,
        r_in=r_in, r_ext=r_ext,
        r_ins_in=r_ins_in, r_ins_ext=r_ins_ext,
        rho_cond=rho_cond, mu_cond=mu_cond, eps_cond=eps_cond,
        rho_ins=rho_ins, mu_ins=mu_ins, eps_ins=eps_ins, tan_ins=tan_ins,
        phase_map=phase_map, cable_map=cable_map
    )
end

include("Engine/io.jl")

end # module Engine