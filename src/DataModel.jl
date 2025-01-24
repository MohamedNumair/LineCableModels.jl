"""
Thickness: Represents the thickness of a cable component. This custom type ensures flexibility in data entry and consistency with engineering practices, where component layers (insulation, metallic tapes etc.) are typically described by thickness rather than laying radius. It standardizes components requiring `radius_ext` for calculations.
"""
struct Thickness
	value::Number
end

"""
thick: A macro for constructing `Thickness` objects.

# Arguments
- `value`: The numerical value representing the thickness to be encapsulated in a `Thickness` object.

# Returns
- A `Thickness` object with the specified `value`.

# Examples
```julia
using .LineCableToolbox

thick_obj = @thick(5.0)
println(thick_obj) # Output: Thickness(5.0)
```

# References
- None.
"""
macro thick(value)
	esc(:(Thickness($value)))
end

"""
diam: A macro that calculates the radius from a given diameter. As trivial and overkill as it may seem, this macro is intended to improve clarity in cases where typical engineering data is commonly referred to in terms of diameters, e.g. wires used in stranded cores and screens.

# Arguments
- `value`: The numerical value representing the diameter to be halved.

# Returns
- A numerical value equal to half of the provided diameter (radius).

# Examples
```julia
using .LineCableToolbox

radius = @diam(10.0)
println(radius) # Output: 5.0
```

# References
- None.
"""
macro diam(value)
	esc(:(($value) / 2))
end

"""
WireArray: Represents an array of wires equally spaced around a circumference of arbitrary radius.
"""
struct WireArray
	radius_in::Number
	radius_ext::Number
	radius_wire::Number
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
	- `radius_wire`: Radius of each individual wire [m].
	- `num_wires`: Number of wires in the array.
	- `lay_ratio`: Ratio defining the lay length of the wires (twisting factor).
	- `material_props`: A `Material` object representing the material properties (e.g., resistivity, temperature coefficient).
	- `temperature`: Temperature at which the properties are evaluated [°C] (default: 20).

	# Returns
	An instance of `WireArray` initialized with calculated geometric and electrical properties:
	- `radius_in`: Internal radius of the wire array [m].
	- `radius_ext`: External radius of the wire array [m].
	- `radius_wire`: Radius of each individual wire [m].
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
	wire_array = WireArray(0.01, @diam(0.002), 7, 10, material_props, temperature=25)
	println(wire_array.mean_diameter) # Outputs: Mean diameter in m
	println(wire_array.resistance)    # Outputs: Resistance in Ω
	```

	# References
	- None.
	"""
	function WireArray(
		radius_in::Union{Number, <:Any},
		radius_wire::Number,
		num_wires::Int,
		lay_ratio::Number,
		material_props::Material;
		temperature::Number = T₀,
	)

		# Extract `radius_in` from `radius_ext` if a custom type is provided
		radius_in = radius_in isa Number ? radius_in : getfield(radius_in, :radius_ext)
		diameter = radius_wire * 2
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
			radius_wire,
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
	- `radius_ext`: External radius of the strip [m].
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
	strip = Strip(0.01, @thick(0.002), 0.05, 10, material_props, temperature=25)
	println(strip.cross_section) # Outputs: Cross-sectional area in m²
	println(strip.resistance)    # Outputs: Resistance in Ω
	```

	# References
	- None.
	"""
	function Strip(
		radius_in::Union{Number, <:Any},
		radius_ext::Union{Number, Thickness},
		width::Number,
		lay_ratio::Number,
		material_props::Material;
		temperature::Number = T₀,
	)
		# Extract `radius_in` from `radius_ext` if a custom type is provided
		radius_in = radius_in isa Number ? radius_in : getfield(radius_in, :radius_ext)

		# Handle external radius: absolute value or relative to radius_in
		radius_ext = radius_ext isa Thickness ? radius_in + radius_ext.value : radius_ext
		thickness = radius_ext - radius_in

		rho = material_props.rho
		T0 = material_props.T0
		alpha = material_props.alpha
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
		radius_ext::Union{Number, Thickness},
		material_props::Material;
		temperature::Number = T₀,
	)

		# Extract `radius_in` from `radius_ext` if a custom type is provided
		radius_in = radius_in isa Number ? radius_in : getfield(radius_in, :radius_ext)

		# Handle external radius: absolute value or relative to radius_in
		radius_ext = radius_ext isa Thickness ? radius_in + radius_ext.value : radius_ext

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
	alpha::Number
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
add_conductor_part!: Adds a new part to an existing `Conductor` object and updates its properties.

# Arguments
- `sc`: A `Conductor` object to which the new part will be added.
- `part_type`: The type of the conductor part to be added (`WireArray`, `Strip`, or `Tubular`).
- `args...`: Positional arguments specific to the constructor of the `part_type`.
- `kwargs...`: Named arguments for the constructor of the `part_type`. Includes optional properties such as `radius_in` and `temperature`.

# Returns
- None. Modifies the `Conductor` instance in place by adding the specified part and updating its properties:
- Updates `gmr`, `resistance`, `alpha`, `radius_ext`, `cross_section`, and `num_wires` to account for the new part.

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
	sc.alpha =
		(sc.alpha * new_part.resistance + new_part.material_props.alpha * sc.resistance) /
		(sc.resistance + new_part.resistance) # composite temperature coefficient 
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
	radius_wire = wa.radius_wire
	num_wires = wa.num_wires
	lay_radius = num_wires == 1 ? 0 : wa.radius_in + radius_wire

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
calc_tubular_inductance: Compute the inductance of a tubular conductor.

# Arguments
- `radius_in`: Internal radius of the tubular conductor [m].
- `radius_ext`: External radius of the tubular conductor [m].
- `mu_r`: Relative permeability of the conductor material (dimensionless).

# Returns
- Inductance of the tubular conductor per unit length [H/m].

# Examples
```julia
L = calc_tubular_inductance(0.01, 0.02, 1.0)
println(L) # Output: Inductance in H/m
```

# Dependencies
- None.

# References
- None.
"""
function calc_tubular_inductance(radius_in::Number, radius_ext::Number, mu_r::Number)
	return mu_r * μ₀ / (2 * π) * log(radius_ext / radius_in)
end

"""
calc_inductance_flat: Calculate the inductance per phase for a flat horizontal cable arrangement using the simplified formula. This is meant for quick verification of datasheet parameters and should not be used for detailed analysis.

# Arguments
- `mu_r`: Relative permeability of the conductor material (dimensionless).
- `r`: Radius of the cable (outer radius) [m].

# Keyword Arguments
- `S`: Separation between adjacent cables in the flat arrangement [m] (default: 7e-2).
- `t`: Thickness of the screen wires [m] (default: 3e-3).

# Returns
- Inductance per phase of the cable arrangement [H/m].

# Examples
```julia
L = calc_inductance_flat(1.0, 0.01, S=0.07, t=0.003)
println(L) # Output: Inductance per phase in H/m
```

# Dependencies
- None.

# References
- None.
"""
function calc_inductance_flat(mu_r::Number, r::Number; S::Number = 7e-2, t::Number = 3e-3)

	# Equivalent distance for flat cable arrangement
	Deq = (S * S * 2S)^(1 / 3)

	# Simplified reduction factor due screen wires
	dL = t / (mu_r * r)

	# Inductance per phase formula
	Lphase = (μ₀ / (2π)) * (log(2 * Deq / r) + (mu_r / 4) - dL)

	return Lphase
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
_get_material_color: Generates a color representation for a material based on its physical properties.

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
color = _get_material_color(material_props)
println(color) # Outputs: RGBA color based on material properties
```

# References
- None.
"""
function _get_material_color(
	material_props;
	rho_weight = 0.8,
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
	final_color = _overlay_colors([rho_color_w, epsr_color_w, mur_color_w])

	return final_color
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
	- `radius_ext`: External radius of the layer [m].
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
	semicon_layer = Semicon(0.01, @thick(0.002), material_props, temperature=25)
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
		radius_ext::Union{Number, Thickness},
		material_props::Material;
		temperature::Number = T₀,
	)

		rho = material_props.rho
		T0 = material_props.T0
		alpha = material_props.alpha
		epsr_r = material_props.eps_r

		# Extract `radius_in` from `radius_ext` if a custom type is provided
		radius_in = radius_in isa Number ? radius_in : getfield(radius_in, :radius_ext)

		# Handle external radius: absolute value or relative to radius_in
		radius_ext = radius_ext isa Thickness ? radius_in + radius_ext.value : radius_ext
		# thickness = radius_ext - radius_in

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
	- `radius_ext`: External radius of the layer [m].
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
	insulator_layer = Insulator(0.01, @thick(0.005), material_props, temperature=25)
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
		radius_ext::Union{Number, Thickness},
		material_props::Material;
		temperature::Number = T₀,
	)

		# Extract `radius_in` from `radius_ext` if a custom type is provided
		radius_in = radius_in isa Number ? radius_in : getfield(radius_in, :radius_ext)

		# Handle external radius: absolute value or relative to radius_in
		radius_ext = radius_ext isa Thickness ? radius_in + radius_ext.value : radius_ext
		# thickness = radius_ext - radius_in

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
function calc_equivalent_gmr(sc::CableParts, layer::CableParts)
	beta = sc.cross_section / (sc.cross_section + layer.cross_section)
	current_conductor = sc isa Conductor ? sc.layers[end] : sc
	gmd = calc_gmd(current_conductor, layer)
	return sc.gmr^(beta^2) * layer.gmr^((1 - beta)^2) * gmd^(2 * beta * (1 - beta))
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
		r1 = co1.radius_wire
		s1 = pi * r1^2
	else
		coords1 = [(0, 0)]
		n1 = 1
		r1 = co1.radius_ext
		s1 = co1.cross_section
	end

	if co2 isa WireArray
		coords2 = get_wirearray_coords(co2)
		n2 = co2.num_wires
		r2 = co2.radius_wire
		s2 = pi * r2^2
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
CableComponent: Represents a cable component with its geometric and material properties.
"""
mutable struct CableComponent
	radius_in_con::Number
	radius_ext_con::Number
	rho_con::Number
	alpha_con::Number
	mu_con::Number
	radius_ext_ins::Number
	eps_ins::Number
	mu_ins::Number
	loss_factor_ins::Number
	component_data::Vector{<:CableParts}

	"""
	Constructor: Initializes a `CableComponent` object based on its components and frequency.

	# Arguments
	- `component_data`: A vector of `CableParts` representing the subcomponents of the cable.
	- `f`: The frequency of operation [Hz] (default: `f₀`).

	# Returns
	An instance of `CableComponent` initialized with the following attributes:
	- `radius_in_con`: Inner radius of the conductor [m].
	- `radius_ext_con`: Outer radius of the conductor [m].
	- `rho_con`: Resistivity of the conductor material [Ω·m].
	- `alpha_con`: Temperature coefficient of resistance of the conductor [1/°C].
	- `mu_con`: Magnetic permeability of the conductor material [H/m].
	- `radius_ext_ins`: Outer radius of the insulator [m].
	- `eps_ins`: Permittivity of the insulator material [F/m].
	- `mu_ins`: Magnetic permeability of the insulator material [H/m].
	- `loss_factor_ins`: Loss factor of the insulator (dimensionless).
	- `component_data`: A vector of `CableParts` representing the subcomponents of the cable.

	# Dependencies
	This constructor uses the following non-native functions:
	- `calc_parallel_equivalent`: Calculates the parallel equivalent of electrical parameters.
	- `calc_gmd`: Computes the geometric mean distance between components.
	- `gmr_to_mu`: Converts geometric mean radius to magnetic permeability.

	# Examples
	```julia
	components = [Conductor(...), Insulator(...)] # Define individual cable parts
	cable = CableComponent(components, f=50)
	println(cable.rho_con) # Output: Resistivity of the conductor [Ω·m]
	println(cable.eps_ins) # Output: Permittivity of the insulator [F/m]
	```

	# References
	- None.
	"""
	function CableComponent(
		# name::String,
		component_data::Vector{<:CableParts},
		f::Number = f₀,
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

				if equiv_resistance === nothing
					alpha_con = part isa Conductor ? part.alpha : part.material_props.alpha
					equiv_resistance = part.resistance
				else
					alpha_new = part isa Conductor ? part.alpha : part.material_props.alpha
					alpha_con =
						(
							alpha_con * part.resistance +
							alpha_new * equiv_resistance
						) /
						(equiv_resistance + part.resistance) # composite temperature coefficient

					equiv_resistance =
						calc_parallel_equivalent(equiv_resistance, part.resistance)
				end

				radius_in_con = min(radius_in_con, part.radius_in)
				radius_ext_con += (part.radius_ext - part.radius_in)
				total_num_wires += part.num_wires
				calc_weighted_num_turns(part)

				if gmr_eff_con === nothing
					gmr_eff_con = part.gmr
				else
					beta =
						total_cross_section_con /
						(total_cross_section_con + part.cross_section)
					gmd = calc_gmd(previous_part, part)
					gmr_eff_con =
						gmr_eff_con^(beta^2) * part.gmr^((1 - beta)^2) *
						gmd^(2 * beta * (1 - beta))
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
			correction_mu_ins =
				isnan(num_turns) ? 1 :
				(
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
NominalData: Represents nominal electrical and geometric parameters for a cable.
"""
mutable struct NominalData
	conductor_cross_section::Union{Nothing, Number}
	screen_cross_section::Union{Nothing, Number}
	armor_cross_section::Union{Nothing, Number}
	resistance::Union{Nothing, Number}
	capacitance::Union{Nothing, Number}
	inductance::Union{Nothing, Number}

	"""
	Constructor: Initializes a `NominalData` object with optional default values.

	# Arguments
	- `conductor_cross_section`: Cross-sectional area of the conductor [mm²] (default: `nothing`).
	- `screen_cross_section`: Cross-sectional area of the screen [mm²] (default: `nothing`).
	- `armor_cross_section`: Cross-sectional area of the armor [mm²] (default: `nothing`).
	- `resistance`: Electrical resistance of the cable [Ω/km] (default: `nothing`).
	- `capacitance`: Electrical capacitance of the cable [μF/km] (default: `nothing`).
	- `inductance`: Electrical inductance of the cable [mH/km] (default: `nothing`).

	# Returns
	An instance of `NominalData` with the specified nominal properties.

	# Dependencies
	- None.

	# Examples
	```julia
	nominal_data = NominalData(
		conductor_cross_section=1.5,
		resistance=0.02,
		capacitance=1e-9,
	)
	println(nominal_data.conductor_cross_section) # Output: 1.5
	println(nominal_data.resistance) # Output: 0.02
	println(nominal_data.capacitance) # Output: 1e-9
	```

	# References
	- None.
	"""
	function NominalData(;
		conductor_cross_section::Union{Nothing, Number} = nothing,
		screen_cross_section::Union{Nothing, Number} = nothing,
		armor_cross_section::Union{Nothing, Number} = nothing,
		resistance::Union{Nothing, Number} = nothing,
		capacitance::Union{Nothing, Number} = nothing,
		inductance::Union{Nothing, Number} = nothing,
	)
		return new(
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
CableDesign: Represents the design of a cable, including its unique identifier, nominal data, and components.
"""
mutable struct CableDesign
	cable_id::String
	nominal_data::NominalData                        # Informative reference data
	components::OrderedDict{String, CableComponent}  # Key: component name, Value: CableComponent object

	"""
	Constructor: Initializes a `CableDesign` object with a unique identifier, nominal data, and components.

	# Arguments
	- `cable_id`: A string representing the unique identifier for the cable design.
	- `component_name`: The name of the first cable component (String).
	- `component_parts`: A vector of parts representing the subcomponents of the first cable component.
	- `f`: The frequency of operation [Hz] (default: `f₀`).
	- `nominal_data`: A `NominalData` object containing reference data (default: `NominalData()`).

	# Returns
	An instance of `CableDesign` with the following attributes:
	- `cable_id`: Unique identifier for the cable design.
	- `nominal_data`: Reference data for the cable design.
	- `components`: An `OrderedDict` mapping component names to `CableComponent` objects.

	# Dependencies
	This constructor uses the following non-native functions:
	- `CableComponent`: Initializes a cable component based on its parts and frequency.

	# Examples
	```julia
	parts = [Conductor(...), Insulator(...)] # Define parts for the component
	design = CableDesign("Cable001", "ComponentA", parts, f=50)
	println(design.cable_id) # Output: "Cable001"
	println(design.components["ComponentA"]) # Output: CableComponent object
	```

	# References
	- None.
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
			CableComponent(Vector{CableParts}(component_parts), f)
		return new(cable_id, nominal_data, components)
	end
end

"""
add_cable_component!: Adds or replaces a cable component in an existing `CableDesign`.

# Arguments
- `design`: A `CableDesign` object where the component will be added.
- `component_name`: The name of the cable component to be added (String).
- `component_parts`: A vector of parts representing the subcomponents of the cable component.
- `f`: The frequency of operation [Hz] (default: `f₀`).

# Returns
Modifies the `CableDesign` object in-place by adding or replacing the specified cable component.

# Dependencies
- `CableComponent`: Constructs a cable component based on its parts and frequency.

# Examples
```julia
parts = [Conductor(...), Insulator(...)] # Define parts for the component
add_cable_component!(design, "ComponentB", parts, f=60)
println(design.components["ComponentB"]) # Output: CableComponent object
```

# Notes
- If a component with the specified name already exists, it will be overwritten, and a warning will be logged.

# References
- None.
"""
function add_cable_component!(
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
		CableComponent(Vector{CableParts}(component_parts), f)
end

"""
core_parameters: Computes the core parameters (R, L, and C) for a given `CableDesign` and evaluates compliance with nominal values.

# Arguments
- `design`: A `CableDesign` object containing the cable components and nominal data.

# Returns
A `DataFrame` with the following columns:
- `parameter`: Names of the parameters (`R [Ω/km]`, `L [mH/km]`, `C [μF/km]`).
- `computed`: Computed values of the parameters based on the core component.
- `nominal`: Nominal values of the parameters from the `CableDesign`.
- `lower`: Lower bounds for the computed values (accounting for error margins).
- `upper`: Upper bounds for the computed values (accounting for error margins).
- `complies?`: A Boolean column indicating whether the nominal value is within the computed bounds.

# Dependencies
- `calc_tubular_resistance`: Computes the resistance of the tubular conductor.
- `calc_inductance_flat`: Computes the inductance of the conductor.
- `calc_shunt_capacitance`: Computes the shunt capacitance of the insulator.
- `_to_lower`: Computes the lower bound for a given value based on error margins.
- `_to_upper`: Computes the upper bound for a given value based on error margins.
- `DataFrame`: Constructs a tabular representation of the computed and nominal values.

# Examples
```julia
core_component = CableComponent([...]) # Define the core component
nominal_data = NominalData(resistance=0.02, inductance=0.5, capacitance=200)
design = CableDesign("Cable001", "core", [core_component]; nominal_data=nominal_data)

data = core_parameters(design)
println(data)
# Output: DataFrame with computed values and compliance checks.
```

# References
- None.
"""
function core_parameters(design::CableDesign)
	# Extract the core component
	cable_core = design.components["core"]

	# Compute R, L, and C using given formulas
	R =
		calc_tubular_resistance(
			cable_core.radius_in_con,
			cable_core.radius_ext_con,
			cable_core.rho_con,
			0,
			20,
			20,
		) * 1e3

	L = calc_inductance_flat(
		cable_core.mu_con,
		cable_core.radius_ext_con,
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

	# Compute the comparison DataFrame
	data = DataFrame(
		parameter = ["R [Ω/km]", "L [mH/km]", "C [μF/km]"],
		computed = [R, L, C],
		nominal = nominals,
		lower = [_to_lower(R), _to_lower(L), _to_lower(C)],
		upper = [_to_upper(R), _to_upper(L), _to_upper(C)],
	)

	# Add compliance column
	data[!, "complies?"] = [
		(data.nominal[i] >= data.lower[i] && data.nominal[i] <= data.upper[i])
		for i in 1:nrow(data)
	]

	return data
end

"""
cable_data: Extracts and displays the properties of components in a `CableDesign` object as a `DataFrame`.

# Arguments
- `design`: A `CableDesign` object containing the components and their respective properties.

# Returns
- A `DataFrame` object with the following structure:
  - `property`: The name of each property (e.g., `radius_in_con`, `rho_con`, etc.).
  - Additional columns: Each component of the cable, with property values or `missing` if the property is not available for the component.

# Dependencies
- `DataFrame`: Used to organize and display the component properties in tabular form.

# Examples
```julia
design = CableDesign(
	"cable1",
	components = Dict(
		"conductor" => Component(radius_in_con=0.01, radius_ext_con=0.02, rho_con=1.68e-8),
		"insulator" => Component(radius_ext_ins=0.03, eps_ins=2.5, loss_factor_ins=0.01),
	)
)

# Extract and display the component properties
data = cable_data(design)
println(data) # Outputs a DataFrame with properties and values for each component
```

# References
- None.
"""
function cable_data(design::CableDesign)
	# Extract properties dynamically
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

	# Initialize the DataFrame with property names
	data = DataFrame(property = properties)

	for (key, part) in design.components
		# Use the key of the dictionary as the column name
		col = key

		# Collect values for each property, or `missing` if not available
		new_col = [
			:radius_in_con in fieldnames(typeof(part)) ?
			getfield(part, :radius_in_con) : missing,
			:radius_ext_con in fieldnames(typeof(part)) ?
			getfield(part, :radius_ext_con) : missing,
			:rho_con in fieldnames(typeof(part)) ? getfield(part, :rho_con) : missing,
			:alpha_con in fieldnames(typeof(part)) ? getfield(part, :alpha_con) : missing,
			:mu_con in fieldnames(typeof(part)) ? getfield(part, :mu_con) : missing,
			:radius_ext_ins in fieldnames(typeof(part)) ?
			getfield(part, :radius_ext_ins) : missing,
			:eps_ins in fieldnames(typeof(part)) ? getfield(part, :eps_ins) : missing,
			:mu_ins in fieldnames(typeof(part)) ? getfield(part, :mu_ins) : missing,
			:loss_factor_ins in fieldnames(typeof(part)) ?
			getfield(part, :loss_factor_ins) : missing,
		]

		# Add the new column to the DataFrame
		data[!, col] = new_col
	end

	return data
end

"""
cable_parts_data: Generates a detailed `DataFrame` summarizing the properties of all cable parts in a `CableDesign`.

# Arguments
- `design`: A `CableDesign` object containing components and their respective parts.

# Returns
A `DataFrame` with the following structure:
- `property`: Names of the properties being analyzed (e.g., `type`, `radius_in`, `radius_ext`, `cross_section`, etc.).
- Columns corresponding to each layer of each component in the design (e.g., `component_name, layer N`).
  Each column contains the respective values for the specified property, or `missing` if the property is not defined for the part.

# Dependencies
- `DataFrame`: Used for tabular representation of the data.
- `getfield`: Accesses field values dynamically based on their names.

# Notes
- The function iterates over all components and their parts to extract and organize their properties.
- If a property is not available for a part, the value will be set to `missing`.
- Column names are generated dynamically in the format `component_name, layer N` for clear identification.

# Examples
```julia
# Define a CableDesign with components and parts
design = CableDesign("Cable001", "core", [Conductor(...), Insulator(...)])
data = cable_parts_data(design)
println(data)
# Output: DataFrame summarizing properties of all parts in the design.
```

# References
- None.
"""
function cable_parts_data(design::CableDesign)
	# Updated properties list
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

	# Initialize the DataFrame with property names
	data = DataFrame(property = properties)

	# Iterate over components in the OrderedDict
	for (component_name, component) in design.components
		# Iterate over each part in component_data with an index
		for (i, part) in enumerate(component.component_data)
			# Generate column name with layer number
			col = lowercase(component_name) * ", layer " * string(i)

			# Collect values for each property, or `missing` if not available
			new_col = [
				lowercase(string(typeof(part))),  # type
				:radius_in in fieldnames(typeof(part)) ? getfield(part, :radius_in) :
				missing,
				:radius_ext in fieldnames(typeof(part)) ? getfield(part, :radius_ext) :
				missing,
				:radius_in in fieldnames(typeof(part)) ?
				2 * getfield(part, :radius_in) : missing,
				:radius_ext in fieldnames(typeof(part)) ?
				2 * getfield(part, :radius_ext) : missing,
				:radius_ext in fieldnames(typeof(part)) &&
				:radius_in in fieldnames(typeof(part)) ?
				(getfield(part, :radius_ext) - getfield(part, :radius_in)) : missing,
				:cross_section in fieldnames(typeof(part)) ?
				getfield(part, :cross_section) : missing,
				:num_wires in fieldnames(typeof(part)) ? getfield(part, :num_wires) :
				missing,
				:resistance in fieldnames(typeof(part)) ? getfield(part, :resistance) :
				missing,
				:alpha in fieldnames(typeof(part)) ? getfield(part, :alpha) :
				missing,
				:gmr in fieldnames(typeof(part)) ? getfield(part, :gmr) : missing,
				:gmr in fieldnames(typeof(part)) &&
				:radius_ext in fieldnames(typeof(part)) ?
				(getfield(part, :gmr) / getfield(part, :radius_ext)) : missing,
				:shunt_capacitance in fieldnames(typeof(part)) ?
				getfield(part, :shunt_capacitance) : missing,
				:shunt_conductance in fieldnames(typeof(part)) ?
				getfield(part, :shunt_conductance) : missing,
			]

			# Add the new column to the DataFrame
			data[!, col] = new_col
		end
	end

	return data
end

"""
preview_cable_cross_section: Generates an interactive visualization of a cable's cross-section based on its design.

# Arguments
- `design`: A `CableDesign` object containing the components and their respective parts.

# Returns
Displays an interactive plot of the cable's cross-section, with distinct layers and components visualized. The plot includes:
- Each layer of the cable (e.g., wires, strips, insulators) represented with different colors.
- Labels for components where applicable (only for the first instance of a type).
- A legend for material types and their corresponding colors.

# Dependencies
- `plotlyjs`: For interactive plotting.
- `Plots`: For creating shapes and handling graphical elements.
- `_get_material_color`: Determines the color associated with a material's properties.
- `_to_nominal`: Converts the dimensions of a layer to its nominal value for plotting.

# Notes
- For `WireArray` layers, wires are plotted individually in their respective positions.
- For `Strip`, `Tubular`, `Semicon`, and `Insulator` layers, full cross-sectional shapes are plotted.
- The plot's aspect ratio is set to `:equal` to ensure proportional representation of dimensions.

# Examples
```julia
# Define a CableDesign with components and parts
design = CableDesign("Cable001", "core", [Conductor(...), Insulator(...)])
preview_cable_cross_section(design)
# Output: Displays the cable cross-section in an interactive plot.
```

# References
- None.
"""
function preview_cable_cross_section(design::CableDesign)
	plotlyjs()  # For interactivity
	# Initialize plot
	plt = plot(size = (800, 600),
		aspect_ratio = :equal,
		legend = (0.875, 1.0),
		title = "Cable cross-section",
		xlabel = "x [m]",
		ylabel = "y [m]",
	)

	# Helper function to plot a layer
	function plot_layer!(layer, label)
		if layer isa WireArray
			radius_wire = _to_nominal(layer.radius_wire)
			num_wires = layer.num_wires

			lay_radius = num_wires == 1 ? 0 : _to_nominal(layer.radius_in) + radius_wire
			material_props = layer.material_props
			color = _get_material_color(material_props)

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
						x .+ radius_wire * cos.(0:0.01:2π),
						y .+ radius_wire * sin.(0:0.01:2π),
					),
					color = color,
					label = label,
				)
				label = ""  # Only add the label once
			end
		elseif layer isa Strip || layer isa Tubular || layer isa Semicon ||
			   layer isa Insulator
			radius_in = _to_nominal(layer.radius_in)
			radius_ext = _to_nominal(layer.radius_ext)
			material_props = layer.material_props
			color = _get_material_color(material_props)

			arcshape(θ1, θ2, rin, rext, N = 100) = Shape(
				vcat(Plots.partialcircle(θ1, θ2, N, rext),
					reverse(Plots.partialcircle(θ1, θ2, N, rin))),
			)

			shape = arcshape(0, 2π, radius_in, radius_ext)
			plot!(plt, shape, linecolor = color, color = color, label = label)
		end
	end

	# Iterate over all CableComponents in the design
	for (name, component) in design.components
		# Iterate over all CableParts in the component
		for part in component.component_data
			# Check if the part has layers
			if part isa Conductor
				# Loop over each layer and add legend only for the first layer
				first_layer = true
				for layer in part.layers
					plot_layer!(layer, first_layer ? lowercase(string(typeof(part))) : "")
					first_layer = false
				end
			else
				# Plot the top-level part with legend entry
				plot_layer!(part, lowercase(string(typeof(part))))
			end
		end
	end

	display(plt)
end

"""
CablesLibrary: Represents a library of cable designs stored as a dictionary.
"""
mutable struct CablesLibrary
	cable_designs::Dict{String, CableDesign}  # Key: cable ID, Value: CableDesign object

	"""
	Constructor: Initializes a `CablesLibrary` object, optionally loading cable designs from a file.

	# Arguments
	- `file_name`: The name of the file to load cable designs from (default: "cables_library.jls").

	# Returns
	An instance of `CablesLibrary` containing:
	- `cable_designs`: A dictionary with keys as cable IDs (String) and values as `CableDesign` objects.

	# Dependencies
	- `_load_cables_from_jls!`: A function to load cable designs from a `.jls` file into the library.
	- `isfile`: A function to check if the specified file exists.

	# Examples
	```julia
	# Create a new library without loading any file
	library = CablesLibrary()

	# Create a library and load designs from a file
	library_with_data = CablesLibrary("existing_library.jls")
	```

	# References
	- None.
	"""
	function CablesLibrary(file_name::String = "cables_library.jls")::CablesLibrary
		library = new(Dict{String, CableDesign}())
		if isfile(file_name)
			println("Loading cables database from $file_name...")
			_load_cables_from_jls!(library, file_name)
		else
			println("No $file_name found. Initializing empty cables database...")
		end
		return library
	end
end

"""
_load_cables_from_jls!: Loads cable designs from a serialized file into a `CablesLibrary` object.

# Arguments
- `library`: An instance of `CablesLibrary` to populate with the loaded cable designs.
- `file_name`: The name of the file to deserialize and load the cable designs from.

# Returns
- None. Modifies the `cable_designs` field of the `CablesLibrary` object in-place.

# Dependencies
- `deserialize`: A function to deserialize the data from the specified file.
- `println`: Used to provide feedback messages to the user.

# Examples
```julia
library = CablesLibrary()
_load_cables_from_jls!(library, "cables_library.jls")
println(library.cable_designs) # Prints the loaded cable designs if successful
```

# References
- None.
"""
function _load_cables_from_jls!(library::CablesLibrary, file_name::String)
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
save_cables_library: Saves the cable designs from a `CablesLibrary` object to a `.jls` file.

# Arguments
- `library`: An instance of `CablesLibrary` whose cable designs are to be saved.
- `file_name`: The name of the file to save the cable designs to (default: "cables_library.jls").

# Returns
- None. Writes the serialized cable designs to the specified file.

# Dependencies
- `serialize`: A function to serialize and save data to a file.
- `println`: Used to provide feedback messages to the user.

# Examples
```julia
library = CablesLibrary()
# Add cable designs to the library
save_cables_library(library, "new_cables_library.jls")
```

# References
- None.
"""
function save_cables_library(
	library::CablesLibrary,
	file_name::String = "cables_library.jls",
)
	try
		serialize(file_name, library.cable_designs)
		println("Cables library saved to $file_name.")
	catch e
		println("Error saving library to $file_name: $e")
	end
end

"""
add_cable_design!: Adds a new cable design to a `CablesLibrary` object.

# Arguments
- `library`: An instance of `CablesLibrary` to which the cable design will be added.
- `design`: A `CableDesign` object representing the cable design to be added. This object must have a `cable_id` field to uniquely identify it.

# Returns
- None. Modifies the `cable_designs` field of the `CablesLibrary` object in-place by adding the new cable design.

# Dependencies
- None.

# Examples
```julia
library = CablesLibrary()
design = CableDesign("cable1", ...) # Initialize CableDesign with required fields
add_cable_design!(library, design)
println(library.cable_designs) # Prints the updated dictionary containing the new cable design
```

# References
- None.
"""
function add_cable_design!(library::CablesLibrary, design::CableDesign)
	library.cable_designs[design.cable_id] = design
	println("Cable design with ID `$(design.cable_id)` added to the library.")
end

"""
remove_cable_design!: Removes a cable design from a `CablesLibrary` object by its ID.

# Arguments
- `library`: An instance of `CablesLibrary` from which the cable design will be removed.
- `cable_id`: The ID of the cable design to remove (String).

# Returns
- None. Modifies the `cable_designs` field of the `CablesLibrary` object in-place by removing the specified cable design if it exists.

# Dependencies
- None.

# Examples
```julia
library = CablesLibrary()
design = CableDesign("cable1", ...) # Initialize and add a CableDesign
add_cable_design!(library, design)

# Remove the cable design
remove_cable_design!(library, "cable1")
println(library.cable_designs) # Prints the dictionary without the removed cable design
```

# References
- None.
"""
function remove_cable_design!(library::CablesLibrary, cable_id::String)
	if haskey(library.cable_designs, cable_id)
		delete!(library.cable_designs, cable_id)
		println("Cable design with ID `$cable_id` removed from the library.")
	else
		println("Cable design with ID `$cable_id` not found in the library.")
	end
end

"""
get_cable_design: Retrieves a cable design from a `CablesLibrary` object by its ID.

# Arguments
- `library`: An instance of `CablesLibrary` from which the cable design will be retrieved.
- `cable_id`: The ID of the cable design to retrieve (String).

# Returns
- A `CableDesign` object corresponding to the given `cable_id` if found, otherwise `nothing`.

# Dependencies
- None.

# Examples
```julia
library = CablesLibrary()
design = CableDesign("cable1", ...) # Initialize and add a CableDesign
add_cable_design!(library, design)

# Retrieve the cable design
retrieved_design = get_cable_design(library, "cable1")
println(retrieved_design) # Prints the retrieved CableDesign object

# Attempt to retrieve a non-existent design
missing_design = get_cable_design(library, "nonexistent_id")
println(missing_design) # Prints nothing
```

# References
- None.
"""
function get_cable_design(
	library::CablesLibrary,
	cable_id::String,
)::Union{Nothing, CableDesign}
	if haskey(library.cable_designs, cable_id)
		return library.cable_designs[cable_id]
	else
		println("Cable design with ID `$cable_id` not found.")
		return nothing
	end
end

"""
display_cables_library: Displays the cable designs in a `CablesLibrary` object as a `DataFrame`.

# Arguments
- `library`: An instance of `CablesLibrary` whose cable designs are to be displayed.

# Returns
- A `DataFrame` object with the following columns:
  - `cable_id`: The unique identifier for each cable design.
  - `nominal_data`: A string representation of the nominal data for each cable design.
  - `components`: A comma-separated string listing the components of each cable design.

# Dependencies
- `DataFrame`: Used to create the tabular representation of the cable designs.

# Examples
```julia
library = CablesLibrary()
design1 = CableDesign("cable1", nominal_data=..., components=Dict("A"=>..., "B"=>...))
design2 = CableDesign("cable2", nominal_data=..., components=Dict("C"=>...))
add_cable_design!(library, design1)
add_cable_design!(library, design2)

# Display the library as a DataFrame
df = display_cables_library(library)
println(df) # Outputs the DataFrame with cable details
```

# References
- None.
"""
function display_cables_library(library::CablesLibrary)
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
