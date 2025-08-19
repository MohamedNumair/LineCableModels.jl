"""
$(TYPEDEF)

Stores a collection of predefined materials for cable modeling, indexed by material name:

$(TYPEDFIELDS)
"""
mutable struct MaterialsLibrary <: AbstractDict{String,Material}
    "Dictionary mapping material names to [`Material`](@ref) objects."
    data::Dict{String,Material}  # Key: Material name, Value: Material object
end

# Implement the AbstractDict interface
Base.length(lib::MaterialsLibrary) = length(lib.data)
Base.setindex!(lib::MaterialsLibrary, value::Material, key::String) = (lib.data[key] = value)
Base.iterate(lib::MaterialsLibrary, state...) = iterate(lib.data, state...)
Base.keys(lib::MaterialsLibrary) = keys(lib.data)
Base.values(lib::MaterialsLibrary) = values(lib.data)
Base.haskey(lib::MaterialsLibrary, key::String) = haskey(lib.data, key)
Base.getindex(lib::MaterialsLibrary, key::String) = getindex(lib.data, key)

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
function MaterialsLibrary(; add_defaults::Bool=true)::MaterialsLibrary
    library = MaterialsLibrary(Dict{String,Material}())

    if add_defaults
        @info "Initializing default materials database..."
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

- [`add!`](@ref)
"""
function _add_default_materials!(library::MaterialsLibrary)
    add!(library, "air", Material(Inf, 1.0, 1.0, 20.0, 0.0))
    add!(library, "pec", Material(eps(), 1.0, 1.0, 20.0, 0.0))
    add!(
        library,
        "copper",
        Material(1.7241e-8, 1.0, 0.999994, 20.0, 0.00393),
    )
    add!(
        library,
        "aluminum",
        Material(2.8264e-8, 1.0, 1.000022, 20.0, 0.00429),
    )
    add!(library, "xlpe", Material(1.97e14, 2.5, 1.0, 20.0, 0.0))
    add!(library, "pe", Material(1.97e14, 2.3, 1.0, 20.0, 0.0))
    add!(
        library,
        "semicon1",
        Material(1000.0, 1000.0, 1.0, 20.0, 0.0),
    )
    add!(
        library,
        "semicon2",
        Material(500.0, 1000.0, 1.0, 20.0, 0.0),
    )
    add!(
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
function LineCableModels.add!(
    library::MaterialsLibrary,
    name::AbstractString,
    material::Material,
)
    if haskey(library, name)
        error("Material $name already exists in the library.")
    end
    library[String(name)] = material
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

- [`add!`](@ref)
"""
function Base.delete!(library::MaterialsLibrary, name::String)
    if !haskey(library, name)
        @error "Material '$name' not found in the library."
        throw(KeyError(name))

    end
    delete!(library.data, name)
    @info "Material '$name' removed from the library."
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

- [`add!`](@ref)
- [`delete!`](@ref)
"""
function Base.get(library::MaterialsLibrary, name::String, default=nothing)::Union{Nothing,Material}
    material = get(library.data, name, default)
    if material === nothing
        @warn "Material '$name' not found in the library."
        # throw(KeyError(name))
    end
    return material
end