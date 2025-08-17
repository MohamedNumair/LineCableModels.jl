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
    num_materials = length(library)
    material_word = num_materials == 1 ? "material" : "materials"
    print(io, "MaterialsLibrary with $num_materials $material_word")

    if num_materials > 0
        print(io, ":")
        # Optional: list the first few materials
        shown_materials = min(5, num_materials)
        material_names = collect(keys(library))[1:shown_materials]

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
function Base.show(io::IO, ::MIME"text/plain", dict::Dict{String,Material})
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