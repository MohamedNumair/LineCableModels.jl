"""
$(TYPEDEF)

Abstract type representing different equivalent homogeneous earth models (EHEM). Used in the multi-dispatch implementation of [`_calc_ehem_properties!`](@ref).

# Currently available formulations

- [`EnforceLayer`](@ref): Effective parameters defined according to a specific earth layer.
"""
abstract type AbstractEHEMFormulation end

"""
$(TYPEDEF)

Represents a homogeneous earth model defined using the properties of a specific earth layer, with atttribute:

$(TYPEDFIELDS)
"""
struct EnforceLayer <: AbstractEHEMFormulation
    "Index of the enforced earth layer."
    layer::Int

    @doc """
    $(TYPEDSIGNATURES)

    Constructs an [`EnforceLayer`](@ref) instance, meaning that the properties of the specified layer are extended to the entire semi-infinite earth.

    # Arguments

    - `layer`: Integer specifying the layer to be enforced as the equivalent homogeneous layer.
    - `-1` selects the bottommost layer.
    - `2` selects the topmost earth layer (excluding air).
    - Any integer `≥ 2` selects a specific layer.

    # Returns

    - An [`EnforceLayer`](@ref) instance with the specified layer index.

    # Examples

    ```julia
    # Enforce the bottommost layer
    bottom_layer = $(FUNCTIONNAME)(-1)
    println(_get_description(bottom_layer)) # Output: "Bottom layer"

    # Enforce the topmost earth layer
    first_layer = $(FUNCTIONNAME)(2)
    println(_get_description(first_layer)) # Output: "Top layer"

    # Enforce a specific layer
    specific_layer = $(FUNCTIONNAME)(3)
    println(_get_description(specific_layer)) # Output: "Layer 3"
    ```
    """
    function EnforceLayer(layer::Int)
        @assert (layer == -1 || layer >= 2) "Invalid earth layer choice."
        return new(layer)
    end
end

function _get_description(formulation::EnforceLayer)
    if formulation.layer == -1
        return "Bottom layer"
    elseif formulation.layer == 2
        return "Top layer"
    else
        return "Layer $(formulation.layer)"
    end
end

"""
$(TYPEDSIGNATURES)

Computes the effective homogeneous earth model (EHEM) properties for an [`EarthModel`](@ref), overriding the layered model with the properties of the layer defined in [`EnforceLayer`](@ref).

# Arguments

- `model`: Instance of [`EarthModel`](@ref) for which effective properties are computed.
- `frequencies`: Vector of frequency values \\[Hz\\].
- `formulation`: Instance of [`AbstractEHEMFormulation`](@ref) specifying how the effective properties should be determined.

# Returns

- Modifies `model` in place by updating `rho_eff`, `eps_eff`, and `mu_eff` with the corresponding values.

# Notes

- If `formulation` is an [`EnforceLayer`](@ref), the effective properties (`rho_eff`, `eps_eff`, `mu_eff`) are **directly assigned** from the specified layer.
- If `layer_idx = -1`, the **last** layer in `model.layers` is used.
- If `layer_idx < 2` or `layer_idx > length(model.layers)`, an error is raised.

# Examples

```julia
frequencies = [1e3, 1e4, 1e5]
earth_model = EarthModel(frequencies, 100, 10, 1, t=5)
earth_model.AbstractEHEMFormulation = EnforceLayer(-1)  # Enforce the last layer as the effective
$(FUNCTIONNAME)(earth_model, frequencies, EnforceLayer(-1))

println(earth_model.rho_eff) # Should match the last layer rho_g = 100
println(earth_model.eps_eff) # Should match the last layer eps_g = 10*ε₀
println(earth_model.mu_eff)  # Should match the last layer mu_g = 1*μ₀
```

# See also

- [`EarthModel`](@ref)
- [`AbstractEHEMFormulation`](@ref)
"""
function _calc_ehem_properties!(
    model::EarthModel,
    frequencies::Vector{<:Number},
    formulation::AbstractEHEMFormulation=EnforceLayer(-1),
)
    layer_idx = formulation.layer

    if layer_idx == -1
        layer_idx = length(model.layers)  # Use last layer
    elseif layer_idx < 2 || layer_idx > length(model.layers)
        error(
            "Invalid layer index: $layer_idx. Must be between 2 and $(length(model.layers))",
        )
    end

    layer = model.layers[layer_idx]

    # Just reference the selected layer
    model.rho_eff = layer.rho_g
    model.eps_eff = layer.eps_g
    model.mu_eff = layer.mu_g
end

# Compute effective parameters **only if we have at least 2 earth layers**
# if model.num_layers > 2 && !isnothing(model.AbstractEHEMFormulation) &&
#    !(model.vertical_layers)
#     _calc_ehem_properties!(model, frequencies, model.AbstractEHEMFormulation)
# end