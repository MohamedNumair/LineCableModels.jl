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

	function WireArray(
		radius_in::Number,
		diameter::Number,
		num_wires::Int,
		lay_ratio::Number,
		material_props::Material;
		temperature::Number = 20,
	)
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

mutable struct Tubular
	radius_in::Number
	radius_ext::Number
	material_props::Material
	temperature::Number
	cross_section::Number
	resistance::Number
	gmr::Number

	function Tubular(
		radius_in::Number,
		radius_ext::Number,
		material_props::Material;
		temperature::Number = 20,
	)

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

const ConductorParts = Union{Strip, WireArray, Tubular}
mutable struct Conductor
	radius_in::Number
	radius_ext::Number
	cross_section::Number
	num_wires::Number
	resistance::Number
	gmr::Number
	layers::Vector{ConductorParts}

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

function calc_equivalent_gmr(sc::Conductor, layer::ConductorParts)
	alph = sc.cross_section / (sc.cross_section + layer.cross_section)
	beta = 1 - alph
	gmd = calc_gmd(sc.layers[end], layer)
	return sc.gmr^(alph^2) * layer.gmr^(beta^2) * gmd^(2 * alph * beta)
end

function get_wirearray_coords(wa::WireArray)
	wire_coords = []  # Global coordinates of all wires
	wire_diam = wa.diameter
	num_wires = wa.num_wires
	lay_radius = num_wires == 1 ? 0 : wa.radius_in + wire_diam / 2
	# mu_r = wa.material_props[:mu_r]  # Relative permeability of the layer

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

function calc_gmd(co1::ConductorParts, co2::ConductorParts)

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
				log_dij = log(max(r1, r2))
			end
			log_sum += (s1 * s2) * log_dij
			area_weights += (s1 * s2)
		end
	end
	return exp(log_sum / area_weights)
end

function calc_parallel_equivalent(total_R::Number, layer_R::Number)
	return 1 / (1 / total_R + 1 / layer_R)
end

function calc_tubular_resistance(
	radius_in::Number,
	radius_ext::Number,
	rho::Number,
	alpha::Number,
	T0::Number,
	T_system::Number,
)
	temp_correction_factor = (1 + alpha * (T_system - T0))
	cross_section = π * (radius_ext^2 - radius_in^2)
	return temp_correction_factor * rho / cross_section
end

function calc_wirearray_gmr(lay_rad::Number, N::Number, rad_wire::Number, mu_r::Number)

	gmr_wire = rad_wire * exp(-mu_r / 4)

	log_gmr_array = log(gmr_wire * N * lay_rad^(N - 1)) / N

	return exp(log_gmr_array)
end

function calc_tubular_gmr(radius_ext::Number, radius_in::Number, mu_r::Number)
	if radius_ext < radius_in
		throw(ArgumentError("Invalid parameters: radius_ext must be >= radius_in."))
	end

	# Constants
	if abs(radius_ext - radius_in) < TOL
		# Tube collapses into a thin shell with infinitesimal thickness and the GMR is simply the radius
		gmr = radius_ext
	elseif abs(radius_in / radius_ext) < eps() && abs(radius_in) > TOL
		# Tube becomes infinitelly thick up to floating point precision
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
			wire_diam = layer.diameter
			num_wires = layer.num_wires

			lay_radius = num_wires == 1 ? 0 : layer.radius_in + wire_diam / 2
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
			radius_in = layer.radius_in
			radius_ext = layer.radius_ext
			material_props = layer.material_props
			color = get_material_color(material_props)

			arcshape(θ1, θ2, rin, rext, N = 100) = Shape(
				vcat(Plots.partialcircle(θ1, θ2, N, rext),
					reverse(Plots.partialcircle(θ1, θ2, N, rin))),
			)

			# println(arcshape(0, 2π, radius_in, radius_ext))
			# plot!(plt, x=[ 0 ], y=[ 0 ], linetype=:scatter, color=color, marker=(1, arcshape(0, 2π, radius_in, radius_ext)), legend=false)
			shape = arcshape(0, 2π, radius_in, radius_ext)
			plot!(plt, shape, linecolor = color, color = color, label = "")
		end

	end

	display(plt)
end

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

function visualize_gradient(gradient, n_steps = 100; title = "Color gradient")
	# Generate evenly spaced values between 0 and 1
	x = range(0, stop = 1, length = n_steps)
	colors = [get(gradient, xi) for xi in x]  # Sample the gradient

	# Create a plot using colored bars
	bar(x, ones(length(x)); color = colors, legend = false, xticks = false, yticks = false)
	title!(title)
end

function overlay_multiple_colors(colors::Vector{<:RGBA})
	# Start with the first color
	result = colors[1]

	# Overlay each subsequent color
	for i in 2:length(colors)
		result = overlay_colors(result, colors[i])
	end

	return result
end

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
