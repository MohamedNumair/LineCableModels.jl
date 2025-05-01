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
    # Convert to nominal values in case of Measurement types
    rho = to_nominal(rho)
    mu_r = to_nominal(mu_r)

    # Constants
    mu_0 = 4e-7 * π  # Vacuum permeability

    # Calculate skin depth
    # δ = sqrt(ρ / (π * f * μ_0 * μ_r))
    return sqrt(rho / (π * freq * mu_0 * mu_r))
end

# """
# $(TYPEDSIGNATURES)

# Calculate appropriate mesh size for a cable part based on its physical properties.

# # Arguments

# - `part`: The cable part to calculate mesh size for.
# - `workspace`: The [`FEMWorkspace`](@ref) containing problem_def parameters.

# # Returns

# - Mesh size \\[m\\].

# # Examples

# ```julia
# mesh_size = $(FUNCTIONNAME)(cable_part, workspace)
# ```
# """
function calc_mesh_size(part::AbstractCablePart, workspace::FEMWorkspace)
    # Extract material properties
    material = part.material_props
    rho = to_nominal(material.rho)
    mu_r = to_nominal(material.mu_r)
    eps_r = to_nominal(material.eps_r)

    # Extract geometric properties
    radius_in = to_nominal(part.radius_in)
    radius_ext = to_nominal(part.radius_ext)
    thickness = radius_ext - radius_in

    # Extract problem_def parameters
    problem_def = workspace.problem_def
    freq = workspace.frequency

    # Calculate skin depth & wavelength
    skin_depth = calc_skin_depth(rho, mu_r, freq)
    wavelength = 1 / sqrt(ε₀ * eps_r * μ₀ * mu_r) / freq

    # Calculate mesh size based on part type and properties
    scale_length = thickness
    arc_length = 2 * π * radius_ext
    if part isa WireArray
        # For wire arrays, consider the wire radius
        scale_length = to_nominal(part.radius_wire) * 2
        num_elements = problem_def.elements_per_length_conductor
    elseif part isa AbstractConductorPart
        num_elements = problem_def.elements_per_length_conductor
    elseif part isa Insulator
        num_elements = problem_def.elements_per_length_insulator
    elseif part isa Semicon
        num_elements = problem_def.elements_per_length_semicon
    end

    skin_based_size = skin_depth / num_elements
    wavelength_based_size = wavelength / num_elements
    geometry_based_size = scale_length / num_elements
    arc_length_based_size = arc_length / num_elements
    # mesh_size = min(skin_based_size, wavelength_based_size, geometry_based_size, arc_length_based_size)

    mesh_size = min(geometry_based_size, arc_length_based_size)

    # Apply bounds from configuration
    mesh_size = max(mesh_size, problem_def.mesh_size_min)
    mesh_size = min(mesh_size, problem_def.mesh_size_max)

    return mesh_size
end

function calc_mesh_size(radius_in::Number, radius_ext::Number, material::Material, num_elements::Int, workspace::FEMWorkspace)
    # Extract material properties
    rho = to_nominal(material.rho)
    mu_r = to_nominal(material.mu_r)
    eps_r = to_nominal(material.eps_r)

    # Extract geometric properties
    thickness = radius_ext - radius_in

    # Extract problem_def parameters
    problem_def = workspace.problem_def
    freq = workspace.frequency

    # Calculate skin depth & wavelength
    skin_depth = calc_skin_depth(rho, mu_r, freq)
    wavelength = 1 / sqrt(ε₀ * eps_r * μ₀ * mu_r) / freq

    # Calculate mesh size based on part type and properties
    scale_length = thickness
    arc_length = 2 * π * radius_ext

    skin_based_size = skin_depth / num_elements
    wavelength_based_size = wavelength / num_elements
    geometry_based_size = scale_length / num_elements
    arc_length_based_size = arc_length / num_elements
    # @show mesh_size = min(skin_based_size, wavelength_based_size, geometry_based_size, arc_length_based_size)

    mesh_size = min(geometry_based_size, arc_length_based_size)

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
function _config_mesh_sizes(workspace::FEMWorkspace)

    gmsh.option.setNumber("General.InitialModule", 2)

    # Set mesh algorithm
    gmsh.option.setNumber("Mesh.Algorithm", workspace.problem_def.mesh_algorithm)

    # Set mesh optimization parameters
    gmsh.option.setNumber("Mesh.Optimize", 0)
    gmsh.option.setNumber("Mesh.OptimizeNetgen", 0)

    # Set mesh globals
    gmsh.option.setNumber("Mesh.SaveAll", 1)  # Mesh all regions
    gmsh.option.setNumber("Mesh.MeshSizeMin", workspace.problem_def.mesh_size_min)
    gmsh.option.setNumber("Mesh.MeshSizeMax", workspace.problem_def.mesh_size_max)
    gmsh.option.setNumber("Mesh.MeshSizeFromPoints", 1)
    gmsh.option.setNumber("Mesh.MeshSizeFromParametricPoints", 0)

    gmsh.option.setNumber("Mesh.MeshSizeExtendFromBoundary", 1)
    gmsh.option.setNumber("Mesh.MeshSizeFromCurvature", workspace.problem_def.points_per_circumference)


    _log(workspace, 2, "Mesh algorithm: $(workspace.problem_def.mesh_algorithm)")
    _log(workspace, 2, "Mesh size range: [$(workspace.problem_def.mesh_size_min), $(workspace.problem_def.mesh_size_max)]")
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

    # Set general visualization options
    gmsh.option.setNumber("Geometry.Points", 1)  # Show points
    gmsh.option.setNumber("Geometry.Curves", 1)  # Show curves
    gmsh.option.setNumber("Geometry.SurfaceLabels", 0)  # Show surface labels

    # Set OCC model healing options
    gmsh.option.setNumber("Geometry.AutoCoherence", 1)
    gmsh.option.setNumber("Geometry.OCCFixDegenerated", 1)
    gmsh.option.setNumber("Geometry.OCCFixSmallEdges", 1)
    gmsh.option.setNumber("Geometry.OCCFixSmallFaces", 1)
    gmsh.option.setNumber("Geometry.OCCSewFaces", 1)
    gmsh.option.setNumber("Geometry.OCCMakeSolids", 1)

    # Log settings based on verbosity
    _log(solver, 2, "Initialized Gmsh model: $case_id")

end
