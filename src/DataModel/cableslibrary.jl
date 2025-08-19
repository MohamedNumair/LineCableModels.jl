"""
$(TYPEDEF)

Represents a library of cable designs stored as a dictionary.

$(TYPEDFIELDS)
"""
mutable struct CablesLibrary
    "Dictionary mapping cable IDs to the respective CableDesign objects."
    data::Dict{String,CableDesign}

    @doc """
    $(TYPEDSIGNATURES)

    Constructs an empty [`CablesLibrary`](@ref) instance.

    # Arguments

    - None.

    # Returns

    - A [`CablesLibrary`](@ref) object with an empty dictionary of cable designs.

    # Examples

    ```julia
    # Create a new, empty library
    library = $(FUNCTIONNAME)()
    ```

    # See also

    - [`CableDesign`](@ref)
    - [`add!`](@ref)
    - [`delete!`](@ref)
    - [`LineCableModels.ImportExport.save`](@ref)
    - [`DataFrame`](@ref)
    """
    function CablesLibrary()::CablesLibrary
        library = new(Dict{String,CableDesign}())
        @info "Initializing empty cables database..."
        return library
    end
end

# Implement the AbstractDict interface
Base.length(lib::CablesLibrary) = length(lib.data)
Base.setindex!(lib::CablesLibrary, value::CableDesign, key::String) = (lib.data[key] = value)
Base.iterate(lib::CablesLibrary, state...) = iterate(lib.data, state...)
Base.keys(lib::CablesLibrary) = keys(lib.data)
Base.values(lib::CablesLibrary) = values(lib.data)
Base.haskey(lib::CablesLibrary, key::String) = haskey(lib.data, key)
Base.getindex(lib::CablesLibrary, key::String) = getindex(lib.data, key)

"""
Stores a cable design in a [`CablesLibrary`](@ref) object.

# Arguments

- `library`: An instance of [`CablesLibrary`](@ref) to which the cable design will be added.
- `design`: A [`CableDesign`](@ref) object representing the cable design to be added. This object must have a `cable_id` field to uniquely identify it.

# Returns

- None. Modifies the `data` field of the [`CablesLibrary`](@ref) object in-place by adding the new cable design.

# Examples
```julia
library = CablesLibrary()
design = CableDesign("example", ...) # Initialize CableDesign with required fields
add!(library, design)
println(library) # Prints the updated dictionary containing the new cable design
```
# See also

- [`CablesLibrary`](@ref)
- [`CableDesign`](@ref)
- [`delete!`](@ref)
"""
function LineCableModels.add!(library::CablesLibrary, design::CableDesign)
    library.data[design.cable_id] = design
    @info "Cable design with ID `$(design.cable_id)` added to the library."
    library
end

"""
$(TYPEDSIGNATURES)

Removes a cable design from a [`CablesLibrary`](@ref) object by its ID.

# Arguments

- `library`: An instance of [`CablesLibrary`](@ref) from which the cable design will be removed.
- `cable_id`: The ID of the cable design to remove.

# Returns

- Nothing. Modifies the `data` field of the [`CablesLibrary`](@ref) object in-place by removing the specified cable design if it exists.

# Examples

```julia
library = CablesLibrary()
design = CableDesign("example", ...) # Initialize a CableDesign
add!(library, design)

# Remove the cable design
$(FUNCTIONNAME)(library, "example")
haskey(library, "example")  # Returns false
```

# See also

- [`CablesLibrary`](@ref)
- [`add!`](@ref)
"""
function LineCableModels.delete!(library::CablesLibrary, cable_id::String)
    if haskey(library, cable_id)
        delete!(library.data, cable_id)
        @info "Cable design with ID `$cable_id` removed from the library."
    else
        @error "Cable design with ID `$cable_id` not found in the library."
        throw(KeyError(cable_id))
    end
end

"""
$(TYPEDSIGNATURES)

Retrieves a cable design from a [`CablesLibrary`](@ref) object by its ID.

# Arguments

- `library`: An instance of [`CablesLibrary`](@ref) from which the cable design will be retrieved.
- `cable_id`: The ID of the cable design to retrieve.

# Returns

- A [`CableDesign`](@ref) object corresponding to the given `cable_id` if found, otherwise `nothing`.

# Examples

```julia
library = CablesLibrary()
design = CableDesign("example", ...) # Initialize a CableDesign
add!(library, design)

# Retrieve the cable design
retrieved_design = $(FUNCTIONNAME)(library, "cable1")
println(retrieved_design.id)  # Prints "example"

# Attempt to retrieve a non-existent design
missing_design = $(FUNCTIONNAME)(library, "nonexistent_id")
println(missing_design === nothing)  # Prints true
```

# See also

- [`CablesLibrary`](@ref)
- [`CableDesign`](@ref)
- [`add!`](@ref)
- [`delete!`](@ref)
"""
function Base.get(library::CablesLibrary, cable_id::String, default=nothing)::Union{Nothing,CableDesign}
    if haskey(library, cable_id)
        @info "Cable design with ID `$cable_id` loaded from the library."
        return library[cable_id]
    else
        @warn "Cable design with ID `$cable_id` not found in the library."
        return default
    end
end