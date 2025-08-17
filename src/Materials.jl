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
include("commondeps.jl")
using ..LineCableModels
using ..Utils
import ..LineCableModels: add!, save

# Module-specific dependencies
using Measurements
using DataFrames
import DataFrames: DataFrame
import Base: get, delete!, length, setindex!, iterate, keys, values, haskey, getindex

"""
$(TYPEDEF)

Defines electromagnetic and thermal properties of a material used in cable modeling:

$(TYPEDFIELDS)
"""
struct Material
    "Electrical resistivity of the material \\[Ω·m\\]."
    rho::Number
    "Relative permittivity \\[dimensionless\\]."
    eps_r::Number
    "Relative permeability \\[dimensionless\\]."
    mu_r::Number
    "Reference temperature for property evaluations \\[°C\\]."
    T0::Number
    "Temperature coefficient of resistivity \\[1/°C\\]."
    alpha::Number
end

include("Materials/materialslibrary.jl")
include("Materials/dataframe.jl")
include("Materials/io.jl")

end # module Materials
