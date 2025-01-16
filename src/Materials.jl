"""
init_materials_db: Initialize a materials database from a file or default values.

# Arguments
- `file_name`: The name of the CSV file to load materials from (String). Defaults to "materials.csv".

# Returns
- A dictionary where each key is a material name (String), and its value is a dictionary containing properties:
  - `:rho` (Resistivity [Ω·m]),
  - `:eps_r` (Relative permittivity),
  - `:mu_r` (Relative permeability),
  - `:T0` (Reference temperature [°C]),
  - `:alpha` (Temperature coefficient [1/°C]).

# Examples
```julia
# Example with a non-existent file (default materials will be initialized):
materials = init_materials_db("nonexistent.csv")
println(materials["air"]) # Output: Dict(:rho => Inf, :eps_r => 1.0, :mu_r => 1.0, :T0 => 20.0, :alpha => 0)

# Example with a valid CSV file:
# Assuming the file "materials.csv" contains:
# name,rho,eps_r,mu_r,T0,alpha
# silver,1.59e-8,1.0,1.0,20.0,0.0038
materials = init_materials_db("materials.csv")
println(materials["silver"]) # Output: Dict(:rho => 1.59e-8, :eps_r => 1.0, :mu_r => 1.0, :T0 => 20.0, :alpha => 0.0038)
```

# References
- None.
"""
function init_materials_db(file_name::String = "materials.csv")
	db = Dict{String, Dict{Symbol, Any}}()
	if isfile(file_name)
		println("Loading materials database from $file_name...")
		# Load from CSV into a temporary DataFrame
		df = DataFrame(CSV.File(file_name))
		for row in eachrow(df)
			db[row[:name]] = Dict(
				:rho => row[:rho],
				:eps_r => row[:eps_r],
				:mu_r => row[:mu_r],
				:T0 => row[:T0],
				:alpha => row[:alpha],
			)
		end
	else
		println("No $file_name found. Initializing default materials database...")

		# Initialize with default values
		db["air"] = Dict(:rho => Inf, :eps_r => 1.0, :mu_r => 1.0, :T0 => 20.0, :alpha => 0)
		db["pec"] =
			Dict(:rho => eps(), :eps_r => 1.0, :mu_r => 1.0, :T0 => 20.0, :alpha => 0)
		db["copper"] = Dict(
			:rho => 1.7241e-8,
			:eps_r => 1.0,
			:mu_r => 0.999994,
			:T0 => 20.0,
			:alpha => 0.00393,
		)
		db["aluminum"] = Dict(
			:rho => 2.8264e-8,
			:eps_r => 1.0,
			:mu_r => 1.000022,
			:T0 => 20.0,
			:alpha => 0.00429,
		)
		db["xlpe"] =
			Dict(:rho => 1.97e14, :eps_r => 2.3, :mu_r => 1.0, :T0 => 20.0, :alpha => 0.0)
		db["semicon1"] =
			Dict(:rho => 1000.0, :eps_r => 1000.0, :mu_r => 1.0, :T0 => 20.0, :alpha => 0.0)
		db["semicon2"] =
			Dict(:rho => 500.0, :eps_r => 1000.0, :mu_r => 1.0, :T0 => 20.0, :alpha => 0.0)
		db["polyacrilate"] =
			Dict(:rho => 5.3e3, :eps_r => 32.3, :mu_r => 1.0, :T0 => 20.0, :alpha => 0.0) # water-blocking tape
	end
	return db
end

"""
get_material: Retrieve material data from a database.

# Arguments
- `db`: A dictionary where each key is a material name (String) and its value is another dictionary containing properties of the material.
- `name`: The name of the material to retrieve (String).

# Returns
- A dictionary containing the properties of the material if the material name exists in `db`, otherwise `nothing`.

# Examples
```julia
db = Dict(
	"Copper" => Dict(:rho => 1.7241e-8, :eps_r => 1),
	"Aluminum" => Dict(:rho => 2.8264e-8, :eps_r => 1)
)

material = get_material(db, "Copper")
println(material) # Output: Dict(:rho => 1.7241e-8, :eps_r => 1)

missing_material = get_material(db, "Gold")
println(missing_material) # Output: nothing
```

# References
- None.
"""
function get_material(db::Dict{String, Dict{Symbol, Any}}, name::String)
	return get(db, name, nothing)
end

"""
save_materials_db: Save a materials database to a CSV file.

# Arguments
- `db`: A dictionary where each key is a material name (String) and its value is a dictionary containing properties:
  - `:rho` (Resistivity [Ω·m]),
  - `:eps_r` (Relative permittivity),
  - `:mu_r` (Relative permeability),
  - `:T0` (Reference temperature [°C]),
  - `:alpha` (Temperature coefficient [1/°C]).
- `file_name`: The name of the CSV file to save the materials database to (String). Defaults to "materials.csv".

# Returns
- None. The function saves the data to the specified file.

# Examples
```julia
# Example of saving a materials database:
db = Dict(
	"copper" => Dict(:rho => 1.7241e-8, :eps_r => 1.0, :mu_r => 0.999994, :T0 => 20.0, :alpha => 0.00393),
	"aluminum" => Dict(:rho => 2.8264e-8, :eps_r => 1.0, :mu_r => 1.000022, :T0 => 20.0, :alpha => 0.00429)
)
save_materials_db(db, "output_materials.csv")

# Check the file content:
println(read("output_materials.csv", String))
```

# References
- None.
"""
function save_materials_db(
	db::Dict{String, Dict{Symbol, Any}},
	file_name::String = "materials.csv",
)
	rows = [merge(Dict(:name => name), props) for (name, props) in db]
	df = DataFrame(rows)
	CSV.write(file_name, df)
end

"""
display_materials_db: Convert a materials database into a DataFrame for display.

# Arguments
- `materials_db`: A dictionary where each key is a material name (String) and its value is a dictionary containing properties:
  - `:rho` (Resistivity [Ω·m]),
  - `:eps_r` (Relative permittivity),
  - `:mu_r` (Relative permeability),
  - `:T0` (Reference temperature [°C]),
  - `:alpha` (Temperature coefficient [1/°C]).

# Returns
- A DataFrame containing the materials database, with columns:
  - `:name`: Material name (String).
  - `:rho`: Resistivity [Ω·m].
  - `:eps_r`: Relative permittivity.
  - `:mu_r`: Relative permeability.
  - `:T0`: Reference temperature [°C].
  - `:alpha`: Temperature coefficient [1/°C].

# Examples
```julia
materials_db = Dict(
	"copper" => Dict(:rho => 1.7241e-8, :eps_r => 1.0, :mu_r => 0.999994, :T0 => 20.0, :alpha => 0.00393),
	"aluminum" => Dict(:rho => 2.8264e-8, :eps_r => 1.0, :mu_r => 1.000022, :T0 => 20.0, :alpha => 0.00429)
)

df = display_materials_db(materials_db)
println(df)
```

# References
- None.
"""
function display_materials_db(materials_db::Dict{String, Dict{Symbol, Any}})
	# Flatten the nested dictionary into a vector of tuples
	rows = [merge(Dict(:name => name), props) for (name, props) in materials_db]
	df = DataFrame(rows)
	return select(df, :name, :rho, :eps_r, :mu_r, :T0, :alpha)
end

"""
get_material_color: Generate a representative color for a material based on its physical properties.

# Arguments
- `material_props`: A dictionary containing the material properties:
  - `:rho`: Electrical resistivity [Ω·m].
  - `:eps_r`: Relative permittivity (dimensionless).
  - `:mu_r`: Relative permeability (dimensionless).
- `rho_weight`: Weight assigned to the contribution of resistivity in the color blending (default: 0.8).
- `epsr_weight`: Weight assigned to the contribution of relative permittivity in the color blending (default: 0.1).
- `mur_weight`: Weight assigned to the contribution of relative permeability in the color blending (default: 0.1).

# Returns
- A `Colors.RGBA` object representing the blended color based on the material's properties.
  - Bright metallic hues represent conductors.
  - Reddish and orange gradients represent semiconductors.
  - Greenish-brown to black gradients represent insulators.
  - Amber and purple hues adjust based on permittivity and permeability.

# Examples
```julia
material_props = Dict(:rho => 1.7e-8, :eps_r => 4.5, :mu_r => 1.2)
color = get_material_color(material_props)
println(color)  # Output: Colors.RGBA(...)

material_props_insulator = Dict(:rho => 1e6, :eps_r => 2.0, :mu_r => 1.0)
color = get_material_color(material_props_insulator, rho_weight=0.5, epsr_weight=0.3, mur_weight=0.2)
println(color)  # Output: Colors.RGBA(...)
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
	rho = to_nominal(material_props[:rho])
	epsr_r = to_nominal(material_props[:eps_r])
	mu_r = to_nominal(material_props[:mu_r])

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
overlay_colors: Blend two RGBA colors using alpha compositing.

# Arguments
- `color1`: The first `Colors.RGBA` color object.
- `color2`: The second `Colors.RGBA` color object.

# Returns
- A `Colors.RGBA` object representing the blended color. The blending is performed based on alpha compositing, where the second color is layered over the first.
  - The resulting color channels (`r`, `g`, `b`) are weighted by their alpha values.
  - The resulting alpha channel represents the combined opacity.

# Examples
```julia
color1 = RGBA(1.0, 0.0, 0.0, 0.5)  # Semi-transparent red
color2 = RGBA(0.0, 0.0, 1.0, 0.7)  # Semi-transparent blue
blended_color = overlay_colors(color1, color2)
println(blended_color)  # Output: Colors.RGBA(...)

color1 = RGBA(0.5, 0.5, 0.5, 1.0)  # Solid gray
color2 = RGBA(0.0, 1.0, 0.0, 0.3)  # Semi-transparent green
blended_color = overlay_colors(color1, color2)
println(blended_color)  # Output: Colors.RGBA(...)
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
visualize_gradient: Visualize a color gradient for debugging or analysis.

# Arguments
- `gradient`: A color gradient object that maps values in [0, 1] to colors.
- `n_steps`: The number of discrete steps to sample from the gradient (default: 100).
- `title`: The title of the plot (default: "Color gradient").

# Returns
- A plot displaying the gradient as a series of colored bars. The x-axis represents the gradient progression, and each bar corresponds to a sampled color.

# Examples
```julia
using Colors

# Define a gradient from blue to red
gradient = cgrad([:blue, :red])

# Visualize the gradient with 50 steps
visualize_gradient(gradient, 50; title="Blue to Red Gradient")

# Define a custom gradient
custom_gradient = cgrad([:green, :yellow, :purple])

# Visualize the custom gradient
visualize_gradient(custom_gradient; title="Custom Gradient")
```

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
overlay_multiple_colors: Blend multiple RGBA colors using sequential alpha compositing.

# Arguments
- `colors`: A vector of `Colors.RGBA` objects to be blended.
  - The colors are composited in sequence, starting with the first color in the vector.

# Returns
- A `Colors.RGBA` object representing the final blended color after compositing all input colors.

# Examples
```julia
using Colors

color1 = RGBA(1.0, 0.0, 0.0, 0.5)  # Semi-transparent red
color2 = RGBA(0.0, 1.0, 0.0, 0.5)  # Semi-transparent green
color3 = RGBA(0.0, 0.0, 1.0, 0.5)  # Semi-transparent blue

blended_color = overlay_multiple_colors([color1, color2, color3])
println(blended_color)  # Output: Colors.RGBA(...)

# Example with a single color
blended_color = overlay_multiple_colors([RGBA(0.5, 0.5, 0.5, 1.0)])
println(blended_color)  # Output: RGBA(0.5, 0.5, 0.5, 1.0)
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

