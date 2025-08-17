"""
$(TYPEDSIGNATURES)

Resolves radius parameters for cable components, converting from various input formats to standardized inner radius, outer radius, and thickness values.

This function serves as a high-level interface to the radius resolution system. It processes inputs through a two-stage pipeline:
1. First normalizes input parameters to consistent forms using [`_parse_inputs_radius`](@ref).
2. Then delegates to specialized implementations via [`_do_resolve_radius`](@ref) based on the component type.

# Arguments

- `param_in`: Inner boundary parameter (defaults to radius) \\[m\\].
  Can be a number, a [`Diameter`](@ref) , a [`Thickness`](@ref), or an [`AbstractCablePart`](@ref).
- `param_ext`: Outer boundary parameter (defaults to radius) \\[m\\].
  Can be a number, a [`Diameter`](@ref) , a [`Thickness`](@ref), or an [`AbstractCablePart`](@ref).
- `object_type`: Type associated to the constructor of the new [`AbstractCablePart`](@ref).

# Returns

- `radius_in`: Normalized inner radius \\[m\\].
- `radius_ext`: Normalized outer radius \\[m\\].
- `thickness`: Computed thickness or specialized dimension depending on the method \\[m\\].
  For [`WireArray`](@ref) components, this value represents the wire radius instead of thickness.

# See also

- [`Diameter`](@ref)
- [`Thickness`](@ref)
- [`AbstractCablePart`](@ref)
"""
function _resolve_radius(param_in, param_ext, object_type=Any)
    # Convert inputs to normalized form (numbers)
    normalized_in = _parse_inputs_radius(param_in, object_type)
    normalized_ext = _parse_inputs_radius(param_ext, object_type)

    # Call the specialized implementation with normalized values
    return _do_resolve_radius(normalized_in, normalized_ext, object_type)
end

"""
$(TYPEDSIGNATURES)

Parses input values into radius representation based on object type and input type.

# Arguments

- `x`: Input value that can be a raw number, a [`Diameter`](@ref), a [`Thickness`](@ref), or other convertible type \\[m\\].
- `object_type`: Type parameter used for dispatch.

# Returns

- Parsed radius value in appropriate units \\[m\\].

# Examples

```julia
radius = $(FUNCTIONNAME)(10.0, ...)   # Direct radius value
radius = $(FUNCTIONNAME)(Diameter(20.0), ...)  # From diameter object
radius = $(FUNCTIONNAME)(Thickness(5.0), ...)  # From thickness object
```

# Methods

$(_CLEANMETHODLIST)

# See also

- [`Diameter`](@ref)
- [`Thickness`](@ref)
- [`strip_uncertainty`](@ref)
"""
function _parse_inputs_radius end

_parse_inputs_radius(x::Number, object_type::Type{T}) where {T} = x
_parse_inputs_radius(d::Diameter, object_type::Type{T}) where {T} = d.value / 2
_parse_inputs_radius(p::Thickness, object_type::Type{T}) where {T} = p
_parse_inputs_radius(x, object_type::Type{T}) where {T} =
    _parse_input_radius(x)

function _parse_inputs_radius(p::AbstractCablePart, object_type::Type{T}) where {T}

    # Get the current outermost radius
    radius_in = getfield(p, :radius_ext)

    # Check if we need to preserve uncertainty
    existing_obj = typeof(p)

    # Keep or strip uncertainty based on type match
    return (existing_obj == object_type) ? radius_in : strip_uncertainty(radius_in)
end

"""
$(TYPEDSIGNATURES)

Resolves radii values based on input types and object type, handling both direct radius specifications and thickness-based specifications.

# Arguments

- `radius_in`: Inner radius value \\[m\\].
- `radius_ext`: Outer radius value or thickness specification \\[m\\].
- `object_type`: Type parameter used for dispatch.

# Returns

- `inner_radius`: Resolved inner radius \\[m\\].
- `outer_radius`: Resolved outer radius \\[m\\].
- `thickness`: Radial thickness between inner and outer surfaces \\[m\\].

# Examples

```julia
# Direct radius specification
inner, outer, thickness = $(FUNCTIONNAME)(0.01, 0.02, ...)
# Output: inner = 0.01, outer = 0.02, thickness = 0.01

# Thickness-based specification
inner, outer, thickness = $(FUNCTIONNAME)(0.01, Thickness(0.005), ...)
# Output: inner = 0.01, outer = 0.015, thickness = 0.005
```

# See also

- [`Thickness`](@ref)
"""

function _do_resolve_radius(radius_in::Number, radius_ext::Number, ::Type{T}) where {T}
    return radius_in, radius_ext, radius_ext - radius_in  # Return inner, outer, thickness
end

function _do_resolve_radius(radius_in::Number, thickness::Thickness, ::Type{T}) where {T}
    radius_ext = radius_in + thickness.value
    return radius_in, radius_ext, thickness.value
end

function _do_resolve_radius(radius_in::Number, radius_wire::Number, ::Type{WireArray})
    thickness = 2 * radius_wire
    return radius_in, radius_in + thickness, thickness
end