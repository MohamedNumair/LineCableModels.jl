"""
Convert an EarthModel{S} to an EarthModel{T} by reconstructing it
with all layers and fields coerced to the new type T.
"""
function coerce_to_T(model::EarthModel, ::Type{T}) where {T}
    # 1. Coerce all existing layers recursively
    new_layers = [coerce_to_T(layer, T) for layer in model.layers]

    # 2. Use the inner constructor to build the new, promoted model
    return EarthModel{T}(
        model.freq_dependence,
        model.vertical_layers,
        new_layers
    )
end

"""
Convert an EarthLayer{S} to an EarthLayer{T} by coercing its fields.
"""
function coerce_to_T(layer::EarthLayer, ::Type{T}) where {T}
    # Reconstruct the layer using the correct internal constructor.
    # The existing coerce_to_T methods for scalars and arrays will be
    # dispatched automatically for each field.
    return EarthLayer{T}(
        coerce_to_T(layer.base_rho_g, T),
        coerce_to_T(layer.base_epsr_g, T),
        coerce_to_T(layer.base_mur_g, T),
        coerce_to_T(layer.t, T),
        coerce_to_T(layer.rho_g, T),
        coerce_to_T(layer.eps_g, T),
        coerce_to_T(layer.mu_g, T)
    )
end

Base.eltype(::EarthModel{T}) where {T} = T

function Base.convert(::Type{EarthModel{T}}, model::EarthModel) where {T}
    # If the model is already the target type, return it without modification.
    model isa EarthModel{T} && return model

    # Delegate the actual conversion logic to the existing coerce_to_T function.
    return coerce_to_T(model, T)
end

function Base.convert(::Type{EarthLayer{T}}, layer::EarthLayer) where {T}
    # Avoid unnecessary work if the layer is already the correct type.
    layer isa EarthLayer{T} && return layer

    # Delegate the conversion logic to the specialized coerce_to_T function.
    return coerce_to_T(layer, T)
end