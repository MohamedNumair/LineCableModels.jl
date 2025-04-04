"""
$(TYPEDEF)

Represents a composite conductor group assembled from multiple conductive layers or stranded wires.

This structure serves as a container for different [`AbstractConductorPart`](@ref) elements 
(such as wire arrays, strips, and tubular conductors) arranged in concentric layers. 
The `ConductorGroup` aggregates these individual parts and provides equivalent electrical 
properties that represent the composite behavior of the entire assembly, stored in the attributes:

$(TYPEDFIELDS)
"""
mutable struct ConductorGroup <: AbstractConductorPart
	"Inner radius of the conductor group \\[m\\]."
	radius_in::Number
	"Outer radius of the conductor group \\[m\\]."
	radius_ext::Number
	"Cross-sectional area of the entire conductor group \\[m²\\]."
	cross_section::Number
	"Number of individual wires in the conductor group \\[dimensionless\\]."
	num_wires::Number
	"Number of turns per meter of each wire strand \\[dimensionless\\]."
	num_turns::Number
	"DC resistance of the conductor group \\[Ω\\]."
	resistance::Number
	"Temperature coefficient of resistance \\[1/°C\\]."
	alpha::Number
	"Geometric mean radius of the conductor group \\[m\\]."
	gmr::Number
	"Vector of conductor layer components."
	layers::Vector{AbstractConductorPart}

	@doc """
	$(TYPEDSIGNATURES)

	Constructs a [`ConductorGroup`](@ref) instance initializing with the central conductor part.

	# Arguments

	- `central_conductor`: An [`AbstractConductorPart`](@ref) object located at the center of the conductor group.

	# Returns

	- A [`ConductorGroup`](@ref) object initialized with geometric and electrical properties derived from the central conductor.

	# Examples

	```julia
	material_props = Material(1.7241e-8, 1.0, 0.999994, 20.0, 0.00393)
	central_strip = Strip(0.01, 0.002, 0.05, 10, material_props)
	conductor_group = $(FUNCTIONNAME)(central_strip)
	println(conductor_group.layers)      # Output: [central_strip]
	println(conductor_group.resistance)  # Output: Resistance in \\[Ω\\]
	```
	"""
	function ConductorGroup(central_conductor::AbstractConductorPart)
		num_wires = 0
		num_turns = 0.0

		if central_conductor isa WireArray || central_conductor isa Strip
			num_wires = central_conductor isa WireArray ? central_conductor.num_wires : 1
			num_turns =
				central_conductor.pitch_length > 0 ?
				1 / central_conductor.pitch_length : 0
		end

		# Initialize object
		return new(
			central_conductor.radius_in,
			central_conductor.radius_ext,
			central_conductor.cross_section,
			num_wires,
			num_turns,
			central_conductor.resistance,
			central_conductor.material_props.alpha,
			central_conductor.gmr,
			[central_conductor],
		)
	end
end

"""
$(TYPEDEF)

Represents a composite coaxial insulator group assembled from multiple insulating layers.

This structure serves as a container for different [`AbstractInsulatorPart`](@ref) elements
(such as insulators and semiconductors) arranged in concentric layers.
The `InsulatorGroup` aggregates these individual parts and provides equivalent electrical
properties that represent the composite behavior of the entire assembly, stored in the attributes:

$(TYPEDFIELDS)
"""
mutable struct InsulatorGroup <: AbstractInsulatorPart
	"Inner radius of the insulator group \\[m\\]."
	radius_in::Number
	"Outer radius of the insulator group \\[m\\]."
	radius_ext::Number
	"Cross-sectional area of the entire insulator group \\[m²\\]."
	cross_section::Number
	"Shunt capacitance per unit length of the insulator group \\[F/m\\]."
	shunt_capacitance::Number
	"Shunt conductance per unit length of the insulator group \\[S/m\\]."
	shunt_conductance::Number
	"Vector of insulator layer components."
	layers::Vector{AbstractInsulatorPart}

	@doc """
	$(TYPEDSIGNATURES)

	Constructs an [`InsulatorGroup`](@ref) instance initializing with the initial insulator part.

	# Arguments

	- `initial_insulator`: An [`AbstractInsulatorPart`](@ref) object located at the innermost position of the insulator group.

	# Returns

	- An [`InsulatorGroup`](@ref) object initialized with geometric and electrical properties derived from the initial insulator.

	# Examples

	```julia
	material_props = Material(1e10, 3.0, 1.0, 20.0, 0.0)
	initial_insulator = Insulator(0.01, 0.015, material_props)
	insulator_group = $(FUNCTIONNAME)(initial_insulator)
	println(insulator_group.layers)           # Output: [initial_insulator]
	println(insulator_group.shunt_capacitance) # Output: Capacitance in \\[F/m\\]
	```
	"""
	function InsulatorGroup(initial_insulator::AbstractInsulatorPart)
		# Initialize object
		return new(
			initial_insulator.radius_in,
			initial_insulator.radius_ext,
			initial_insulator.cross_section,
			initial_insulator.shunt_capacitance,
			initial_insulator.shunt_conductance,
			[initial_insulator],
		)
	end
end

"""
$(TYPEDSIGNATURES)

Adds a new part to an existing [`ConductorGroup`](@ref) object and updates its equivalent electrical parameters.

# Arguments

- `group`: [`ConductorGroup`](@ref) object to which the new part will be added ([`ConductorGroup`](@ref)).
- `part_type`: Type of conductor part to add ([`AbstractConductorPart`](@ref)).
- `args...`: Positional arguments specific to the constructor of the `part_type` ([`AbstractConductorPart`](@ref)) \\[various\\].
- `kwargs...`: Named arguments for the constructor including optional values specific to the constructor of the `part_type` ([`AbstractConductorPart`](@ref)) \\[various\\].

# Returns

- The function modifies the [`ConductorGroup`](@ref) instance in place and does not return a value.

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
function addto_conductorgroup!(
	group::ConductorGroup,
	part_type::Type{T},  # The type of conductor part (WireArray, Strip, Tubular)
	args...;  # Arguments specific to the part type
	kwargs...,
) where T <: AbstractConductorPart
	# Infer default properties
	radius_in = get(kwargs, :radius_in, group.radius_ext)
	kwargs = merge((temperature = group.layers[1].temperature,), kwargs)

	# Create the new part
	new_part = T(radius_in, args...; kwargs...)

	# Update the Conductor with the new part
	group.gmr = calc_equivalent_gmr(group, new_part)
	group.alpha = calc_equivalent_alpha(
		group.alpha,
		group.resistance,
		new_part.material_props.alpha,
		new_part.resistance,
	)

	group.resistance = calc_parallel_equivalent(group.resistance, new_part.resistance)
	group.radius_ext += (new_part.radius_ext - new_part.radius_in)
	group.cross_section += new_part.cross_section

	# For WireArray, update the number of wires and turns
	if new_part isa WireArray || new_part isa Strip
		cum_num_wires = group.num_wires
		cum_num_turns = group.num_turns
		new_wires = new_part isa WireArray ? new_part.num_wires : 1
		new_turns = new_part.pitch_length > 0 ? 1 / new_part.pitch_length : 0
		group.num_wires += new_wires
		group.num_turns =
			(cum_num_wires * cum_num_turns + new_wires * new_turns) / (group.num_wires)
	end

	push!(group.layers, new_part)
	group
end

"""
$(TYPEDSIGNATURES)

Adds a new part to an existing [`InsulatorGroup`](@ref) object and updates its equivalent electrical parameters.

# Arguments

- `group`: [`InsulatorGroup`](@ref) object to which the new part will be added ([`InsulatorGroup`](@ref)).
- `part_type`: Type of insulator part to add ([`AbstractInsulatorPart`](@ref)).
- `args...`: Positional arguments specific to the constructor of the `part_type` ([`AbstractInsulatorPart`](@ref)) \\[various\\].
- `kwargs...`: Named arguments for the constructor including optional values specific to the constructor of the `part_type` ([`AbstractInsulatorPart`](@ref)) \\[various\\].

# Returns

- The function modifies the [`InsulatorGroup`](@ref) instance in place and does not return a value.

# Notes

- Updates `shunt_capacitance`, `shunt_conductance`, `radius_ext`, and `cross_section` to account for the new part.
- The `radius_in` of the new part defaults to the external radius of the existing insulator group if not specified.

!!! warning "Note"
	- When an [`AbstractCablePart`](@ref) is provided as `radius_in`, the constructor retrieves its `radius_ext` value, allowing the new cable part to be placed directly over the existing part in a layered cable design.
	- In case of uncertain measurements, if the added cable part is of a different type than the existing one, the uncertainty is removed from the radius value before being passed to the new component. This ensures that measurement uncertainties do not inappropriately cascade across different cable parts.

# Examples

```julia
material_props = Material(1e10, 3.0, 1.0, 20.0, 0.0)
insulator_group = InsulatorGroup(Insulator(0.01, 0.015, material_props))
$(FUNCTIONNAME)(insulator_group, Semicon, 0.015, 0.018, material_props)
```

# See also

- [`InsulatorGroup`](@ref)
- [`Insulator`](@ref)
- [`Semicon`](@ref)
- [`calc_equivalent_gmr`](@ref)
- [`calc_parallel_equivalent`](@ref)
- [`calc_equivalent_alpha`](@ref)
"""
function addto_insulatorgroup!(
	group::InsulatorGroup,
	part_type::Type{T},  # The type of insulator part (Insulator, Semicon)
	args...;  # Arguments specific to the part type
	f::Number = f₀,  # Add the f parameter with default value f₀
	kwargs...,
) where T <: AbstractInsulatorPart
	# Infer default properties
	radius_in = get(kwargs, :radius_in, group.radius_ext)
	kwargs = merge((temperature = group.layers[1].temperature,), kwargs...)

	# Create the new part
	new_part = T(radius_in, args...; kwargs...)

	# For admittances (parallel combination)
	ω = 2 * π * f
	Y_group = Complex(group.shunt_conductance, ω * group.shunt_capacitance)
	Y_newpart = Complex(new_part.shunt_conductance, ω * new_part.shunt_capacitance)
	Y_equiv = calc_parallel_equivalent(Y_group, Y_newpart)
	group.shunt_capacitance = imag(Y_equiv) / ω
	group.shunt_conductance = real(Y_equiv)

	# Update geometric properties
	group.radius_ext += (new_part.radius_ext - new_part.radius_in)
	group.cross_section += new_part.cross_section

	# Add to layers
	push!(group.layers, new_part)
	group
end

mutable struct CableComponent
	"Cable component identification (e.g. core/sheath/armor)."
	id::String
	"The conductor group containing all conductive parts."
	conductor_group::ConductorGroup
	"Effective properties of the composite conductor."
	conductor_props::Material
	"The insulator group containing all insulating parts."
	insulator_group::InsulatorGroup
	"Effective properties of the composite insulator."
	insulator_props::Material

	function CableComponent(
		id::String,
		conductor_group::ConductorGroup,
		insulator_group::InsulatorGroup)
		# Validate the geometry
		if conductor_group.radius_ext != insulator_group.radius_in
			error("Conductor outer radius must match insulator inner radius.")
		end

		# Use pre-calculated values from the groups
		radius_in_con = conductor_group.radius_in
		radius_ext_con = conductor_group.radius_ext
		radius_ext_ins = insulator_group.radius_ext

		# Equivalent conductor properties
		rho_con =
			calc_equivalent_rho(conductor_group.resistance, radius_ext_con, radius_in_con)
		mu_con = calc_equivalent_mu(conductor_group.gmr, radius_ext_con, radius_in_con)
		alpha_con = conductor_group.alpha
		conductor_props =
			Material(rho_con, 0.0, mu_con, conductor_group.layers[1].temperature, alpha_con)

		# Insulator properties
		C_eq = insulator_group.shunt_capacitance
		G_eq = insulator_group.shunt_conductance
		eps_ins = calc_equivalent_eps(C_eq, radius_ext_ins, radius_ext_con)
		rho_ins = 1 / calc_sigma_lossfact(G_eq, radius_ext_con, radius_ext_ins)
		correction_mu_ins = calc_solenoid_correction(
			conductor_group.num_turns,
			# 1 / conductor_group.layers[end].pitch_length,
			radius_ext_con,
			radius_ext_ins,
		)
		mu_ins = correction_mu_ins
		insulator_props =
			Material(rho_ins, eps_ins, mu_ins, insulator_group.layers[1].temperature, 0.0)

		# Initialize object
		return new(
			id,
			conductor_group,
			conductor_props,
			insulator_group,
			insulator_props,
		)
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
	# Calculate total number of parts across both groups
	total_parts =
		length(component.conductor_group.layers) + length(component.insulator_group.layers)

	# Print header
	println(io, "$(total_parts)-element CableComponent \"$(component.id)\":")

	# Display conductor group parts in a tree structure
	print(io, "├─ $(length(component.conductor_group.layers))-element ConductorGroup: [")
	_print_fields(
		io,
		component.conductor_group,
		[:radius_in, :radius_ext, :cross_section, :resistance, :gmr],
	)
	println(io, "]")
	print(io, "│  ", "├─", " Effective properties: [")
	_print_fields(io, component.conductor_props, [:rho, :eps_r, :mu_r, :alpha])
	println(io, "]")

	for (i, part) in enumerate(component.conductor_group.layers)

		prefix = i == length(component.conductor_group.layers) ? "└───" : "├───"

		# Print part information with proper indentation
		print(io, "│  ", prefix, " $(nameof(typeof(part))): [")

		# Print each field with proper formatting
		_print_fields(
			io,
			part,
			[:radius_in, :radius_ext, :cross_section, :resistance, :gmr],
		)

		println(io, "]")
	end

	# Display insulator group parts
	if !isempty(component.insulator_group.layers)
		print(
			io,
			"└─ $(length(component.insulator_group.layers))-element InsulatorGroup: [",
		)
		_print_fields(
			io,
			component.insulator_group,
			[
				:radius_in,
				:radius_ext,
				:cross_section,
				:shunt_capacitance,
				:shunt_conductance,
			],
		)
		println(io, "]")
		print(io, "   ", "├─", " Effective properties: [")
		_print_fields(io, component.insulator_props, [:rho, :eps_r, :mu_r, :alpha])
		println(io, "]")
		for (i, part) in enumerate(component.insulator_group.layers)
			# Determine prefix based on whether it's the last part
			prefix = i == length(component.insulator_group.layers) ? "└───" : "├───"

			# Print part information with proper indentation
			print(io, "   ", prefix, " $(nameof(typeof(part))): [")

			# Print each field with proper formatting
			_print_fields(
				io,
				part,
				[
					:radius_in,
					:radius_ext,
					:cross_section,
					:shunt_capacitance,
					:shunt_conductance,
				],
			)

			println(io, "]")
		end
	end
end
