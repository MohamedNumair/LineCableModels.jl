"""
	LineCableModels.Materials

The [`Materials`](@ref) module provides functionality for managing and utilizing material properties within the [`LineCableModels.jl`](index.md) package. This module includes definitions for material properties, a library for storing and retrieving materials, and functions for manipulating material data.

# Overview

- Defines the [`Material`](@ref) struct representing fundamental physical properties of materials.
- Provides the [`MaterialsLibrary`](@ref) mutable struct for storing a collection of materials.
- Includes functions for adding, removing, and retrieving materials from the library.
- Supports loading material data from CSV files and saving material data to CSV files.
- Contains utility functions for displaying material data.

# Dependencies

$(IMPORTS)

# Exports

$(EXPORTS)
"""
module Materials

# Load common dependencies
include("CommonDeps.jl")
using ..Utils

# Module-specific dependencies
using Measurements
using CSV
using DataFrames

"""
$(TYPEDEF)

Defines electromagnetic and thermal properties of a material used in conductor modeling:

$(TYPEDFIELDS)
"""
struct Material
	"Electrical resistivity of the material \\[Ω·m\\]."
	rho::Number
	"Relative permittivity \\[dimensionless\\]."
	eps_r::Number
	"Relative permeability \\[dimensionless\\]."
	mu_r::Number
	"Reference temperature for property evaluations \\[°C\\]."
	T0::Number
	"Temperature coefficient of resistivity \\[1/°C\\]."
	alpha::Number
end

"""
$(TYPEDEF)

Stores a collection of predefined materials for conductor modeling, indexed by material name:

$(TYPEDFIELDS)
"""
mutable struct MaterialsLibrary
	"Dictionary mapping material names to [`Material`](@ref) objects."
	materials::Dict{String, Material}  # Key: Material name, Value: Material object
end

"""
$(TYPEDSIGNATURES)

Constructs a [`MaterialsLibrary`](@ref) instance, loading materials from a CSV file if available.

# Arguments

- `file_name`: Name of the CSV file containing material definitions (default: `"materials_library.csv"`).

# Returns

- An instance of [`MaterialsLibrary`](@ref), either loaded from the file or initialized with default materials.

# Examples

```julia
library = MaterialsLibrary()
```

# See also

- [`Material`](@ref)
- [`store_materials_library!`](@ref)
- [`remove_materials_library!`](@ref)
- [`save_materials_library`](@ref)
- [`list_materials_library`](@ref)
"""
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
$(TYPEDSIGNATURES)

Populates a [`MaterialsLibrary`](@ref) with commonly used materials, assigning predefined electrical and thermal properties.

# Arguments

- `library`: Instance of [`MaterialsLibrary`](@ref) to be populated.

# Returns

- The modified instance of [`MaterialsLibrary`](@ref) containing the predefined materials.

# Examples

```julia
library = MaterialsLibrary()
$(FUNCTIONNAME)(library)
```

# See also

- [`store_materials_library!`](@ref)
"""
function _add_default_materials!(library::MaterialsLibrary)
	store_materials_library!(library, "air", Material(Inf, 1.0, 1.0, 20.0, 0.0))
	store_materials_library!(library, "pec", Material(eps(), 1.0, 1.0, 20.0, 0.0))
	store_materials_library!(
		library,
		"copper",
		Material(1.7241e-8, 1.0, 0.999994, 20.0, 0.00393),
	)
	store_materials_library!(
		library,
		"aluminum",
		Material(2.8264e-8, 1.0, 1.000022, 20.0, 0.00429),
	)
	store_materials_library!(library, "xlpe", Material(1.97e14, 2.5, 1.0, 20.0, 0.0))
	store_materials_library!(library, "pe", Material(1.97e14, 2.3, 1.0, 20.0, 0.0))
	store_materials_library!(library, "semicon1", Material(1000.0, 1000.0, 1.0, 20.0, 0.0))
	store_materials_library!(library, "semicon2", Material(500.0, 1000.0, 1.0, 20.0, 0.0))
	store_materials_library!(
		library,
		"polyacrylate",
		Material(5.3e3, 32.3, 1.0, 20.0, 0.0),
	)
end

"""
$(TYPEDSIGNATURES)

Loads materials from a CSV file into a [`MaterialsLibrary`](@ref).

# Arguments

- `library`: Instance of [`MaterialsLibrary`](@ref) to be populated.
- `file_name`: Path to the CSV file containing material properties.

# Returns

- The modified instance of [`MaterialsLibrary`](@ref) with materials loaded from the file.

# Errors

Throws an error if the CSV file format is invalid or missing required fields.

# Examples

```julia
library = MaterialsLibrary()
$(FUNCTIONNAME)(library, "materials_library.csv")
```

# See also

- [`store_materials_library!`](@ref)
- [`MaterialsLibrary`](@ref)
"""
function _load_from_csv!(library::MaterialsLibrary, file_name::String)
	df = DataFrame(CSV.File(file_name))
	for row in eachrow(df)
		material = Material(row.rho, row.eps_r, row.mu_r, row.T0, row.alpha)
		store_materials_library!(library, row.name, material)
	end
end

"""
$(TYPEDSIGNATURES)

Adds a new material to a [`MaterialsLibrary`](@ref).

# Arguments

- `library`: Instance of [`MaterialsLibrary`](@ref) where the material will be added.
- `name`: Name of the material.
- `material`: Instance of [`Material`](@ref) containing its properties.

# Returns

- The modified instance of [`MaterialsLibrary`](@ref) with the new material added.

# Errors

Throws an error if a material with the same name already exists in the library.

# Examples

```julia
library = MaterialsLibrary()
material = Material(1.7241e-8, 1.0, 0.999994, 20.0, 0.00393)
$(FUNCTIONNAME)(library, "copper", material)
```
"""
function store_materials_library!(
	library::MaterialsLibrary,
	name::AbstractString,
	material::Material,
)
	if haskey(library.materials, name)
		error("Material $name already exists in the library.")
	end
	library.materials[String(name)] = material
	library
end

"""
$(TYPEDSIGNATURES)

Removes a material from a [`MaterialsLibrary`](@ref).

# Arguments

- `library`: Instance of [`MaterialsLibrary`](@ref) from which the material will be removed.
- `name`: Name of the material to be removed.

# Returns

- The modified instance of [`MaterialsLibrary`](@ref) without the specified material.

# Errors

Throws an error if the material does not exist in the library.

# Examples

```julia
library = MaterialsLibrary()
$(FUNCTIONNAME)(library, "copper")
```

# See also

- [`store_materials_library!`](@ref)
"""
function remove_materials_library!(library::MaterialsLibrary, name::String)
	if !haskey(library.materials, name)
		error("Material $name not found in the library.")
	end
	delete!(library.materials, name)
	library
end

"""
$(TYPEDSIGNATURES)

Saves a [`MaterialsLibrary`](@ref) to a CSV file.

# Arguments

- `library`: Instance of [`MaterialsLibrary`](@ref) to be saved.
- `file_name`: Path to the output CSV file (default: `"materials_library.csv"`).

# Returns

- The path of the saved CSV file.

# Examples

```julia
library = MaterialsLibrary()
$(FUNCTIONNAME)(library, file_name = "materials_library.csv")
```

# See also

- [`_load_from_csv!`](@ref)
"""
function save_materials_library(
	library::MaterialsLibrary;
	file_name::String = "materials_library.csv",
)::String
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

	return abspath(file_name)
end

"""
$(TYPEDSIGNATURES)

Lists the contents of a [`MaterialsLibrary`](@ref) as a `DataFrame`.

# Arguments

- `library`: Instance of [`MaterialsLibrary`](@ref) to be displayed.

# Returns

- A `DataFrame` containing the material properties.

# Examples

```julia
library = MaterialsLibrary()
df = $(FUNCTIONNAME)(library)
```

# See also

- [`save_materials_library`](@ref)
"""
function list_materials_library(library::MaterialsLibrary)::DataFrame
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
$(TYPEDSIGNATURES)

Retrieves a material from a [`MaterialsLibrary`](@ref) by name.

# Arguments

- `library`: Instance of [`MaterialsLibrary`](@ref) containing the materials.
- `name`: Name of the material to retrieve.

# Returns

- The requested [`Material`](@ref) if found, otherwise `nothing`.

# Examples

```julia
library = MaterialsLibrary()
material = $(FUNCTIONNAME)(library, "copper")
```

# See also

- [`store_materials_library!`](@ref)
- [`remove_materials_library!`](@ref)
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

"""
$(TYPEDSIGNATURES)

Defines the display representation of a [`Material`](@ref) object for REPL or text output.

# Arguments

- `io`: Output stream.
- `::MIME"text/plain"`: MIME type for plain text output.
- `material`: The [`Material`](@ref) instance to be displayed.

# Returns

- Nothing. Modifies `io` by writing text representation of the material.
"""
function Base.show(io::IO, ::MIME"text/plain", material::Material)
	print(io, "Material with properties: [")

	# Define fields to display
	fields = [:rho, :eps_r, :mu_r, :T0, :alpha]

	# Print each field with proper formatting
	for (i, field) in enumerate(fields)
		value = getfield(material, field)
		# Add comma only between items, not after the last one
		delimiter = i < length(fields) ? ", " : ""
		print(io, "$field=$(round(value, sigdigits=4))$delimiter")
	end

	print(io, "]")
end

"""
$(TYPEDSIGNATURES)

Defines the display representation of a [`MaterialsLibrary`](@ref) object for REPL or text output.

# Arguments

- `io`: Output stream.
- `::MIME"text/plain"`: MIME type for plain text output.
- `library`: The [`MaterialsLibrary`](@ref) instance to be displayed.

# Returns

- Nothing. Modifies `io` by writing text representation of the library.
"""
function Base.show(io::IO, ::MIME"text/plain", library::MaterialsLibrary)
	num_materials = length(library.materials)
	material_word = num_materials == 1 ? "material" : "materials"
	print(io, "MaterialsLibrary with $num_materials $material_word")

	if num_materials > 0
		print(io, ":")
		# Optional: list the first few materials
		shown_materials = min(5, num_materials)
		material_names = collect(keys(library.materials))[1:shown_materials]

		for (i, name) in enumerate(material_names)
			print(io, "\n$(i == shown_materials ? "└─" : "├─") $name")
		end

		# If there are more materials than we're showing
		if num_materials > shown_materials
			print(io, "\n└─ ... and $(num_materials - shown_materials) more")
		end
	end
end

"""
$(TYPEDSIGNATURES)

Defines the display representation of a [`MaterialsLibrary`](@ref) object for REPL or text output.

# Arguments

- `io`: Output stream.
- `::MIME"text/plain"`: MIME type for plain text output.
- `dict`: The [`MaterialsLibrary`](@ref) contents to be displayed.

# Returns

- Nothing. Modifies `io` by writing text representation of the library.
"""
function Base.show(io::IO, ::MIME"text/plain", dict::Dict{String, Material})
	num_materials = length(dict)
	material_word = num_materials == 1 ? "material" : "materials"
	print(io, "Dict{String, Material} with $num_materials $material_word")

	if num_materials > 0
		print(io, ":")
		# List the first few materials
		shown_materials = min(5, num_materials)
		material_names = collect(keys(dict))[1:shown_materials]

		for (i, name) in enumerate(material_names)
			print(io, "\n$(i == shown_materials ? "└─" : "├─") $name")
		end

		# If there are more materials than we're showing
		if num_materials > shown_materials
			print(io, "\n└─ ... and $(num_materials - shown_materials) more")
		end
	end
end

Utils.@_autoexport

end
