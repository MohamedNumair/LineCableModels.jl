"""
WireArray: Represents an array of wires equally spaced around a circumference of arbitrary radius.
"""
struct WireArray
	radius_in::Number
	radius_ext::Number
	diameter::Number
	num_wires::Int
	lay_ratio::Number
	mean_diameter::Number
	pitch_length::Number
	material_props::Material
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
	- `material_props`: A `Material` object representing the material properties (e.g., resistivity, temperature coefficient).
	- `temperature`: Temperature at which the properties are evaluated [°C] (default: 20).

	# Returns
	An instance of `WireArray` initialized with calculated geometric and electrical properties:
	- `radius_in`: Internal radius of the wire array [m].
	- `radius_ext`: External radius of the wire array [m].
	- `diameter`: Diameter of each individual wire [m].
	- `num_wires`: Number of wires in the array.
	- `lay_ratio`: Ratio defining the lay length of the wires (twisting factor).
	- `mean_diameter`: Mean diameter of the wire array [m].
	- `pitch_length`: Pitch length of the wire array [m].
	- `material_props`: A `Material` object representing the physical properties of the wire material.
	- `temperature`: Temperature at which the properties are evaluated [°C].
	- `cross_section`: Cross-sectional area of all wires in the array [m²].
	- `resistance`: Electrical resistance per wire in the array [Ω].
	- `gmr`: Geometric mean radius of the wire array [m].

	# Dependencies
	This constructor uses the following custom functions:
	- `calc_tubular_resistance`: Computes the DC resistance of the wires.
	- `calc_wirearray_gmr`: Calculates the geometric mean radius (GMR) of the wire array.

	# Examples
	```julia
	material_props = Material(1.7241e-8, 1.0, 0.999994, 20.0, 0.00393)
	wire_array = WireArray(0.01, 0.002, 7, 10, material_props, temperature=25)
	println(wire_array.mean_diameter) # Outputs: Mean diameter in m
	println(wire_array.resistance)    # Outputs: Resistance in Ω
	```

	# References
	- None.
	"""
	function WireArray(
		radius_in::Union{Number, <:Any},
		diameter::Number,
		num_wires::Int,
		lay_ratio::Number,
		material_props::Material;
		temperature::Number = 20,
	)

		# Extract `radius_in` from `radius_ext` if a custom type is provided
		radius_in = radius_in isa Number ? radius_in : getfield(radius_in, :radius_ext)

		rho = material_props.rho
		T0 = material_props.T0
		alpha = material_props.alpha
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
			material_props.mu_r,
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
Strip: Represents a flat conductive strip with defined geometric and material properties.
"""
struct Strip
	radius_in::Number
	radius_ext::Number
	thickness::Number
	width::Number
	lay_ratio::Number
	mean_diameter::Number
	pitch_length::Number
	material_props::Material
	temperature::Number
	cross_section::Number
	resistance::Number
	gmr::Number

	"""
	Constructor: Initializes a `Strip` object with specified geometric and material parameters.

	# Arguments
	- `radius_in`: Internal radius of the strip [m].
	- `thickness`: Thickness of the strip [m].
	- `width`: Width of the strip [m].
	- `lay_ratio`: Ratio defining the lay length of the strip (twisting factor).
	- `material_props`: A `Material` object representing the physical properties of the strip material.
	- `temperature`: Temperature at which the properties are evaluated [°C] (default: 20).

	# Returns
	An instance of `Strip` initialized with calculated geometric and electrical properties.

	# Dependencies
	- `calc_strip_resistance`: Computes the DC resistance of the strip.
	- `calc_tubular_gmr`: Calculates the geometric mean radius (GMR) of the strip.

	# Examples
	```julia
	material_props = Material(1.7241e-8, 1.0, 0.999994, 20.0, 0.00393)
	strip = Strip(0.01, 0.002, 0.05, 10, material_props, temperature=25)
	println(strip.cross_section) # Outputs: Cross-sectional area in m²
	println(strip.resistance)    # Outputs: Resistance in Ω
	```

	# References
	- None.
	"""
	function Strip(
		radius_in::Number,
		thickness::Number,
		width::Number,
		lay_ratio::Number,
		material_props::Material;
		temperature::Number = 20,
	)
		rho = material_props.rho
		T0 = material_props.T0
		alpha = material_props.alpha
		radius_ext = radius_in + thickness
		mean_diameter = 2 * (radius_in + thickness / 2)
		pitch_length = lay_ratio * mean_diameter
		overlength = pitch_length != 0 ? sqrt(1 + (π * mean_diameter / pitch_length)^2) : 1

		cross_section = thickness * width

		R_strip =
			calc_strip_resistance(thickness, width, rho, alpha, T0, temperature) *
			overlength

		gmr = calc_tubular_gmr(radius_ext, radius_in, material_props.mu_r)

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
Tubular: Represents a tubular or solid (radius_in=0) conductor with defined geometric and material properties.
"""
mutable struct Tubular
	radius_in::Number
	radius_ext::Number
	material_props::Material
	temperature::Number
	cross_section::Number
	resistance::Number
	gmr::Number

	"""
	Constructor: Initializes a `Tubular` object with specified geometric and material parameters.

	# Arguments
	- `radius_in`: Internal radius of the tubular conductor [m].
	- `radius_ext`: External radius of the tubular conductor [m].
	- `material_props`: A `Material` object representing the physical properties of the conductor material.
	- `temperature`: Temperature at which the properties are evaluated [°C] (default: 20).

	# Returns
	An instance of `Tubular` initialized with calculated geometric and electrical properties.

	# Dependencies
	- `calc_tubular_resistance`: Computes the DC resistance of the tubular conductor.
	- `calc_tubular_gmr`: Calculates the geometric mean radius (GMR) of the tubular conductor.

	# Examples
	```julia
	material_props = Material(1.7241e-8, 1.0, 0.999994, 20.0, 0.00393)
	tubular = Tubular(0.01, 0.02, material_props, temperature=25)
	println(tubular.cross_section) # Outputs: Cross-sectional area in m²
	println(tubular.resistance)    # Outputs: Resistance in Ω
	```

	# References
	- None.
	"""
	function Tubular(
		radius_in::Union{Number, <:Any},
		radius_ext::Number,
		material_props::Material;
		temperature::Number = 20,
	)

		# Extract `radius_in` from `radius_ext` if a custom type is provided
		radius_in = radius_in isa Number ? radius_in : getfield(radius_in, :radius_ext)

		rho = material_props.rho
		T0 = material_props.T0
		alpha = material_props.alpha

		cross_section = π * (radius_ext^2 - radius_in^2)

		R0 = calc_tubular_resistance(radius_in, radius_ext, rho, alpha, T0, temperature)

		gmr = calc_tubular_gmr(radius_ext, radius_in, material_props.mu_r)

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
ConductorParts: Defines an abstract conductor type which may be a `WireArray`, `Tubular` or `Strip`, used for composite conductor modeling.
"""
const ConductorParts = Union{WireArray, Tubular, Strip}

"""
Conductor: Represents a composite coaxial conductor consisting of multiple layers of different `ConductorParts`.
"""
mutable struct Conductor
	radius_in::Number
	radius_ext::Number
	cross_section::Number
	num_wires::Number
	resistance::Number
	gmr::Number
	layers::Vector{ConductorParts}

	"""
	Constructor: Initializes a `Conductor` object using a central conductor part (e.g., Strip, WireArray, or Tubular).

	# Arguments
	- `central_conductor`: A `ConductorParts` object (Strip, WireArray, or Tubular) representing the central part of the conductor.

	# Returns
	An instance of `Conductor` initialized with geometric and electrical properties derived from the central conductor.

	# Examples
	```julia
	material_props = Material(1.7241e-8, 1.0, 0.999994, 20.0, 0.00393)
	central_strip = Strip(0.01, 0.002, 0.05, 10, material_props)
	conductor = Conductor(central_strip)
	println(conductor.layers) # Outputs: [central_strip]
	println(conductor.resistance) # Outputs: Resistance in Ω
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

"""
add_conductor_part!: Adds a new part to an existing `Conductor` object and updates its properties.

# Arguments
- `sc`: A `Conductor` object to which the new part will be added.
- `part_type`: The type of the conductor part to be added (`WireArray`, `Strip`, or `Tubular`).
- `args...`: Positional arguments specific to the constructor of the `part_type`.
- `kwargs...`: Named arguments for the constructor of the `part_type`. Includes optional properties such as `radius_in` and `temperature`.

# Returns
- None. Modifies the `Conductor` instance in place by adding the specified part and updating its properties:
- Updates `gmr`, `resistance`, `radius_ext`, `cross_section`, and `num_wires` to account for the new part.

# Dependencies
- `calc_equivalent_gmr`: Calculates the equivalent geometric mean radius (GMR) after adding the new part.
- `calc_parallel_equivalent`: Computes the parallel equivalent resistance of the conductor.

# Examples
```julia
material_props = Material(1.7241e-8, 1.0, 0.999994, 20.0, 0.00393)
conductor = Conductor(Strip(0.01, 0.002, 0.05, 10, material_props))
add_conductor_part!(
	conductor, WireArray, 0.02, 0.002, 7, 15, material_props;
	temperature = 25
)
println(conductor.cross_section) # Outputs: Updated cross-sectional area
println(conductor.layers)       # Outputs: Updated layers including the new part
```

# References
- None.
"""
function add_conductor_part!(
	sc::Conductor,
	part_type::Type{T},  # The type of conductor part (WireArray, Strip, Tubular)
	args...;  # Arguments specific to the part type
	kwargs...,
) where T <: ConductorParts
	# Infer default properties
	radius_in = get(kwargs, :radius_in, sc.radius_ext)
	kwargs = merge((temperature = sc.layers[1].temperature,), kwargs)

	# Create the new part
	new_part = T(radius_in, args...; kwargs...)

	# Update the Conductor with the new part
	sc.gmr = calc_equivalent_gmr(sc, new_part)
	sc.resistance = calc_parallel_equivalent(sc.resistance, new_part.resistance)
	sc.radius_ext += (new_part.radius_ext - new_part.radius_in)
	sc.cross_section += new_part.cross_section
	sc.num_wires += new_part isa WireArray ? new_part.num_wires : 0
	push!(sc.layers, new_part)
end

"""
get_wirearray_coords: Computes the global coordinates of wires in a `WireArray`.

# Arguments
- `wa`: A `WireArray` object containing the geometric and material properties of the wire array.

# Returns
- A vector of tuples, where each tuple represents the `(x, y)` coordinates [m] of the center of a wire.

# Examples
```julia
wa = WireArray(0.01, 0.002, 7, 10, Material(1.7241e-8, 1.0, 0.999994, 20.0, 0.00393))
wire_coords = get_wirearray_coords(wa)
println(wire_coords) # Outputs: [(x1, y1), (x2, y2), ...] for all wires
```

# References
- None.
"""
function get_wirearray_coords(wa::WireArray)
	wire_coords = []  # Global coordinates of all wires
	wire_diam = wa.diameter
	num_wires = wa.num_wires
	lay_radius = num_wires == 1 ? 0 : wa.radius_in + wire_diam / 2

	# Calculate the angle between each wire
	angle_step = 2 * π / num_wires
	for i in 0:num_wires-1
		angle = i * angle_step
		x = lay_radius * cos(angle)
		y = lay_radius * sin(angle)
		push!(wire_coords, (x, y))  # Add wire center
	end
	return wire_coords
end

"""
calc_parallel_equivalent: Computes the parallel equivalent resistance of two impedances (or series equivalent of two admittances).

# Arguments
- `total_R`: The total impedance of the existing system [Ω].
- `layer_R`: The impedance of the new layer being added [Ω].

# Returns
- The parallel equivalent impedance as a `Number` [Ω].

# Examples
```julia
total_R = 5.0
layer_R = 10.0
parallel_R = calc_parallel_equivalent(total_R, layer_R)
println(parallel_R) # Outputs: 3.3333333333333335
```

# References
- None.
"""
function calc_parallel_equivalent(total_R::Number, layer_R::Number)
	return 1 / (1 / total_R + 1 / layer_R)
end

"""
calc_tubular_resistance: Computes the DC resistance of a tubular conductor based on its geometric and material properties, with temperature correction.

# Arguments
- `radius_in`: Internal radius of the tubular conductor [m].
- `radius_ext`: External radius of the tubular conductor [m].
- `rho`: Electrical resistivity of the conductor material [Ω·m].
- `alpha`: Temperature coefficient of resistivity [1/°C].
- `T0`: Reference temperature for the material properties [°C].
- `T`: Operating temperature of the system [°C].

# Returns
- The DC resistance of the tubular conductor as a `Number` [Ω].

# Examples
```julia
radius_in = 0.01
radius_ext = 0.02
rho = 1.7241e-8
alpha = 0.00393
T0 = 20
T = 25
resistance = calc_tubular_resistance(radius_in, radius_ext, rho, alpha, T0, T)
println(resistance) # Outputs: Resistance in Ω
```

# References
- None.
"""
function calc_tubular_resistance(
	radius_in::Number,
	radius_ext::Number,
	rho::Number,
	alpha::Number,
	T0::Number,
	T::Number,
)
	temp_correction_factor = (1 + alpha * (T - T0))
	cross_section = π * (radius_ext^2 - radius_in^2)
	return temp_correction_factor * rho / cross_section
end

"""
calc_strip_resistance: Computes the DC resistance of a strip conductor based on its geometric and material properties.

# Arguments
- `thickness`: Thickness of the strip [m].
- `width`: Width of the strip [m].
- `rho`: Electrical resistivity of the conductor material [Ω·m].
- `alpha`: Temperature coefficient of resistivity [1/°C].
- `T0`: Reference temperature for the material properties [°C].
- `T`: Operating temperature of the system [°C].

# Returns
- The DC resistance of the strip conductor as a `Number` [Ω].

# Examples
```julia
thickness = 0.002
width = 0.05
rho = 1.7241e-8
alpha = 0.00393
T0 = 20
T = 25
resistance = calc_strip_resistance(thickness, width, rho, alpha, T0, T)
println(resistance) # Outputs: Resistance in Ω
```

# References
- None.
"""
function calc_strip_resistance(
	thickness::Number,
	width::Number,
	rho::Number,
	alpha::Number,
	T0::Number,
	T::Number,
)
	temp_correction_factor = (1 + alpha * (T - T0))
	cross_section = thickness * width
	return temp_correction_factor * rho / cross_section
end

"""
calc_wirearray_gmr: Computes the geometric mean radius (GMR) of a circular wire array.

# Arguments
- `lay_rad`: Layout radius of the wire array [m].
- `N`: Number of wires in the array.
- `rad_wire`: Radius of an individual wire [m].
- `mu_r`: Relative permeability of the wire material (dimensionless).

# Returns
- The GMR of the wire array as a `Number` [m].

# Examples
```julia
lay_rad = 0.05
N = 7
rad_wire = 0.002
mu_r = 1.0
gmr = calc_wirearray_gmr(lay_rad, N, rad_wire, mu_r)
println(gmr) # Outputs: GMR value [m]
```

# References
- None.
"""
function calc_wirearray_gmr(lay_rad::Number, N::Number, rad_wire::Number, mu_r::Number)
	gmr_wire = rad_wire * exp(-mu_r / 4)
	log_gmr_array = log(gmr_wire * N * lay_rad^(N - 1)) / N
	return exp(log_gmr_array)
end

"""
calc_tubular_gmr: Computes the geometric mean radius (GMR) of a tubular conductor.

# Arguments
- `radius_ext`: External radius of the tubular conductor [m].
- `radius_in`: Internal radius of the tubular conductor [m].
- `mu_r`: Relative permeability of the conductor material (dimensionless).

# Returns
- The GMR of the tubular conductor as a `Number` [m].

# Notes
- If `radius_ext` is approximately equal to `radius_in`, the tube collapses into a thin shell, and the GMR is equal to `radius_ext`.
- If the tube becomes infinitely thick (e.g., `radius_in` approaches 0), the GMR is considered infinite.
- For general cases, the GMR is computed using the logarithmic integral of the tubular geometry.

# Examples
```julia
radius_ext = 0.02
radius_in = 0.01
mu_r = 1.0
gmr = calc_tubular_gmr(radius_ext, radius_in, mu_r)
println(gmr) # Outputs: GMR value [m]
```

# References
- None.
"""
function calc_tubular_gmr(radius_ext::Number, radius_in::Number, mu_r::Number)
	if radius_ext < radius_in
		throw(ArgumentError("Invalid parameters: radius_ext must be >= radius_in."))
	end

	# Constants
	if abs(radius_ext - radius_in) < TOL
		# Tube collapses into a thin shell with infinitesimal thickness and the GMR is simply the radius
		gmr = radius_ext
	elseif abs(radius_in / radius_ext) < eps() && abs(radius_in) > TOL
		# Tube becomes infinitely thick up to floating point precision
		gmr = Inf
	else
		term1 =
			radius_in == 0 ? 0 :
			(radius_in^4 / (radius_ext^2 - radius_in^2)^2) * log(radius_ext / radius_in)
		term2 = (3 * radius_in^2 - radius_ext^2) / (4 * (radius_ext^2 - radius_in^2))
		Lin = (μ₀ * mu_r / (2 * π)) * (term1 - term2)

		# Compute the GMR
		gmr = exp(log(radius_ext) - (2 * π / μ₀) * Lin)
	end

	return gmr
end

"""
gmr_to_mu: Computes the relative permeability (mu_r) based on the geometric mean radius (GMR) and conductor dimensions.

# Arguments
- `gmr`: Geometric mean radius of the conductor [m].
- `radius_ext`: External radius of the conductor [m].
- `radius_in`: Internal radius of the conductor [m].

# Returns
- The relative permeability (`mu_r`) as a `Number` (dimensionless).

# Examples
```julia
gmr = 0.015
radius_ext = 0.02
radius_in = 0.01
mu_r = gmr_to_mu(gmr, radius_ext, radius_in)
println(mu_r) # Outputs: Relative permeability value
```

# Notes
- If `radius_ext` is less than `radius_in`, an `ArgumentError` is thrown.
- Assumes a tubular geometry for the conductor, reducing to the solid case if `radius_in` is zero.

# References
- None.
"""
function gmr_to_mu(gmr::Number, radius_ext::Number, radius_in::Number)
	if radius_ext < radius_in
		throw(ArgumentError("Invalid parameters: radius_ext must be >= radius_in."))
	end

	term1 =
		radius_in == 0 ? 0 :
		(radius_in^4 / (radius_ext^2 - radius_in^2)^2) * log(radius_ext / radius_in)
	term2 = (3 * radius_in^2 - radius_ext^2) / (4 * (radius_ext^2 - radius_in^2))
	# Compute the log difference
	log_diff = log(gmr) - log(radius_ext)

	# Compute mu_r
	mu_r = -log_diff / (term1 - term2)

	return mu_r
end

"""
calc_shunt_capacitance: Computes the shunt capacitance per unit length of a coaxial structure.

# Arguments
- `radius_in`: Internal radius of the coaxial structure [m].
- `radius_ext`: External radius of the coaxial structure [m].
- `epsr`: Relative permittivity of the dielectric material (dimensionless).

# Returns
- The shunt capacitance per unit length as a `Number` [F/m].

# Examples
```julia
radius_in = 0.01
radius_ext = 0.02
epsr = 2.3
capacitance = calc_shunt_capacitance(radius_in, radius_ext, epsr)
println(capacitance) # Outputs: Capacitance in F/m
```

# Notes
- Uses the vacuum permittivity constant `ε₀`.
- Assumes a uniform dielectric material between the inner and outer radii.

# References
- None.
"""
function calc_shunt_capacitance(radius_in::Number, radius_ext::Number, epsr::Number)
	return 2 * π * ε₀ * epsr / log(radius_ext / radius_in)
end

"""
calc_shunt_conductance: Computes the shunt conductance per unit length of a coaxial structure.

# Arguments
- `radius_in`: Internal radius of the coaxial structure [m].
- `radius_ext`: External radius of the coaxial structure [m].
- `rho`: Resistivity of the dielectric material [Ω·m].

# Returns
- The shunt conductance per unit length as a `Number` [S/m].

# Examples
```julia
radius_in = 0.01
radius_ext = 0.02
rho = 1e9
conductance = calc_shunt_conductance(radius_in, radius_ext, rho)
println(conductance) # Outputs: Conductance in S/m
```

# Notes
- Assumes a uniform dielectric material between the inner and outer radii.
- Inverse of resistivity (`1 / rho`) is used to calculate conductance.

# References
- None.
"""
function calc_shunt_conductance(radius_in::Number, radius_ext::Number, rho::Number)
	return 2 * π * (1 / rho) / log(radius_ext / radius_in)
end

"""
preview_conductor_cross_section: Visualizes the cross-section of a composite conductor.

# Arguments
- `sc`: A `Conductor` object representing the composite conductor to be visualized.

# Returns
- None. Displays an interactive plot of the conductor's cross-section.

# Dependencies
- `plotlyjs`: Enables interactive plotting.
- `unique`: Ensures unique material properties are processed.
- `get_wirearray_coords`: Calculates the coordinates for wires in a `WireArray`.
- `get_material_color`: Maps material properties to colors for visualization.

# Examples
```julia
material_props = Material(1.7241e-8, 1.0, 0.999994, 20.0, 0.00393)
wire_array = WireArray(0.01, 0.002, 7, 10, material_props)
conductor = Conductor(wire_array)
preview_conductor_cross_section(conductor)
```

# Notes
- This function uses `plotlyjs()` for interactive visualization. Ensure the `Plots` package is installed and configured.
- Each conductor layer is visualized based on its type (`WireArray`, `Strip`, `Tubular`, etc.) and material properties.

# References
- None.
"""
function preview_conductor_cross_section(sc::Conductor)
	plotlyjs()  # For interactivity
	# Initialize plot
	plt = plot(
		aspect_ratio = :equal,
		legend = false,
		title = "Composite conductor cross-section",
		xlabel = "x [m]",
		ylabel = "y [m]",
	)

	# Collect unique material properties
	unique_materials =
		unique([layer.material_props for layer in sc.layers if layer isa WireArray])

	# Loop over each layer
	for layer in sc.layers
		if layer isa WireArray
			wire_diam = _to_nominal(layer.diameter)
			num_wires = layer.num_wires

			lay_radius = num_wires == 1 ? 0 : _to_nominal(layer.radius_in) + wire_diam / 2
			material_props = layer.material_props
			color = get_material_color(material_props)

			# Calculate the angle between each wire
			angle_step = 2 * π / num_wires

			# Plot each wire in the layer
			for i in 0:num_wires-1
				angle = i * angle_step
				x = lay_radius * cos(angle)
				y = lay_radius * sin(angle)
				plot!(
					plt,
					Shape(
						x .+ wire_diam / 2 * cos.(0:0.01:2π),
						y .+ wire_diam / 2 * sin.(0:0.01:2π),
					),
					color = color,
				)
			end
		elseif layer isa Strip || layer isa Tubular || layer isa Semicon ||
			   layer isa Insulator
			radius_in = _to_nominal(layer.radius_in)
			radius_ext = _to_nominal(layer.radius_ext)
			material_props = layer.material_props
			color = get_material_color(material_props)

			arcshape(θ1, θ2, rin, rext, N = 100) = Shape(
				vcat(Plots.partialcircle(θ1, θ2, N, rext),
					reverse(Plots.partialcircle(θ1, θ2, N, rin))),
			)

			shape = arcshape(0, 2π, radius_in, radius_ext)
			plot!(plt, shape, linecolor = color, color = color, label = "")
		end

	end
	display(plt)
end

"""
get_material_color: Generates a color representation for a material based on its physical properties.

# Arguments
- `material_props`: A dictionary containing the material's properties:
  - `rho`: Electrical resistivity [Ω·m].
  - `eps_r`: Relative permittivity (dimensionless).
  - `mu_r`: Relative permeability (dimensionless).
- `rho_weight`: Weight assigned to the resistivity in the color blending (default: 0.8).
- `epsr_weight`: Weight assigned to the permittivity in the color blending (default: 0.1).
- `mur_weight`: Weight assigned to the permeability in the color blending (default: 0.1).

# Returns
- An `RGBA` object representing the combined color based on the material's properties.

# Notes
- Colors are normalized and weighted to emphasize specific properties (e.g., high resistivity materials like insulators).
- Includes normalization for resistivity, permittivity, and permeability ranges.

# Examples
```julia
material_props = Dict(
	:rho => 1.7241e-8,
	:eps_r => 2.3,
	:mu_r => 1.0
)
color = get_material_color(material_props)
println(color) # Outputs: RGBA color based on material properties
```

# References
- None.
"""
function get_material_color(
	material_props;
	rho_weight = 0.8,
	epsr_weight = 0.1,
	mur_weight = 0.1,
)
	# Fixed normalization bounds
	epsr_min, epsr_max = 1.0, 1000.0  # Adjusted permittivity range for semiconductors
	mur_min, mur_max = 1.0, 300.0  # Relative permeability range
	rho_base = 1.72e-8

	# Extract nominal values for uncertain measurements
	rho = _to_nominal(material_props.rho)
	epsr_r = _to_nominal(material_props.eps_r)
	mu_r = _to_nominal(material_props.mu_r)

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
	final_color = overlay_multiple_colors([rho_color_w, epsr_color_w, mur_color_w])

	return final_color
end

"""
overlay_colors: Blends two RGBA colors using alpha compositing.

# Arguments
- `color1`: An `RGBA` object representing the first color.
- `color2`: An `RGBA` object representing the second color.

# Returns
- An `RGBA` object representing the blended color based on alpha compositing.

# Notes
- The blending considers the alpha transparency of each color.
- If the resulting alpha (`a_result`) is 0, the function returns a fully transparent black (`RGBA(0, 0, 0, 0)`).

# Examples
```julia
color1 = RGBA(1.0, 0.0, 0.0, 0.5)  # Semi-transparent red
color2 = RGBA(0.0, 0.0, 1.0, 0.5)  # Semi-transparent blue
result_color = overlay_colors(color1, color2)
println(result_color) # Outputs the blended color
```

# References
- None.
"""
function overlay_colors(color1::RGBA, color2::RGBA)
	# Extract components
	r1, g1, b1, a1 = red(color1), green(color1), blue(color1), alpha(color1)
	r2, g2, b2, a2 = red(color2), green(color2), blue(color2), alpha(color2)

	# Compute resulting alpha
	a_result = a2 + a1 * (1 - a2)

	# Avoid division by zero if resulting alpha is 0
	if a_result == 0
		return RGBA(0, 0, 0, 0)
	end

	# Compute resulting RGB channels
	r_result = (r2 * a2 + r1 * a1 * (1 - a2)) / a_result
	g_result = (g2 * a2 + g1 * a1 * (1 - a2)) / a_result
	b_result = (b2 * a2 + b1 * a1 * (1 - a2)) / a_result

	return RGBA(r_result, g_result, b_result, a_result)
end

"""
visualize_gradient: Displays a color gradient for visualization.

# Arguments
- `gradient`: A color gradient object to be visualized (e.g., `cgrad`).
- `n_steps`: The number of steps to sample from the gradient (default: 100).
- `title`: A string representing the title of the visualization (default: "Color gradient").

# Returns
- None. Displays a plot of the color gradient.

# Examples
```julia
gradient = cgrad([:blue, :green, :yellow, :red])
visualize_gradient(gradient, 200; title = "My Custom Gradient")
```

# Notes
- This function creates a bar plot with colored bars representing the gradient.
- The x-axis and y-axis are hidden for better visualization.

# References
- None.
"""
function visualize_gradient(gradient, n_steps = 100; title = "Color gradient")
	# Generate evenly spaced values between 0 and 1
	x = range(0, stop = 1, length = n_steps)
	colors = [get(gradient, xi) for xi in x]  # Sample the gradient

	# Create a plot using colored bars
	bar(x, ones(length(x)); color = colors, legend = false, xticks = false, yticks = false)
	title!(title)
end

"""
overlay_multiple_colors: Blends multiple RGBA colors using sequential alpha compositing.

# Arguments
- `colors`: A vector of `RGBA` objects representing the colors to be blended.

# Returns
- An `RGBA` object representing the final blended color.

# Notes
- Colors are composited sequentially, starting with the first color in the vector.
- If the vector contains only one color, that color is returned as the result.

# Examples
```julia
colors = [RGBA(1.0, 0.0, 0.0, 0.5), RGBA(0.0, 1.0, 0.0, 0.5), RGBA(0.0, 0.0, 1.0, 0.5)]
result_color = overlay_multiple_colors(colors)
println(result_color) # Outputs the blended color
```

# References
- None.
"""
function overlay_multiple_colors(colors::Vector{<:RGBA})
	# Start with the first color
	result = colors[1]

	# Overlay each subsequent color
	for i in 2:length(colors)
		result = overlay_colors(result, colors[i])
	end

	return result
end

"""
conductor_data: Generates a tabular representation of key properties of a `Conductor`.

# Arguments
- `conductor`: A `Conductor` object whose properties are to be summarized.

# Returns
- A `DataFrame` containing the properties of the conductor and their corresponding values.
  The table includes the following columns:
  - `property`: Name of the property (e.g., `radius_in`, `resistance`).
  - `value`: Value of the property.

# Examples
```julia
conductor = Conductor(WireArray(0.01, 0.002, 7, 10, Material(1.7241e-8, 1.0, 0.999994, 20.0, 0.00393)))
data = conductor_data(conductor)
println(data) # Outputs a DataFrame with conductor properties and values
```

# Notes
- The additional property `alpha` is calculated as `gmr / radius_ext` and included in the output.

# References
- None.
"""
function conductor_data(conductor::Conductor)
	data = [
		("radius_in", conductor.radius_in),
		("radius_ext", conductor.radius_ext),
		("cross_section", conductor.cross_section),
		("num_wires", conductor.num_wires),
		("resistance", conductor.resistance),
		("gmr", conductor.gmr),
		("alpha", conductor.gmr / conductor.radius_ext),
	]
	df = DataFrame(data, [:property, :value])
	return df
end

"""
Semicon: Represents a semiconducting layer with defined geometric, material, and electrical properties.
"""
mutable struct Semicon
	radius_in::Number
	radius_ext::Number
	material_props::Material
	temperature::Number
	cross_section::Number
	resistance::Number
	gmr::Number
	shunt_capacitance::Number
	shunt_conductance::Number

	"""
	Constructor: Initializes a `Semicon` object based on specified geometric and material parameters.

	# Arguments
	- `radius_in`: Internal radius of the semiconducting layer [m].
	- `thickness`: Thickness of the layer [m].
	- `material_props`: A `Material` object representing the physical properties of the semiconducting material.
	- `temperature`: Operating temperature of the layer [°C] (default: 20).

	# Returns
	An instance of `Semicon` initialized with the following calculated properties:
	- `radius_ext`: External radius of the semiconducting layer [m].
	- `cross_section`: Cross-sectional area of the layer [m²].
	- `resistance`: Electrical resistance of the layer [Ω].
	- `gmr`: Geometric mean radius of the semiconductor [m].
	- `shunt_capacitance`: Shunt capacitance per unit length of the layer [F/m].
	- `shunt_conductance`: Shunt conductance per unit length of the layer [S/m].

	# Dependencies
	- `calc_tubular_resistance`: Computes the DC resistance of the semiconducting layer.
	- `calc_tubular_gmr`: Calculates the geometric mean radius (GMR) of the tubular element.
	- `calc_shunt_capacitance`: Computes the shunt capacitance per unit length.
	- `calc_shunt_conductance`: Computes the shunt conductance per unit length.

	# Examples
	```julia
	material_props = Material(1e6, 2.3, 1.0, 20.0, 0.00393)
	semicon_layer = Semicon(0.01, 0.002, material_props, temperature=25)
	println(semicon_layer.cross_section)    # Outputs: Cross-sectional area in m²
	println(semicon_layer.resistance)       # Outputs: Resistance in Ω
	println(semicon_layer.gmr)       		# Outputs: GMR in m
	println(semicon_layer.shunt_capacitance) # Outputs: Capacitance in F/m
	println(semicon_layer.shunt_conductance) # Outputs: Conductance in S/m
	```

	# References
	- None.
	"""
	function Semicon(
		radius_in::Union{Number, <:Any},
		thickness::Number,
		material_props::Material;
		temperature::Number = 20,
	)

		rho = material_props.rho
		T0 = material_props.T0
		alpha = material_props.alpha
		epsr_r = material_props.eps_r

		# Extract `radius_in` from `radius_ext` if a custom type is provided
		radius_in = radius_in isa Number ? radius_in : getfield(radius_in, :radius_ext)


		radius_ext = radius_in + thickness
		cross_section = π * (radius_ext^2 - radius_in^2)

		resistance =
			calc_tubular_resistance(radius_in, radius_ext, rho, alpha, T0, temperature)
		gmr = calc_tubular_gmr(radius_ext, radius_in, material_props.mu_r)
		shunt_capacitance = calc_shunt_capacitance(radius_in, radius_ext, epsr_r)
		shunt_conductance = calc_shunt_conductance(radius_in, radius_ext, rho)

		# Initialize object
		return new(
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
end

"""
Insulator: Represents an insulating layer with defined geometric, material, and electrical properties.
"""
mutable struct Insulator
	radius_in::Number
	radius_ext::Number
	material_props::Material
	temperature::Number
	cross_section::Number
	resistance::Number
	gmr::Number
	shunt_capacitance::Number
	shunt_conductance::Number

	"""
	Constructor: Initializes an `Insulator` object based on specified geometric and material parameters.

	# Arguments
	- `radius_in`: Internal radius of the insulating layer [m].
	- `thickness`: Thickness of the layer [m].
	- `material_props`: A `Material` object representing the physical properties of the insulating material.
	- `temperature`: Operating temperature of the layer [°C] (default: 20).

	# Returns
	An instance of `Insulator` initialized with the following calculated properties:
	- `radius_ext`: External radius of the insulating layer [m].
	- `cross_section`: Cross-sectional area of the layer [m²].
	- `resistance`: Electrical resistance of the layer [Ω].
	- `gmr`: Geometric mean radius of the insulator [m].
	- `shunt_capacitance`: Shunt capacitance per unit length of the layer [F/m].
	- `shunt_conductance`: Shunt conductance per unit length of the layer [S/m].

	# Dependencies
	- `calc_tubular_resistance`: Computes the DC resistance of the insulating layer.
	- `calc_tubular_gmr`: Calculates the geometric mean radius (GMR) of the tubular element.
	- `calc_shunt_capacitance`: Computes the shunt capacitance per unit length.
	- `calc_shunt_conductance`: Computes the shunt conductance per unit length.

	# Examples
	```julia
	material_props = Material(1e10, 3.0, 1.0, 20.0, 0.0)
	insulator_layer = Insulator(0.01, 0.005, material_props, temperature=25)
	println(insulator_layer.cross_section)    # Outputs: Cross-sectional area in m²
	println(insulator_layer.resistance)       # Outputs: Resistance in Ω
	println(insulator_layer.shunt_capacitance) # Outputs: Capacitance in F/m
	println(insulator_layer.shunt_conductance) # Outputs: Conductance in S/m
	```

	# References
	- None.
	"""
	function Insulator(
		radius_in::Union{Number, <:Any},
		thickness::Number,
		material_props::Material;
		temperature::Number = 20,
	)

		# Extract `radius_in` from `radius_ext` if a custom type is provided
		radius_in = radius_in isa Number ? radius_in : getfield(radius_in, :radius_ext)

		rho = material_props.rho
		T0 = material_props.T0
		alpha = material_props.alpha
		epsr_r = material_props.eps_r

		radius_ext = radius_in + thickness
		cross_section = π * (radius_ext^2 - radius_in^2)

		resistance =
			calc_tubular_resistance(radius_in, radius_ext, rho, alpha, T0, temperature)
		gmr = calc_tubular_gmr(radius_ext, radius_in, material_props.mu_r)
		shunt_capacitance = calc_shunt_capacitance(radius_in, radius_ext, epsr_r)
		shunt_conductance = calc_shunt_conductance(radius_in, radius_ext, rho)

		# Initialize object
		return new(
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
end

"""
CableParts: Defines a generic type for any cable part.
"""
const CableParts = Union{Conductor, Strip, WireArray, Tubular, Semicon, Insulator}

"""
calc_equivalent_gmr: Computes the equivalent geometric mean radius (GMR) of a `Conductor` after adding a new layer.

# Arguments
- `sc`: A `CableParts` object representing the existing cable part.
- `layer`: A `CableParts` object representing the new layer being added.

# Returns
- The updated equivalent GMR of the `CablePart` as a `Number` [m].

# Dependencies
- `calc_gmd`: Computes the geometric mean distance (GMD) between the last layer of the cable and the new layer.

# Examples
```julia
material_props = Material(1.7241e-8, 1.0, 0.999994, 20.0, 0.00393)
conductor = Conductor(Strip(0.01, 0.002, 0.05, 10, material_props))
new_layer = WireArray(0.02, 0.002, 7, 15, material_props)
equivalent_gmr = calc_equivalent_gmr(conductor, new_layer)
println(equivalent_gmr) # Outputs: Updated GMR value [m]
```

# References
- None.
"""
# function calc_equivalent_gmr(sc::Union{Conductor, ConductorParts}, layer::ConductorParts)
function calc_equivalent_gmr(sc::CableParts, layer::CableParts)
	alph = sc.cross_section / (sc.cross_section + layer.cross_section)
	beta = 1 - alph
	current_conductor = sc isa Conductor ? sc.layers[end] : sc
	gmd = calc_gmd(current_conductor, layer)
	return sc.gmr^(alph^2) * layer.gmr^(beta^2) * gmd^(2 * alph * beta)
end

"""
calc_gmd: Computes the geometric mean distance (GMD) between two cable parts.

# Arguments
- `co1`: A `CableParts` object representing the first cable part (e.g., `WireArray`, `Strip`, `Tubular`, `Semicon` or `Insulator`).
- `co2`: A `CableParts` object representing the second cable part (e.g., `WireArray`, `Strip`, `Tubular`, `Semicon` or `Insulator`).

# Returns
- The GMD as a `Number` [m], which represents the logarithmic average of pairwise distances between the cable parts.

# Dependencies
- `get_wirearray_coords`: Computes the coordinates of wires in a `WireArray`.

# Examples
```julia
material_props = Material(1.7241e-8, 1.0, 0.999994, 20.0, 0.00393)
wire_array1 = WireArray(0.01, 0.002, 7, 10, material_props)
wire_array2 = WireArray(0.02, 0.002, 7, 15, material_props)
gmd = calc_gmd(wire_array1, wire_array2)
println(gmd) # Outputs: GMD value [m]

strip = Strip(0.01, 0.002, 0.05, 10, material_props)
tubular = Tubular(0.01, 0.02, material_props)
gmd = calc_gmd(strip, tubular)
println(gmd) # Outputs: GMD value [m]
```

# Notes
- For concentric structures (e.g., a `Strip` within a `Tubular`), the GMD defaults to the outermost radius.

# References
- None.
"""
function calc_gmd(co1::CableParts, co2::CableParts)

	if co1 isa WireArray
		coords1 = get_wirearray_coords(co1)
		n1 = co1.num_wires
		r1 = co1.diameter / 2
		s1 = pi * (r1)^2
	else
		coords1 = [(0, 0)]
		n1 = 1
		r1 = co1.radius_ext
		s1 = co1.cross_section
	end

	if co2 isa WireArray
		coords2 = get_wirearray_coords(co2)
		n2 = co2.num_wires
		r2 = co2.diameter / 2
		s2 = pi * (co2.diameter / 2)^2
	else
		coords2 = [(0, 0)]
		n2 = 1
		r2 = co2.radius_ext
		s2 = co2.cross_section
	end

	log_sum = 0.0
	area_weights = 0.0

	for i in 1:n1
		for j in 1:n2
			# Pair-wise distances
			x1, y1 = coords1[i]
			x2, y2 = coords2[j]
			d_ij = sqrt((x1 - x2)^2 + (y1 - y2)^2)
			if d_ij > eps()
				# The GMD is computed as the Euclidean distance from center-to-center
				log_dij = log(d_ij)
			else
				# This means two concentric structures (solid/strip or tubular, tubular/strip or tubular, strip/strip or tubular)
				# In all cases the GMD is the outermost radius
				max(r1, r2)
				log_dij = log(max(r1, r2))
			end
			log_sum += (s1 * s2) * log_dij
			area_weights += (s1 * s2)
		end
	end
	return exp(log_sum / area_weights)
end

"""
insulator_data: Generates a tabular representation of key properties of an `Insulator` or `Semicon` object.

# Arguments
- `insu`: An object of type `Insulator` or `Semicon` whose properties are to be summarized.

# Returns
- A `DataFrame` containing the properties of the object and their corresponding values.
  The table includes the following columns:
  - `property`: Name of the property (e.g., `radius_in`, `resistance`).
  - `value`: Value of the property.

# Examples
```julia
material_props = Material(1e10, 3.0, 1.0, 20.0, 0.0)
insulator = Insulator(0.01, 0.005, material_props, temperature=25)
data = insulator_data(insulator)
println(data) # Outputs a DataFrame with insulator properties and values

semicon = Semicon(0.01, 0.002, material_props, temperature=30)
data = insulator_data(semicon)
println(data) # Outputs a DataFrame with semicon properties and values
```

# Notes
- This function is compatible with both `Insulator` and `Semicon` types.
- The returned table includes geometric, material, and electrical properties.

# References
- None.
"""
function insulator_data(insu::Union{Insulator, Semicon})
	data = [
		("radius_in", insu.radius_in),
		("radius_ext", insu.radius_ext),
		("cross_section", insu.cross_section),
		("resistance", insu.resistance),
		("gmr", insu.gmr),
		("shunt_capacitance", insu.shunt_capacitance),
		("shunt_conductance", insu.shunt_conductance)]
	df = DataFrame(data, [:property, :value])
	return df
end

mutable struct CableComponent
	name::String
	radius_in_con::Number
	radius_ext_con::Number
	rho_con::Number
	mu_con::Number
	radius_ext_ins::Number
	eps_ins::Number
	mu_ins::Number
	loss_factor_ins::Number
	component_data::Vector{<:CableParts}

	# Constructor
	function CableComponent(
		name::String,
		component_data::Vector{<:CableParts},
		f::Number = 50,
	)
		# Validate the geometry
		radius_exts = [part.radius_ext for part in component_data]
		if !issorted(radius_exts)
			error(
				"Components in CableParts must be supplied in ascending order of radius_ext.",
			)
		end

		ω = 2 * π * f

		# Initialize conductor and insulator parameters
		radius_in_con = Inf
		radius_ext_con = 0.0
		rho_con = 0.0
		mu_con = 0.0
		radius_ext_ins = 0.0
		eps_ins = 0.0
		mu_ins = 0.0
		loss_factor_ins = 0.0
		equiv_resistance = Inf
		equiv_admittance = Inf
		gmr_eff_con = nothing
		gmr_eff_ins = nothing
		previous_part = nothing
		total_num_wires = 0
		weighted_num_turns = 0.0
		total_cross_section_ins = 0.0
		total_cross_section_con = 0.0

		# Helper function to extract equivalent parameters from conductor parts
		function calc_weighted_num_turns(part)
			if part isa Conductor
				for sub_part in part.layers
					calc_weighted_num_turns(sub_part)
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
				radius_in_con = min(radius_in_con, part.radius_in)
				radius_ext_con += (part.radius_ext - part.radius_in)
				equiv_resistance =
					calc_parallel_equivalent(equiv_resistance, part.resistance)
				total_num_wires += part.num_wires
				calc_weighted_num_turns(part)

				if gmr_eff_con === nothing
					gmr_eff_con = part.gmr
				else
					alph =
						total_cross_section_con /
						(total_cross_section_con + part.cross_section)
					beta = 1 - alph
					gmd = calc_gmd(previous_part, part)
					gmr_eff_con =
						gmr_eff_con^(alph^2) * part.gmr^(beta^2) * gmd^(2 * alph * beta)
				end
				total_cross_section_con += part.cross_section

			elseif part isa Semicon || part isa Insulator
				radius_ext_ins += (part.radius_ext - part.radius_in)
				Y = Complex(part.shunt_conductance, ω * part.shunt_capacitance)
				equiv_admittance = calc_parallel_equivalent(equiv_admittance, Y)
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
		eff_conductor_area = π * (radius_ext_con^2 - radius_in_con^2)
		rho_con = equiv_resistance * eff_conductor_area
		mu_con = gmr_to_mu(gmr_eff_con, radius_ext_con, radius_in_con)
		num_turns = weighted_num_turns / total_num_wires

		# Insulator effective parameters
		if radius_ext_ins > 0
			radius_ext_ins += radius_ext_con
			G_eq = real(equiv_admittance)
			C_eq = imag(equiv_admittance) / ω
			eps_ins = (C_eq * log(radius_ext_ins / radius_ext_con)) / (2 * pi) / ε₀
			loss_factor_ins = G_eq / (ω * C_eq)
			correction_mu_ins = (
				1 +
				2 * num_turns^2 * pi^2 * (radius_ext_ins^2 - radius_ext_con^2) /
				log(radius_ext_ins / radius_ext_con)
			)
			mu_ins = mu_ins * correction_mu_ins
		else
			radius_ext_ins = NaN
			eps_ins = NaN
			mu_ins = NaN
			loss_factor_ins = NaN
		end

		# Initialize object
		return new(
			name,
			radius_in_con,
			radius_ext_con,
			rho_con,
			mu_con,
			radius_ext_ins,
			eps_ins,
			mu_ins,
			loss_factor_ins,
			component_data,
		)
	end
end

function cable_parts_data(component::CableComponent)
	properties = [
		"diam_in",
		"diam_ext",
		"cross_section",
		"num_wires",
		"resistance",
		"gmr",
		"alpha",
	]

	# Initialize the DataFrame with property names
	data = DataFrame(property = properties)

	# Iterate over each part in component_data with an index
	for (i, part) in enumerate(component.component_data)
		# Generate column name with type and index
		col = string(i) * "-" * lowercase(string(typeof(part)))

		# Collect values for each property, or `missing` if not available
		new_col = [
			:radius_in in fieldnames(typeof(part)) ? 2 * getfield(part, :radius_in) :
			missing,
			:radius_ext in fieldnames(typeof(part)) ? 2 * getfield(part, :radius_ext) :
			missing,
			:cross_section in fieldnames(typeof(part)) ?
			getfield(part, :cross_section) : missing,
			:num_wires in fieldnames(typeof(part)) ? getfield(part, :num_wires) : missing,
			:resistance in fieldnames(typeof(part)) ? getfield(part, :resistance) : missing,
			:gmr in fieldnames(typeof(part)) ? getfield(part, :gmr) : missing,
			getfield(part, :gmr) / getfield(part, :radius_ext),
		]

		# Add the new column to the DataFrame
		data[!, col] = new_col
	end

	return data
end

function cable_component_data(component::CableComponent)
	data = [
		("name", component.name),
		("radius_in_con", component.radius_in_con),
		("radius_ext_con", component.radius_ext_con),
		("rho_con", component.rho_con),
		("mu_con", component.mu_con),
		("radius_ext_ins", component.radius_ext_ins),
		("eps_ins", component.eps_ins),
		("mu_ins", component.mu_ins),
		("loss_factor_ins", component.loss_factor_ins),
	]
	df = DataFrame(data, [:property, :value])
	return df
end