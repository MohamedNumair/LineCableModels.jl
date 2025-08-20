"""
	LineCableModels.Materials

The [`Materials`](@ref) module provides functionality for managing and utilizing material properties within the [`LineCableModels.jl`](index.md) package. This module includes definitions for material properties, a library for storing and retrieving materials, and functions for manipulating material data.

# Overview

- Defines the [`Material`](@ref) struct representing fundamental physical properties of materials.
- Provides the [`MaterialsLibrary`](@ref) mutable struct for storing a collection of materials.
- Includes functions for adding, removing, and retrieving materials from the library.
- Supports loading and saving material data from/to JSON files.
- Contains utility functions for displaying material data.

# Dependencies

$(IMPORTS)

# Exports

$(EXPORTS)
"""
module Materials

# Export public API
export Material, MaterialsLibrary
export add!, get, delete!, length, setindex!, iterate, keys, values, haskey, getindex
export DataFrame

# Load common dependencies
using ..LineCableModels
include("commondeps.jl")


# Module-specific dependencies
using Measurements
using DataFrames
using ..Utils
import ..LineCableModels: _coerce_args_to_T

"""
$(TYPEDEF)

Defines electromagnetic and thermal properties of a material used in cable modeling:

$(TYPEDFIELDS)
"""
struct Material{T<:REALSCALAR}
    "Electrical resistivity of the material \\[Ω·m\\]."
    rho::T
    "Relative permittivity \\[dimensionless\\]."
    eps_r::T
    "Relative permeability \\[dimensionless\\]."
    mu_r::T
    "Reference temperature for property evaluations \\[°C\\]."
    T0::T
    "Temperature coefficient of resistivity \\[1/°C\\]."
    alpha::T
end

function Material(rho, eps_r, mu_r, T0, alpha)

    T = _coerce_args_to_T(rho, eps_r, mu_r, T0, alpha)
    return Material{T}(
        convert(T, rho),
        convert(T, eps_r),
        convert(T, mu_r),
        convert(T, T0),
        convert(T, alpha),
    )
end

Base.convert(::Type{Material{T}}, m::Material) where {T<:REALSCALAR} =
    Material{T}(convert(T, m.rho), convert(T, m.eps_r), convert(T, m.mu_r),
        convert(T, m.T0), convert(T, m.alpha))

include("Materials/materialslibrary.jl")
include("Materials/dataframe.jl")
include("Materials/io.jl")

end # module Materials
