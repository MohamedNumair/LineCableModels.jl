"""
	LineCableModels.DataModel

The [`DataModel`](@ref) module provides data structures, constructors and utilities for modeling power cables within the [`LineCableModels.jl`](index.md) package. This module includes definitions for various cable components, and visualization tools for cable designs.

# Overview

- Provides objects for detailed **cable** modeling with the [`CableDesign`](@ref) and supporting types: [`Conductor`](@ref), [`WireArray`](@ref), [`Strip`](@ref), [`Tubular`](@ref), [`Semicon`](@ref), and [`Insulator`](@ref).
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

# Load common dependencies
include("CommonDeps.jl")
using ..Utils
using ..Materials
using ..EarthProps

# Module-specific dependencies
using Measurements
using DataFrames
using Colors
using Plots
using DataStructures
using Serialization

"""
$(TYPEDEF)

Represents the thickness of a cable component.

$(TYPEDFIELDS)
"""
struct Thickness{T <: Number} <: Number
	"Numerical value of the thickness \\[m\\]."
	value::T
end


"""
$(TYPEDEF)

Represents the diameter of a cable component.

$(TYPEDFIELDS)
"""
struct Diameter{T <: Number} <: Number
	"Numerical value of the diameter \\[m\\]."
	value::T
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
- [`Conductor`](@ref)
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

"""
$(TYPEDEF)

Represents an array of wires equally spaced around a circumference of arbitrary radius, with attributes:

$(TYPEDFIELDS)
"""
struct WireArray <: AbstractConductorPart
	"Internal radius of the wire array \\[m\\]."
	radius_in::Number
	"External radius of the wire array \\[m\\]."
	radius_ext::Number
	"Radius of each individual wire \\[m\\]."
	radius_wire::Number
	"Number of wires in the array \\[dimensionless\\]."
	num_wires::Int
	"Ratio defining the lay length of the wires (twisting factor) \\[dimensionless\\]."
	lay_ratio::Number
	"Mean diameter of the wire array \\[m\\]."
	mean_diameter::Number
	"Pitch length of the wire array \\[m\\]."
	pitch_length::Number
	"Twisting direction of the strands (1 = unilay, -1 = contralay) \\[dimensionless\\]."
	lay_direction::Int
	"Material object representing the physical properties of the wire material."
	material_props::Material
	"Temperature at which the properties are evaluated \\[°C\\]."
	temperature::Number
	"Cross-sectional area of all wires in the array \\[m²\\]."
	cross_section::Number
	"Electrical resistance per wire in the array \\[Ω/m\\]."
	resistance::Number
	"Geometric mean radius of the wire array \\[m\\]."
	gmr::Number
end

"""
$(TYPEDEF)

Represents a flat conductive strip with defined geometric and material properties given by the attributes:

$(TYPEDFIELDS)
"""
struct Strip <: AbstractConductorPart
	"Internal radius of the strip \\[m\\]."
	radius_in::Number
	"External radius of the strip \\[m\\]."
	radius_ext::Number
	"Thickness of the strip \\[m\\]."
	thickness::Number
	"Width of the strip \\[m\\]."
	width::Number
	"Ratio defining the lay length of the strip (twisting factor) \\[dimensionless\\]."
	lay_ratio::Number
	"Mean diameter of the strip's helical path \\[m\\]."
	mean_diameter::Number
	"Pitch length of the strip's helical path \\[m\\]."
	pitch_length::Number
	"Twisting direction of the strip (1 = unilay, -1 = contralay) \\[dimensionless\\]."
	lay_direction::Int
	"Material properties of the strip."
	material_props::Material
	"Temperature at which the properties are evaluated \\[°C\\]."
	temperature::Number
	"Cross-sectional area of the strip \\[m²\\]."
	cross_section::Number
	"Electrical resistance of the strip \\[Ω/m\\]."
	resistance::Number
	"Geometric mean radius of the strip \\[m\\]."
	gmr::Number
end

"""
$(TYPEDEF)

Represents a tubular or solid (`radius_in=0`) conductor with geometric and material properties defined as:

$(TYPEDFIELDS)
"""
struct Tubular <: AbstractConductorPart
	"Internal radius of the tubular conductor \\[m\\]."
	radius_in::Number
	"External radius of the tubular conductor \\[m\\]."
	radius_ext::Number
	"A [`Material`](@ref) object representing the physical properties of the conductor material."
	material_props::Material
	"Temperature at which the properties are evaluated \\[°C\\]."
	temperature::Number
	"Cross-sectional area of the tubular conductor \\[m²\\]."
	cross_section::Number
	"Electrical resistance (DC) of the tubular conductor \\[Ω/m\\]."
	resistance::Number
	"Geometric mean radius of the tubular conductor \\[m\\]."
	gmr::Number
end

"""
$(TYPEDEF)

Represents a composite coaxial conductor assembled from multiple conductive layers.

This structure serves as a container for different [`AbstractConductorPart`](@ref) elements 
(such as wire arrays, strips, and tubular conductors) arranged in concentric layers. 
The `Conductor` aggregates these individual parts and provides equivalent electrical 
properties that represent the composite behavior of the entire assembly, stored in the attributes:

$(TYPEDFIELDS)
"""
mutable struct Conductor <: AbstractConductorPart
	"Inner radius of the conductor \\[m\\]."
	radius_in::Number
	"Outer radius of the conductor \\[m\\]."
	radius_ext::Number
	"Cross-sectional area of the entire conductor \\[m²\\]."
	cross_section::Number
	"Number of individual wires in the conductor \\[dimensionless\\]."
	num_wires::Number
	"DC resistance of the conductor \\[Ω\\]."
	resistance::Number
	"Temperature coefficient of resistance \\[1/°C\\]."
	alpha::Number
	"Geometric mean radius of the conductor \\[m\\]."
	gmr::Number
	"Vector of conductor layer components."
	layers::Vector{AbstractConductorPart}

	@doc """
	$(TYPEDSIGNATURES)

	Constructs a [`Conductor`](@ref) instance initializing with the central conductor part.

	# Arguments

	- `central_conductor`: An [`AbstractConductorPart`](@ref) object located at the center of the conductor.

	# Returns

	- A [`Conductor`](@ref) object initialized with geometric and electrical properties derived from the central conductor.

	# Examples

	```julia
	material_props = Material(1.7241e-8, 1.0, 0.999994, 20.0, 0.00393)
	central_strip = Strip(0.01, 0.002, 0.05, 10, material_props)
	conductor = $(FUNCTIONNAME)(central_strip)
	println(conductor.layers)      # Output: [central_strip]
	println(conductor.resistance)  # Output: Resistance in \\[Ω\\]
	```
	"""
	function Conductor(central_conductor::AbstractConductorPart)

		num_wires = central_conductor isa WireArray ? central_conductor.num_wires : 0

		# Initialize object
		return new(
			central_conductor.radius_in,
			central_conductor.radius_ext,
			central_conductor.cross_section,
			num_wires,
			central_conductor.resistance,
			central_conductor.material_props.alpha,
			central_conductor.gmr,
			[central_conductor],
		)
	end
end

"""
$(TYPEDEF)

Represents a semiconducting layer with defined geometric, material, and electrical properties given by the attributes:

$(TYPEDFIELDS)
"""
mutable struct Semicon <: AbstractInsulatorPart
	"Internal radius of the semiconducting layer \\[m\\]."
	radius_in::Number
	"External radius of the semiconducting layer \\[m\\]."
	radius_ext::Number
	"Material properties of the semiconductor."
	material_props::Material
	"Operating temperature of the semiconductor \\[°C\\]."
	temperature::Number
	"Cross-sectional area of the semiconducting layer \\[m²\\]."
	cross_section::Number
	"Electrical resistance of the semiconducting layer \\[Ω/m\\]."
	resistance::Number
	"Geometric mean radius of the semiconducting layer \\[m\\]."
	gmr::Number
	"Shunt capacitance per unit length of the semiconducting layer \\[F/m\\]."
	shunt_capacitance::Number
	"Shunt conductance per unit length of the semiconducting layer \\[S/m\\]."
	shunt_conductance::Number
end

"""
$(TYPEDEF)

Represents an insulating layer with defined geometric, material, and electrical properties given by the attributes:

$(TYPEDFIELDS)
"""
mutable struct Insulator <: AbstractInsulatorPart
	"Internal radius of the insulating layer \\[m\\]."
	radius_in::Number
	"External radius of the insulating layer \\[m\\]."
	radius_ext::Number
	"Material properties of the insulator."
	material_props::Material
	"Operating temperature of the insulator \\[°C\\]."
	temperature::Number
	"Cross-sectional area of the insulating layer \\[m²\\]."
	cross_section::Number
	"Electrical resistance of the insulating layer \\[Ω/m\\]."
	resistance::Number
	"Geometric mean radius of the insulator \\[m\\]."
	gmr::Number
	"Shunt capacitance per unit length of the insulating layer \\[F/m\\]."
	shunt_capacitance::Number
	"Shunt conductance per unit length of the insulating layer \\[S/m\\]."
	shunt_conductance::Number
end

# Submodule `BaseParams`
include("BaseParams.jl")
@force using .BaseParams

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
function _resolve_radius(param_in, param_ext, object_type = Any)
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

$(METHODLIST)

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
function _do_resolve_radius end

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

"""
$(TYPEDSIGNATURES)

Constructs a [`WireArray`](@ref) instance based on specified geometric and material parameters.

# Arguments

- `radius_in`: Internal radius of the wire array \\[m\\].
- `radius_wire`: Radius of each individual wire \\[m\\].
- `num_wires`: Number of wires in the array \\[dimensionless\\].
- `lay_ratio`: Ratio defining the lay length of the wires (twisting factor) \\[dimensionless\\].
- `material_props`: A [`Material`](@ref) object representing the material properties.
- `temperature`: Temperature at which the properties are evaluated \\[°C\\].
- `lay_direction`: Twisting direction of the strands (1 = unilay, -1 = contralay) \\[dimensionless\\].

# Returns

- A [`WireArray`](@ref) object with calculated geometric and electrical properties.

# Examples

```julia
material_props = Material(1.7241e-8, 1.0, 0.999994, 20.0, 0.00393)
wire_array = $(FUNCTIONNAME)(0.01, Diameter(0.002), 7, 10, material_props, temperature=25)
println(wire_array.mean_diameter)  # Outputs mean diameter in m
println(wire_array.resistance)     # Outputs resistance in Ω/m
```

# See also

- [`Material`](@ref)
- [`Conductor`](@ref)
- [`calc_tubular_resistance`](@ref)
- [`calc_wirearray_gmr`](@ref)
- [`calc_helical_params`](@ref)
"""
function WireArray(
	radius_in::Union{Number, <:AbstractCablePart},
	radius_wire::Union{Number, Diameter},
	num_wires::Int,
	lay_ratio::Number,
	material_props::Material;
	temperature::Number = T₀,
	lay_direction::Int = 1,
)

	radius_in, radius_ext, diameter =
		_resolve_radius(radius_in, radius_wire, WireArray)
	radius_wire = diameter / 2
	rho = material_props.rho
	T0 = material_props.T0
	alpha = material_props.alpha
	radius_ext = num_wires == 1 ? diameter / 2 : radius_in + diameter

	mean_diameter, pitch_length, overlength = calc_helical_params(
		radius_in,
		radius_ext,
		lay_ratio,
	)

	cross_section = num_wires * (π * (diameter / 2)^2)

	R_wire =
		calc_tubular_resistance(0, diameter / 2, rho, alpha, T0, temperature) *
		overlength
	R_all_wires = R_wire / num_wires

	gmr = calc_wirearray_gmr(
		radius_in + (diameter / 2),
		num_wires,
		diameter / 2,
		material_props.mu_r,
	)

	# Initialize object
	return WireArray(
		radius_in,
		radius_ext,
		diameter / 2,
		num_wires,
		lay_ratio,
		mean_diameter,
		pitch_length,
		lay_direction,
		material_props,
		temperature,
		cross_section,
		R_all_wires,
		gmr,
	)
end

"""
$(TYPEDSIGNATURES)

Constructs a [`Strip`](@ref) object with specified geometric and material parameters.

# Arguments

- `radius_in`: Internal radius of the strip \\[m\\].
- `radius_ext`: External radius or thickness of the strip \\[m\\].
- `width`: Width of the strip \\[m\\].
- `lay_ratio`: Ratio defining the lay length of the strip \\[dimensionless\\].
- `material_props`: Material properties of the strip.
- `temperature`: Temperature at which the properties are evaluated \\[°C\\]. Defaults to T₀.
- `lay_direction`: Twisting direction of the strip (1 = unilay, -1 = contralay) \\[dimensionless\\]. Defaults to 1.

# Returns

- A [`Strip`](@ref) object with calculated geometric and electrical properties.

# Examples

```julia
material_props = Material(1.7241e-8, 1.0, 0.999994, 20.0, 0.00393)
strip = $(FUNCTIONNAME)(0.01, Thickness(0.002), 0.05, 10, material_props, temperature=25)
println(strip.cross_section) # Output: 0.0001 [m²]
println(strip.resistance)    # Output: Resistance value [Ω/m]
```

# See also

- [`Material`](@ref)
- [`Conductor`](@ref)
- [`calc_strip_resistance`](@ref)
- [`calc_tubular_gmr`](@ref)
- [`calc_helical_params`](@ref)
"""
function Strip(
	radius_in::Union{Number, <:AbstractCablePart},
	radius_ext::Union{Number, Thickness},
	width::Number,
	lay_ratio::Number,
	material_props::Material;
	temperature::Number = T₀,
	lay_direction::Int = 1,
)

	radius_in, radius_ext, thickness =
		_resolve_radius(radius_in, radius_ext, Strip)
	rho = material_props.rho
	T0 = material_props.T0
	alpha = material_props.alpha

	mean_diameter, pitch_length, overlength = calc_helical_params(
		radius_in,
		radius_ext,
		lay_ratio,
	)

	cross_section = thickness * width

	R_strip =
		calc_strip_resistance(thickness, width, rho, alpha, T0, temperature) *
		overlength

	gmr = calc_tubular_gmr(radius_ext, radius_in, material_props.mu_r)

	# Initialize object
	return Strip(
		radius_in,
		radius_ext,
		thickness,
		width,
		lay_ratio,
		mean_diameter,
		pitch_length,
		lay_direction,
		material_props,
		temperature,
		cross_section,
		R_strip,
		gmr,
	)
end

"""
$(TYPEDSIGNATURES)

Initializes a [`Tubular`](@ref) object with specified geometric and material parameters.

# Arguments

- `radius_in`: Internal radius of the tubular conductor \\[m\\].
- `radius_ext`: External radius of the tubular conductor \\[m\\].
- `material_props`: A [`Material`](@ref) object representing the physical properties of the conductor material.
- `temperature`: Temperature at which the properties are evaluated \\[°C\\]. Defaults to T₀.

# Returns

- An instance of [`Tubular`](@ref) initialized with calculated geometric and electrical properties.

# Examples

```julia
material_props = Material(1.7241e-8, 1.0, 0.999994, 20.0, 0.00393)
tubular = $(FUNCTIONNAME)(0.01, 0.02, material_props, temperature=25)
println(tubular.cross_section) # Output: 0.000942 [m²]
println(tubular.resistance)    # Output: Resistance value [Ω/m]
```

# See also

- [`Material`](@ref)
- [`calc_tubular_resistance`](@ref)
- [`calc_tubular_gmr`](@ref)
"""
function Tubular(
	radius_in::Union{Number, <:AbstractCablePart},
	radius_ext::Union{Number, Thickness},
	material_props::Material;
	temperature::Number = T₀,
)

	radius_in, radius_ext, thickness =
		_resolve_radius(radius_in, radius_ext, Tubular)

	rho = material_props.rho
	T0 = material_props.T0
	alpha = material_props.alpha

	cross_section = π * (radius_ext^2 - radius_in^2)

	R0 = calc_tubular_resistance(radius_in, radius_ext, rho, alpha, T0, temperature)

	gmr = calc_tubular_gmr(radius_ext, radius_in, material_props.mu_r)

	# Initialize object
	return Tubular(
		radius_in,
		radius_ext,
		material_props,
		temperature,
		cross_section,
		R0,
		gmr,
	)
end

"""
$(TYPEDSIGNATURES)

Constructs a [`Semicon`](@ref) instance with calculated electrical and geometric properties.

# Arguments

- `radius_in`: Internal radius of the semiconducting layer \\[m\\].
- `radius_ext`: External radius or thickness of the layer \\[m\\].
- `material_props`: Material properties of the semiconducting material.
- `temperature`: Operating temperature of the layer \\[°C\\] (default: T₀).

# Returns

- A [`Semicon`](@ref) object with initialized properties.

# Examples

```julia
material_props = Material(1e6, 2.3, 1.0, 20.0, 0.00393)
semicon_layer = $(FUNCTIONNAME)(0.01, Thickness(0.002), material_props, temperature=25)
println(semicon_layer.cross_section)      # Expected output: ~6.28e-5 [m²]
println(semicon_layer.resistance)         # Expected output: Resistance in [Ω/m]
println(semicon_layer.gmr)                # Expected output: GMR in [m]
println(semicon_layer.shunt_capacitance)  # Expected output: Capacitance in [F/m]
println(semicon_layer.shunt_conductance)  # Expected output: Conductance in [S/m]
```
"""
function Semicon(
	radius_in::Union{Number, <:AbstractCablePart},
	radius_ext::Union{Number, Thickness},
	material_props::Material;
	temperature::Number = T₀,
)

	rho = material_props.rho
	T0 = material_props.T0
	alpha = material_props.alpha
	epsr_r = material_props.eps_r

	radius_in, radius_ext, thickness =
		_resolve_radius(radius_in, radius_ext, Semicon)

	cross_section = π * (radius_ext^2 - radius_in^2)

	resistance =
		calc_tubular_resistance(radius_in, radius_ext, rho, alpha, T0, temperature)
	gmr = calc_tubular_gmr(radius_ext, radius_in, material_props.mu_r)
	shunt_capacitance = calc_shunt_capacitance(radius_in, radius_ext, epsr_r)
	shunt_conductance = calc_shunt_conductance(radius_in, radius_ext, rho)

	# Initialize object
	return Semicon(
		radius_in,
		radius_ext,
		material_props,
		temperature,
		cross_section,
		resistance,
		gmr,
		shunt_capacitance,
		shunt_conductance,
	)
end

"""
$(TYPEDSIGNATURES)

Constructs an [`Insulator`](@ref) object with specified geometric and material parameters.

# Arguments

- `radius_in`: Internal radius of the insulating layer \\[m\\].
- `radius_ext`: External radius or thickness of the layer \\[m\\].
- `material_props`: Material properties of the insulating material.
- `temperature`: Operating temperature of the insulator \\[°C\\].

# Returns

- An [`Insulator`](@ref) object with calculated electrical properties.

# Examples

```julia
material_props = Material(1e10, 3.0, 1.0, 20.0, 0.0)
insulator_layer = $(FUNCTIONNAME)(0.01, 0.015, material_props, temperature=25)
```
"""
function Insulator(
	radius_in::Union{Number, <:AbstractCablePart},
	radius_ext::Union{Number, Thickness},
	material_props::Material;
	temperature::Number = T₀,
)

	radius_in, radius_ext, thickness =
		_resolve_radius(radius_in, radius_ext, Insulator)
	rho = material_props.rho
	T0 = material_props.T0
	alpha = material_props.alpha
	epsr_r = material_props.eps_r

	cross_section = π * (radius_ext^2 - radius_in^2)

	resistance =
		calc_tubular_resistance(radius_in, radius_ext, rho, alpha, T0, temperature)
	gmr = calc_tubular_gmr(radius_ext, radius_in, material_props.mu_r)
	shunt_capacitance = calc_shunt_capacitance(radius_in, radius_ext, epsr_r)
	shunt_conductance = calc_shunt_conductance(radius_in, radius_ext, rho)

	# Initialize object
	return Insulator(
		radius_in,
		radius_ext,
		material_props,
		temperature,
		cross_section,
		resistance,
		gmr,
		shunt_capacitance,
		shunt_conductance,
	)
end

"""
$(TYPEDSIGNATURES)

Adds a new part to an existing [`Conductor`](@ref)  object and updates its equivalent electrical properties.

# Arguments

- `sc`: [`Conductor`](@ref) object to which the new part will be added ([`Conductor`](@ref)).
- `part_type`: Type of conductor part to add ([`AbstractConductorPart`](@ref)).
- `args...`: Positional arguments specific to the constructor of the `part_type` ([`AbstractConductorPart`](@ref)) \\[various\\].
- `kwargs...`: Named arguments for the constructor including optional values specific to the constructor of the `part_type` ([`AbstractConductorPart`](@ref)) \\[various\\].

# Returns

- The function modifies the [`Conductor`](@ref) instance in place and does not return a value.

# Notes

- Updates `gmr`, `resistance`, `alpha`, `radius_ext`, `cross_section`, and `num_wires` to account for the new part.
- The `temperature` of the new part defaults to the temperature of the first layer if not specified.
- The `radius_in` of the new part defaults to the external radius of the existing conductor if not specified.

!!! warning "Note"
	- When an [`AbstractCablePart`](@ref) is provided as `radius_in`, the constructor retrieves its `radius_ext` value, allowing the new cable part to be placed directly over the existing part in a layered cable design.
	- In case of uncertain measurements, if the added cable part is of a different type than the existing one, the uncertainty is removed from the radius value before being passed to the new component. This ensures that measurement uncertainties do not inappropriately cascade across different cable parts.

# Examples

```julia
material_props = Material(1.7241e-8, 1.0, 0.999994, 20.0, 0.00393)
conductor = Conductor(Strip(0.01, 0.002, 0.05, 10, material_props))
$(FUNCTIONNAME)(conductor, WireArray, 0.02, 0.002, 7, 15, material_props; temperature = 25)
```

# See also

- [`Conductor`](@ref)
- [`WireArray`](@ref)
- [`Strip`](@ref)
- [`Tubular`](@ref)
- [`calc_equivalent_gmr`](@ref)
- [`calc_parallel_equivalent`](@ref)
- [`calc_equivalent_alpha`](@ref)
"""
function addto_conductor!(
	sc::Conductor,
	part_type::Type{T},  # The type of conductor part (WireArray, Strip, Tubular)
	args...;  # Arguments specific to the part type
	kwargs...,
) where T <: AbstractConductorPart
	# Infer default properties
	radius_in = get(kwargs, :radius_in, sc.radius_ext)
	kwargs = merge((temperature = sc.layers[1].temperature,), kwargs)

	# Create the new part
	new_part = T(radius_in, args...; kwargs...)

	# Update the Conductor with the new part
	sc.gmr = calc_equivalent_gmr(sc, new_part)
	sc.alpha = calc_equivalent_alpha(
		sc.alpha,
		sc.resistance,
		new_part.material_props.alpha,
		new_part.resistance,
	)

	sc.resistance = calc_parallel_equivalent(sc.resistance, new_part.resistance)
	sc.radius_ext += (new_part.radius_ext - new_part.radius_in)
	sc.cross_section += new_part.cross_section
	sc.num_wires += new_part isa WireArray ? new_part.num_wires : 0
	push!(sc.layers, new_part)
	sc
end

"""
$(TYPEDSIGNATURES)

Generates a color representation for a [`Material`](@ref) based on its physical properties.

# Arguments

- `material_props`: Dictionary containing material properties:
  - `rho`: Electrical resistivity \\[Ω·m\\].
  - `eps_r`: Relative permittivity \\[dimensionless\\].
  - `mu_r`: Relative permeability \\[dimensionless\\].
- `rho_weight`: Weight assigned to resistivity in color blending (default: 1.0) \\[dimensionless\\].
- `epsr_weight`: Weight assigned to permittivity in color blending (default: 0.1) \\[dimensionless\\].
- `mur_weight`: Weight assigned to permeability in color blending (default: 0.1) \\[dimensionless\\].

# Returns

- An `RGBA` object representing the combined color based on the material's properties.

# Notes

Colors are normalized and weighted using property-specific gradients:
- Conductors (ρ ≤ 5ρ₀): White → Dark gray
- Poor conductors (5ρ₀ < ρ ≤ 10⁴): Bronze → Greenish-brown
- Insulators (ρ > 10⁴): Greenish-brown → Black
- Permittivity: Gray → Orange
- Permeability: Silver → Purple
- The overlay function combines colors with their respective alpha/weight values.

# Examples

```julia
material_props = Dict(
	:rho => 1.7241e-8,
	:eps_r => 2.3,
	:mu_r => 1.0
)
color = $(FUNCTIONNAME)(material_props)
println(color) # Expected output: RGBA(0.9, 0.9, 0.9, 1.0)
```
"""
function _get_material_color(
	material_props;
	rho_weight = 1.0, #0.8,
	epsr_weight = 0.1,
	mur_weight = 0.1,
)

	# Auxiliar function to combine colors
	function _overlay_colors(colors::Vector{<:RGBA})
		# Handle edge cases
		if length(colors) == 0
			return RGBA(0, 0, 0, 0)
		elseif length(colors) == 1
			return colors[1]
		end

		# Initialize with the first color
		r, g, b, a = red(colors[1]), green(colors[1]), blue(colors[1]), alpha(colors[1])

		# Single-pass overlay for the remaining colors
		for i in 2:length(colors)
			r2, g2, b2, a2 =
				red(colors[i]), green(colors[i]), blue(colors[i]), alpha(colors[i])
			a_new = a2 + a * (1 - a2)

			if a_new == 0
				r, g, b, a = 0, 0, 0, 0
			else
				r = (r2 * a2 + r * a * (1 - a2)) / a_new
				g = (g2 * a2 + g * a * (1 - a2)) / a_new
				b = (b2 * a2 + b * a * (1 - a2)) / a_new
				a = a_new
			end
		end

		return RGBA(r, g, b, a)
	end

	# Fixed normalization bounds
	epsr_min, epsr_max = 1.0, 1000.0  # Adjusted permittivity range for semiconductors
	mur_min, mur_max = 1.0, 300.0  # Relative permeability range
	rho_base = 1.72e-8

	# Extract nominal values for uncertain measurements
	rho = to_nominal(material_props.rho)
	epsr_r = to_nominal(material_props.eps_r)
	mu_r = to_nominal(material_props.mu_r)

	# Handle air/void
	if isinf(rho)
		return RGBA(1.0, 1.0, 1.0, 1.0)  # Transparent white
	end

	# Normalize epsr and mur
	epsr_norm = (epsr_r - epsr_min) / (epsr_max - epsr_min)
	mur_norm = (mu_r - mur_min) / (mur_max - mur_min)

	# Define color gradients based on resistivity
	if rho <= 5 * rho_base
		# Conductors: Bright metallic white → Darker metallic gray (logarithmic scaling)
		rho_norm = log10(rho / rho_base) / log10(5)  # Normalize based on `5 * rho_base`

		rho_color = get(cgrad([
				RGB(0.9, 0.9, 0.9),  # Almost white
				RGB(0.6, 0.6, 0.6),  # Light gray
				RGB(0.4, 0.4, 0.4)  # Dark gray
			]), clamp(rho_norm, 0.0, 1.0))

	elseif rho <= 10000
		# Poor conductors/semiconductors: Bronze → Gold → Reddish-brown → Dark orange → Greenish-brown
		rho_norm = (rho - 10e-8) / (10000 - 10e-8)
		rho_color = get(
			cgrad([
				RGB(0.8, 0.5, 0.2),  # Metallic bronze
				RGB(1.0, 0.85, 0.4),  # Metallic gold
				RGB(0.8, 0.4, 0.2),  # Reddish-brown
				RGB(0.8, 0.3, 0.1),  # Dark orange
				RGB(0.6, 0.4, 0.3),   # Greenish-brown
			]), rho_norm)
	else
		# Insulators: Greenish-brown → Black
		rho_norm = (rho - 10000) / (1e5 - 10000)
		rho_color = get(cgrad([RGB(0.6, 0.4, 0.3), :black]), clamp(rho_norm, 0.0, 1.0))
	end

	# Normalize epsr and mur values to [0, 1]
	epsr_norm = clamp(epsr_norm, 0.0, 1.0)
	mur_norm = clamp(mur_norm, 0.0, 1.0)

	# Create color gradients for epsr and mur
	epsr_color = get(cgrad([:gray, RGB(1.0, 0.9, 0.7), :orange]), epsr_norm)  # Custom amber
	mur_color = get(
		cgrad([:silver, :gray, RGB(0.9, 0.8, 1.0), :purple, RGB(0.3, 0.1, 0.6)]),
		mur_norm,
	)  # Custom purple

	# Apply weights to each property
	rho_color_w = Colors.RGBA(rho_color.r, rho_color.g, rho_color.b, rho_weight)
	epsr_color_w = Colors.RGBA(epsr_color.r, epsr_color.g, epsr_color.b, epsr_weight)
	mur_color_w = Colors.RGBA(mur_color.r, mur_color.g, mur_color.b, mur_weight)

	# Combine weighted colors
	final_color = _overlay_colors([rho_color_w, epsr_color_w, mur_color_w])

	return final_color
end

"""
$(TYPEDEF)

Represents a [`CableComponent`](@ref), i.e. a group of [`AbstractCablePart`](@ref) objects, with the equivalent geometric and material properties:

$(TYPEDFIELDS)

!!! info "Definition & application"
	Cable components operate as containers for multiple cable parts, allowing the calculation of effective electromagnetic (EM) properties (``\\sigma, \\varepsilon, \\mu``). This is performed by transforming the physical objects within the [`CableComponent`](@ref) into one equivalent coaxial homogeneous structure comprised of one conductor and one insulator.

	This procedure is the current modeling approach widely adopted in EMT-type simulations, and involves locking the internal and external radii of the conductor and insulator parts, respectively, and calculating the equivalent EM properties in order to match the previously determined values of R, L, C and G [916943](@cite) [1458878](@cite).

	In applications, the [`CableComponent`](@ref) type is mapped to the main cable structures described in manufacturer datasheets, e.g., core, sheath, armor and jacket.
"""
mutable struct CableComponent
	"Inner radius of the conductor \\[m\\]."
	radius_in_con::Number
	"Outer radius of the conductor \\[m\\]."
	radius_ext_con::Number
	"Equivalent resistivity of the conductor material \\[Ω·m\\]."
	rho_con::Number
	"Equivalent temperature coefficient of resistance of the conductor \\[1/°C\\]."
	alpha_con::Number
	"Equivalent magnetic permeability of the conductor material \\[H/m\\]."
	mu_con::Number
	"Outer radius of the insulator \\[m\\]."
	radius_ext_ins::Number
	"Equivalent permittivity of the insulator material \\[F/m\\]."
	eps_ins::Number
	"Equivalent magnetic permeability of the insulator material \\[H/m\\]."
	mu_ins::Number
	"Equivalent loss factor of the insulator \\[dimensionless\\]."
	loss_factor_ins::Number
	"Vector of cable parts ([`AbstractCablePart`](@ref))."
	component_data::Vector{<:AbstractCablePart}

	@doc """
	$(TYPEDSIGNATURES)

	Initializes a [`CableComponent`](@ref) object based on its parts and operating frequency. The constructor performs the following sequence of steps:

	1. Group conductors and insulators and calculate their corresponding thicknesses,  internal and external radii.
	2. Series R and L: calculate equivalent resistances through parallel combination, incorporate mutual coupling effects in inductances via GMR transformations.
	3. Shunt C and G: determine capacitances and dielectric losses through series association of components.
	4. Apply correction factors for conductor temperature and solenoid effects on insulation.
	5. Calculate the effective electromagnetic properties:

	| Quantity | Symbol | Function |
	|----------|--------|----------|
	| Resistivity (conductor) | ``\\rho_{con}`` | [`calc_equivalent_rho`](@ref) |
	| Permeability (conductor) | ``\\mu_{con}`` | [`calc_equivalent_mu`](@ref) |
	| Permittivity (insulation) | ``\\varepsilon_{ins}`` | [`calc_equivalent_eps`](@ref) |
	| Permeability (insulation) | ``\\mu_{ins}`` | [`calc_solenoid_correction`](@ref) |
	| Loss factor (insulation) | ``\\tan \\,  \\delta`` | [`calc_equivalent_lossfact`](@ref) |

	# Arguments

	- `component_data`: Vector of objects [`AbstractCablePart`](@ref).
	- `f`: Frequency of operation \\[Hz\\] (default: [`f₀`](@ref)).

	# Returns

	- A [`CableComponent`](@ref) instance with calculated equivalent properties.

	# Examples

	```julia
	components = [Conductor(...), Insulator(...)]
	cable = $(FUNCTIONNAME)(components, 50)  # Create cable component with base parameters @ 50 Hz
	```

	# See also

	- [`calc_equivalent_rho`](@ref)
	- [`calc_equivalent_mu`](@ref)
	- [`calc_equivalent_eps`](@ref)
	- [`calc_equivalent_lossfact`](@ref)
	- [`calc_solenoid_correction`](@ref)
	"""
	function CableComponent(
		component_data::Vector{<:AbstractCablePart},
		f::Number = f₀,
	)
		# Validate the geometry
		radius_exts = [part.radius_ext for part in component_data]
		if !issorted(radius_exts)
			error(
				"Components must be supplied in ascending order of radius_ext.",
			)
		end

		ω = 2 * π * f

		# Initialize conductor and insulator parameters
		radius_in_con = Inf
		radius_ext_con = 0.0
		rho_con = 0.0
		alpha_con = nothing
		mu_con = 0.0
		radius_ext_ins = 0.0
		eps_ins = 0.0
		mu_ins = 0.0
		loss_factor_ins = 0.0
		equiv_resistance = nothing
		equiv_admittance = nothing
		gmr_eff_con = nothing
		previous_part = nothing
		total_num_wires = 0
		weighted_num_turns = 0.0
		total_cross_section_ins = 0.0
		total_cross_section_con = 0.0

		# Helper function to extract equivalent parameters from conductor parts
		function _calc_weighted_num_turns(part)
			if part isa Conductor
				for sub_part in part.layers
					_calc_weighted_num_turns(sub_part)
				end
			elseif part isa WireArray || part isa Strip
				num_wires = part isa WireArray ? part.num_wires : 1
				total_num_wires += num_wires
				weighted_num_turns +=
					part.pitch_length > 0 ? num_wires * 1 / part.pitch_length : 0
			end
		end

		for (index, part) in enumerate(component_data)
			if part isa Conductor || part isa Strip || part isa WireArray ||
			   part isa Tubular

				if equiv_resistance === nothing
					alpha_con = part isa Conductor ? part.alpha : part.material_props.alpha
					equiv_resistance = part.resistance
				else
					alpha_new = part isa Conductor ? part.alpha : part.material_props.alpha
					alpha_con = calc_equivalent_alpha(
						alpha_con,
						equiv_resistance,
						alpha_new,
						part.resistance,
					)
					# (
					# 	alpha_con * part.resistance +
					# 	alpha_new * equiv_resistance
					# ) /
					# (equiv_resistance + part.resistance) # composite temperature coefficient

					equiv_resistance =
						calc_parallel_equivalent(equiv_resistance, part.resistance)
				end

				radius_in_con = min(radius_in_con, part.radius_in)
				radius_ext_con += (part.radius_ext - part.radius_in)
				total_num_wires += part.num_wires
				_calc_weighted_num_turns(part)

				if gmr_eff_con === nothing
					gmr_eff_con = part.gmr
					temp_con = part # creates a temporary conductor part to use in calc_gmd
				else
					temp_con.gmr = gmr_eff_con
					temp_con.cross_section = total_cross_section_con
					gmr_eff_con = calc_equivalent_gmr(temp_con, part)
					# TODO(feat): Refactor CableComponent constructor to remove redundancy 

				end
				total_cross_section_con += part.cross_section

			elseif part isa Semicon || part isa Insulator
				radius_ext_ins += (part.radius_ext - part.radius_in)
				Y = Complex(part.shunt_conductance, ω * part.shunt_capacitance)
				if equiv_admittance === nothing
					equiv_admittance = Y
				else
					equiv_admittance = calc_parallel_equivalent(equiv_admittance, Y)
				end
				mu_ins =
					(
						mu_ins * total_cross_section_ins +
						part.material_props.mu_r * part.cross_section
					) / (total_cross_section_ins + part.cross_section)

				total_cross_section_ins += part.cross_section
			end
			previous_part = part
		end

		# Conductor effective parameters
		radius_ext_con += radius_in_con
		rho_con = calc_equivalent_rho(equiv_resistance, radius_ext_con, radius_in_con)
		mu_con = calc_equivalent_mu(gmr_eff_con, radius_ext_con, radius_in_con)
		num_turns = weighted_num_turns / total_num_wires

		# Insulator effective parameters
		if radius_ext_ins > 0
			radius_ext_ins += radius_ext_con
			G_eq = real(equiv_admittance)
			C_eq = imag(equiv_admittance) / ω
			eps_ins = calc_equivalent_eps(C_eq, radius_ext_ins, radius_ext_con)
			loss_factor_ins = calc_equivalent_lossfact(G_eq, C_eq, ω)
			correction_mu_ins =
				calc_solenoid_correction(num_turns, radius_ext_con, radius_ext_ins)
			mu_ins = mu_ins * correction_mu_ins
		else
			radius_ext_ins = NaN
			eps_ins = NaN
			mu_ins = NaN
			loss_factor_ins = NaN
		end

		# Initialize object
		return new(
			# name,
			radius_in_con,
			radius_ext_con,
			rho_con,
			alpha_con,
			mu_con,
			radius_ext_ins,
			eps_ins,
			mu_ins,
			loss_factor_ins,
			component_data,
		)
	end
end

"""
$(TYPEDEF)

Stores the nominal electrical and geometric parameters for a cable design, with attributes:

$(TYPEDFIELDS)
"""
struct NominalData
	"Cable designation as per DIN VDE 0271/0276."
	designation_code::Union{Nothing, String}
	"Rated phase-to-earth voltage \\[kV\\]."
	U0::Union{Nothing, Number}
	"Rated phase-to-phase voltage \\[kV\\]."
	"Cross-sectional area of the conductor \\[mm²\\]."
	U::Union{Nothing, Number}
	conductor_cross_section::Union{Nothing, Number}
	"Cross-sectional area of the screen \\[mm²\\]."
	screen_cross_section::Union{Nothing, Number}
	"Cross-sectional area of the armor \\[mm²\\]."
	armor_cross_section::Union{Nothing, Number}
	"Base (DC) resistance of the cable core \\[Ω/km\\]."
	resistance::Union{Nothing, Number}
	"Capacitance of the main insulation \\[μF/km\\]."
	capacitance::Union{Nothing, Number}
	"Inductance of the cable (trifoil formation) \\[mH/km\\]."
	inductance::Union{Nothing, Number}

	@doc """
	$(TYPEDSIGNATURES)

	Initializes a [`NominalData`](@ref) object with optional default values.

	# Arguments
	- `designation_code`: Cable designation (default: `nothing`).
	- `U0`: Phase-to-earth voltage rating \\[kV\\] (default: `nothing`).
	- `U`: Phase-to-phase voltage rating \\[kV\\] (default: `nothing`).
	- `conductor_cross_section`: Conductor cross-section \\[mm²\\] (default: `nothing`).
	- `screen_cross_section`: Screen cross-section \\[mm²\\] (default: `nothing`).
	- `armor_cross_section`: Armor cross-section \\[mm²\\] (default: `nothing`).
	- `resistance`: Cable resistance \\[Ω/km\\] (default: `nothing`).
	- `capacitance`: Cable capacitance \\[μF/km\\] (default: `nothing`).
	- `inductance`: Cable inductance (trifoil) \\[mH/km\\] (default: `nothing`).

	# Returns
	An instance of [`NominalData`](@ref) with the specified nominal properties.

	# Examples
	```julia
	nominal_data = $(FUNCTIONNAME)(
		conductor_cross_section=1000,
		resistance=0.0291,
		capacitance=0.39,
	)
	println(nominal_data.conductor_cross_section)
	println(nominal_data.resistance)
	println(nominal_data.capacitance)
	```
	"""
	function NominalData(;
		designation_code::Union{Nothing, String} = nothing,
		U0::Union{Nothing, Number} = nothing,
		U::Union{Nothing, Number} = nothing,
		conductor_cross_section::Union{Nothing, Number} = nothing,
		screen_cross_section::Union{Nothing, Number} = nothing,
		armor_cross_section::Union{Nothing, Number} = nothing,
		resistance::Union{Nothing, Number} = nothing,
		capacitance::Union{Nothing, Number} = nothing,
		inductance::Union{Nothing, Number} = nothing,
	)
		return new(
			designation_code,
			U0,
			U,
			conductor_cross_section,
			screen_cross_section,
			armor_cross_section,
			resistance,
			capacitance,
			inductance,
		)
	end
end

"""
$(TYPEDEF)

Represents the design of a cable, including its unique identifier, nominal data, and components.

$(TYPEDFIELDS)
"""
mutable struct CableDesign
	"Unique identifier for the cable design."
	cable_id::String
	"Informative reference data."
	nominal_data::NominalData
	"Dictionary mapping component names to CableComponent objects."
	components::OrderedDict{String, CableComponent}

	@doc """
	$(TYPEDSIGNATURES)

	Constructs a [`CableDesign`](@ref) instance.

	# Arguments

	- `cable_id`: Unique identifier for the cable design.
	- `component_name`: Name of the first cable component.
	- `component_parts`: Vector of parts representing the subcomponents of the first cable component.
	- `f`: Frequency of operation \\[Hz\\]. Default: [`f₀`](@ref).
	- `nominal_data`: Reference data for the cable design. Default: `NominalData()`.

	# Returns

	- A [`CableDesign`](@ref) object with the specified properties.

	# Examples

	```julia
	parts = [Conductor(...), Insulator(...)]
	design = $(FUNCTIONNAME)("example", "ComponentA", parts, 50)
	```

	# See also

	- [`CableComponent`](@ref)
	"""
	function CableDesign(
		cable_id::String,
		component_name::String,
		component_parts::Vector{<:Any},
		f::Number = f₀;
		nominal_data::NominalData = NominalData(),
	)
		components = OrderedDict{String, CableComponent}()
		# Create and add the first component
		components[component_name] =
			CableComponent(Vector{AbstractCablePart}(component_parts), f)
		return new(cable_id, nominal_data, components)
	end
end

"""
$(TYPEDSIGNATURES)

Adds or replaces a cable component in an existing [`CableDesign`](@ref).

# Arguments

- `design`: A [`CableDesign`](@ref) object where the component will be added.
- `component_name`: The name of the cable component to be added.
- `component_parts`: A vector of parts representing the subcomponents of the cable component.
- `f`: The frequency of operation \\[Hz\\]. Default: [`f₀`](@ref).

# Returns

- Nothing. Modifies the [`CableDesign`](@ref) object in-place.

# Notes

If a component with the specified name already exists, it will be overwritten, and a warning will be logged.

# Examples

```julia
parts = [Conductor(...), Insulator(...)]
$(FUNCTIONNAME)(design, "ComponentB", parts, 60)
```

# See also

- [`CableDesign`](@ref)
- [`CableComponent`](@ref)
"""
function addto_design!(
	design::CableDesign,
	component_name::String,
	component_parts::Vector{<:Any},
	f::Number = f₀,
)
	if haskey(design.components, component_name)
		@warn "Component with name '$component_name' already exists in the CableDesign and will be overwritten."
	end
	# Construct the CableComponent internally
	design.components[component_name] =
		CableComponent(Vector{AbstractCablePart}(component_parts), f)
	design
end

"""
$(TYPEDSIGNATURES)

Extracts and displays data from a [`CableDesign`](@ref).

# Arguments

- `design`: A [`CableDesign`](@ref) object to extract data from.
- `format`: Symbol indicating the level of detail:
  - `:core`: Basic RLC parameters with nominal value comparison (default).
  - `:components`: Component-level equivalent properties.
  - `:detailed`: Individual cable part properties with layer-by-layer breakdown.
- `S`: Separation distance between cables \\[m\\] (only used for `:core` format). Default: outermost cable diameter.
- `rho_e`: Resistivity of the earth \\[Ω·m\\] (only used for `:core` format). Default: 100.

# Returns

- A `DataFrame` containing the requested cable data in the specified format.

# Examples

```julia
# Get basic RLC parameters
data = design_data(design)  # Default is :core format

# Get component-level data
comp_data = design_data(design, :components)

# Get detailed part-by-part breakdown
detailed_data = design_data(design, :detailed)

# Specify earth parameters for core calculations
core_data = design_data(design, :core, S=0.5, rho_e=150)
```

# See also

- [`CableDesign`](@ref)
- [`calc_tubular_resistance`](@ref)
- [`calc_inductance_trifoil`](@ref)
- [`calc_shunt_capacitance`](@ref)
"""
function design_data(
	design::CableDesign,
	format::Symbol = :core;
	S::Union{Nothing, Number} = nothing,
	rho_e::Number = 100,
)
	if format == :core
		# Core parameters calculation (
		cable_core = collect(values(design.components))[1]
		cable_shield = collect(values(design.components))[2]
		cable_outer = collect(values(design.components))[end]

		S =
			S === nothing ?
			(
				isnan(cable_outer.radius_ext_ins) ?
				2 * cable_outer.radius_ext_con :
				2 * cable_outer.radius_ext_ins
			) : S

		# Compute R, L, and C using given formulas
		R =
			calc_tubular_resistance(
				cable_core.radius_in_con,
				cable_core.radius_ext_con,
				cable_core.rho_con,
				0, 20, 20,
			) * 1e3

		L =
			calc_inductance_trifoil(
				cable_core.radius_in_con,
				cable_core.radius_ext_con,
				cable_core.rho_con,
				cable_core.mu_con,
				cable_shield.radius_in_con,
				cable_shield.radius_ext_con,
				cable_shield.rho_con,
				cable_shield.mu_con,
				S,
				rho_e = rho_e,
			) * 1e6

		C =
			calc_shunt_capacitance(
				cable_core.radius_ext_con,
				cable_core.radius_ext_ins,
				cable_core.eps_ins,
			) * 1e6 * 1e3

		# Prepare nominal values from CableDesign
		nominals = [
			design.nominal_data.resistance,
			design.nominal_data.inductance,
			design.nominal_data.capacitance,
		]

		# Calculate differences
		diffs = [
			abs(design.nominal_data.resistance - R) / design.nominal_data.resistance * 100,
			abs(design.nominal_data.inductance - L) / design.nominal_data.inductance * 100,
			abs(design.nominal_data.capacitance - C) / design.nominal_data.capacitance *
			100,
		]

		# Compute the comparison DataFrame
		data = DataFrame(
			parameter = ["R [Ω/km]", "L [mH/km]", "C [μF/km]"],
			computed = [R, L, C],
			nominal = nominals,
			percent_diff = diffs,
			lower = [to_lower(R), to_lower(L), to_lower(C)],
			upper = [to_upper(R), to_upper(L), to_upper(C)],
		)

		# Add compliance column
		data[!, "in_range?"] = [
			(data.nominal[i] >= data.lower[i] && data.nominal[i] <= data.upper[i])
			for i in 1:nrow(data)
		]

	elseif format == :components
		# Component-level properties 
		properties = [
			:radius_in_con,
			:radius_ext_con,
			:rho_con,
			:alpha_con,
			:mu_con,
			:radius_ext_ins,
			:eps_ins,
			:mu_ins,
			:loss_factor_ins,
		]

		# Initialize the DataFrame
		data = DataFrame(property = properties)

		for (key, part) in design.components
			col = key

			# Collect values for each property
			new_col = [
				:radius_in_con in fieldnames(typeof(part)) ?
				getfield(part, :radius_in_con) : missing,
				:radius_ext_con in fieldnames(typeof(part)) ?
				getfield(part, :radius_ext_con) : missing,
				:rho_con in fieldnames(typeof(part)) ?
				getfield(part, :rho_con) : missing,
				:alpha_con in fieldnames(typeof(part)) ?
				getfield(part, :alpha_con) : missing,
				:mu_con in fieldnames(typeof(part)) ?
				getfield(part, :mu_con) : missing,
				:radius_ext_ins in fieldnames(typeof(part)) ?
				getfield(part, :radius_ext_ins) : missing,
				:eps_ins in fieldnames(typeof(part)) ?
				getfield(part, :eps_ins) : missing,
				:mu_ins in fieldnames(typeof(part)) ?
				getfield(part, :mu_ins) : missing,
				:loss_factor_ins in fieldnames(typeof(part)) ?
				getfield(part, :loss_factor_ins) : missing,
			]

			# Add to DataFrame
			data[!, col] = new_col
		end

	elseif format == :detailed
		# Detailed part-by-part breakdown
		properties = [
			"type",
			"radius_in",
			"radius_ext",
			"diam_in",
			"diam_ext",
			"thickness",
			"cross_section",
			"num_wires",
			"resistance",
			"alpha",
			"gmr",
			"gmr/radius",
			"shunt_capacitance",
			"shunt_conductance",
		]

		# Initialize the DataFrame
		data = DataFrame(property = properties)

		# Iterate over components in the OrderedDict
		for (component_name, component) in design.components
			# Iterate over each part with index
			for (i, part) in enumerate(component.component_data)
				# Column name with layer number
				col = lowercase(component_name) * ", layer " * string(i)

				# Collect values for each property
				new_col = [
					lowercase(string(typeof(part))),  # type
					:radius_in in fieldnames(typeof(part)) ?
					getfield(part, :radius_in) : missing,
					:radius_ext in fieldnames(typeof(part)) ?
					getfield(part, :radius_ext) : missing,
					:radius_in in fieldnames(typeof(part)) ?
					2 * getfield(part, :radius_in) : missing,
					:radius_ext in fieldnames(typeof(part)) ?
					2 * getfield(part, :radius_ext) : missing,
					:radius_ext in fieldnames(typeof(part)) &&
					:radius_in in fieldnames(typeof(part)) ?
					(getfield(part, :radius_ext) - getfield(part, :radius_in)) :
					missing,
					:cross_section in fieldnames(typeof(part)) ?
					getfield(part, :cross_section) : missing,
					:num_wires in fieldnames(typeof(part)) ?
					getfield(part, :num_wires) : missing,
					:resistance in fieldnames(typeof(part)) ?
					getfield(part, :resistance) : missing,
					:alpha in fieldnames(typeof(part)) ?
					getfield(part, :alpha) : missing,
					:gmr in fieldnames(typeof(part)) ?
					getfield(part, :gmr) : missing,
					:gmr in fieldnames(typeof(part)) &&
					:radius_ext in fieldnames(typeof(part)) ?
					(getfield(part, :gmr) / getfield(part, :radius_ext)) : missing,
					:shunt_capacitance in fieldnames(typeof(part)) ?
					getfield(part, :shunt_capacitance) : missing,
					:shunt_conductance in fieldnames(typeof(part)) ?
					getfield(part, :shunt_conductance) : missing,
				]

				# Add to DataFrame
				data[!, col] = new_col
			end
		end
	else
		error("Unsupported format: $format. Use :core, :components, or :detailed")
	end

	return data
end

"""
$(TYPEDSIGNATURES)

Displays the cross-section of a cable design.

# Arguments

- `design`: A `[CableDesign`](@ref) object representing the cable structure.
- `x_offset`: Horizontal offset for the plot \\[m\\].
- `y_offset`: Vertical offset for the plot \\[m\\].
- `plt`: An optional `Plots.Plot` object to use for plotting.
- `display_plot`: Boolean flag to display the plot after rendering.
- `display_legend`: Boolean flag to display the legend in the plot.

# Returns

- A `Plots.Plot` object representing the visualized cable design.

# Examples

```julia
design = CableDesign("example", "core", [Conductor(...), Insulator(...)])
cable_plot = $(FUNCTIONNAME)(design)  # Cable cross-section is displayed
```

# See also

- [`CableDesign`](@ref)
- [`Conductor`](@ref)
- [`Insulator`](@ref)
- [`WireArray`](@ref)
- [`Tubular`](@ref)
- [`Strip`](@ref)
- [`Semicon`](@ref)
"""
function design_preview(
	design::CableDesign;
	x_offset = 0.0,
	y_offset = 0.0,
	plt = nothing,
	display_plot = true,
	display_legend = true,
)
	if isnothing(plt)
		plotlyjs()  # Initialize only if plt is not provided
		plt = plot(size = (800, 600),
			aspect_ratio = :equal,
			legend = (0.875, 1.0),
			title = "Cable design preview",
			xlabel = "y [m]",
			ylabel = "z [m]")
	end

	# Helper function to plot a layer
	function _plot_layer!(layer, label; x0 = 0.0, y0 = 0.0)
		if layer isa WireArray
			radius_wire = to_nominal(layer.radius_wire)
			num_wires = layer.num_wires

			lay_radius = num_wires == 1 ? 0 : to_nominal(layer.radius_in)
			material_props = layer.material_props
			color = _get_material_color(material_props)

			# Use the existing calc_wirearray_coords function to get wire centers
			wire_coords = calc_wirearray_coords(
				num_wires,
				radius_wire,
				to_nominal(lay_radius),
				C = (x0, y0),
			)

			# Plot each wire in the layer
			for (i, (x, y)) in enumerate(wire_coords)
				plot!(
					plt,
					Shape(
						x .+ radius_wire * cos.(0:0.01:2π),
						y .+ radius_wire * sin.(0:0.01:2π),
					),
					linecolor = :black,
					color = color,
					label = (i == 1 && display_legend) ? label : "",  # Only add label for first wire
				)
			end

		elseif layer isa Strip || layer isa Tubular || layer isa Semicon ||
			   layer isa Insulator
			radius_in = to_nominal(layer.radius_in)
			radius_ext = to_nominal(layer.radius_ext)
			material_props = layer.material_props
			color = _get_material_color(material_props)

			arcshape(θ1, θ2, rin, rext, x0 = 0.0, y0 = 0.0, N = 100) = begin
				# Outer circle coordinates
				outer_coords = Plots.partialcircle(θ1, θ2, N, rext)
				x_outer = first.(outer_coords) .+ x0
				y_outer = last.(outer_coords) .+ y0

				# Inner circle coordinates (reversed to close the shape properly)
				inner_coords = Plots.partialcircle(θ1, θ2, N, rin)
				x_inner = reverse(first.(inner_coords)) .+ x0
				y_inner = reverse(last.(inner_coords)) .+ y0

				Shape(vcat(x_outer, x_inner), vcat(y_outer, y_inner))
			end

			shape = arcshape(0, 2π + 0.01, radius_in, radius_ext, x0, y0)
			plot!(
				plt,
				shape,
				linecolor = color,
				color = color,
				label = display_legend ? label : "",
			)
		end
	end

	# Iterate over all CableComponents in the design
	for (name, component) in design.components
		# Iterate over all AbstractCablePart in the component
		for part in component.component_data
			# Check if the part has layers
			if part isa Conductor
				# Loop over each layer and add legend only for the first layer
				first_layer = true
				for layer in part.layers
					_plot_layer!(
						layer,
						first_layer ? lowercase(string(typeof(part))) : "",
						x0 = x_offset,
						y0 = y_offset,
					)
					first_layer = false
				end
			else
				# Plot the top-level part with legend entry
				_plot_layer!(
					part,
					lowercase(string(typeof(part))),
					x0 = x_offset,
					y0 = y_offset,
				)
			end
		end
	end

	if display_plot
		display(plt)
	end

	return plt
end

"""
$(TYPEDEF)

Represents a library of cable designs stored as a dictionary.

$(TYPEDFIELDS)
"""
mutable struct CablesLibrary
	"Dictionary mapping cable IDs to the respective CableDesign objects."
	cable_designs::Dict{String, CableDesign}

	@doc """
	$(TYPEDSIGNATURES)

	Constructs a [`CablesLibrary`](@ref) instance, optionally loading cable designs from a file.

	# Arguments

	- `file_name`: The name of the file to load cable designs from.

	# Returns

	- A [`CablesLibrary`](@ref) object containing the loaded cable designs or an empty dictionary.

	# Examples

	```julia
	# Create a new library without loading any file
	library = $(FUNCTIONNAME)()

	# Create a library and load designs from a file
	library_with_data = $(FUNCTIONNAME)(file_name="existing_library.jls")
	```

	# See also

	- [`CableDesign`](@ref)
	- [`store_cables_library!`](@ref)
	- [`remove_cables_library!`](@ref)
	- [`save_cables_library`](@ref)
	- [`list_cables_library`](@ref)
	"""
	function CablesLibrary(; file_name::String = "cables_library.jls")::CablesLibrary
		library = new(Dict{String, CableDesign}())
		if isfile(file_name)
			println("Loading cables database from $file_name...")
			_load_cables_from_jls!(library, file_name = file_name)
		else
			println("No $file_name found. Initializing empty cables database...")
		end
		return library
	end
end

"""
$(TYPEDSIGNATURES)

Loads cable designs from a serialized file into a [`CablesLibrary`](@ref) object.

# Arguments

- `library`: An instance of [`CablesLibrary`](@ref) to populate with the loaded cable designs.
- `file_name`: The name of the file to deserialize and load the cable designs from.

# Returns

- Nothing. Modifies the `cable_designs` field of the [`CablesLibrary`](@ref) object in-place.

# Examples

```julia
library = CablesLibrary()
$(FUNCTIONNAME)(library, file_name="cables_library.jls")
println(length(library.cable_designs))  # Prints the number of loaded cable designs
```

# See also

- [`CablesLibrary`](@ref)
"""
function _load_cables_from_jls!(library::CablesLibrary; file_name::String)
	try
		loaded_data = deserialize(file_name)
		if isa(loaded_data, Dict{String, CableDesign})
			library.cable_designs = loaded_data
			println("Cables database successfully loaded!")
		else
			println("Invalid file format in $file_name. Initializing empty database.")
		end
	catch e
		println("Error loading file $file_name: $e. Initializing empty database.")
	end
end

"""
$(TYPEDSIGNATURES)

Saves the cable designs from a [`CablesLibrary`](@ref) object to a `.jls` file.

# Arguments

- `library`: An instance of [`CablesLibrary`](@ref) whose cable designs are to be saved.
- `file_name`: The name of the file to save the cable designs to.

# Returns

- Nothing. Writes the serialized cable designs to the specified file.

# Examples

```julia
library = CablesLibrary()
# Add cable designs to the library
$(FUNCTIONNAME)(library, file_name="new_cables_library.jls")
```

# See also

- [`CablesLibrary`](@ref)
"""
function save_cables_library(
	library::CablesLibrary;
	file_name::String = "cables_library.jls",
)
	try
		serialize(file_name, library.cable_designs)
		return file_name
	catch e
		println("Error saving library to $file_name: $e")
	end

end

"""
Stores a cable design in a [`CablesLibrary`](@ref) object.

# Arguments

- `library`: An instance of [`CablesLibrary`](@ref) to which the cable design will be added.
- `design`: A [`CableDesign`](@ref) object representing the cable design to be added. This object must have a `cable_id` field to uniquely identify it.

# Returns

- None. Modifies the `cable_designs` field of the [`CablesLibrary`](@ref) object in-place by adding the new cable design.

# Examples
```julia
library = CablesLibrary()
design = CableDesign("example", ...) # Initialize CableDesign with required fields
store_cables_library!(library, design)
println(library.cable_designs) # Prints the updated dictionary containing the new cable design
```
# See also

- [`CablesLibrary`](@ref)
- [`CableDesign`](@ref)
- [`remove_cables_library!`](@ref)
"""
function store_cables_library!(library::CablesLibrary, design::CableDesign)
	library.cable_designs[design.cable_id] = design
	println("Cable design with ID `$(design.cable_id)` added to the library.")
	library
end

"""
$(TYPEDSIGNATURES)

Removes a cable design from a [`CablesLibrary`](@ref) object by its ID.

# Arguments

- `library`: An instance of [`CablesLibrary`](@ref) from which the cable design will be removed.
- `cable_id`: The ID of the cable design to remove.

# Returns

- Nothing. Modifies the `cable_designs` field of the [`CablesLibrary`](@ref) object in-place by removing the specified cable design if it exists.

# Examples

```julia
library = CablesLibrary()
design = CableDesign("example", ...) # Initialize a CableDesign
store_cables_library!(library, design)

# Remove the cable design
$(FUNCTIONNAME)(library, "example")
haskey(library.cable_designs, "example")  # Returns false
```

# See also

- [`CablesLibrary`](@ref)
- [`store_cables_library!`](@ref)
"""
function remove_cables_library!(library::CablesLibrary, cable_id::String)
	if haskey(library.cable_designs, cable_id)
		delete!(library.cable_designs, cable_id)
		println("Cable design with ID `$cable_id` removed from the library.")
	else
		println("Cable design with ID `$cable_id` not found in the library.")
	end
end

"""
$(TYPEDSIGNATURES)

Retrieves a cable design from a [`CablesLibrary`](@ref) object by its ID.

# Arguments

- `library`: An instance of [`CablesLibrary`](@ref) from which the cable design will be retrieved.
- `cable_id`: The ID of the cable design to retrieve.

# Returns

- A [`CableDesign`](@ref) object corresponding to the given `cable_id` if found, otherwise `nothing`.

# Examples

```julia
library = CablesLibrary()
design = CableDesign("example", ...) # Initialize a CableDesign
store_cables_library!(library, design)

# Retrieve the cable design
retrieved_design = $(FUNCTIONNAME)(library, "cable1")
println(retrieved_design.id)  # Prints "example"

# Attempt to retrieve a non-existent design
missing_design = $(FUNCTIONNAME)(library, "nonexistent_id")
println(missing_design === nothing)  # Prints true
```

# See also

- [`CablesLibrary`](@ref)
- [`CableDesign`](@ref)
- [`store_cables_library!`](@ref)
- [`remove_cables_library!`](@ref)
"""
function get_design(
	library::CablesLibrary,
	cable_id::String,
)::Union{Nothing, CableDesign}
	if haskey(library.cable_designs, cable_id)
		println("Cable design with ID `$cable_id` loaded from the library.")
		return library.cable_designs[cable_id]
	else
		println("Cable design with ID `$cable_id` not found.")
		return nothing
	end
end

"""
$(TYPEDSIGNATURES)

Lists the cable designs in a [`CablesLibrary`](@ref) object as a `DataFrame`.

# Arguments

- `library`: An instance of [`CablesLibrary`](@ref) whose cable designs are to be displayed.

# Returns

- A `DataFrame` object with the following columns:
  - `cable_id`: The unique identifier for each cable design.
  - `nominal_data`: A string representation of the nominal data for each cable design.
  - `components`: A comma-separated string listing the components of each cable design.

# Examples

```julia
library = CablesLibrary()
design1 = CableDesign("example1", nominal_data=NominalData(...), components=Dict("A"=>...))
design2 = CableDesign("example2", nominal_data=NominalData(...), components=Dict("C"=>...))
store_cables_library!(library, design1)
store_cables_library!(library, design2)

# Display the library as a DataFrame
df = $(FUNCTIONNAME)(library)
first(df, 5)  # Show the first 5 rows of the DataFrame
```

# See also

- [`CablesLibrary`](@ref)
- [`CableDesign`](@ref)
- [`store_cables_library!`](@ref)
"""
function list_cables_library(library::CablesLibrary)
	ids = keys(library.cable_designs)
	nominal_data = [string(design.nominal_data) for design in values(library.cable_designs)]
	components =
		[join(keys(design.components), ", ") for design in values(library.cable_designs)]
	df = DataFrame(
		cable_id = collect(ids),
		nominal_data = nominal_data,
		components = components,
	)
	return (df)
end

"""
$(TYPEDEF)

Represents a defined position and phase mapping of a cable within a system.

$(TYPEDFIELDS)
"""
struct CableDef
	"The [`CableDesign`](@ref) object assigned to this cable definition."
	cable::CableDesign
	"Horizontal coordinate \\[m\\]."
	horz::Number
	"Vertical coordinate \\[m\\]."
	vert::Number
	"Phase mapping vector (aligned with cable.components)."
	conn::Vector{Int}

	@doc """
	$(TYPEDSIGNATURES)

	Constructs a [`CableDef`](@ref) instance with specified cable design, coordinates, and phase mapping.

	# Arguments

	- `cable`: A [`CableDesign`](@ref) object defining the cable structure.
	- `horz`: Horizontal coordinate \\[m\\].
	- `vert`: Vertical coordinate \\[m\\].
	- `conn`: A dictionary mapping component names to phase indices, or `nothing` for default mapping.

	# Returns

	- A [`CableDef`](@ref) object with the assigned cable design, coordinates, and phase mapping.

	# Notes

	Components mapped to phase 0 will be eliminated (grounded). Components set to the same phase will be bundled into an equivalent phase.

	# Examples

	```julia
	cable_design = CableDesign("example", nominal_data, components_dict)
	xa, ya = 0.0, -1.0  # Coordinates in meters

	# With explicit phase mapping
	cabledef1 = $(FUNCTIONNAME)(cable_design, xa, ya, Dict("core" => 1))

	# With default phase mapping (first component to phase 1, others to 0)
	default_cabledef = $(FUNCTIONNAME)(cable_design, xa, ya)
	```

	# See also

	- [`CableDesign`](@ref)
	"""
	function CableDef(
		cable::CableDesign,
		horz::Number,
		vert::Number,
		conn::Union{Dict{String, Int}, Nothing} = nothing,
	)
		components = collect(keys(cable.components))  # Maintain ordered component names
		if isnothing(conn)
			conn_vector = [i == 1 ? 1 : 0 for i in 1:length(components)]  # Default: First component gets phase 1
		else
			conn_vector = [get(conn, name, 0) for name in components]  # Ensure correct mapping order
		end
		return new(cable, horz, vert, conn_vector)
	end
end

"""
$(TYPEDEF)

Represents a cable system configuration, defining the structure, earth resistivity, operating temperature, and phase assignments.

$(TYPEDFIELDS)
"""
mutable struct LineCableSystem
	"Unique identifier for the system."
	case_id::String
	"Operating temperature \\[°C\\]."
	T::Number
	"Earth properties model."
	earth_props::EarthModel
	"Length of the cable system \\[m\\]."
	line_length::Number
	"Number of cables in the system."
	num_cables::Int
	"Number of actual phases in the system."
	num_phases::Int
	"Cross-section cable definition."
	cables::Vector{CableDef}

	@doc """
	$(TYPEDSIGNATURES)

	Constructs a [`LineCableSystem`](@ref) with an initial cable definition and system parameters.

	# Arguments

	- `case_id`: Identifier for the cable system.
	- `T`: Operating temperature \\[°C\\].
	- `earth_props`: Instance of [`EarthModel`](@ref) defining the earth properties.
	- `line_length`: Length of the cable system \\[m\\].
	- `cable`: Initial [`CableDef`](@ref) object defining a cable position and phase mapping.

	# Returns

	- A [`LineCableSystem`](@ref) object initialized with a single cable definition.

	# Examples

	```julia
	earth_params = EarthModel(10.0 .^ range(0, stop=6, length=10), 100, 10, 1)
	cable_design = CableDesign("example", nominal_data, components_dict)
	cabledef1 = CableDef(cable_design, 0.0, 0.0, Dict("core" => 1))

	cable_system = $(FUNCTIONNAME)("test_case_1", 20.0, earth_params, 1000.0, cabledef1)
	println(cable_system.num_phases)  # Prints number of unique phase assignments
	```

	# See also

	- [`CableDef`](@ref)
	- [`EarthModel`](@ref)
	- [`CableDesign`](@ref)
	"""
	function LineCableSystem(
		case_id::String,
		T::Number,
		earth_props::EarthModel,
		line_length::Number,
		cable::CableDef,
	)
		# Initialize with the first cable definition
		num_cables = 1

		# Count unique nonzero phases from the first cable
		assigned_phases = unique(cable.conn)
		num_phases = count(x -> x > 0, assigned_phases)

		return new(case_id, T, earth_props, line_length, num_cables, num_phases, [cable])
	end
end

"""
$(TYPEDSIGNATURES)

Adds a new cable definition to an existing [`LineCableSystem`](@ref), updating its phase mapping and cable count.

# Arguments

- `system`: Instance of [`LineCableSystem`](@ref) to which the cable will be added.
- `cable`: Instance of [`CableDesign`](@ref) defining the cable structure.
- `horz`: Horizontal coordinate \\[m\\].
- `vert`: Vertical coordinate \\[m\\].
- `conn`: Dictionary mapping component names to phase indices, or `nothing` for automatic assignment.

# Returns

- Nothing. Modifies `system` in place by adding a new [`CableDef`](@ref) and updating `num_cables` and `num_phases`.

# Examples

```julia
earth_params = EarthModel(...)
cable_design = CableDesign("example", nominal_data, components_dict)

# Define coordinates for two cables
xa, ya = 0.0, -1.0
xb, yb = 1.0, -2.0

# Create initial system with one cable
cabledef1 = CableDef(cable_design, xa, ya, Dict("core" => 1))
cable_system = LineCableSystem("test_case_1", 20.0, earth_params, 1000.0, cabledef1)

# Add second cable to system
$(FUNCTIONNAME)(cable_system, cable_design, xb, yb, Dict("core" => 2))

println(cable_system.num_cables)  # Prints: 2
```

# See also

- [`LineCableSystem`](@ref)
- [`CableDef`](@ref)
- [`CableDesign`](@ref)
"""
function addto_system!(
	system::LineCableSystem,
	cable::CableDesign,
	horz::Number,
	vert::Number,
	conn::Union{Dict{String, Int}, Nothing} = nothing,
)
	max_phase =
		isempty(system.cables) ? 0 : maximum(maximum.(getfield.(system.cables, :conn)))

	component_names = keys(cable.components)  # Maintain the correct order

	new_conn = if isnothing(conn)
		Dict(name => (i == 1 ? max_phase + 1 : 0) for (i, name) in enumerate(component_names))
	else
		Dict(name => get(conn, name, 0) for name in component_names)  # Ensures correct mapping order
	end

	push!(system.cables, CableDef(cable, horz, vert, new_conn))

	# Update num_cables
	system.num_cables += 1

	# Update num_phases by counting unique nonzero phases
	assigned_phases = unique(vcat(values.(getfield.(system.cables, :conn))...))
	system.num_phases = count(x -> x > 0, assigned_phases)
	system
end

"""
$(TYPEDSIGNATURES)

Displays the cross-section of a cable system, including earth layers and cables.

# Arguments

- `system`: A [`LineCableSystem`](@ref) object containing the cable arrangement and earth properties.
- `zoom_factor`: A scaling factor for adjusting the x-axis limits \\[dimensionless\\].

# Returns

- Nothing. Displays a plot of the cable system cross-section with cables, earth layers (if applicable), and the air/earth interface.

# Examples

```julia
system = LineCableSystem("test_system", 20.0, earth_model, 1000.0, cable_def)
$(FUNCTIONNAME)(system, zoom_factor=0.5)
```

# See also

- [`LineCableSystem`](@ref)
- [`EarthModel`](@ref)
- [`CableDef`](@ref)
"""
function system_preview(system::LineCableSystem; zoom_factor = 0.25)
	plotlyjs()
	plt = plot(size = (800, 600),
		aspect_ratio = :equal,
		legend = (0.8, 0.9),
		title = "Cable system cross-section",
		xlabel = "y [m]",
		ylabel = "z [m]")

	# Plot the air/earth interface at y=0
	hline!(
		plt,
		[0],
		linestyle = :solid,
		linecolor = :black,
		linewidth = 1.25,
		label = "Air/earth interface",
	)

	# Determine explicit wide horizontal range for earth layer plotting
	x_positions = [to_nominal(cable.horz) for cable in system.cables]
	max_span = maximum(abs, x_positions) + 5  # extend 5 m beyond farthest cable position
	x_limits = [-max_span, max_span]

	# Plot earth layers if vertical_layers == false
	if !system.earth_props.vertical_layers
		layer_colors = [:burlywood, :sienna, :peru, :tan, :goldenrod, :chocolate]
		cumulative_depth = 0.0
		for (i, layer) in enumerate(system.earth_props.layers[2:end])
			# Skip bottommost infinite layer
			if isinf(layer.t)
				break
			end

			# Compute the depth of the current interface
			cumulative_depth -= layer.t
			hline!(
				plt,
				[cumulative_depth],
				linestyle = :solid,
				linecolor = layer_colors[mod1(i, length(layer_colors))],
				linewidth = 1.25,
				label = "Earth layer $i",
			)

			# Fill the area for current earth layer
			y_coords = [cumulative_depth + layer.t, cumulative_depth]
			plot!(plt, [x_limits[1], x_limits[2], x_limits[2], x_limits[1]],
				[y_coords[1], y_coords[1], y_coords[2], y_coords[2]],
				seriestype = :shape, color = layer_colors[mod1(i, length(layer_colors))],
				alpha = 0.25, linecolor = :transparent,
				label = "")
		end
	end

	for cabledef in system.cables
		x_offset = to_nominal(cabledef.horz)
		y_offset = to_nominal(cabledef.vert)
		design_preview(
			cabledef.cable;
			x_offset,
			y_offset,
			plt,
			display_plot = false,
			display_legend = false,
		)
	end

	plot!(plt, xlim = (x_limits[1], x_limits[2]) .* zoom_factor)

	display(plt)
	return plt
end

"""
$(TYPEDSIGNATURES)

Calculates the coordinates of three cables arranged in a trifoil pattern.

# Arguments

- `xc`: X-coordinate of the center point \\[m\\].
- `yc`: Y-coordinate of the center point \\[m\\].
- `r_ext`: External radius of the circular layout \\[m\\].

# Returns

- A tuple containing:
  - `xa`, `ya`: Coordinates of the top cable \\[m\\].
  - `xb`, `yb`: Coordinates of the bottom-left cable \\[m\\].
  - `xc`, `yc`: Coordinates of the bottom-right cable \\[m\\].

# Examples

```julia
xa, ya, xb, yb, xc, yc = $(FUNCTIONNAME)(0.0, 0.0, 0.035)
println((xa, ya))  # Coordinates of top cable
println((xb, yb))  # Coordinates of bottom-left cable
println((xc, yc))  # Coordinates of bottom-right cable
```
"""
function trifoil_formation(xc, yc, r_ext)
	# Horizontal distance between centers of adjacent circles (equal to twice the radius of each circle)
	d = 2 * r_ext
	# Vertical distance from top circle center to the line between bottom two circles
	h = sqrt(3) * r_ext

	# Calculate the top circle coordinates (centered directly above the midpoint of the bottom two circles)
	xa = xc
	ya = yc + h / 2

	# Calculate the coordinates of the bottom two circles
	xb = xc - d / 2
	yb = yc - h / 2
	xc = xc + d / 2
	yc = yc - h / 2

	return xa, ya, xb, yb, xc, yc
end

"""
$(TYPEDSIGNATURES)

Calculates the coordinates of three conductors arranged in a flat (horizontal or vertical) formation.

# Arguments

- `xc`: X-coordinate of the reference point \\[m\\].
- `yc`: Y-coordinate of the reference point \\[m\\].
- `s`: Spacing between adjacent conductors \\[m\\].
- `vertical`: Boolean flag indicating whether the formation is vertical.

# Returns

- A tuple containing:
  - `xa`, `ya`: Coordinates of the first conductor \\[m\\].
  - `xb`, `yb`: Coordinates of the second conductor \\[m\\].
  - `xc`, `yc`: Coordinates of the third conductor \\[m\\].

# Examples

```julia
# Horizontal formation
xa, ya, xb, yb, xc, yc = $(FUNCTIONNAME)(0.0, 0.0, 0.1)
println((xa, ya))  # First conductor coordinates
println((xb, yb))  # Second conductor coordinates
println((xc, yc))  # Third conductor coordinates

# Vertical formation
xa, ya, xb, yb, xc, yc = $(FUNCTIONNAME)(0.0, 0.0, 0.1, vertical=true)
```
"""
function flat_formation(xc, yc, s; vertical = false)
	if vertical
		# Layout is vertical; adjust only y-coordinates
		xa, ya = xc, yc
		xb, yb = xc, yc - s
		xc, yc = xc, yc - 2s
	else
		# Layout is horizontal; adjust only x-coordinates
		xa, ya = xc, yc
		xb, yb = xc + s, yc
		xc, yc = xc + 2s, yc
	end

	return xa, ya, xb, yb, xc, yc
end

"""
$(TYPEDSIGNATURES)

Generates a summary DataFrame for cable positions and phase mappings within a [`LineCableSystem`](@ref).

# Arguments

- `system`: A [`LineCableSystem`](@ref) object containing the cable definitions and their configurations.

# Returns

- A `DataFrame` containing:
  - `cable_id`: Identifier of each cable design.
  - `horz`: Horizontal coordinate of each cable \\[m\\].
  - `vert`: Vertical coordinate of each cable \\[m\\].
  - `phase_mapping`: Human-readable string representation mapping each cable component to its assigned phase.

# Examples

```julia
df = $(FUNCTIONNAME)(cable_system)
println(df)
# Output:
# │ cable_id   │ horz │ vert  │ phase_mapping           │
# │------------│------│-------│-------------------------│
# │ "Cable1"   │ 0.0  │ -0.5  │ core: 1, sheath: 0      │
# │ "Cable2"   │ 0.35 │ -1.25 │ core: 2, sheath: 0      │
```

# See also

- [`LineCableSystem`](@ref)
- [`CableDef`](@ref)
"""
function system_data(system::LineCableSystem)
	cable_ids = String[]
	horz_coords = Number[]
	vert_coords = Number[]
	mappings = String[]

	for cabledef in system.cables
		# Correct access here:
		push!(cable_ids, cabledef.cable.cable_id)
		push!(horz_coords, cabledef.horz)
		push!(vert_coords, cabledef.vert)

		component_names = collect(keys(cabledef.cable.components))
		mapping_str = join(
			["$(name): $(phase)" for (name, phase) in zip(component_names, cabledef.conn)],
			", ",
		)
		push!(mappings, mapping_str)
	end

	return DataFrame(
		cable_id = cable_ids,
		horz = horz_coords,
		vert = vert_coords,
		phase_mapping = mappings,
	)
end

"""
$(TYPEDSIGNATURES)

Defines the display representation of a [`Conductor`](@ref) object for REPL or text output.

# Arguments

- `io`: Output stream.
- `::MIME"text/plain"`: MIME type for plain text output.
- `conductor`: The [`Conductor`](@ref) instance to be displayed.

# Returns

- Nothing. Modifies `io` by writing text representation of the object.
"""
function Base.show(io::IO, ::MIME"text/plain", conductor::Conductor)
	# Compact property summary
	# List only the specific fields we want to display
	fields_to_show = [:radius_in, :radius_ext, :cross_section, :resistance, :gmr]

	print(io, "$(length(conductor.layers))-element $(nameof(typeof(conductor))): [")

	# Print only the selected fields that exist in the conductor
	displayed_fields = 0
	for field in fields_to_show
		if hasproperty(conductor, field)
			value = getproperty(conductor, field)
			# Add comma if not the first item
			if displayed_fields > 0
				print(io, ", ")
			end
			print(io, "$field=$(round(value, sigdigits=4))")
			displayed_fields += 1
		end
	end

	println(io, "]")

	# Tree-like layer representation

	for (i, layer) in enumerate(conductor.layers)
		# Determine prefix based on whether it's the last layer
		prefix = i == length(conductor.layers) ? "└─" : "├─"
		# Print layer information with only selected fields
		print(io, prefix, "$(nameof(typeof(layer))): [")

		displayed_fields = 0
		for field in fields_to_show
			if hasproperty(layer, field)
				value = getproperty(layer, field)
				# Add comma if not the first item
				if displayed_fields > 0
					print(io, ", ")
				end
				print(io, "$field=$(round(value, sigdigits=4))")
				displayed_fields += 1
			end
		end
		println(io, "]")
	end
end

"""
$(TYPEDSIGNATURES)

Defines the display representation of multiple [`AbstractConductorPart`](@ref) objects for REPL or text output.

# Arguments

- `io`: Output stream.
- `::MIME"text/plain"`: MIME type for plain text output.
- `v`: The [`AbstractConductorPart`](@ref) vector to be displayed.

# Returns

- Nothing. Modifies `io` by writing text representation of the object.
"""
function Base.show(
	io::IO,
	::MIME"text/plain",
	v::Vector{T},
) where {T <: AbstractConductorPart}
	fields_to_show = [:radius_in, :radius_ext, :cross_section, :resistance, :gmr]
	println(io, "$(length(v))-element Vector{$T}:")

	for (i, layer) in enumerate(v)
		# Determine prefix based on whether it's the last layer
		prefix = i == length(v) ? "└─" : "├─"
		# Print layer information
		fields = propertynames(layer)
		print(io, prefix, "$(nameof(typeof(layer))): [")
		displayed_fields = 0
		for field in fields_to_show
			if hasproperty(layer, field)
				value = getproperty(layer, field)
				# Add comma if not the first item
				if displayed_fields > 0
					print(io, ", ")
				end
				print(io, "$field=$(round(value, sigdigits=4))")
				displayed_fields += 1
			end
		end
		println(io, "]")
	end
end

"""
$(TYPEDSIGNATURES)

Defines the display representation of an [`AbstractCablePart`](@ref) object for REPL or text output.

# Arguments

- `io`: Output stream.
- `::MIME"text/plain"`: MIME type for plain text output.
- `part`: The [`AbstractCablePart`](@ref) instance to be displayed.

# Returns

- Nothing. Modifies `io` by writing text representation of the object.
"""
function Base.show(io::IO, ::MIME"text/plain", part::T) where {T <: AbstractCablePart}
	# Get the type name without module qualification
	type_name = string(nameof(T))

	# Define fields to display based on part type
	common_fields = [:radius_in, :radius_ext, :cross_section]
	specific_fields = if T <: AbstractConductorPart
		[:resistance, :gmr]
	elseif T <: AbstractInsulatorPart
		[:shunt_capacitance, :shunt_conductance]
	else
		Symbol[]
	end

	# Combine all relevant fields
	all_fields = [common_fields; specific_fields]

	# Get available fields that exist in this part
	available_fields = filter(field -> hasproperty(part, field), all_fields)

	# Start output with type name
	print(io, "$(type_name): [")

	# Print each field with proper formatting
	for (i, field) in enumerate(available_fields)
		value = getproperty(part, field)
		# Add comma only between items, not after the last one
		delimiter = i < length(available_fields) ? ", " : ""
		print(io, "$field=$(round(value, sigdigits=4))$delimiter")
	end

	println(io, "]")
end

"""
$(TYPEDSIGNATURES)

Defines the display representation of multiple [`AbstractCablePart`](@ref) objects for REPL or text output.

# Arguments

- `io`: Output stream.
- `::MIME"text/plain"`: MIME type for plain text output.
- `v`: The [`AbstractCablePart`](@ref) vector to be displayed.

# Returns

- Nothing. Modifies `io` by writing text representation of the object.
"""
function Base.show(io::IO, ::MIME"text/plain", v::Vector{T}) where {T <: AbstractCablePart}
	println(io, "$(length(v))-element Vector{$T}:")

	for (i, part) in enumerate(v)
		# Determine prefix based on whether it's the last layer
		prefix = i == length(v) ? "└─" : "├─"
		type_name = string(typeof(part))
		print(io, prefix, "$(type_name): [")

		# Collect fields to display based on part type
		common_fields = [:radius_in, :radius_ext, :cross_section]
		specific_fields = if part isa AbstractConductorPart
			[:resistance, :gmr]
		elseif part isa AbstractInsulatorPart
			[:shunt_capacitance, :shunt_conductance]
		else
			Symbol[]
		end

		# Combine all relevant fields
		all_fields = [common_fields; specific_fields]

		# Get available fields that exist in this part
		available_fields = filter(field -> hasproperty(part, field), all_fields)

		# Print each field with proper formatting
		for (j, field) in enumerate(available_fields)
			value = getproperty(part, field)
			# Add comma only between items, not after the last one
			delimiter = j < length(available_fields) ? ", " : ""
			print(io, "$field=$(round(value, sigdigits=4))$delimiter")
		end

		println(io, "]")
	end
end

"""
$(TYPEDSIGNATURES)

Defines the display representation of a [`CableDesign`](@ref) object for REPL or text output.

# Arguments

- `io`: Output stream.
- `::MIME"text/plain"`: MIME type for plain text output.
- `design`: The [`CableDesign`](@ref) object to be displayed.

# Returns

- Nothing. Modifies `io` by writing text representation of the object.
"""
function Base.show(io::IO, ::MIME"text/plain", design::CableDesign)
	# Print header with cable ID and count of components
	print(io, "$(length(design.components))-element CableDesign \"$(design.cable_id)\"")

	# Add nominal values if available
	nominal_values = []
	if design.nominal_data.resistance !== nothing
		push!(
			nominal_values,
			"resistance=$(round(design.nominal_data.resistance, sigdigits=4))",
		)
	end
	if design.nominal_data.inductance !== nothing
		push!(
			nominal_values,
			"inductance=$(round(design.nominal_data.inductance, sigdigits=4))",
		)
	end
	if design.nominal_data.capacitance !== nothing
		push!(
			nominal_values,
			"capacitance=$(round(design.nominal_data.capacitance, sigdigits=4))",
		)
	end

	if !isempty(nominal_values)
		print(io, ", with nominal values: [", join(nominal_values, ", "), "]")
	end
	println(io)

	# For each component, display its properties in a tree structure
	component_keys = collect(keys(design.components))
	for (i, key) in enumerate(component_keys)
		component = design.components[key]

		# Determine prefix based on whether it's the last component
		prefix = i == length(component_keys) ? "└─" : "├─"

		# Print component name and basic properties
		print(io, prefix, "Component \"", key, "\": [")

		# Collect relevant fields to display
		fields = [
			:radius_in_con, :radius_ext_con, :rho_con, :alpha_con, :mu_con,
			:radius_ext_ins, :eps_ins, :mu_ins, :loss_factor_ins,
		]

		# Filter to only fields that exist and aren't NaN
		displayed_fields = 0
		for field in fields
			if hasproperty(component, field)
				value = getproperty(component, field)
				if !(value isa Number && isnan(value))
					# Add comma if not the first item
					if displayed_fields > 0
						print(io, ", ")
					end
					print(io, "$field=$(round(value, sigdigits=4))")
					displayed_fields += 1
				end
			end
		end

		println(io, "]")

	end
end

"""
$(TYPEDSIGNATURES)

Defines the display representation of a [`CableComponent`](@ref) object for REPL or text output.

# Arguments

- `io`: Output stream.
- `::MIME"text/plain"`: MIME type for plain text output.
- `component`: The [`CableComponent`](@ref) object to be displayed.

# Returns

- Nothing. Modifies `io` by writing text representation of the object.
"""
function Base.show(io::IO, ::MIME"text/plain", component::CableComponent)
	# Print header with component count
	print(io, "$(length(component.component_data))-element CableComponent: [")

	# Collect relevant fields to display
	fields = [
		:radius_in_con, :radius_ext_con, :rho_con, :alpha_con, :mu_con,
		:radius_ext_ins, :eps_ins, :mu_ins, :loss_factor_ins,
	]

	# Filter to only fields that exist and aren't NaN
	displayed_fields = 0
	for field in fields
		if hasproperty(component, field)
			value = getproperty(component, field)
			if !(value isa Number && isnan(value))
				# Add comma if not the first item
				if displayed_fields > 0
					print(io, ", ")
				end
				print(io, "$field=$(round(value, sigdigits=4))")
				displayed_fields += 1
			end
		end
	end

	println(io, "]")

	# Display the component parts in a tree structure
	for (i, part) in enumerate(component.component_data)
		# Determine prefix based on whether it's the last part
		prefix = i == length(component.component_data) ? "└─" : "├─"

		# Print part information
		print(io, prefix, "$(nameof(typeof(part))): [")

		# Determine fields based on part type
		part_fields = if part isa AbstractConductorPart
			[:radius_in, :radius_ext, :cross_section, :resistance, :gmr]
		elseif part isa AbstractInsulatorPart
			[:radius_in, :radius_ext, :cross_section, :shunt_capacitance, :shunt_conductance]
		else
			[:radius_in, :radius_ext, :cross_section]
		end

		# Print each field with proper formatting
		for (j, field) in enumerate(part_fields)
			if hasproperty(part, field)
				value = getproperty(part, field)
				# Add comma only between items, not after the last one
				delimiter = j < length(part_fields) ? ", " : ""
				print(io, "$field=$(round(value, sigdigits=4))$delimiter")
			end
		end

		println(io, "]")
	end
end

function Base.show(io::IO, ::MIME"text/plain", system::LineCableSystem)
	# Print top level info
	println(
		io,
		"LineCableSystem \"$(system.case_id)\": [T=$(system.T), length=$(system.line_length), cables=$(system.num_cables), phases=$(system.num_phases)]",
	)

	# Print earth model summary
	# Get model type summary
	model_type = system.earth_props.num_layers == 2 ? "homogeneous" : "multilayer"
	orientation = system.earth_props.vertical_layers ? "vertical" : "horizontal"
	layer_word = (system.earth_props.num_layers - 1) == 1 ? "layer" : "layers"

	# Format earth model info
	earth_model_summary = "EarthModel: $(system.earth_props.num_layers-1) $(orientation) $(model_type) $(layer_word)"

	# Add formulation info if available
	if !isnothing(system.earth_props.FDformulation)
		formulation_tag =
			EarthProps._get_earth_formulation_tag(system.earth_props.FDformulation)
		earth_model_summary *= ", $(formulation_tag)"
	end

	println(io, "├─ $(earth_model_summary)")

	# Print cable definitions
	println(io, "└─ $(length(system.cables))-element CableDef:")

	# Display each cable definition
	for (i, cabledef) in enumerate(system.cables)
		# Cable prefix
		prefix = i == length(system.cables) ? "   └─" : "   ├─"

		# Format connections as a string
		components = collect(keys(cabledef.cable.components))
		conn_str = join(
			["$(comp)→$(phase)" for (comp, phase) in zip(components, cabledef.conn)],
			", ",
		)

		# Print cable info
		println(
			io,
			"$(prefix) CableDesign \"$(cabledef.cable.cable_id)\": [horz=$(round(cabledef.horz, sigdigits=4)), vert=$(round(cabledef.vert, sigdigits=4)), conn=[$(conn_str)]",
		)
	end
end
@reexport using .BaseParams
Utils.@_autoexport

end