"""
Represents the fundamental physical properties of a material.

# Fields
- `rho`: Electrical resistivity of the material \\[Ω·m\\].
- `eps_r`: Relative permittivity of the material (dimensionless).
- `mu_r`: Relative permeability of the material (dimensionless).
- `T0`: Reference temperature at which properties are evaluated \\[°C\\].
- `alpha`: Temperature coefficient of resistivity \\[1/°C\\].
"""
struct Material
	rho::Number      # Resistivity \\[Ω·m\\]
	eps_r::Number    # Relative permittivity
	mu_r::Number     # Relative permeability
	T0::Number       # Reference temperature \\[°C\\]
	alpha::Number    # Temperature coefficient \\[1/°C\\]
end

"""
Stores a collection of materials and their corresponding properties.

# Constructor

- Initializes a `MaterialsLibrary` object with materials loaded from a CSV file or a default database.

# Arguments
- `file_name`: Name of the CSV file containing material data (default: "materials_library.csv").

# Returns
- An instance of `MaterialsLibrary` containing material data either loaded from the specified file or initialized with default materials.

# Fields
- `materials`: A dictionary where keys are material names (String) and values are `Material` objects.

# Dependencies
- `_load_from_csv!`: Loads material data from a CSV file into the library.
- `_add_default_materials!`: Adds default material data to the library.

# Examples
```julia
library = MaterialsLibrary("custom_materials_library.csv")
println(length(library.materials)) # Outputs the number of materials loaded

library = MaterialsLibrary()
println(length(library.materials)) # Outputs the number of default materials initialized
```

"""
mutable struct MaterialsLibrary
	materials::Dict{String, Material}  # Key: Material name, Value: Material object
end

function MaterialsLibrary(; file_name::String = "materials_library.csv")::MaterialsLibrary
	library = MaterialsLibrary(Dict{String, Material}())
	if isfile(file_name)
		println("Loading materials database from $file_name...")
		_load_from_csv!(library, file_name)
	else
		println("No $file_name found. Initializing default materials database...")
		_add_default_materials!(library)
	end
	return library
end

"""
Adds a predefined set of materials to the `MaterialsLibrary` instance.

# Arguments
- `library`: A `MaterialsLibrary` instance to which default materials will be added.

# Returns
- None. Modifies the `MaterialsLibrary` instance in place by adding default materials.

# Dependencies
- `add_material!`: Adds a single material to the library.
- `Material`: Constructs material objects with specified properties.

# Examples
```julia
library = MaterialsLibrary()
_add_default_materials!(library)
println(keys(library.materials)) # Outputs names of default materials added
```


"""
function _add_default_materials!(library::MaterialsLibrary)
	add_material!(library, "air", Material(Inf, 1.0, 1.0, 20.0, 0.0))
	add_material!(library, "pec", Material(eps(), 1.0, 1.0, 20.0, 0.0))
	add_material!(library, "copper", Material(1.7241e-8, 1.0, 0.999994, 20.0, 0.00393))
	add_material!(library, "aluminum", Material(2.8264e-8, 1.0, 1.000022, 20.0, 0.00429))
	add_material!(library, "xlpe", Material(1.97e14, 2.5, 1.0, 20.0, 0.0))
	add_material!(library, "pe", Material(1.97e14, 2.3, 1.0, 20.0, 0.0))
	add_material!(library, "semicon1", Material(1000.0, 1000.0, 1.0, 20.0, 0.0))
	add_material!(library, "semicon2", Material(500.0, 1000.0, 1.0, 20.0, 0.0))
	add_material!(library, "polyacrylate", Material(5.3e3, 32.3, 1.0, 20.0, 0.0))
end

"""
Loads material data from a CSV file into the `MaterialsLibrary` instance.

# Arguments
- `library`: A `MaterialsLibrary` instance where the material data will be loaded.
- `file_name`: Name of the CSV file containing material data.

# Returns
- None. Modifies the `MaterialsLibrary` instance in place by adding materials from the CSV file.

# Dependencies
- `Material`: Constructs material objects with specified properties.
- `add_material!`: Adds a single material to the library.

# Examples
```julia
library = MaterialsLibrary()
_load_from_csv!(library, "materials_library.csv")
println(keys(library.materials)) # Outputs names of materials loaded from the file
```


"""
function _load_from_csv!(library::MaterialsLibrary, file_name::String)
	df = DataFrame(CSV.File(file_name))
	for row in eachrow(df)
		material = Material(row.rho, row.eps_r, row.mu_r, row.T0, row.alpha)
		add_material!(library, row.name, material)
	end
end

"""
Adds a material to the `MaterialsLibrary` instance.

# Arguments
- `library`: A `MaterialsLibrary` instance to which the material will be added.
- `name`: The name of the material to add (String).
- `material`: A `Material` object representing the material to be added.

# Returns
- None. Modifies the `MaterialsLibrary` instance in place by adding the specified material.

# Examples
```julia
material = Material(1.7241e-8, 1.0, 0.999994, 20.0, 0.00393)
add_material!(library, "copper", material)
println(keys(library.materials)) # Outputs: ["copper"]
```


"""
function add_material!(library::MaterialsLibrary, name::String, material::Material)
	if haskey(library.materials, name)
		error("Material $name already exists in the library.")
	end
	library.materials[name] = material
end

"""
Removes a material from the `MaterialsLibrary` instance.

# Arguments
- `library`: A `MaterialsLibrary` instance from which the material will be removed.
- `name`: The name of the material to remove (String).

# Returns
- None. Modifies the `MaterialsLibrary` instance in place by removing the specified material.

# Examples
```julia
remove_material!(library, "copper")
println(keys(library.materials)) # Outputs: []
```


"""
function remove_material!(library::MaterialsLibrary, name::String)
	if !haskey(library.materials, name)
		error("Material $name not found in the library.")
	end
	delete!(library.materials, name)
end

"""
Saves the materials from the `MaterialsLibrary` instance to a CSV file.

# Arguments
- `library`: A `MaterialsLibrary` instance whose materials will be saved.
- `file_name`: Name of the CSV file where the materials will be saved (default: "materials_library.csv").

# Returns
- None. Writes the materials data to the specified file.

# Dependencies
- None.

# Examples
```julia
save_materials_library(library, "materials_backup.csv")
println("Materials saved to materials_backup.csv")
```


"""
function save_materials_library(
	library::MaterialsLibrary,
	file_name::String = "materials_library.csv",
)
	rows = [
		(
			name = name,
			rho = m.rho,
			eps_r = m.eps_r,
			mu_r = m.mu_r,
			T0 = m.T0,
			alpha = m.alpha,
		)
		for (name, m) in library.materials
	]
	df = DataFrame(rows)
	CSV.write(file_name, df)
end

"""
Displays the materials from the `MaterialsLibrary` instance as a DataFrame.

# Arguments
- `library`: A `MaterialsLibrary` instance whose materials will be displayed.

# Returns
- A `DataFrame` representing the materials and their properties.

# Dependencies
- None.

# Examples
```julia
df = display_materials_library(library)
println(df) # Displays materials and their properties
```


"""
function display_materials_library(library::MaterialsLibrary)::DataFrame
	rows = [
		(
			name = name,
			rho = m.rho,
			eps_r = m.eps_r,
			mu_r = m.mu_r,
			T0 = m.T0,
			alpha = m.alpha,
		)
		for (name, m) in library.materials
	]
	return DataFrame(rows)
end

"""
Retrieve material data from a library.

# Arguments
- `library`: A `MaterialsLibrary` object containing properties of the material.
- `name`: The name of the material to retrieve (String).

# Returns
- A `Material` object containing the corresponding properties if the material name exists in `library`, otherwise `nothing`.

# Examples
```julia
material = get_material(library, "copper")
println(material) # Outputs: Material(1.7241e-8, 1.0, 0.999994, 20.0, 0.00393)

missing_material = get_material(library, "gold")
println(missing_material) # Outputs: nothing
```


"""
function get_material(library::MaterialsLibrary, name::String)::Union{Nothing, Material}
	material = get(library.materials, name, nothing)
	if material === nothing
		println("Material '$name' not found in the library.")
		return nothing
	else
		return material
	end
end
