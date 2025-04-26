"""
Material handling functions for the FEMTools.jl module.
These functions handle the management of material properties.
"""

"""
$(TYPEDSIGNATURES)

Get the name of a material from a materials library.

# Arguments

- `material`: The [`Material`](@ref) object to find.
- `library`: The [`MaterialsLibrary`](@ref) to search in.
- `tol`: Tolerance for floating-point comparisons \\[dimensionless\\]. Default: 1e-6.

# Returns

- The name of the material if found, or a hash-based name if not found.

# Examples

```julia
name = $(FUNCTIONNAME)(material, materials_db)
```
"""
function get_material_name(material::Material, library::MaterialsLibrary; tol=1e-6)
    # If material has infinite resistivity, it's air
    if isinf(to_nominal(material.rho))
        return "air"
    end

    # Convert values to nominal (remove uncertainties)
    rho = to_nominal(material.rho)
    eps_r = to_nominal(material.eps_r)
    mu_r = to_nominal(material.mu_r)
    alpha = to_nominal(material.alpha)

    # Try to find an exact match
    for (name, lib_material) in library.materials
        # Check if all properties match within tolerance
        if isapprox(rho, to_nominal(lib_material.rho), rtol=tol) &&
           isapprox(eps_r, to_nominal(lib_material.eps_r), rtol=tol) &&
           isapprox(mu_r, to_nominal(lib_material.mu_r), rtol=tol) &&
           isapprox(alpha, to_nominal(lib_material.alpha), rtol=tol)
            return name
        end
    end

    # If no match, create a unique hash-based name
    return "material_" * hash_material_properties(material)
end

"""
$(TYPEDSIGNATURES)

Create a hash string based on material properties.

# Arguments

- `material`: The [`Material`](@ref) object to hash.

# Returns

- A string hash of the material properties.

# Examples

```julia
hash = $(FUNCTIONNAME)(material)
```
"""
function hash_material_properties(material::Material)
    # Create a deterministic hash based on material properties
    rho = to_nominal(material.rho)
    eps_r = to_nominal(material.eps_r)
    mu_r = to_nominal(material.mu_r)

    rho_str = isinf(rho) ? "inf" : "$(round(rho, sigdigits=6))"
    eps_str = "$(round(eps_r, sigdigits=6))"
    mu_str = "$(round(mu_r, sigdigits=6))"

    return "rho=$(rho_str)_epsr=$(eps_str)_mu=$(mu_str)"
end

# """
# $(TYPEDSIGNATURES)

# Get a material from a materials library by name.

# # Arguments

# - `library`: The [`MaterialsLibrary`](@ref) to search in.
# - `name`: The name of the material to find.

# # Returns

# - The [`Material`](@ref) object if found, or `nothing` if not found.

# # Examples

# ```julia
# material = $(FUNCTIONNAME)(materials_db, "copper")
# ```
# """
# function get_material(library::MaterialsLibrary, name::String)
#     return get(library.materials, name, nothing)
# end


function get_space_material(workspace::FEMWorkspace, layer_idx::Int)

    earth_model = workspace.cable_system.earth_props
    num_layers = workspace.cable_system.earth_props.num_layers

    if layer_idx <= num_layers

        # Create a material with the earth properties
        rho = earth_model.layers[layer_idx].base_rho_g  # Layer 1 is air, Layer 2 is first earth layer
        eps_r = earth_model.layers[layer_idx].base_epsr_g
        mu_r = earth_model.layers[layer_idx].base_mur_g

        return Material(rho, eps_r, mu_r, 20.0, 0.0)
    else
        # Default to bottom earth layer if layer_idx is out of bounds

        # Create a material with the earth properties
        rho = earth_model.layers[end].base_rho_g  # Layer 1 is air, Layer 2 is first earth layer
        eps_r = earth_model.layers[end].base_epsr_g
        mu_r = earth_model.layers[end].base_mur_g

        return Material(rho, eps_r, mu_r, 20.0, 0.0)
    end
end

function get_air_material(workspace::FEMWorkspace)
    if !isnothing(workspace.problem_def.materials_db)
        air_material = get_material(workspace.problem_def.materials_db, "air")
        if isnothing(air_material)
            @warn("Air material not found in database. Overriding with default properties.")
            air_material = Material(Inf, 1.0, 1.0, 20.0, 0.0)
        end
    end
    return air_material
end

# """
# $(TYPEDSIGNATURES)

# Register a material in the workspace.

# # Arguments

# - `workspace`: The [`FEMWorkspace`](@ref) to register the material in.
# - `physical_group_tag`: The physical tag to associate with the material \\[dimensionless\\].
# - `material`: The [`Material`](@ref) object to register.

# # Returns

# - Nothing. Updates the material_map in the workspace.

# # Examples

# ```julia
# $(FUNCTIONNAME)(workspace, 101210001, material)
# ```
# """
# function register_material!(workspace::FEMWorkspace, physical_group_tag::Int, material::Material)
#     workspace.material_map[physical_group_tag] = material
# end
