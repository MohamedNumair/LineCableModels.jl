"""
	LineCableModels.DataModel

The [`DataModel`](@ref) module provides data structures, constructors and utilities for modeling power cables within the [`LineCableModels.jl`](index.md) package. This module includes definitions for various cable components, and visualization tools for cable designs.

# Overview

- Provides objects for detailed cable modeling with the [`CableDesign`](@ref) and supporting types: [`WireArray`](@ref), [`Strip`](@ref), [`Tubular`](@ref), [`Semicon`](@ref), and [`Insulator`](@ref).
- Includes objects for cable **system** modeling with the [`LineCableSystem`](@ref) type, and multiple formation patterns like trifoil and flat arrangements.
- Contains functions for calculating the base electric properties of all elements within a [`CableDesign`](@ref), namely: resistance, inductance (via GMR), shunt capacitance, and shunt conductance (via loss factor).
- Offers visualization tools for previewing cable cross-sections and system layouts.
- Provides a library system for storing and retrieving cable designs.

# Dependencies

$(IMPORTS)

# Exports

$(EXPORTS)
"""
module DataModel

# Export public API
export Thickness, Diameter  # Type definitions
export WireArray, Strip, Tubular  # Conductor types
export Semicon, Insulator  # Insulator types
export ConductorGroup, InsulatorGroup  # Group types
export CableComponent, CableDesign  # Cable design types
export CablePosition, LineCableSystem  # System types
export CablesLibrary, NominalData  # Support types
export add!, get, delete!, length, setindex!, iterate, keys, values, haskey, getindex
export trifoil_formation, flat_formation  # Formation helpers
export preview  # Visualization
export DataFrame  # Data conversion

# Load common dependencies
using ..LineCableModels
include("commondeps.jl")

# Module-specific dependencies
using Measurements
using DataFrames
using Colors
using Plots
using DisplayAs: DisplayAs
using ..Utils
using ..Materials
using ..EarthProps
import ..LineCableModels: _is_headless, _is_in_testset, _CLEANMETHODLIST

# To handle radius-related operations
abstract type AbstractRadius end
function _do_resolve_radius end

# TODO: Develop and integrate input type normalization
# Issue URL: https://github.com/Electa-Git/LineCableModels.jl/issues/10

"""
$(TYPEDEF)

Represents the thickness of a cable component.

$(TYPEDFIELDS)
"""
struct Thickness{T<:Real} <: AbstractRadius
    "Numerical value of the thickness \\[m\\]."
    value::T
    function Thickness(value::T) where {T<:Real}
        value >= 0 || throw(ArgumentError("Thickness must be a non-negative number."))
        new{T}(value)
    end
end

"""
$(TYPEDEF)

Represents the diameter of a cable component.

$(TYPEDFIELDS)
"""
struct Diameter{T<:Real} <: AbstractRadius
    "Numerical value of the diameter \\[m\\]."
    value::T
    function Diameter(value::T) where {T<:Real}
        value > 0 || throw(ArgumentError("Diameter must be a positive number."))
        new{T}(value)
    end
end

"""
$(TYPEDEF)

Abstract type representing a generic cable part.
"""
abstract type AbstractCablePart end

"""
$(TYPEDEF)

Abstract type representing a conductive part of a cable.

Subtypes implement specific configurations:
- [`WireArray`](@ref)
- [`Tubular`](@ref)
- [`Strip`](@ref)
"""
abstract type AbstractConductorPart <: AbstractCablePart end

"""
$(TYPEDEF)

Abstract type representing an insulating part of a cable.

Subtypes implement specific configurations:
- [`Insulator`](@ref)
- [`Semicon`](@ref)
"""
abstract type AbstractInsulatorPart <: AbstractCablePart end

include("DataModel/conductors.jl")

include("DataModel/insulators.jl")

# Submodule `BaseParams`
include("DataModel/BaseParams.jl")
@force using .BaseParams

include("DataModel/cabledesign.jl")
include("DataModel/cableslibrary.jl")
include("DataModel/linecablesystem.jl")
include("DataModel/utils.jl")
include("DataModel/radii.jl")
include("DataModel/preview.jl")
include("DataModel/dataframe.jl")
include("DataModel/io.jl")

@reexport using .BaseParams

end # module DataModel