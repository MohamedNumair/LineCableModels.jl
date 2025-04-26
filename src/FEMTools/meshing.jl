"""
Mesh generation functions for the FEMTools.jl module.
These functions handle the configuration and generation of the mesh.
"""

# function register_mesh_size!(workspace::FEMWorkspace, physical_group_tag::Int, mesh_size::Number)
#     workspace.mesh_size_map[physical_group_tag] = mesh_size
# end

"""
$(TYPEDSIGNATURES)

Calculate the skin depth for a conductive material.

# Arguments

- `rho`: Electrical resistivity \\[Ω·m\\].
- `mu_r`: Relative permeability \\[dimensionless\\].
- `freq`: Frequency \\[Hz\\].

# Returns

- Skin depth \\[m\\].

# Examples

```julia
depth = $(FUNCTIONNAME)(1.7241e-8, 1.0, 50.0)
```

# Notes

```math
\\delta = \\sqrt{\\frac{\\rho}{\\pi \\cdot f \\cdot \\mu_0 \\cdot \\mu_r}}
```

where \\(\\mu_0 = 4\\pi \\times 10^{-7}\\) H/m is the vacuum permeability.
"""
function calc_skin_depth(rho::Number, mu_r::Number, freq::Number)
    # If material is an insulator (high resistivity), return infinity
    if isinf(rho) || rho > 1e6
        return Inf
    end

    # Convert to nominal values in case of Measurement types
    rho = to_nominal(rho)
    mu_r = to_nominal(mu_r)

    # Constants
    mu_0 = 4e-7 * π  # Vacuum permeability

    # Calculate skin depth
    # δ = sqrt(ρ / (π * f * μ_0 * μ_r))
    return sqrt(rho / (π * freq * mu_0 * mu_r))
end

"""
$(TYPEDSIGNATURES)

Calculate appropriate mesh size for a cable part based on its physical properties.

# Arguments

- `part`: The cable part to calculate mesh size for.
- `workspace`: The [`FEMWorkspace`](@ref) containing problem_def parameters.

# Returns

- Mesh size \\[m\\].

# Examples

```julia
mesh_size = $(FUNCTIONNAME)(cable_part, workspace)
```
"""
function calc_mesh_size(part::AbstractCablePart, workspace::FEMWorkspace)
    # Extract material properties
    material = part.material_props
    rho = to_nominal(material.rho)
    mu_r = to_nominal(material.mu_r)

    # Extract geometric properties
    radius_in = to_nominal(part.radius_in)
    radius_ext = to_nominal(part.radius_ext)
    thickness = radius_ext - radius_in

    # Extract problem_def parameters
    problem_def = workspace.problem_def
    freq = workspace.frequency

    # Calculate skin depth
    skin_depth = calc_skin_depth(rho, mu_r, freq)

    # Calculate mesh size based on part type and properties
    if part isa WireArray
        # For wire arrays, consider the wire radius
        wire_radius = to_nominal(part.radius_wire)

        if isinf(skin_depth)  # Insulator or semiconductor
            mesh_size = wire_radius / problem_def.elements_per_scale_length_insulator
        else  # Conductor - use either skin depth or geometry, whichever needs finer mesh
            skin_based_size = skin_depth / problem_def.elements_per_scale_length_conductor
            geometry_based_size = wire_radius * 2 / problem_def.elements_per_scale_length_insulator
            mesh_size = min(skin_based_size, geometry_based_size)
        end
    else
        # For tubular, strip, insulator, semicon
        if isinf(skin_depth)  # Insulator
            if part isa Semicon
                mesh_size = thickness / problem_def.elements_per_scale_length_semicon
            else
                mesh_size = thickness / problem_def.elements_per_scale_length_insulator
            end
        else  # Conductor - ensure proper skin depth resolution
            skin_based_size = skin_depth / problem_def.elements_per_scale_length_conductor
            geometry_based_size = thickness / problem_def.elements_per_scale_length_insulator
            mesh_size = min(skin_based_size, geometry_based_size)
        end

        # For thin shells with large radius, adjust circumferential sizing
        if thickness < radius_ext * 0.1
            # Aim for approximately 20-30 elements around the circumference
            circumferential_size = 2 * π * radius_ext / 25
            mesh_size = min(mesh_size, circumferential_size)
        end
    end

    # Apply bounds from configuration
    mesh_size = max(mesh_size, problem_def.mesh_size_min)
    mesh_size = min(mesh_size, problem_def.mesh_size_max)

    return mesh_size
end

"""
$(TYPEDSIGNATURES)

Configure mesh sizes for all entities in the model.

# Arguments

- `workspace`: The [`FEMWorkspace`](@ref) containing the entities.

# Returns

- Nothing. Updates the mesh size map in the workspace.

# Examples

```julia
$(FUNCTIONNAME)(workspace)
```
"""
# function _config_mesh_sizes(workspace::FEMWorkspace)
#     _log(workspace, 1, "Configuring mesh sizes...")

#     # Apply mesh sizes from the mesh_size_map
#     for (tag, mesh_size) in workspace.mesh_size_map
#         gmsh.model.mesh.setSize(gmsh.model.getBoundary([(2, tag)], false, false, true), mesh_size)
#     end

#     # Set global mesh size parameters
#     gmsh.option.setNumber("Mesh.MeshSizeMin", workspace.problem_def.mesh_size_min)
#     gmsh.option.setNumber("Mesh.MeshSizeMax", workspace.problem_def.mesh_size_max)
#     gmsh.option.setNumber("Mesh.MeshSizeFromPoints", 1)
#     gmsh.option.setNumber("Mesh.MeshSizeExtendFromBoundary", 1)

#     _log(workspace, 1, "Mesh sizes configured")
# end
function _config_mesh_sizes(workspace::FEMWorkspace)
    _log(workspace, 1, "Configuring mesh sizes...")

    # Track how many entities had mesh sizes applied
    applied_count = 0

    # Loop through identified entities (these are the actual Gmsh entity tags after fragmentation)
    for (entity_tag, (physical_group_tag, _)) in workspace.identified_entities
        # Look up the mesh size for this physical tag
        if haskey(workspace.mesh_size_map, physical_group_tag)
            mesh_size = workspace.mesh_size_map[physical_group_tag]

            # Get the boundary points/curves of this entity
            boundary_entities = gmsh.model.get_boundary([(2, entity_tag)], false, false, true)

            # Apply mesh size to all boundary entities
            gmsh.model.mesh.set_size(boundary_entities, mesh_size)
            applied_count += 1

            _log(workspace, 3, "Applied mesh size $(mesh_size) to entity $(entity_tag) (physical tag: $(physical_group_tag))")
        else
            _log(workspace, 2, "No mesh size defined for entity $(entity_tag) (physical tag: $(physical_group_tag))")
        end
    end

    # Set global mesh size parameters
    gmsh.option.setNumber("Mesh.MeshSizeMin", workspace.problem_def.mesh_size_min)
    gmsh.option.setNumber("Mesh.MeshSizeMax", workspace.problem_def.mesh_size_max)
    gmsh.option.setNumber("Mesh.MeshSizeFromPoints", 1)
    gmsh.option.setNumber("Mesh.MeshSizeExtendFromBoundary", 1)

    _log(workspace, 1, "Mesh sizes configured for $(applied_count) entities")
end

"""
$(TYPEDSIGNATURES)

Generate the mesh.

# Arguments

- `workspace`: The [`FEMWorkspace`](@ref) containing the model.

# Returns

- Nothing. Generates the mesh in the Gmsh model.

# Examples

```julia
$(FUNCTIONNAME)(workspace)
```
"""
function _mesh_generate(workspace::FEMWorkspace)
    _log(workspace, 1, "Generating mesh...")

    # Set mesh algorithm
    gmsh.option.setNumber("Mesh.Algorithm", workspace.problem_def.mesh_algorithm)

    # Set mesh optimization parameters
    gmsh.option.setNumber("Mesh.Optimize", 1)
    gmsh.option.setNumber("Mesh.OptimizeNetgen", 1)

    # Generate 2D mesh
    gmsh.model.mesh.generate(2)

    # Get mesh statistics
    nodes = gmsh.model.mesh.getNodes()
    elements = gmsh.model.mesh.getElements()

    num_nodes = length(nodes[1])
    num_elements = sum(length.(elements[2]))

    _log(workspace, 1, "Mesh generation completed")
    _log(workspace, 1, "Created mesh with $(num_nodes) nodes and $(num_elements) elements")
end

"""
$(TYPEDSIGNATURES)

Initialize a Gmsh model with appropriate settings.

# Arguments

- `case_id`: Identifier for the model.
- `problem_def`: The [`FEMProblemDefinition`](@ref) containing mesh parameters.
- `solver`: The [`FEMSolver`](@ref) containing visualization parameters.

# Returns

- Nothing. Initializes the Gmsh model.

# Examples

```julia
$(FUNCTIONNAME)("test_case", problem_def, solver)
```
"""
function _initialize_gmsh(case_id::String, problem_def::FEMProblemDefinition, solver::FEMSolver)
    # Create a new model
    gmsh.model.add(case_id)

    # Module launched on startup (0: automatic, 1: geometry, 2: mesh, 3: solver, 4: post-processing)
    gmsh.option.setNumber("General.InitialModule", 0)
    gmsh.option.setString("General.DefaultFileName", case_id * ".geo")

    # Set a full onelab db
    # gmsh.onelab.set("""
    # { "onelab":{
    #     "creator":"LineCableModels.jl",
    #     "parameters":[
    #         { "type":"number", "name":"Materials", "values":[1], "attributes":{"Closed":"1", "ReadOnly":"1"} }
    #     ] }
    # }
    # """)

    # Set critical options
    gmsh.option.setNumber("Mesh.SaveAll", 1)  # Mesh all regions
    gmsh.option.setNumber("Mesh.Algorithm", problem_def.mesh_algorithm)
    gmsh.option.setNumber("Mesh.MeshSizeMin", problem_def.mesh_size_min)
    gmsh.option.setNumber("Mesh.MeshSizeMax", problem_def.mesh_size_max)
    gmsh.option.setNumber("Mesh.MeshSizeFromPoints", 1)
    gmsh.option.setNumber("Mesh.MeshSizeExtendFromBoundary", 1)

    # Set general visualization options
    gmsh.option.setNumber("Geometry.Points", 1)  # Show points
    gmsh.option.setNumber("Geometry.Curves", 1)  # Show curves
    gmsh.option.setNumber("Geometry.SurfaceLabels", 1)  # Show surface labels

    # Log settings based on verbosity
    _log(solver, 2, "Initialized Gmsh model: $case_id")
    _log(solver, 2, "Mesh algorithm: $(problem_def.mesh_algorithm)")
    _log(solver, 2, "Mesh size range: [$(problem_def.mesh_size_min), $(problem_def.mesh_size_max)]")
end
