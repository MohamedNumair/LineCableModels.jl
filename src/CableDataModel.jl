"""
WireArray: Represents an array of wires equally spaced around a circumference of arbitrary radius.

# Fields
- `radius_in`: Internal radius of the wire array [m].
- `radius_ext`: External radius of the wire array [m].
- `diameter`: Diameter of each individual wire [m].
- `num_wires`: Number of wires in the array.
- `lay_ratio`: Ratio defining the lay length of the wires (twisting factor).
- `mean_diameter`: Mean diameter of the wire array [m].
- `pitch_length`: Pitch length of the wire array [m].
- `material_props`: Dictionary containing material properties such as resistivity (`rho`), temperature coefficient (`alpha`), and reference temperature (`T0`).
- `temperature`: Temperature at which the properties are evaluated [°C].
- `cross_section`: Cross-sectional area of all wires in the array [m²].
- `resistance`: Electrical resistance per wire in the array [Ω].
- `gmr`: Geometric mean radius of the wire array [m].
"""
struct WireArray
	radius_in::Number
	radius_ext::Number
	diameter::Number
	num_wires::Int
	lay_ratio::Number
	mean_diameter::Number
	pitch_length::Number
	material_props::Dict{Symbol, Any}
	temperature::Number
	cross_section::Number
	resistance::Number
	gmr::Number

	"""
	Constructor: Initializes a `WireArray` object based on specified geometric and material parameters.

	# Arguments
	- `radius_in`: Internal radius of the wire array [m].
	- `diameter`: Diameter of each individual wire [m].
	- `num_wires`: Number of wires in the array.
	- `lay_ratio`: Ratio defining the lay length of the wires (twisting factor).
	- `material_props`: Dictionary containing material properties such as resistivity (`rho`), temperature coefficient (`alpha`), and reference temperature (`T0`).
	- `temperature`: Temperature at which the properties are evaluated [°C] (default: 20).

	# Returns
	- An instance of `WireArray` initialized with calculated geometric and electrical properties.

	# Examples
	```julia
	material_props = init_materials_db()
	wire_array = WireArray(0.01, 0.002, 7, 10, material_props, temperature=25)
	println(wire_array.mean_diameter) # Output: Mean diameter in m
	println(wire_array.resistance) # Output: Resistance in Ω
	```

	# References
	- None.
	"""
	function WireArray(
		radius_in::Number,
		diameter::Number,
		num_wires::Int,
		lay_ratio::Number,
		material_props::Dict{Symbol, Any};
		temperature::Number = 20,
	)
		rho = material_props[:rho]
		T0 = material_props[:T0]
		alpha = material_props[:alpha]
		mean_diameter = 2 * (radius_in + diameter / 2)
		radius_ext = num_wires == 1 ? diameter / 2 : radius_in + diameter
		pitch_length = lay_ratio * mean_diameter
		overlength = pitch_length != 0 ? sqrt(1 + (π * mean_diameter / pitch_length)^2) : 1

		cross_section = num_wires * (π * (diameter / 2)^2)

		R_wire =
			calc_tubular_resistance(0, diameter / 2, rho, alpha, T0, temperature) *
			overlength
		R_all_wires = R_wire / num_wires

		gmr = calc_wirearray_gmr(
			radius_in + (diameter / 2),
			num_wires,
			diameter / 2,
			material_props[:mu_r],
		)

		# Initialize object
		return new(
			radius_in,
			radius_ext,
			diameter,
			num_wires,
			lay_ratio,
			mean_diameter,
			pitch_length,
			material_props,
			temperature,
			cross_section,
			R_all_wires,
			gmr,
		)
	end
end

"""
Strip: Represents a conductive strip with geometric, material, and electrical properties.

# Fields
- `radius_in`: Inner radius of the strip [m].
- `radius_ext`: Outer radius of the strip [m].
- `thickness`: Thickness of the strip [m].
- `width`: Width of the strip [m].
- `lay_ratio`: Lay ratio of the strip, defining the relationship between pitch length and diameter (dimensionless).
- `mean_diameter`: Mean diameter of the strip [m].
- `pitch_length`: Pitch length of the strip [m].
- `material_props`: A dictionary containing material properties such as resistivity (`:rho`), reference temperature (`:T0`), temperature coefficient (`:alpha`), and relative permeability (`:mu_r`).
- `temperature`: Operating temperature of the strip [°C].
- `cross_section`: Cross-sectional area of the strip [m²].
- `resistance`: Electrical resistance of the strip [Ω].
- `gmr`: Geometric mean radius of the strip [m].
"""
struct Strip
	radius_in::Number
	radius_ext::Number
	thickness::Number
	width::Number
	lay_ratio::Number
	mean_diameter::Number
	pitch_length::Number
	material_props::Dict{Symbol, Any}
	temperature::Number
	cross_section::Number
	resistance::Number
	gmr::Number

	"""
	Constructor: Initializes a `Strip` object with given dimensions, lay ratio, material properties, and optional temperature.

	## Arguments
	- `radius_in`: Inner radius of the strip [m].
	- `thickness`: Thickness of the strip [m].
	- `width`: Width of the strip [m].
	- `lay_ratio`: Lay ratio of the strip (dimensionless).
	- `material_props`: Dictionary containing material properties (`:rho`, `:T0`, `:alpha`, `:mu_r`).
	- `temperature` (optional): Operating temperature of the strip [°C], default is 20°C.

	## Returns
	- A `Strip` object with calculated geometric, material, and electrical properties.

	# Examples
	```julia
	material_props = init_materials_db()
	strip = Strip(0.01, 0.002, 0.05, 10, material_props, temperature = 25)
	println(strip)
	```

	# References
	- None.
	"""
	function Strip(
		radius_in::Number,
		thickness::Number,
		width::Number,
		lay_ratio::Number,
		material_props::Dict{Symbol, Any};
		temperature::Number = 20,
	)
		rho = material_props[:rho]
		T0 = material_props[:T0]
		alpha = material_props[:alpha]
		radius_ext = radius_in + thickness
		mean_diameter = 2 * (radius_in + thickness / 2)
		pitch_length = lay_ratio * mean_diameter
		overlength = pitch_length != 0 ? sqrt(1 + (π * mean_diameter / pitch_length)^2) : 1

		cross_section = thickness * width

		R_strip =
			calc_strip_resistance(thickness, width, rho, alpha, T0, temperature) *
			overlength

		gmr = calc_tubular_gmr(radius_ext, radius_in, material_props[:mu_r])

		# Initialize object
		return new(
			radius_in,
			radius_ext,
			thickness,
			width,
			lay_ratio,
			mean_diameter,
			pitch_length,
			material_props,
			temperature,
			cross_section,
			R_strip,
			gmr,
		)
	end
end

"""
Tubular: Represents a tubular conductor with geometric, material, and electrical properties.

# Fields
- `radius_in`: Inner radius of the tubular conductor [m].
- `radius_ext`: Outer radius of the tubular conductor [m].
- `material_props`: A dictionary containing material properties such as resistivity (`:rho`), reference temperature (`:T0`), temperature coefficient (`:alpha`), and relative permeability (`:mu_r`).
- `temperature`: Operating temperature of the tubular conductor [°C].
- `cross_section`: Cross-sectional area of the tubular conductor [m²].
- `resistance`: Electrical resistance of the tubular conductor [Ω].
- `gmr`: Geometric mean radius of the tubular conductor [m].
"""
mutable struct Tubular
	radius_in::Number
	radius_ext::Number
	material_props::Dict{Symbol, Any}
	temperature::Number
	cross_section::Number
	resistance::Number
	gmr::Number

	"""
	Constructor: Initializes a `Tubular` object with specified inner and outer radii, material properties, and optional temperature.

	## Arguments
	- `radius_in`: Inner radius of the tubular conductor [m].
	- `radius_ext`: Outer radius of the tubular conductor [m].
	- `material_props`: Dictionary containing material properties (`:rho`, `:T0`, `:alpha`, `:mu_r`).
	- `temperature` (optional): Operating temperature of the tubular conductor [°C], default is 20°C.

	## Returns
	- A `Tubular` object with calculated geometric, material, and electrical properties.

	# Examples
	```julia
	material_props = Dict(:rho => 1.72e-8, :T0 => 20, :alpha => 0.004, :mu_r => 1.0)
	tubular = Tubular(0.01, 0.02, material_props, temperature = 25)
	println(tubular)
	```

	# References
	- None.
	"""
	function Tubular(
		radius_in::Number,
		radius_ext::Number,
		material_props::Dict{Symbol, Any};
		temperature::Number = 20,
	)

		rho = material_props[:rho]
		T0 = material_props[:T0]
		alpha = material_props[:alpha]

		cross_section = π * (radius_ext^2 - radius_in^2)

		R0 = calc_tubular_resistance(radius_in, radius_ext, rho, alpha, T0, temperature)

		gmr = calc_tubular_gmr(radius_ext, radius_in, material_props[:mu_r])

		# Initialize object
		return new(
			radius_in,
			radius_ext,
			material_props,
			temperature,
			cross_section,
			R0,
			gmr,
		)
	end
end

"""
Conductor: Represents a generic electrical conductor composed of multiple layers, which may include different conductor parts.

# Fields
- `radius_in`: Inner radius of the conductor [m].
- `radius_ext`: Outer radius of the conductor [m].
- `cross_section`: Cross-sectional area of the conductor [m²].
- `num_wires`: Number of wires in the conductor, applicable if the central part is a `WireArray` (dimensionless).
- `resistance`: Electrical resistance of the conductor [Ω].
- `gmr`: Geometric mean radius of the conductor [m].
- `layers`: A vector of conductor parts (`ConductorParts`), which can include `Strip`, `WireArray`, or `Tubular` components.
"""
const ConductorParts = Union{Strip, WireArray, Tubular}
mutable struct Conductor
	radius_in::Number
	radius_ext::Number
	cross_section::Number
	num_wires::Number
	resistance::Number
	gmr::Number
	layers::Vector{ConductorParts}

	"""
	# Constructor: Initializes a `Conductor` object with a central conductor part, which can be a `Strip`, `WireArray`, or `Tubular`.

	## Arguments
	- `central_conductor`: A component of type `ConductorParts` (either `Strip`, `WireArray`, or `Tubular`) representing the central part of the conductor.

	## Returns
	- A `Conductor` object with properties inherited from the central conductor and initialized layers.

	# Examples
	```julia
	material_props = init_materials_db()
	strip = Strip(0.01, 0.002, 0.05, 10, material_props, temperature = 25)
	conductor = Conductor(strip)
	println(conductor)
	```

	# References
	- None.
	"""
	function Conductor(central_conductor::ConductorParts)

		R0 = central_conductor.resistance
		gmr = central_conductor.gmr
		num_wires = central_conductor isa WireArray ? central_conductor.num_wires : 0
		# Initialize object
		return new(
			central_conductor.radius_in,
			central_conductor.radius_ext,
			central_conductor.cross_section,
			num_wires,
			R0,
			gmr,
			[central_conductor],
		)
	end
end
