"""
	save_cableslibrary_json(library::CablesLibrary; file_name::String = "cables_library.json")::String

Saves a [`CablesLibrary`](@ref) to a JSON file with the refactored structure.
Expects the new Vector-based component structure.

# Arguments
- `library`: Instance of [`CablesLibrary`](@ref) to be saved.
- `file_name`: Path to the output JSON file (default: `"cables_library.json"`).

# Returns
- The path of the saved JSON file.
"""
function _save_cableslibrary_json(
	library::CablesLibrary;
	file_name::String = "cables_library.json",
)::String
	serialized_designs = Dict{String, Any}()

	for (id, design) in library.cable_designs
		design_dict = Dict{String, Any}(
			"cable_id" => design.cable_id,
			"nominal_data" => serialize_nominal_data(design.nominal_data),
			"components" => [],
		)

		# Process components as a Vector
		for component in design.components
			comp_dict = Dict{String, Any}(
				"id" => component.id,
				"conductor_group" =>
					serialize_group_layers(component.conductor_group.layers),
				"insulator_group" =>
					serialize_group_layers(component.insulator_group.layers),
			)

			push!(design_dict["components"], comp_dict)
		end

		serialized_designs[id] = design_dict
	end

	open(file_name, "w") do io
		JSON3.pretty(io, serialized_designs)
	end

	return abspath(file_name)
end

"""
	serialize_group_layers(layers)

Serialize a group's layers with minimal required constructor parameters.
"""
function serialize_group_layers(layers)
	serialized_layers = []

	for layer in layers
		layer_type = typeof(layer)
		layer_dict = Dict{String, Any}(
			"type" => string(layer_type),
		)

		# Get all fields that might be needed for construction
		# Skip these fields as they're either derived or internal
		skip_fields = [:cross_section, :resistance, :gmr,
			:mean_diameter, :pitch_length, :overlength,
			:shunt_capacitance, :shunt_conductance]

		# Extract all other fields - potential constructor params
		for field in fieldnames(layer_type)
			if !(field in skip_fields) && hasproperty(layer, field)
				value = getfield(layer, field)

				# Handle special field types
				if value isa Material
					layer_dict[string(field)] = serialize_material(value)
				elseif !(value isa AbstractCablePart) &&
					   !(value isa Vector{<:AbstractCablePart})
					layer_dict[string(field)] = serialize_measurement(value)
				end
			end
		end

		push!(serialized_layers, layer_dict)
	end

	return serialized_layers
end

"""
	serialize_measurement(x)

Serialize a value, preserving measurement uncertainty if present.
"""
function serialize_measurement(x)
	if x isa Measurements.Measurement
		return Dict{String, Any}(
			"value" => Measurements.value(x),
			"uncertainty" => Measurements.uncertainty(x),
		)
	else
		return x
	end
end

"""
	serialize_material(material)

Serialize a Material object, preserving measurement uncertainties.
"""
function serialize_material(material)
	material_dict = Dict{String, Any}()

	for field in fieldnames(typeof(material))
		value = getfield(material, field)
		material_dict[string(field)] = serialize_measurement(value)
	end

	return material_dict
end

"""
	serialize_nominal_data(data)

Serialize NominalData, skipping nil values.
"""
function serialize_nominal_data(data)
	result = Dict{String, Any}()

	for field in fieldnames(typeof(data))
		value = getfield(data, field)
		if value !== nothing
			result[string(field)] = serialize_measurement(value)
		end
	end

	return result
end

##############################################################


"""
	_load_cableslibrary_json(file_name::String = "cables_library.json")::CablesLibrary

Loads a [`CablesLibrary`](@ref) from a JSON file created with `save_cableslibrary_json`.

# Arguments
- `file_name`: Path to the JSON file (default: `"cables_library.json"`).

# Returns
- A [`CablesLibrary`](@ref) instance with reconstructed cable designs.
"""
function _load_cableslibrary_json!(library, file_name::String)::CablesLibrary

	# Check if file exists
	if !isfile(file_name)
		@warn "File $file_name not found. Returning empty library."
		return library
	end

	# Load and parse the JSON
	json_data = open(file_name, "r") do io
		JSON3.read(io, Dict{String, Any})
	end

	# Process each design in the file
	for (id, design_data) in json_data
		# Reconstruct nominal data
		nominal_data = reconstruct_nominal_data(design_data["nominal_data"])

		# Reconstruct components
		components = CableComponent[]

		for comp_data in design_data["components"]
			# Get component ID
			comp_id = comp_data["id"]

			# Build conductor group
			conductor_layers = reconstruct_layers(comp_data["conductor_group"])
			conductor_group = ConductorGroup(conductor_layers[1])

			# Add additional conductor layers
			for layer in conductor_layers[2:end]
				addto_conductorgroup!(conductor_group, layer)
			end

			# Build insulator group
			insulator_layers = reconstruct_layers(comp_data["insulator_group"])
			insulator_group = InsulatorGroup(insulator_layers[1])

			# Add additional insulator layers
			for layer in insulator_layers[2:end]
				addto_insulatorgroup!(insulator_group, layer)
			end

			# Create component
			component = CableComponent(comp_id, conductor_group, insulator_group)
			push!(components, component)
		end

		# Create design
		design =
			CableDesign(design_data["cable_id"], components[1], nominal_data = nominal_data)

		# Add additional components
		for component in components[2:end]
			addto_cabledesign!(design, component)
		end

		# Add to library
		store_cableslibrary!(library, design)
	end

	return library
end

"""
	reconstruct_nominal_data(data::Dict)

Reconstructs a NominalData object from its serialized form.
"""
function reconstruct_nominal_data(data::Dict)
	# Extract fields with measurement handling
	designation_code = get(data, "designation_code", nothing)
	U0 = deserialize_measurement(get(data, "U0", nothing))
	U = deserialize_measurement(get(data, "U", nothing))
	conductor_cross_section =
		deserialize_measurement(get(data, "conductor_cross_section", nothing))
	screen_cross_section =
		deserialize_measurement(get(data, "screen_cross_section", nothing))
	armor_cross_section = deserialize_measurement(get(data, "armor_cross_section", nothing))
	resistance = deserialize_measurement(get(data, "resistance", nothing))
	capacitance = deserialize_measurement(get(data, "capacitance", nothing))
	inductance = deserialize_measurement(get(data, "inductance", nothing))

	# Create NominalData object
	return NominalData(
		designation_code = designation_code,
		U0 = U0,
		U = U,
		conductor_cross_section = conductor_cross_section,
		screen_cross_section = screen_cross_section,
		armor_cross_section = armor_cross_section,
		resistance = resistance,
		capacitance = capacitance,
		inductance = inductance,
	)
end

"""
	reconstruct_layers(layers_data::Vector)

Reconstructs cable part layers from their serialized form.
"""
function reconstruct_layers(layers_data::Vector)
	reconstructed_layers = AbstractCablePart[]

	for layer_data in layers_data
		layer_type = layer_data["type"]

		if endswith(layer_type, "WireArray")
			push!(reconstructed_layers, reconstruct_wirearray(layer_data))
		elseif endswith(layer_type, "Strip")
			push!(reconstructed_layers, reconstruct_strip(layer_data))
		elseif endswith(layer_type, "Tubular")
			push!(reconstructed_layers, reconstruct_tubular(layer_data))
		elseif endswith(layer_type, "Semicon")
			push!(reconstructed_layers, reconstruct_semicon(layer_data))
		elseif endswith(layer_type, "Insulator")
			push!(reconstructed_layers, reconstruct_insulator(layer_data))
		else
			@warn "Unknown layer type: $layer_type"
		end
	end

	return reconstructed_layers
end

"""
	reconstruct_wirearray(data::Dict)

Reconstructs a WireArray from its serialized form.
"""
function reconstruct_wirearray(data::Dict)
	material_props = reconstruct_material(data["material_props"])
	radius_in = deserialize_measurement(data["radius_in"])
	radius_wire = deserialize_measurement(data["radius_wire"])
	num_wires = data["num_wires"]
	lay_ratio = deserialize_measurement(data["lay_ratio"])
	temperature = deserialize_measurement(get(data, "temperature", T₀))
	lay_direction = get(data, "lay_direction", 1)

	return WireArray(
		radius_in,
		radius_wire,
		num_wires,
		lay_ratio,
		material_props;
		temperature = temperature,
		lay_direction = lay_direction,
	)
end

"""
	reconstruct_strip(data::Dict)

Reconstructs a Strip from its serialized form.
"""
function reconstruct_strip(data::Dict)
	material_props = reconstruct_material(data["material_props"])
	radius_in = deserialize_measurement(data["radius_in"])
	radius_ext = deserialize_measurement(data["radius_ext"])
	width = deserialize_measurement(data["width"])
	lay_ratio = deserialize_measurement(data["lay_ratio"])
	temperature = deserialize_measurement(get(data, "temperature", T₀))
	lay_direction = get(data, "lay_direction", 1)

	return Strip(
		radius_in,
		radius_ext,  # Pass radius_ext directly, not thickness
		width,
		lay_ratio,
		material_props;
		temperature = temperature,
		lay_direction = lay_direction,
	)
end

"""
	reconstruct_tubular(data::Dict)

Reconstructs a Tubular from its serialized form.
"""
function reconstruct_tubular(data::Dict)
	material_props = reconstruct_material(data["material_props"])
	radius_in = deserialize_measurement(data["radius_in"])
	radius_ext = deserialize_measurement(data["radius_ext"])
	temperature = deserialize_measurement(get(data, "temperature", T₀))

	return Tubular(
		radius_in,
		radius_ext,
		material_props;
		temperature = temperature,
	)
end

"""
	reconstruct_semicon(data::Dict)

Reconstructs a Semicon from its serialized form.
"""
function reconstruct_semicon(data::Dict)
	material_props = reconstruct_material(data["material_props"])
	radius_in = deserialize_measurement(data["radius_in"])
	radius_ext = deserialize_measurement(data["radius_ext"])
	temperature = deserialize_measurement(get(data, "temperature", T₀))

	return Semicon(
		radius_in,
		radius_ext,
		material_props;
		temperature = temperature,
	)
end

"""
	reconstruct_insulator(data::Dict)

Reconstructs an Insulator from its serialized form.
"""
function reconstruct_insulator(data::Dict)
	material_props = reconstruct_material(data["material_props"])
	radius_in = deserialize_measurement(data["radius_in"])
	radius_ext = deserialize_measurement(data["radius_ext"])
	temperature = deserialize_measurement(get(data, "temperature", T₀))

	return Insulator(
		radius_in,
		radius_ext,
		material_props;
		temperature = temperature,
	)
end

"""
	reconstruct_material(data::Dict)

Reconstructs a Material from its serialized form.
"""
function reconstruct_material(data::Dict)
	rho = deserialize_measurement(data["rho"])
	eps_r = deserialize_measurement(data["eps_r"])
	mu_r = deserialize_measurement(data["mu_r"])
	T0 = deserialize_measurement(data["T0"])
	alpha = deserialize_measurement(data["alpha"])

	return Material(rho, eps_r, mu_r, T0, alpha)
end

"""
	deserialize_measurement(value)

Recreates a measurement with uncertainty if present.
"""
function deserialize_measurement(value)
	if value isa Dict{String, Any} && haskey(value, "value") && haskey(value, "uncertainty")
		return value["value"] ± value["uncertainty"]
	else
		return value
	end
end

"""
	addto_conductorgroup!(group::ConductorGroup, part::AbstractConductorPart)

Helper method to add a pre-constructed part to a conductor group.
"""
function addto_conductorgroup!(group::ConductorGroup, part::AbstractConductorPart)
	# This is a fallback method that doesn't use the type parameterization
	# It directly adds a fully constructed part to the group

	# Update the Conductor with the new part
	group.gmr = calc_equivalent_gmr(group, part)
	group.alpha = calc_equivalent_alpha(
		group.alpha,
		group.resistance,
		part.material_props.alpha,
		part.resistance,
	)

	group.resistance = calc_parallel_equivalent(group.resistance, part.resistance)
	group.radius_ext += (part.radius_ext - part.radius_in)
	group.cross_section += part.cross_section

	# For WireArray and Strip, update the number of wires and turns
	if part isa WireArray || part isa Strip
		cum_num_wires = group.num_wires
		cum_num_turns = group.num_turns
		new_wires = part isa WireArray ? part.num_wires : 1
		new_turns = part.pitch_length > 0 ? 1 / part.pitch_length : 0
		group.num_wires += new_wires
		group.num_turns =
			(cum_num_wires * cum_num_turns + new_wires * new_turns) / (group.num_wires)
	end

	push!(group.layers, part)
	group
end

"""
	addto_insulatorgroup!(group::InsulatorGroup, part::AbstractInsulatorPart)

Helper method to add a pre-constructed part to an insulator group.
"""
function addto_insulatorgroup!(group::InsulatorGroup, part::AbstractInsulatorPart)
	# This is a fallback method that doesn't use the type parameterization
	# It directly adds a fully constructed part to the group

	# For admittances (parallel combination)
	ω = 2 * π * f₀  # Default frequency
	Y_group = Complex(group.shunt_conductance, ω * group.shunt_capacitance)
	Y_newpart = Complex(part.shunt_conductance, ω * part.shunt_capacitance)
	Y_equiv = calc_parallel_equivalent(Y_group, Y_newpart)
	group.shunt_capacitance = imag(Y_equiv) / ω
	group.shunt_conductance = real(Y_equiv)

	# Update geometric properties
	group.radius_ext += (part.radius_ext - part.radius_in)
	group.cross_section += part.cross_section

	# Add to layers
	push!(group.layers, part)
	group
end

"""
	save_cableslibrary(library::CablesLibrary; file_name::String = "cables_library.json")

Saves a [`CablesLibrary`](@ref) to a file, with the format determined by the file extension.

# Arguments
- `library`: Instance of [`CablesLibrary`](@ref) to be saved.
- `file_name`: Path to the output file. Extension determines the format (default: `"cables_library.json"`).
  - `.json`: JSON format (default)
  - `.jls`: Binary Julia serialization

# Returns
- The absolute path of the saved file.

# Examples
```julia
library = CablesLibrary()
save_cableslibrary(library)  # Default JSON format
save_cableslibrary(library, file_name = "backup.jls") # Binary format
```
"""
function save_cableslibrary(
	library::CablesLibrary;
	file_name::String = "cables_library.json",
)
	# Extract file extension
	_, ext = splitext(file_name)
	ext = lowercase(ext)

	# Dispatch based on extension
	if ext == ".jls"
		return _save_cableslibrary_jls(library, file_name = file_name)
	elseif ext == ".json"
		return _save_cableslibrary_json(library, file_name = file_name)
	else
		@warn "Unrecognized file extension '$ext'. Defaulting to .json format."
		return _save_cableslibrary_json(library, file_name = "$file_name.json")
	end
end

# Keep original function but make it private
function _save_cableslibrary_jls(
	library::CablesLibrary;
	file_name::String = "cables_library.jls",
)
	try
		serialize(file_name, library.cable_designs)
		return abspath(file_name)
	catch e
		println("Error saving library to $file_name: $e")
		return nothing
	end
end

"""
	load_cableslibrary(; file_name::String = "cables_library.json")::CablesLibrary

Loads a [`CablesLibrary`](@ref) from a file, with the format determined by the file extension.

# Arguments
- `file_name`: Path to the file to load. Extension determines the format (default: `"cables_library.json"`).
  - `.json`: JSON format (default)
  - `.jls`: Binary Julia serialization

# Returns
- A [`CablesLibrary`](@ref) instance with the loaded cable designs.

# Examples
```julia
# Load from JSON format (default)
library = load_cableslibrary()

# Load from binary format
library = load_cableslibrary(file_name = "backup.jls")
```
"""
function load_cableslibrary!(
	library;
	file_name::String = "cables_library.json",
)::CablesLibrary
	# Check if file exists
	if !isfile(file_name)
		@warn "File $file_name not found. Initializing empty library."
		return library
	end

	# Extract file extension
	_, ext = splitext(file_name)
	ext = lowercase(ext)

	# Dispatch based on extension
	if ext == ".jls"
		return _load_cableslibrary_jls!(library, file_name)
	elseif ext == ".json"
		return _load_cableslibrary_json!(library, file_name)
	else
		@warn "Unrecognized file extension '$ext'. Attempting to load as .json format."
		return _load_cableslibrary_json!(library, file_name)
	end
end
