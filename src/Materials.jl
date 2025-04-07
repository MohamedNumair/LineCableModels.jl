"""
	LineCableModels.Materials

The [`Materials`](@ref) module provides functionality for managing and utilizing material properties within the [`LineCableModels.jl`](index.md) package. This module includes definitions for material properties, a library for storing and retrieving materials, and functions for manipulating material data.

# Overview

- Defines the [`Material`](@ref) struct representing fundamental physical properties of materials.
- Provides the [`MaterialsLibrary`](@ref) mutable struct for storing a collection of materials.
- Includes functions for adding, removing, and retrieving materials from the library.
- Supports loading and saving material data from/to JSON files.
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
using DataFrames

"""
$(TYPEDEF)

Defines electromagnetic and thermal properties of a material used in cable modeling:

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

Stores a collection of predefined materials for cable modeling, indexed by material name:

$(TYPEDFIELDS)
"""
mutable struct MaterialsLibrary
	"Dictionary mapping material names to [`Material`](@ref) objects."
	materials::Dict{String, Material}  # Key: Material name, Value: Material object
end

"""
$(TYPEDSIGNATURES)

Constructs an empty [`MaterialsLibrary`](@ref) instance and initializes with default materials.

# Arguments

- None.

# Returns

- A [`MaterialsLibrary`](@ref) object populated with default materials.

# Examples

```julia
# Create a new, empty library
library = $(FUNCTIONNAME)()
```

# See also

- [`Material`](@ref)
- [`_add_default_materials!`](@ref)
"""
function MaterialsLibrary(; add_defaults::Bool = true)::MaterialsLibrary
	library = MaterialsLibrary(Dict{String, Material}())

	if add_defaults
		println("Initializing default materials database...")
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

- [`store_materialslibrary!`](@ref)
"""
function _add_default_materials!(library::MaterialsLibrary)
	store_materialslibrary!(library, "air", Material(Inf, 1.0, 1.0, 20.0, 0.0))
	store_materialslibrary!(library, "pec", Material(eps(), 1.0, 1.0, 20.0, 0.0))
	store_materialslibrary!(
		library,
		"copper",
		Material(1.7241e-8, 1.0, 0.999994, 20.0, 0.00393),
	)
	store_materialslibrary!(
		library,
		"aluminum",
		Material(2.8264e-8, 1.0, 1.000022, 20.0, 0.00429),
	)
	store_materialslibrary!(library, "xlpe", Material(1.97e14, 2.5, 1.0, 20.0, 0.0))
	store_materialslibrary!(library, "pe", Material(1.97e14, 2.3, 1.0, 20.0, 0.0))
	store_materialslibrary!(
		library,
		"semicon1",
		Material(1000.0, 1000.0, 1.0, 20.0, 0.0),
	)
	store_materialslibrary!(
		library,
		"semicon2",
		Material(500.0, 1000.0, 1.0, 20.0, 0.0),
	)
	store_materialslibrary!(
		library,
		"polyacrylate",
		Material(5.3e3, 32.3, 1.0, 20.0, 0.0),
	)
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
function store_materialslibrary!(
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

- [`store_materialslibrary!`](@ref)
"""
function remove_materialslibrary!(library::MaterialsLibrary, name::String)
	if !haskey(library.materials, name)
		error("Material $name not found in the library.")
	end
	delete!(library.materials, name)
	library
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

- [`LineCableModels.ImportExport.save_materialslibrary`](@ref)
"""
function list_materialslibrary(library::MaterialsLibrary)::DataFrame
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

- [`store_materialslibrary!`](@ref)
- [`remove_materialslibrary!`](@ref)
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
