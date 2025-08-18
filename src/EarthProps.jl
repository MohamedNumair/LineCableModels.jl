"""
	LineCableModels.EarthProps

The [`EarthProps`](@ref) module provides functionality for modeling and computing earth properties within the [`LineCableModels.jl`](index.md) package. This module includes definitions for homogeneous and layered earth models, and formulations for frequency-dependent earth properties, to be used in impedance/admittance calculations.

# Overview

- Defines the [`EarthModel`](@ref) object for representing horizontally or vertically multi-layered earth models with frequency-dependent properties (ρ, ε, μ).
- Provides the [`EarthLayer`](@ref) type for representing individual soil layers with electromagnetic properties.
- Implements a multi-dispatch framework to allow different formulations of frequency-dependent earth models with [`AbstractFDEMFormulation`](@ref).
- Contains utility functions for building complex multi-layered earth models and generating data summaries.

# Dependencies

$(IMPORTS)

# Exports

$(EXPORTS)
"""
module EarthProps

# Load common dependencies
include("commondeps.jl")
using ..Utils
using ..LineCableModels # For physical constants (f₀, μ₀, ε₀, ρ₀, T₀, TOL, ΔTmax)
import ..LineCableModels: _get_description, add!
import ..LineCableModels: REALTYPES, COMPLEXTYPES, NUMERICTYPES

# Module-specific dependencies
using Measurements
using DataFrames
import DataFrames: DataFrame
import Base: show

# Export public API
export CPEarth,
    EarthLayer,
    EarthModel,
    DataFrame


include("EarthProps/fdprops.jl")

"""
$(TYPEDEF)

Represents one single earth layer in an [`EarthModel`](@ref) object, with base and frequency-dependent properties, and attributes:

$(TYPEDFIELDS)
"""
struct EarthLayer{T<:REALTYPES}
    "Base (DC) electrical resistivity \\[Ω·m\\]."
    base_rho_g::T
    "Base (DC) relative permittivity \\[dimensionless\\]."
    base_epsr_g::T
    "Base (DC)  relative permeability \\[dimensionless\\]."
    base_mur_g::T
    "Thickness of the layer \\[m\\]."
    t::T
    "Computed resistivity values \\[Ω·m\\] at given frequencies."
    rho_g::Vector{T}
    "Computed permittivity values \\[F/m\\] at given frequencies."
    eps_g::Vector{T}
    "Computed permeability values \\[H/m\\] at given frequencies."
    mu_g::Vector{T}

    @doc """
    $(TYPEDSIGNATURES)

    Constructs an [`EarthLayer`](@ref) instance with specified base properties and computes its frequency-dependent values.

    # Arguments

    - `frequencies`: Vector of frequency values \\[Hz\\].
    - `base_rho_g`: Base (DC) electrical resistivity of the layer \\[Ω·m\\].
    - `base_epsr_g`: Base (DC) relative permittivity of the layer \\[dimensionless\\].
    - `base_mur_g`: Base (DC) relative permeability of the layer \\[dimensionless\\].
    - `t`: Thickness of the layer \\[m\\].
    - `FDformulation`: Instance of a subtype of [`AbstractFDEMFormulation`](@ref) defining the computation method for frequency-dependent properties.

    # Returns

    - An [`EarthLayer`](@ref) instance with computed frequency-dependent properties.

    # Examples

    ```julia
    frequencies = [1e3, 1e4, 1e5]
    layer = $(FUNCTIONNAME)(frequencies, 100, 10, 1, 5, CPEarth())
    println(layer.rho_g) # Output: [100, 100, 100]
    println(layer.eps_g) # Output: [8.854e-11, 8.854e-11, 8.854e-11]
    println(layer.mu_g)  # Output: [1.2566e-6, 1.2566e-6, 1.2566e-6]
    ```

    # See also

    - [`_calc_earth_properties`](@ref)
    """
    function EarthLayer(
        frequencies::Vector{T},
        base_rho_g::T,
        base_epsr_g::T,
        base_mur_g::T,
        t::T,
        FDformulation::AbstractFDEMFormulation,
    ) where {T<:REALTYPES}

        rho_g, eps_g, mu_g = _calc_earth_properties(
            frequencies,
            base_rho_g,
            base_epsr_g,
            base_mur_g,
            FDformulation,
        )
        return new{T}(
            base_rho_g,
            base_epsr_g,
            base_mur_g,
            t,
            rho_g,
            eps_g,
            mu_g,
        )
    end
end

"""
$(TYPEDEF)

Represents a multi-layered earth model with frequency-dependent properties, and attributes:

$(TYPEDFIELDS)
"""
struct EarthModel{T<:REALTYPES}
    "Selected frequency-dependent formulation for earth properties."
    FDformulation::AbstractFDEMFormulation
    "Boolean flag indicating whether the model is treated as vertically layered."
    vertical_layers::Bool
    "Vector of [`EarthLayer`](@ref) objects, starting with an air layer and the specified first earth layer."
    layers::Vector{EarthLayer{T}}

    @doc """
    $(TYPEDSIGNATURES)

    Constructs an [`EarthModel`](@ref) instance with a specified first earth layer. A semi-infinite air layer is always added before the first earth layer.

    # Arguments

    - `frequencies`: Vector of frequency values \\[Hz\\].
    - `rho_g`: Base (DC) electrical resistivity of the first earth layer \\[Ω·m\\].
    - `epsr_g`: Base (DC) relative permittivity of the first earth layer \\[dimensionless\\].
    - `mur_g`: Base (DC) relative permeability of the first earth layer \\[dimensionless\\].
    - `t`: Thickness of the first earth layer \\[m\\]. For homogeneous earth models (or the bottommost layer), set `t = Inf`.
    - `FDformulation`: Instance of a subtype of [`AbstractFDEMFormulation`](@ref) defining the computation method for frequency-dependent properties (default: [`CPEarth`](@ref)).
    - `vertical_layers`: Boolean flag indicating whether the model should be treated as vertically-layered (default: `false`).
    - `air_layer`: optional [`EarthLayer`](@ref) object representing the semi-infinite air layer (default: `EarthLayer(frequencies, Inf, 1.0, 1.0, Inf, FDformulation)`).

    # Returns

    - An [`EarthModel`](@ref) instance with the specified attributes and computed frequency-dependent properties.

    # Examples

    ```julia
    frequencies = [1e3, 1e4, 1e5]
    earth_model = $(FUNCTIONNAME)(frequencies, 100, 10, 1, t=Inf)
    println(length(earth_model.layers)) # Output: 2 (air + top layer)
    println(earth_model.rho_eff) # Output: missing
    ```

    # See also

    - [`EarthLayer`](@ref)
    - [`add!`](@ref)
    """
    function EarthModel(
        frequencies::Vector{T},
        rho_g::T,
        epsr_g::T,
        mur_g::T;
        t::T=T(Inf),
        FDformulation::AbstractFDEMFormulation=CPEarth(),
        vertical_layers::Bool=false,
        air_layer::Union{EarthLayer{T},Nothing}=nothing,
    ) where {T<:REALTYPES}

        # Validate inputs
        @assert all(f -> f > 0, frequencies) "Frequencies must be positive"
        @assert rho_g > 0 "Resistivity must be positive"
        @assert epsr_g > 0 "Relative permittivity must be positive"
        @assert mur_g > 0 "Relative permeability must be positive"
        @assert t > 0 || isinf(t) "Layer thickness must be positive or infinite"

        # Enforce rule for vertical model initialization
        if vertical_layers && !isinf(t)
            error("A vertically-layered model must be initialized with an infinite thickness (t=Inf).")
        end

        # Create air layer if not provided
        if air_layer === nothing
            air_layer = EarthLayer(frequencies, T(Inf), T(1.0), T(1.0), T(Inf), FDformulation)
        end

        # Create top earth layer
        top_layer = EarthLayer(frequencies, rho_g, epsr_g, mur_g, t, FDformulation)

        return new{T}(
            FDformulation,
            vertical_layers,
            [air_layer, top_layer]
        )
    end
end

"""
$(TYPEDSIGNATURES)

Adds a new earth layer to an existing [`EarthModel`](@ref).

# Arguments

- `model`: Instance of [`EarthModel`](@ref) to which the new layer will be added.
- `frequencies`: Vector of frequency values \\[Hz\\].
- `base_rho_g`: Base electrical resistivity of the new earth layer \\[Ω·m\\].
- `base_epsr_g`: Base relative permittivity of the new earth layer \\[dimensionless\\].
- `base_mur_g`: Base relative permeability of the new earth layer \\[dimensionless\\].
- `t`: Thickness of the new earth layer \\[m\\] (default: `Inf`).

# Returns

- Modifies `model` in place by appending a new [`EarthLayer`](@ref).

# Notes

For **horizontal layering** (`vertical_layers = false`):

- Layer 1 (air) is always infinite (`t = Inf`).
- Layer 2 (first earth layer) can be infinite if modeling a homogeneous half-space.
- If adding a third layer (`length(EarthModel.layers) == 3`), it can be infinite **only if the previous layer is finite**.
- No two successive earth layers (`length(EarthModel.layers) > 2`) can have infinite thickness.

For **vertical layering** (`vertical_layers = true`):

- Layer 1 (air) is always **horizontal** and infinite at `z > 0`.
- Layer 2 (first vertical layer) is always **infinite** in `z < 0` **and** `y < 0`. The first vertical layer is assumed to always end at `y = 0`.
- Layer 3 (second vertical layer) **can be infinite** (establishing a vertical interface at `y = 0`).
- Subsequent layers **can be infinite only if the previous is finite**.
- No two successive vertical layers (`length(EarthModel.layers) > 3`) can both be infinite.

# Examples

```julia
frequencies = [1e3, 1e4, 1e5]

# Define a horizontal model with finite thickness for the first earth layer
horz_earth_model = EarthModel(frequencies, 100, 10, 1, t=5)

# Add a second horizontal earth layer
$(FUNCTIONNAME)(horz_earth_model, frequencies, 200, 15, 1, t=10)
println(length(horz_earth_model.layers)) # Output: 3

# The bottom layer should be set to infinite thickness
$(FUNCTIONNAME)(horz_earth_model, frequencies, 300, 15, 1, t=Inf)
println(length(horz_earth_model.layers)) # Output: 4

# Initialize a vertical-layered model with first interface at y = 0.
vert_earth_model = EarthModel(frequencies, 100, 10, 1, t=Inf, vertical_layers=true)

# Add a second vertical layer at y = 0 (this can also be infinite)
$(FUNCTIONNAME)(vert_earth_model, frequencies, 150, 12, 1, t=Inf)
println(length(vert_earth_model.layers)) # Output: 3

# Attempt to add a third infinite layer (invalid case)
try
	$(FUNCTIONNAME)(vert_earth_model, frequencies, 120, 12, 1, t=Inf)
catch e
	println(e) # Error: Cannot add consecutive vertical layers with infinite thickness.
end

# Fix: Set a finite thickness to the currently rightmost layer
vert_earth_model.layers[end].t = 3

# Add the third layer with infinite thickness now
$(FUNCTIONNAME)(vert_earth_model, frequencies, 120, 12, 1, t=Inf)
println(length(vert_earth_model.layers)) # Output: 4
```

# See also

- [`EarthLayer`](@ref)
"""
function add!(
    model::EarthModel{T},
    frequencies::Vector{T},
    base_rho_g::T,
    base_epsr_g::T,
    base_mur_g::T;
    t::T=T(Inf),
) where {T<:REALTYPES}

    num_layers = length(model.layers)

    # Validate inputs following established pattern
    @assert all(f -> f > 0, frequencies) "Frequencies must be positive"
    @assert base_rho_g > 0 "Resistivity must be positive"
    @assert base_epsr_g > 0 "Relative permittivity must be positive"
    @assert base_mur_g > 0 "Relative permeability must be positive"
    @assert t > 0 || isinf(t) "Layer thickness must be positive or infinite"

    # Enforce thickness rules
    if isinf(last(model.layers).t)
        # The current last layer is infinite.
        if model.vertical_layers && num_layers == 2
            # This is the special case: adding the second earth layer to a vertical model.
            # The new layer can be finite or infinite. No error.
        else
            # For all other cases (horizontal, or vertical with >2 earth layers),
            # it's an error to add anything after an infinite layer.
            model_type = model.vertical_layers ? "vertical" : "horizontal"
            error("Cannot add a $(model_type) layer after an infinite one.")
        end
    end

    # Create the new earth layer
    new_layer = EarthLayer(
        frequencies,
        base_rho_g,
        base_epsr_g,
        base_mur_g,
        t,
        model.FDformulation,
    )
    push!(model.layers, new_layer)

    model
end

include("EarthProps/dataframe.jl")
include("EarthProps/io.jl")

end # module EarthProps