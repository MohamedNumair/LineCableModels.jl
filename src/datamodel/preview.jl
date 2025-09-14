

# """
# $(TYPEDSIGNATURES)

# Generates a color representation for a [`Material`](@ref) based on its physical properties.

# # Arguments

# - `material_props`: Dictionary containing material properties:
#   - `rho`: Electrical resistivity \\[Ω·m\\].
#   - `eps_r`: Relative permittivity \\[dimensionless\\].
#   - `mu_r`: Relative permeability \\[dimensionless\\].
# - `rho_weight`: Weight assigned to resistivity in color blending (default: 1.0) \\[dimensionless\\].
# - `epsr_weight`: Weight assigned to permittivity in color blending (default: 0.1) \\[dimensionless\\].
# - `mur_weight`: Weight assigned to permeability in color blending (default: 0.1) \\[dimensionless\\].

# # Returns

# - An `RGBA` object representing the combined color based on the material's properties.

# # Notes

# Colors are normalized and weighted using property-specific gradients:
# - Conductors (ρ ≤ 5ρ₀): White → Dark gray
# - Poor conductors (5ρ₀ < ρ ≤ 10⁴): Bronze → Greenish-brown
# - Insulators (ρ > 10⁴): Greenish-brown → Black
# - Permittivity: Gray → Orange
# - Permeability: Silver → Purple
# - The overlay function combines colors with their respective alpha/weight values.

# # Examples

# ```julia
# material_props = Dict(
# 	:rho => 1.7241e-8,
# 	:eps_r => 2.3,
# 	:mu_r => 1.0
# )
# color = $(FUNCTIONNAME)(material_props)
# println(color) # Expected output: RGBA(0.9, 0.9, 0.9, 1.0)
# ```
# """
# function _get_material_color(
# 	material_props;
# 	rho_weight = 1.0, #0.8,
# 	epsr_weight = 0.1,
# 	mur_weight = 0.1,
# )

# 	# Auxiliar function to combine colors
# 	function _overlay_colors(colors::Vector{<:RGBA})
# 		# Handle edge cases
# 		if length(colors) == 0
# 			return RGBA(0, 0, 0, 0)
# 		elseif length(colors) == 1
# 			return colors[1]
# 		end

# 		# Initialize with the first color
# 		r, g, b, a = red(colors[1]), green(colors[1]), blue(colors[1]), alpha(colors[1])

# 		# Single-pass overlay for the remaining colors
# 		for i in 2:length(colors)
# 			r2, g2, b2, a2 =
# 				red(colors[i]), green(colors[i]), blue(colors[i]), alpha(colors[i])
# 			a_new = a2 + a * (1 - a2)

# 			if a_new == 0
# 				r, g, b, a = 0, 0, 0, 0
# 			else
# 				r = (r2 * a2 + r * a * (1 - a2)) / a_new
# 				g = (g2 * a2 + g * a * (1 - a2)) / a_new
# 				b = (b2 * a2 + b * a * (1 - a2)) / a_new
# 				a = a_new
# 			end
# 		end

# 		return RGBA(r, g, b, a)
# 	end

# 	# Fixed normalization bounds
# 	epsr_min, epsr_max = 1.0, 1000.0  # Adjusted permittivity range for semiconductors
# 	mur_min, mur_max = 1.0, 300.0  # Relative permeability range
# 	rho_base = 1.72e-8

# 	# Extract nominal values for uncertain measurements
# 	rho = to_nominal(material_props.rho)
# 	epsr_r = to_nominal(material_props.eps_r)
# 	mu_r = to_nominal(material_props.mu_r)

# 	# Handle air/void
# 	if isinf(rho)
# 		return RGBA(1.0, 1.0, 1.0, 1.0)  # Transparent white
# 	end

# 	# Normalize epsr and mur
# 	epsr_norm = (epsr_r - epsr_min) / (epsr_max - epsr_min)
# 	mur_norm = (mu_r - mur_min) / (mur_max - mur_min)

# 	# Define color gradients based on resistivity
# 	if rho <= 1000 * rho_base
# 		# Conductors: Bright metallic white → Darker metallic gray (logarithmic scaling)
# 		rho_norm = log10(rho / rho_base) / log10(5)  # Normalize based on `5 * rho_base`

# 		rho_color = get(cgrad([
# 				RGB(0.9, 0.9, 0.9),  # Almost white
# 				RGB(0.6, 0.6, 0.6),  # Light gray
# 				RGB(0.4, 0.4, 0.4)  # Dark gray
# 			]), clamp(rho_norm, 0.0, 1.0))

# 	elseif rho <= 10000
# 		# Poor conductors/semiconductors: Bronze → Gold → Reddish-brown → Dark orange → Greenish-brown
# 		rho_norm = (rho - 10e-8) / (10000 - 10e-8)
# 		rho_color = get(
# 			cgrad([
# 				RGB(0.8, 0.5, 0.2),  # Metallic bronze
# 				RGB(1.0, 0.85, 0.4),  # Metallic gold
# 				RGB(0.8, 0.4, 0.2),  # Reddish-brown
# 				RGB(0.8, 0.3, 0.1),  # Dark orange
# 				RGB(0.6, 0.4, 0.3),   # Greenish-brown
# 			]), rho_norm)

# 	else
# 		# Insulators: Greenish-brown → Black
# 		rho_norm = (rho - 10000) / (1e5 - 10000)
# 		rho_color = get(cgrad([RGB(0.6, 0.4, 0.3), :black]), clamp(rho_norm, 0.0, 1.0))
# 	end

# 	# Normalize epsr and mur values to [0, 1]
# 	epsr_norm = clamp(epsr_norm, 0.0, 1.0)
# 	mur_norm = clamp(mur_norm, 0.0, 1.0)

# 	# Create color gradients for epsr and mur
# 	epsr_color = get(cgrad([:gray, RGB(1.0, 0.9, 0.7), :orange]), epsr_norm)  # Custom amber
# 	mur_color = get(
# 		cgrad([:silver, :gray, RGB(0.9, 0.8, 1.0), :purple, RGB(0.3, 0.1, 0.6)]),
# 		mur_norm,
# 	)  # Custom purple

# 	# Apply weights to each property
# 	rho_color_w = Colors.RGBA(rho_color.r, rho_color.g, rho_color.b, rho_weight)
# 	epsr_color_w = Colors.RGBA(epsr_color.r, epsr_color.g, epsr_color.b, epsr_weight)
# 	mur_color_w = Colors.RGBA(mur_color.r, mur_color.g, mur_color.b, mur_weight)

# 	# Combine weighted colors
# 	final_color = _overlay_colors([rho_color_w, epsr_color_w, mur_color_w])

# 	return final_color
# end

# """
# $(TYPEDSIGNATURES)

# Displays the cross-section of a cable design.

# # Arguments

# - `design`: A [`CableDesign`](@ref) object representing the cable structure.
# - `x_offset`: Horizontal offset for the plot \\[m\\].
# - `y_offset`: Vertical offset for the plot \\[m\\].
# - `plt`: An optional `Plots.Plot` object to use for plotting.
# - `display_plot`: Boolean flag to display the plot after rendering.
# - `display_legend`: Boolean flag to display the legend in the plot.
# - `backend`: Optional plotting backend to use. If not specified, the function will choose a suitable backend based on the environment (e.g., GR for headless, PlotlyJS for interactive).
# - `sz`: Optional plot dimensions (width, height). Default: (800, 600).

# # Returns

# - A `Plots.Plot` object representing the visualized cable design.

# # Examples

# ```julia
# conductor_group = ConductorGroup(central_conductor)
# insulator_group = InsulatorGroup(main_insulation)
# component = CableComponent("core", conductor_group, insulator_group)
# design = CableDesign("example", component)
# cable_plot = $(FUNCTIONNAME)(design)  # Cable cross-section is displayed
# ```

# # See also

# - [`CableDesign`](@ref)
# - [`ConductorGroup`](@ref)
# - [`InsulatorGroup`](@ref)
# - [`WireArray`](@ref)
# - [`Tubular`](@ref)
# - [`Strip`](@ref)
# - [`Semicon`](@ref)
# """
# function preview(
# 	design::CableDesign;
# 	x_offset = 0.0,
# 	y_offset = 0.0,
# 	plt = nothing,
# 	display_plot = true,
# 	display_legend = true,
# 	backend = nothing,
# 	sz = (800, 600),
# 	display_id = false,
# )
# 	if isnothing(plt)
# 		# Choose appropriate backend based on environment
# 		resolve_backend(backend)
# 		plt = plot(size = sz,
# 			aspect_ratio = :equal,
# 			legend = (0.875, 1.0),
# 			title = display_id ? "Cable design preview: $(design.cable_id)" :
# 					"Cable design preview",
# 			xlabel = "y [m]",
# 			ylabel = "z [m]")
# 	end

# 	# Helper function to plot a layer
# 	function _plot_layer!(layer, label; x0 = 0.0, y0 = 0.0)
# 		if layer isa WireArray
# 			radius_wire = to_nominal(layer.radius_wire)
# 			num_wires = layer.num_wires

# 			lay_radius = num_wires == 1 ? 0.0 : to_nominal(layer.radius_in)
# 			material_props = layer.material_props
# 			color = _get_material_color(material_props)

# 			# Use the existing calc_wirearray_coords function to get wire centers
# 			wire_coords = calc_wirearray_coords(
# 				num_wires,
# 				radius_wire,
# 				to_nominal(lay_radius),
# 				C = (x0, y0),
# 			)

# 			# Plot each wire in the layer
# 			for (i, (x, y)) in enumerate(wire_coords)
# 				plot!(
# 					plt,
# 					Shape(
# 						x .+ radius_wire * cos.(0:0.01:2π),
# 						y .+ radius_wire * sin.(0:0.01:2π),
# 					),
# 					linecolor = :black,
# 					color = color,
# 					label = (i == 1 && display_legend) ? label : "",  # Only add label for first wire
# 				)
# 			end

# 		elseif layer isa Strip || layer isa Tubular || layer isa Semicon ||
# 			   layer isa Insulator
# 			radius_in = to_nominal(layer.radius_in)
# 			radius_ext = to_nominal(layer.radius_ext)
# 			material_props = layer.material_props
# 			color = _get_material_color(material_props)

# 			arcshape(θ1, θ2, rin, rext, x0 = 0.0, y0 = 0.0, N = 100) = begin
# 				# Generate angles for the arc
# 				θ = range(θ1, θ2, length = N)

# 				# Outer circle coordinates
# 				x_outer = x0 .+ rext .* cos.(θ)
# 				y_outer = y0 .+ rext .* sin.(θ)

# 				# Inner circle coordinates (reversed to close the shape properly)
# 				x_inner = x0 .+ rin .* cos.(reverse(θ))
# 				y_inner = y0 .+ rin .* sin.(reverse(θ))

# 				# Concatenate and explicitly close the shape by repeating the first point
# 				x_coords = [x_outer; x_inner; x_outer[1]]
# 				y_coords = [y_outer; y_inner; y_outer[1]]

# 				Shape(x_coords, y_coords)
# 			end
# 			shape = arcshape(0, 2π, radius_in, radius_ext, x0, y0)
# 			plot!(
# 				plt,
# 				shape,
# 				linecolor = color,
# 				color = color,
# 				label = display_legend ? label : "",
# 			)
# 		end
# 	end

# 	# Iterate over all CableComponents in the design
# 	for component in design.components
# 		# Process conductor group layers
# 		for layer in component.conductor_group.layers
# 			# Check if layer is a compound structure
# 			if layer isa ConductorGroup
# 				# Special handling for nested conductor groups
# 				first_layer = true
# 				for sublayer in layer.layers
# 					_plot_layer!(
# 						sublayer,
# 						first_layer ? lowercase(string(nameof(typeof(layer)))) : "",
# 						x0 = x_offset,
# 						y0 = y_offset,
# 					)
# 					first_layer = false
# 				end
# 			else
# 				# Plot standard conductor layer
# 				_plot_layer!(
# 					layer,
# 					lowercase(string(nameof(typeof(layer)))),
# 					x0 = x_offset,
# 					y0 = y_offset,
# 				)
# 			end
# 		end

# 		# Process insulator group layers
# 		for layer in component.insulator_group.layers
# 			_plot_layer!(
# 				layer,
# 				lowercase(string(nameof(typeof(layer)))),
# 				x0 = x_offset,
# 				y0 = y_offset,
# 			)
# 		end
# 	end

# 	if display_plot
# 		if !is_in_testset()
# 			if is_headless()
# 				DisplayAs.Text(DisplayAs.PNG(plt))
# 			else
# 				display(plt)
# 			end
# 		end
# 	end

# 	return plt
# end

# """
# $(TYPEDSIGNATURES)

# Displays the cross-section of a cable system.

# # Arguments

# - `system`: A [`LineCableSystem`](@ref) object containing the cable arrangement.
# - `earth_model`: Optional [`EarthModel`](@ref) to display earth layers.
# - `zoom_factor`: A scaling factor for adjusting the x-axis limits \\[dimensionless\\].
# - `backend`: Optional plotting backend to use.
# - `sz`: Optional plot dimensions (width, height). Default: (800, 600).

# # Returns

# - Nothing. Displays a plot of the cable system cross-section with cables, earth layers (if applicable), and the air/earth interface.

# # Examples

# ```julia
# system = LineCableSystem("test_system", 1000.0, cable_pos)
# earth_params = EarthModel(f, 100.0, 10.0, 1.0)
# $(FUNCTIONNAME)(system, earth_model=earth_params, zoom_factor=0.5)
# ```

# # See also

# - [`LineCableSystem`](@ref)
# - [`EarthModel`](@ref)
# - [`CablePosition`](@ref)
# """
# function preview(
# 	system::LineCableSystem;
# 	earth_model = nothing,
# 	zoom_factor = 0.25,
# 	backend = nothing,
# 	sz = (800, 600),
# 	display_plot = true,
# 	display_id = false,
# )
# 	resolve_backend(backend)
# 	plt = plot(size = sz,
# 		aspect_ratio = :equal,
# 		legend = (0.8, 0.9),
# 		title = display_id ? "Cable system cross-section: $(system.system_id)" :
# 				"Cable system cross-section",
# 		xlabel = "y [m]",
# 		ylabel = "z [m]")

# 	# Plot the air/earth interface at y=0
# 	hline!(
# 		plt,
# 		[0],
# 		linestyle = :solid,
# 		linecolor = :black,
# 		linewidth = 1.25,
# 		label = "Air/earth interface",
# 	)

# 	# Determine explicit wide horizontal range for earth layer plotting
# 	x_positions = [to_nominal(cable.horz) for cable in system.cables]
# 	max_span = maximum(abs, x_positions) + 5  # extend 5 m beyond farthest cable position
# 	x_limits = [-max_span, max_span]

# 	# Plot earth layers if provided and vertical_layers == false
# 	if !isnothing(earth_model) && !earth_model.vertical_layers
# 		layer_colors = [:burlywood, :sienna, :peru, :tan, :goldenrod, :chocolate]
# 		cumulative_depth = 0.0
# 		for (i, layer) in enumerate(earth_model.layers[2:end])
# 			# Skip bottommost infinite layer
# 			if isinf(layer.t)
# 				break
# 			end

# 			# Compute the depth of the current interface
# 			cumulative_depth -= layer.t
# 			hline!(
# 				plt,
# 				[cumulative_depth],
# 				linestyle = :solid,
# 				linecolor = layer_colors[mod1(i, length(layer_colors))],
# 				linewidth = 1.25,
# 				label = "Earth layer $i",
# 			)

# 			# Fill the area for current earth layer
# 			y_coords = [cumulative_depth + layer.t, cumulative_depth]
# 			plot!(plt, [x_limits[1], x_limits[2], x_limits[2], x_limits[1]],
# 				[y_coords[1], y_coords[1], y_coords[2], y_coords[2]],
# 				seriestype = :shape, color = layer_colors[mod1(i, length(layer_colors))],
# 				alpha = 0.25, linecolor = :transparent,
# 				label = "")
# 		end
# 	end

# 	for cable_position in system.cables
# 		x_offset = to_nominal(cable_position.horz)
# 		y_offset = to_nominal(cable_position.vert)
# 		preview(
# 			cable_position.design_data;  # Changed from cable_position.design_data
# 			x_offset,
# 			y_offset,
# 			plt,
# 			display_plot = false,
# 			display_legend = false,
# 		)
# 	end

# 	plot!(plt, xlim = (x_limits[1], x_limits[2]) .* zoom_factor)

# 	if display_plot
# 		if !is_in_testset()
# 			if is_headless()
# 				DisplayAs.Text(DisplayAs.PNG(plt))
# 			else
# 				display(plt)
# 			end
# 		end
# 	end

# 	return plt
# end


using Makie, Colors
using Printf
using Dates
using Statistics

# Optional backends: import if available (also top-level only)
const HAS_GLM   = (
try
	using GLMakie: GLMakie;
	true;
catch
	false;
end)
const HAS_WGL   = (
try
	using WGLMakie: WGLMakie;
	true;
catch
	false;
end)
const HAS_CAIRO = (
try
	using CairoMakie: CairoMakie;
	true;
catch
	false;
end)

(HAS_GLM || HAS_WGL || HAS_CAIRO) ||
	Base.Base.error("No Makie backend installed. Add GLMakie or CairoMakie.")

_is_interactive_backend() = nameof(Makie.current_backend()) in (:GLMakie, :WGLMakie)



############################
# Backend selection helper #
############################
function _use_makie_backend(backend::Union{Nothing, Symbol})
	if is_headless()
		if HAS_CAIRO
			@warn "Using CairoMakie in headless mode."
			CairoMakie.activate!()
		else
			Base.error("CairoMakie not available in headless mode.")
		end
		return  # already set appropriately
	end

	if backend === :gl
		if HAS_GLM
			GLMakie.activate!()
		elseif HAS_CAIRO
			@warn "GLMakie not available; falling back to CairoMakie."
			CairoMakie.activate!()
		else
			Base.error("GLMakie not installed.")
		end
	elseif backend === :wgl
		if HAS_WGL
			WGLMakie.activate!()
		elseif HAS_CAIRO
			@warn "WGLMakie not available; falling back to CairoMakie."
			CairoMakie.activate!()
		else
			Base.error("WGLMakie not installed.")
		end
	elseif backend === :cairo
		if HAS_CAIRO
			CairoMakie.activate!()
		elseif HAS_GLM
			@warn "CairoMakie not available; using GLMakie."
			GLMakie.activate!()
		else
			Base.error("CairoMakie not installed.")
		end
	else
		# default preference: GL → Cairo → WGL
		if HAS_GLM
			GLMakie.activate!()
		elseif HAS_CAIRO
			CairoMakie.activate!()
		elseif HAS_WGL
			WGLMakie.activate!()
		else
			Base.error("No Makie backend installed.")
		end
	end
end

########################
# Small utility glue   #
########################
const _TAU = 2π

# finite & nonnegative
_valid_finite(x, y) = isfinite(x) && isfinite(y)


# Tunables (bands & palettes)
# ----------------------------
const RHO_MIN       = 1e-9      # for legend floor
const RHO_METAL_MAX = 1e-6
const RHO_SEMIMETAL = 1e-4
const RHO_SEMI_MAX  = 1e3
const RHO_LEAKY_MAX = 1e8
const RHO_MAX       = 1e10      # for legend ceiling

const METAL_GRADIENT = [
	RGB(0.92, 0.90, 0.86), # warm-silver (copper-ish)
	RGB(0.89, 0.89, 0.89), # neutral silver
	RGB(0.86, 0.89, 0.92), # cool-silver (aluminium-ish)
	RGB(0.70, 0.72, 0.75),  # slightly darker metal
]

const SEMIMETAL_GRADIENT = [
	RGB(0.70, 0.72, 0.75),   # gray
	RGB(0.80, 0.75, 0.65),    # sand/bronze hint
]

const SEMICON_GRADIENT = [
	RGB(1.00, 0.83, 0.40),   # light amber
	RGB(0.85, 0.55, 0.18),    # dark amber-brown
]

const LEAKY_GRADIENT = [
	RGB(0.42, 0.55, 0.15),   # olive/earthy
	RGB(0.13, 0.13, 0.13),    # charcoal
]

const INSULATOR_GRADIENT = [
	RGB(0.07, 0.07, 0.07),   # near-black (keep >0 so overlays remain visible)
	RGB(0.00, 0.00, 0.00),
]

# Overlays
const MU_OVERLAY_GRADIENT  = [RGB(0.20, 0.50, 0.95), RGB(0.56, 0.00, 0.91)]  # blue → indigo
const EPS_OVERLAY_GRADIENT = [RGB(0.00, 0.85, 0.70), RGB(0.00, 0.55, 0.90)]  # teal → cyan


# Linear interpolation across a list of colors in [0,1]
# robust gradient (no reinterpret)
_interpolate_gradient(colors::Vector{<:Colorant}, t::Real) = begin
	n = length(colors);
	n >= 2 || throw(ArgumentError("Need ≥ 2 colors"))
	tc = clamp(Float64(t), 0, 1)
	x  = tc * (n - 1)
	i  = clamp(floor(Int, x) + 1, 1, n - 1)
	f  = x - (i - 1)
	c1 = RGB(colors[i]);
	c2 = RGB(colors[i+1])
	RGB(
		(1 - f) * red(c1) + f * red(c2),
		(1 - f) * green(c1) + f * green(c2),
		(1 - f) * blue(c1) + f * blue(c2),
	)
end

# Log normalization helper: map v∈[a,b] (log10) → t∈[0,1]
_lognorm(v, a, b) = begin
	va = clamp(v, min(a, b), max(a, b))
	(log10(va) - log10(a)) / (log10(b) - log10(a))
end

_overlay(a::Colors.RGBA, b::Colors.RGBA) = begin
	a1, a2 = alpha(a), alpha(b)
	out_a = a2 + a1*(1 - a2)
	out_a == 0 && return Colors.RGBA(0, 0, 0, 0)
	r = (red(b)*a2 + red(a)*a1*(1 - a2)) / out_a
	g = (green(b)*a2 + green(a)*a1*(1 - a2)) / out_a
	b_ = (blue(b)*a2 + blue(a)*a1*(1 - a2)) / out_a
	Colors.RGBA(r, g, b_, out_a)
end

# Clamp lightness to keep overlays visible on "black"
function _ensure_min_lightness(c::RGB, Lmin::Float64 = 0.07)
	hsl = HSL(c)
	L = max(hsl.l, Lmin)
	rgb = RGB(HSL(hsl.h, hsl.s, L))
	return rgb
end

# ----------------------------
# Base color controlled by ρ
# ----------------------------
function _base_color_from_rho(ρ::Real)::RGB
	if !isfinite(ρ)
		return INSULATOR_GRADIENT[end]
	elseif ρ ≤ RHO_METAL_MAX
		t = _lognorm(ρ, 1e-8, RHO_METAL_MAX)
		return _interpolate_gradient(METAL_GRADIENT, t)
	elseif ρ ≤ RHO_SEMIMETAL
		t = _lognorm(ρ, RHO_METAL_MAX, RHO_SEMIMETAL)
		return _interpolate_gradient(SEMIMETAL_GRADIENT, t)
	elseif ρ ≤ RHO_SEMI_MAX
		t = _lognorm(ρ, RHO_SEMIMETAL, RHO_SEMI_MAX)
		return _interpolate_gradient(SEMICON_GRADIENT, t)
	elseif ρ ≤ RHO_LEAKY_MAX
		t = _lognorm(ρ, RHO_SEMI_MAX, RHO_LEAKY_MAX)
		return _interpolate_gradient(LEAKY_GRADIENT, t)
	else
		t = _lognorm(min(ρ, RHO_MAX), RHO_LEAKY_MAX, RHO_MAX)
		return _ensure_min_lightness(_interpolate_gradient(INSULATOR_GRADIENT, t), 0.07)
	end
end

# ----------------------------
# Overlays (μr & εr)
# ----------------------------
# μr in [1, 300] → alpha up to ~0.5, stronger on dark bases
function _mu_overlay(base::RGB, μr::Real)::Colors.RGBA
	μn = clamp((_lognorm(max(μr, 1.0), 1.0, 300.0)), 0, 1)
	tint = _interpolate_gradient(MU_OVERLAY_GRADIENT, μn)
	L = HSL(base).l
	α = 0.50 * μn * (0.6 + 0.4*(1 - L)) # reduce on bright silver, boost on dark
	Colors.RGBA(tint.r, tint.g, tint.b, α)
end

# εr in [1, 1000] → alpha up to ~0.6 on insulators, ~0.2 on metals
function _eps_overlay(base::RGB, εr::Real, ρ::Real)::Colors.RGBA
	εn = clamp((_lognorm(max(εr, 1.0), 1.0, 1000.0)), 0, 1)
	tint = _interpolate_gradient(EPS_OVERLAY_GRADIENT, εn)
	# weight more if it's an insulator/leaky (so it shows on dark)
	band_weight = ρ > RHO_SEMI_MAX ? 1.0 : (ρ > RHO_METAL_MAX ? 0.6 : 0.35)
	L = HSL(base).l
	α = (0.20 + 0.40*band_weight) * εn * (0.55 + 0.45*(1 - L))
	Colors.RGBA(tint.r, tint.g, tint.b, α)
end

"""
	get_material_color_makie(material_props; mu_scale=1.0, eps_scale=1.0)

Piecewise ρ→base color (metals→silver, semiconductors→amber, etc.) with
blue/purple magnetic overlay (μr) and teal/cyan permittivity overlay (εr).
`mu_scale` and `eps_scale` scale overlay strength (1.0 = default).
"""
function get_material_color_makie(material_props; mu_scale = 1.0, eps_scale = 1.0)
	ρ  = to_nominal(material_props.rho)
	εr = to_nominal(material_props.eps_r)
	μr = to_nominal(material_props.mu_r)

	base = _base_color_from_rho(ρ) |> c -> _ensure_min_lightness(c, 0.07)

	# Compose overlays
	mu  = _mu_overlay(base, μr);
	mu  = Colors.RGBA(mu.r, mu.g, mu.b, clamp(alpha(mu)*mu_scale, 0, 1))
	eps = _eps_overlay(base, εr, ρ);
	eps = Colors.RGBA(eps.r, eps.g, eps.b, clamp(alpha(eps)*eps_scale, 0, 1))

	out = _overlay(Colors.RGBA(base.r, base.g, base.b, 1.0), mu)
	out = _overlay(out, eps)
	return out
end

function show_material_scale(; size = (1000, 480), backend = nothing)
	if backend !== nothing
		_use_makie_backend(backend)
	end
	fig = Figure(size = size)

	# sampling density for smooth bars
	N = 1024

	# --- ρ colorbar (log scale by ticks/limits) -------------------------------
	ρmin_log, ρmax_log = log10(RHO_MIN), log10(RHO_MAX)
	# sample uniformly in log(ρ) so the bar matches your piecewise mapping
	cm_ρ = begin
		cols = Vector{RGBA}(undef, N)
		for i in 1:N
			t = (i - 1) / (N - 1)
			ρ = 10^(ρmin_log + t * (ρmax_log - ρmin_log))
			c = _base_color_from_rho(ρ)
			cols[i] = RGBA(c.r, c.g, c.b, 1.0)
		end
		cols
	end

	cb_ρ = Colorbar(fig[1, 1];
		colormap = cm_ρ,
		limits   = (ρmin_log, ρmax_log),   # we encode log(ρ) in limits/ticks
		vertical = false,
		label    = "Base color by resistivity ρ [Ω·m] (log scale)",
	)

	# label ticks at meaningful boundaries
	edges = [RHO_MIN, 1e-8, 1e-7, RHO_METAL_MAX, RHO_SEMIMETAL, RHO_SEMI_MAX,
		1e4, 1e6, RHO_LEAKY_MAX, RHO_MAX]
	cb_ρ.ticks = (log10.(edges), string.(edges))

	# --- μr overlay colorbar (blue→indigo on mid-gray) ------------------------
	μmin, μmax = 1.0, 300.0
	base_mid = RGB(0.5, 0.5, 0.5)
	cm_μ = begin
		cols = Vector{RGBA}(undef, N)
		for i in 1:N
			t = (i - 1) / (N - 1)
			μ = 10^(log10(μmin) + t * (log10(μmax) - log10(μmin)))
			o = _mu_overlay(base_mid, μ)
			out = _overlay(RGBA(base_mid.r, base_mid.g, base_mid.b, 1.0), o)
			cols[i] = out
		end
		cols
	end

	cb_μ = Colorbar(fig[2, 1];
		colormap = cm_μ,
		limits   = (μmin, μmax),
		vertical = false,
		label    = "Magnetic overlay μᵣ (blue→indigo)",
	)
	cb_μ.ticks = (
		[1, 2, 5, 10, 20, 50, 100, 200, 300],
		string.([1, 2, 5, 10, 20, 50, 100, 200, 300]),
	)

	# --- εr overlay colorbar (teal→cyan on dark base) -------------------------
	εmin, εmax = 1.0, 1000.0
	base_dark = RGB(0.10, 0.10, 0.10)
	cm_ε = begin
		cols = Vector{RGBA}(undef, N)
		for i in 1:N
			t = (i - 1) / (N - 1)
			ε = 10^(log10(εmin) + t * (log10(εmax) - log10(εmin)))
			o = _eps_overlay(base_dark, ε, RHO_MAX + 1)  # treat as strong insulator
			out = _overlay(RGBA(base_dark.r, base_dark.g, base_dark.b, 1.0), o)
			cols[i] = out
		end
		cols
	end

	cb_ε = Colorbar(fig[3, 1];
		colormap = cm_ε,
		limits   = (εmin, εmax),
		vertical = false,
		label    = "Permittivity overlay εᵣ (teal→cyan)",
	)
	cb_ε.ticks = ([1, 2, 5, 10, 20, 50, 100, 200, 500, 1000],
		string.([1, 2, 5, 10, 20, 50, 100, 200, 500, 1000]))

	display(fig)
	return fig
end


#################################
# Geometry helpers (polygons)   #
#################################
# polygons (Float32 points; filter non-finite)
function _annulus_poly(rin::Real, rex::Real, x0::Real, y0::Real; N::Int = 256)
	N ≥ 32 || throw(ArgumentError("N too small for a smooth annulus"))
	θo = range(0, _TAU; length = N);
	θi = reverse(θo)
	xo = x0 .+ rex .* cos.(θo);
	yo = y0 .+ rex .* sin.(θo)
	xi = x0 .+ rin .* cos.(θi);
	yi = y0 .+ rin .* sin.(θi)
	px = vcat(xo, xi, xo[1]);
	py = vcat(yo, yi, yo[1])
	pts = Makie.Point2f.(px, py)
	filter(p -> _valid_finite(p[1], p[2]), pts)
end

function _circle_poly(r::Real, x0::Real, y0::Real; N::Int = 128)
	θ = range(0, _TAU; length = N)
	x = x0 .+ r .* cos.(θ);
	y = y0 .+ r .* sin.(θ)
	pts = Makie.Point2f.(vcat(x, x[1]), vcat(y, y[1]))
	filter(p -> _valid_finite(p[1], p[2]), pts)
end

#############################
# Layer -> Makie primitives #
#############################
function _plot_layer_makie!(ax, layer, label::String;
	x0::Real = 0.0, y0::Real = 0.0, display_legend::Bool = true,
	legend_sink::Union{Nothing, Tuple} = nothing,
)

	if layer isa WireArray
		rwire = to_nominal(layer.radius_wire)
		nW = layer.num_wires
		lay_r = nW == 1 ? 0.0 : to_nominal(layer.radius_in)
		color = get_material_color_makie(layer.material_props)

		coords = calc_wirearray_coords(nW, rwire, to_nominal(lay_r), C = (x0, y0))

		plots = Any[]
		handle = nothing
		for (i, (x, y)) in enumerate(coords)
			poly = Makie.poly!(ax, _circle_poly(rwire, x, y);
				color = color,
				strokecolor = :black,
				strokewidth = 0.5,
				label = (i==1 && display_legend) ? label : "")
			push!(plots, poly)
			if i==1 && display_legend
				handle = poly
			end
		end

		# Legend sink: push one entry per layer. If sink has 3rd slot, store the group.
		if legend_sink !== nothing && display_legend && handle !== nothing
			push!(legend_sink[1], handle)
			push!(legend_sink[2], label)
			if length(legend_sink) >= 3
				push!(legend_sink[3], plots)   # group = all wires in this layer
			end
			if length(legend_sink) >= 4
				push!(legend_sink[4], to_nominal(layer.material_props.rho))  # <-- rho key
			end
		end
		return plots
	end

	if layer isa Strip || layer isa Tubular || layer isa Semicon || layer isa Insulator
		rin = to_nominal(layer.radius_in)
		rex = to_nominal(layer.radius_ext)
		color = get_material_color_makie(layer.material_props)

		poly = Makie.poly!(ax, _annulus_poly(rin, rex, x0, y0);
			color = color,
			label = display_legend ? label : "")

		if legend_sink !== nothing && display_legend
			push!(legend_sink[1], poly)
			push!(legend_sink[2], label)
			if length(legend_sink) >= 3
				push!(legend_sink[3], [poly])
			end
			if length(legend_sink) >= 4
				push!(legend_sink[4], NaN)      # not a wirearray
			end
		end
		return (poly,)
	end

	if layer isa ConductorGroup
		plots = Any[]
		first_label = true
		for sub in layer.layers
			append!(
				plots,
				_plot_layer_makie!(ax, sub,
					first_label ? lowercase(string(nameof(typeof(layer)))) : "";
					x0 = x0, y0 = y0, display_legend = display_legend,
					legend_sink = legend_sink),
			)
			first_label = false
		end
		return plots
	end

	@warn "Unknown layer type $(typeof(layer)); skipping"
	return ()
end

###############################################
# CableDesign cross-section (Makie version)   #
###############################################
function preview(design::CableDesign;
	x_offset::Real = 0.0,
	y_offset::Real = 0.0,
	backend::Union{Nothing, Symbol} = nothing,
	size::Tuple{Int, Int} = (800, 600),
	display_plot::Bool = true,
	display_legend::Bool = true,
	display_id::Bool = false,
	axis = nothing,
	legend_sink::Union{Nothing, Tuple{Vector{Any}, Vector{String}}} = nothing,
	display_colorbars::Bool = true,
	side_frac::Real = 0.26,     # ~26% right column
)
	_use_makie_backend(backend)
	backgroundcolor = backend === :cairo ? :white : :gray90
	set_theme!(backgroundcolor = backgroundcolor)

	fig = isnothing(axis) ? Makie.Figure(size = size) : nothing

	# ── 2 columns: left = main axis, right = container (button + legend + bars)
	local ax
	local side
	if isnothing(axis)
		ax   = Makie.Axis(fig[1, 1], aspect = Makie.DataAspect())
		side = fig[1, 2] = Makie.GridLayout()          # single container on the right
		Makie.colsize!(fig.layout, 1, Makie.Relative(1 - side_frac))
		Makie.colsize!(fig.layout, 2, Makie.Relative(side_frac))
		Makie.rowsize!(fig.layout, 1, Makie.Relative(1.0))

		ax.xlabel = "y [m]"
		ax.ylabel = "z [m]"
		ax.title  = display_id ? "Cable design preview: $(design.cable_id)" : "Cable design preview"

		avail_w = size[1] * (1 - side_frac)
		avail_h = size[2]
		s = floor(Int, min(avail_w, avail_h))
		Makie.colsize!(fig.layout, 1, Makie.Fixed(s))
		Makie.rowsize!(fig.layout, 1, Makie.Fixed(s))
	else
		ax = axis
		side = nothing
	end

	# legend sink
	local own_legend = false
	local sink = legend_sink
	if sink === nothing && display_legend
		sink = (Any[], String[], Vector{Vector{Any}}(), Float64[])   # handles, labels, groups, rho_keys
		own_legend = true
	end

	let r = try
			to_nominal(design.components[end].insulator_group.radius_ext)
		catch
			NaN
		end
		if isfinite(r) && r > 0
			Makie.poly!(ax, _circle_poly(r, x_offset, y_offset);
				color = :white,
				strokecolor = :transparent)
		end
	end

	# draw layers
	for comp in design.components
		for layer in comp.conductor_group.layers
			_plot_layer_makie!(ax, layer, lowercase(string(nameof(typeof(layer))));
				x0 = x_offset, y0 = y_offset,
				display_legend = display_legend, legend_sink = sink)
		end
		for layer in comp.insulator_group.layers
			_plot_layer_makie!(ax, layer, lowercase(string(nameof(typeof(layer))));
				x0 = x_offset, y0 = y_offset,
				display_legend = display_legend, legend_sink = sink)
		end
	end


	# Right column: stack button, legend, colorbars
	if isnothing(axis)
		row_idx = 1

		if _is_interactive_backend()
			# Reset button at top
			_add_reset_button!(side[row_idx, 1], ax, fig)
			row_idx += 1
			_add_save_svg_button!(
				side[row_idx, 1], design;
				display_id = display_id,
				display_legend = display_legend,
				display_colorbars = display_colorbars,
				side_frac = side_frac,
				size = size,
				base = design.cable_id,
			)
			row_idx += 1
		end

		# Legend (optional)
		if display_legend && own_legend
			handles = sink[1]
			labels  = sink[2]
			groups  = length(sink) >= 3 ? sink[3] : [[h] for h in handles]
			rhos    = length(sink) >= 4 ? sink[4] : fill(NaN, length(handles))

			# Merge consecutive wirearray entries with equal rho
			merged_handles = Any[]
			merged_labels  = String[]
			merged_groups  = Vector{Any}[]  # Vector{Vector{Any}}

			i = 1
			while i <= length(handles)
				h = handles[i];
				l = labels[i];
				g = groups[i];
				ρ = rhos[i]
				if l == "wirearray" && isfinite(ρ)
					j = i + 1
					merged_g = Vector{Any}(g)
					while j <= length(handles) &&
							  labels[j] == "wirearray" &&
							  isfinite(rhos[j]) &&
							  isapprox(ρ, rhos[j]; rtol = 1e-6, atol = 0.0)
						append!(merged_g, groups[j])
						j += 1
					end
					push!(merged_handles, h)        # keep first handle for the group
					push!(merged_labels, l)         # keep label "wirearray"
					push!(merged_groups, merged_g)  # all wires across merged layers
					i = j
				else
					push!(merged_handles, h)
					push!(merged_labels, l)
					push!(merged_groups, g)
					i += 1
				end
			end

			# Build legend with merged entries
			leg = Makie.Legend(
				side[row_idx, 1],
				merged_handles,
				merged_labels,
				padding = (6, 6, 6, 6),
				halign = :center,
				valign = :top,
			)

			# Clicking one entry toggles its whole merged group
			for (h, grp) in zip(merged_handles, merged_groups)
				Makie.on(h.visible) do v
					for p in grp
						p === h && continue
						p.visible[] = v
					end
				end
			end

			row_idx += 1
		end

		# Colorbars (optional)
		if display_colorbars
			# read actual ranges (helper you already have)
			ρmin, ρmax, μmin, μmax, εmin, εmax = _collect_material_ranges(design)

			cbgrid = side[row_idx, 1] = Makie.GridLayout()
			_build_colorbars!(cbgrid; ρmin, ρmax, μmin, μmax, εmin, εmax)

		end
	end

	if display_plot && isnothing(axis) && !is_in_testset()
		resize_to_layout!(fig)
		if nameof(Makie.current_backend()) in (:GLMakie,)
			scr = GLMakie.Screen(; title = "CableDesign preview: $(design.cable_id)")
			display(scr, fig)
		else
			if is_headless()
				DisplayAs.Text(DisplayAs.PNG(fig))
			else
				display(fig)
			end
		end

	end
	return fig, ax
end

function preview(system::LineCableSystem;
	earth_model = nothing,
	zoom_factor = nothing,
	backend::Union{Nothing, Symbol} = nothing,
	size::Tuple{Int, Int} = (800, 600),
	display_plot::Bool = true,
	display_id::Bool = false,
	axis = nothing,
	display_legend::Bool = true,
	display_colorbars::Bool = true,
	side_frac::Real = 0.26,
)
	_use_makie_backend(backend)
	backgroundcolor = backend === :cairo ? :white : :gray90
	set_theme!(backgroundcolor = backgroundcolor)

	fig = isnothing(axis) ? Makie.Figure(size = size) : nothing

	# Layout: left = main axis, right = legend/colorbars (only if we own the axis)
	local ax
	local side
	if isnothing(axis)
		ax   = Makie.Axis(fig[1, 1], aspect = Makie.DataAspect())
		side = fig[1, 2] = Makie.GridLayout()
		Makie.colsize!(fig.layout, 1, Makie.Relative(1 - side_frac))
		Makie.colsize!(fig.layout, 2, Makie.Relative(side_frac))
		Makie.rowsize!(fig.layout, 1, Makie.Relative(1.0))

		ax.xlabel = "y [m]"
		ax.ylabel = "z [m]"
		ax.title  = display_id ? "Cable system cross-section: $(system.system_id)" :
		"Cable system cross-section"

		# Make the plotting canvas square if we own the axis
		avail_w = size[1] * (1 - side_frac)
		avail_h = size[2]
		s = floor(Int, min(avail_w, avail_h))
		Makie.colsize!(fig.layout, 1, Makie.Fixed(s))
		Makie.rowsize!(fig.layout, 1, Makie.Fixed(s))
	else
		ax = axis
		side = nothing
	end

	# Air/earth interface
	Makie.hlines!(ax, [0.0], color = :black, linewidth = 1.5)

	# Compute barycentered, square view from cable bounding box
	x0s = Float64[to_nominal(c.horz) for c in system.cables]
	y0s = Float64[to_nominal(c.vert) for c in system.cables]
	radii = Float64[
		(comp = last(c.design_data.components);
			max(to_nominal(comp.conductor_group.radius_ext),
				to_nominal(comp.insulator_group.radius_ext)))
		for c in system.cables
	]
	cx = isempty(x0s) ? 0.0 : mean(x0s)
	cy = isempty(y0s) ? -1.0 : mean(y0s)
	x_min = isempty(x0s) ? -1.0 : minimum(x0s .- radii)
	x_max = isempty(x0s) ? 1.0 : maximum(x0s .+ radii)
	y_min = isempty(y0s) ? -1.0 : minimum(y0s .- radii)
	y_max = isempty(y0s) ? 1.0 : maximum(y0s .+ radii)
	half_x = max(x_max - cx, cx - x_min)
	half_y = max(y_max - cy, cy - y_min)
	base_halfspan = max(half_x, half_y)
	base_halfspan = base_halfspan > 0 ? base_halfspan : 1.0
	pad_factor = 1.05
	zf = zoom_factor === nothing ? 1.5 : Float64(zoom_factor)
	halfspan = base_halfspan * pad_factor * zf
	x_limits = (cx - halfspan, cx + halfspan)
	y_limits = (cy - halfspan, cy + halfspan)

	# Expanded fill extents beyond visible region
	x_fill = (x_limits[1] - 0.5*halfspan, x_limits[2] + 0.5*halfspan)
	y_fill_min = y_limits[1] - 0.5*halfspan - 2.0

	# Build legend entries only for earth layers
	earth_handles = Any[]
	earth_labels  = String[]

	# Plot earth layers if provided and horizontal (vertical_layers == false)
	if !isnothing(earth_model) && getfield(earth_model, :vertical_layers) == false
		cumulative_depth = 0.0
		# Skip air layer (index 1). Iterate finite-thickness layers; stop on Inf.
		for (i, layer) in enumerate(earth_model.layers[2:end])
			# Compute color using the same material convention
			# Adapt EarthLayer base_* fields to material_props (rho, eps_r, mu_r)
			mat = (;
				rho = layer.base_rho_g,
				eps_r = layer.base_epsr_g,
				mu_r = layer.base_mur_g,
			)
			fillcol = get_material_color_makie(mat)
			# Slight transparency for fill
			fillcol = Makie.RGBA(fillcol.r, fillcol.g, fillcol.b, 0.25)

			if isinf(layer.t)
				# Semi-infinite: fill from current depth down to far below visible
				ytop = cumulative_depth  # bottom of previous finite layer
				ybot = y_fill_min        # push well below visible range
			else
				# Finite thickness: update cumulative and compute band extents
				t = to_nominal(layer.t)
				ytop = cumulative_depth
				ybot = cumulative_depth - t
				cumulative_depth = ybot
			end

			xs = (x_fill[1], x_fill[2], x_fill[2], x_fill[1])
			ys = (ytop, ytop, ybot, ybot)

			# Filled band and a colored interface line
			poly = Makie.poly!(
				ax,
				collect(Makie.Point2f.(xs, ys)),  # ensure a Vector, not a Tuple
				color = fillcol,
				strokecolor = :transparent,
				label = "",
			)
			Makie.hlines!(ax, [ybot], color = fillcol, linewidth = 1.0)

			if display_legend && isnothing(axis)
				push!(earth_handles, poly)
				push!(earth_labels, "Earth layer $(i)")
			end
		end
	end

	# Draw each cable onto the same axis (no legend for cable components)
	for cable in system.cables
		x0 = to_nominal(cable.horz)
		y0 = to_nominal(cable.vert)
		# Reuse the design-level preview on our axis
		preview(
			cable.design_data;
			x_offset = x0,
			y_offset = y0,
			backend = backend,
			size = size,
			display_plot = false,
			display_legend = false,
			axis = ax,
		)
	end

	# Set limits only when we own the axis (square extents)
	if isnothing(axis)
		Makie.xlims!(ax, x_limits...)
		Makie.ylims!(ax, y_limits...)
	end

	# Right-column: buttons, earth-only legend and optional colorbars
	if isnothing(axis)
		row_idx = 1
		if _is_interactive_backend()
			_add_reset_button!(side[row_idx, 1], ax, fig)
			row_idx += 1
			_add_save_svg_button!(
				side[row_idx, 1], system;
				earth_model = earth_model,
				zoom_factor = zoom_factor,
				display_legend = display_legend,
				display_colorbars = display_colorbars,
				side_frac = side_frac,
				display_id = display_id,
				size = size,
				base = system.system_id,
			)
			row_idx += 1
		end

		if display_legend && !isempty(earth_handles)
			Makie.Legend(
				side[row_idx, 1],
				earth_handles,
				earth_labels,
				padding = (6, 6, 6, 6),
				halign = :center,
				valign = :top,
			)
			row_idx += 1
		end

		if display_colorbars
			ρmin, ρmax, μmin, μmax, εmin, εmax = _collect_earth_ranges(earth_model)
			cbgrid = side[row_idx, 1] = Makie.GridLayout()
			_build_colorbars!(
				cbgrid;
				ρmin,
				ρmax,
				μmin,
				μmax,
				εmin,
				εmax,
				alpha_global = 0.25,
				showμminmax = false,
				showεminmax = false,
			)
		end
	end


	if display_plot && isnothing(axis) && !is_in_testset()
		resize_to_layout!(fig)
		if nameof(Makie.current_backend()) in (:GLMakie,)
			scr = GLMakie.Screen(;
				title = "LineCableSystem preview: $(system.system_id)",
			)
			display(scr, fig)
		else
			if is_headless()
				DisplayAs.Text(DisplayAs.PNG(fig))
			else
				display(fig)
			end
		end

	end


	return fig, ax
end

# Add a save-to-SVG button to a grid cell, re-rendering with Cairo backend
function _add_save_svg_button!(parent_cell, system;
	earth_model = nothing,
	zoom_factor = nothing,
	display_id::Bool,
	display_legend::Bool,
	display_colorbars::Bool,
	side_frac::Real,
	size::Tuple{Int, Int},
	base::String = "preview",
)
	btn = Makie.Button(
		parent_cell, label = "Save SVG", halign = :center,
		valign = :top, width = Makie.Relative(1.0),
	)
	Makie.on(btn.clicks) do _
		@async begin
			orig_label = btn.label[]
			btn.label[] = "Saving…"
			orig_color = hasproperty(btn, :buttoncolor) ? btn.buttoncolor[] : nothing
			try
				_use_makie_backend(:cairo)
				if system isa CableDesign
					fig, _ = preview(
						system;
						display_legend = display_legend,
						display_colorbars = display_colorbars,
						display_plot = false,
						size = size,
						display_id = display_id,
						backend = :cairo,
						side_frac = side_frac,
					)
				elseif system isa LineCableSystem
					fig, _ = preview(
						system;
						earth_model = earth_model,
						zoom_factor = zoom_factor,
						display_id = display_id,
						display_legend = display_legend,
						display_colorbars = display_colorbars,
						display_plot = false,
						size = size,
						backend = :cairo,
						side_frac = side_frac,
					)
				end
				ts = Dates.format(Dates.now(), "yyyymmdd-HHMMSS")
				file = joinpath(@__DIR__, "$(base)_$ts.svg")
				CairoMakie.save(file, fig)
				btn.label[] = "Saved ✓"
				hasproperty(btn, :buttoncolor) &&
					(btn.buttoncolor[] = Makie.RGBA(0.15, 0.65, 0.25, 1.0))
				sleep(1.2)
			catch e
				@error "Save failed: $(typeof(e)): $(e)"
				btn.label[] = "Failed ✗"
				hasproperty(btn, :buttoncolor) &&
					(btn.buttoncolor[] = Makie.RGBA(0.80, 0.20, 0.20, 1.0))
				sleep(1.6)
			finally
				if orig_color !== nothing
					btn.buttoncolor[] = orig_color
				end
				btn.label[] = orig_label
			end
		end
	end
	return btn
end

# Add a reset button to a grid cell, wired to reset axis limits
function _add_reset_button!(parent_cell, ax, fig)
	btn = Makie.Button(
		parent_cell,
		label = "↻ Reset view",
		halign = :center,
		valign = :top,
		width = Makie.Relative(1.0),
	)
	Makie.on(btn.clicks) do _
		reset_limits!(ax)
		resize_to_layout!(fig)

	end
	return btn
end

function _build_colorbars!(cbgrid::Makie.GridLayout;
	ρmin::Real, ρmax::Real, μmin::Real, μmax::Real, εmin::Real, εmax::Real,
	cb_bar_h::Int = 12, alpha_global::Real = 1.0, showρminmax::Bool = true,
	showμminmax::Bool = true, showεminmax::Bool = true,
)
	Makie.colsize!(cbgrid, 1, Makie.Fixed(2))

	function _nice(x)
		axv = abs(x)
		axv == 0 && return "0"
		(axv ≥ 1e-3 && axv < 1e4) ? @sprintf("%.4g", x) : @sprintf("%.1e", x)
	end

	N = 256
	idx=1

	# ρ bar sampled in log-space between actual min/max
	if showρminmax
		cm_ρ = let cols = Vector{Makie.RGBA}(undef, N)
			lo, hi = log10(ρmin), log10(ρmax)
			for i in 1:N
				t = (i-1)/(N-1)
				ρ = 10^(lo + t*(hi - lo))
				c = _base_color_from_rho(ρ)
				cols[i] = Makie.RGBA(c.r, c.g, c.b, 1*alpha_global)
			end;
			cols
		end
		Makie.Label(cbgrid[idx, 1], "ρ"; halign = :left)
		Makie.Colorbar(cbgrid[idx, 2]; colormap = cm_ρ, limits = (0.0, 1.0),
			vertical = false,
			ticks = ([0.0, 1.0], [_nice(ρmin), _nice(ρmax)]),
			labelvisible = false, height = cb_bar_h)
		idx += 1
	end

	# μr bar overlay on mid-gray
	if showμminmax
		base_mid = Makie.RGB(0.5, 0.5, 0.5)
		cm_μ = let cols = Vector{Makie.RGBA}(undef, N)
			lo, hi = log10(μmin), log10(μmax)
			for i in 1:N
				t = (i-1)/(N-1)
				μ = 10^(lo + t*(hi - lo))
				o = _mu_overlay(base_mid, μ)
				cols[i] = _overlay(
					Makie.RGBA(base_mid.r, base_mid.g, base_mid.b, 1),
					o*alpha_global,
				)
			end;
			cols
		end
		Makie.Label(cbgrid[idx, 1], "μᵣ"; halign = :left)
		Makie.Colorbar(cbgrid[idx, 2]; colormap = cm_μ, limits = (0.0, 1.0),
			vertical = false,
			ticks = ([0.0, 1.0], [_nice(μmin), _nice(μmax)]),
			labelvisible = false, height = cb_bar_h)
		idx += 1
	end

	if showεminmax
		# εr bar overlay on dark
		base_dark = Makie.RGB(0.10, 0.10, 0.10)
		cm_ε = let cols = Vector{Makie.RGBA}(undef, N)
			lo, hi = log10(εmin), log10(εmax)
			for i in 1:N
				t = (i-1)/(N-1)
				ε = 10^(lo + t*(hi - lo))
				o = _eps_overlay(base_dark, ε, RHO_MAX + 1)
				cols[i] = _overlay(
					Makie.RGBA(base_dark.r, base_dark.g, base_dark.b, 1),
					o*alpha_global,
				)
			end;
			cols
		end
		Makie.Label(cbgrid[idx, 1], "εᵣ"; halign = :left)
		Makie.Colorbar(cbgrid[idx, 2]; colormap = cm_ε, limits = (0.0, 1.0),
			vertical = false,
			ticks = ([0.0, 1.0], [_nice(εmin), _nice(εmax)]),
			labelvisible = false, height = cb_bar_h)
	end

	return cbgrid
end

# collect actual property ranges from the design (finite values only)
function _collect_material_ranges(design::CableDesign)
	rhos  = Float64[]
	mus   = Float64[]
	epses = Float64[]

	_push_props!(layer) = begin
		ρ  = try
			to_nominal(layer.material_props.rho)
		catch
			NaN
		end
		μr = try
			to_nominal(layer.material_props.mu_r)
		catch
			NaN
		end
		εr = try
			to_nominal(layer.material_props.eps_r)
		catch
			NaN
		end
		isfinite(ρ) && push!(rhos, ρ)
		isfinite(μr) && push!(mus, μr)
		isfinite(εr) && push!(epses, εr)
		nothing
	end

	for comp in design.components
		for L in comp.conductor_group.layers
			if L isa ConductorGroup
				for s in L.layers
					_push_props!(s);
				end
			else
				_push_props!(L)
			end
		end
		for L in comp.insulator_group.layers
			_push_props!(L)
		end
	end

	ρmin = isempty(rhos) ? RHO_MIN : minimum(rhos)
	ρmax = isempty(rhos) ? RHO_MAX : maximum(rhos)
	μmin = isempty(mus) ? 1.0 : max(1.0, minimum(mus))
	μmax = isempty(mus) ? 300.0 : maximum(mus)
	εmin = isempty(epses) ? 1.0 : max(1.0, minimum(epses))
	εmax = isempty(epses) ? 1000.0 : maximum(epses)
	ρmax == ρmin && (ρmax = nextfloat(ρmax))
	μmax == μmin && (μmax += 1e-6)
	εmax == εmin && (εmax += 1e-6)

	return ρmin, ρmax, μmin, μmax, εmin, εmax
end

function _collect_earth_ranges(earth_model)
	rhos = Float64[];
	mus = Float64[];
	epses = Float64[]
	if !isnothing(earth_model)
		for layer in earth_model.layers[2:end]
			ρ = try
				to_nominal(layer.base_rho_g)
			catch
				NaN
			end
			μr = try
				to_nominal(layer.base_mur_g)
			catch
				NaN
			end
			εr = try
				to_nominal(layer.base_epsr_g)
			catch
				NaN
			end
			isfinite(ρ) && push!(rhos, ρ)
			isfinite(μr) && push!(mus, μr)
			isfinite(εr) && push!(epses, εr)
		end
	end
	ρmin = isempty(rhos) ? RHO_MIN : minimum(rhos)
	ρmax = isempty(rhos) ? RHO_MAX : maximum(rhos)
	μmin = isempty(mus) ? 1.0 : max(1.0, minimum(mus))
	μmax = isempty(mus) ? 300.0 : maximum(mus)
	εmin = isempty(epses) ? 1.0 : max(1.0, minimum(epses))
	εmax = isempty(epses) ? 1000.0 : maximum(epses)
	return ρmin, ρmax, μmin, μmax, εmin, εmax
end
