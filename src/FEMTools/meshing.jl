"""
Mesh generation functions for the FEMTools.jl module.
These functions handle the configuration and generation of the mesh.
"""

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
function _calc_mesh_size(part::AbstractCablePart, workspace::FEMWorkspace)
    # Extract material properties
    # material = part.material_props
    # rho = to_nominal(material.rho)
    # mu_r = to_nominal(material.mu_r)
    # eps_r = to_nominal(material.eps_r)

    # Extract geometric properties
    radius_in = to_nominal(part.radius_in)
    radius_ext = to_nominal(part.radius_ext)
    thickness = radius_ext - radius_in

    # Extract formulation parameters
    formulation = workspace.formulation

    # Calculate skin depth & wavelength
    # freq = workspace.frequency
    # skin_depth = calc_skin_depth(rho, mu_r, freq)
    # wavelength = 1 / sqrt(ε₀ * eps_r * μ₀ * mu_r) / freq

    # Calculate mesh size based on part type and properties
    scale_length = thickness
    if part isa WireArray
        # For wire arrays, consider the wire radius
        scale_length = to_nominal(part.radius_wire) * 2
        num_elements = formulation.elements_per_length_conductor
    elseif part isa AbstractConductorPart
        num_elements = formulation.elements_per_length_conductor
    elseif part isa Insulator
        num_elements = formulation.elements_per_length_insulator
    elseif part isa Semicon
        num_elements = formulation.elements_per_length_semicon
    end

    # skin_based_size = skin_depth / num_elements
    # wavelength_based_size = wavelength / num_elements
    # mesh_size = min(skin_based_size, wavelength_based_size, geometry_based_size, arc_length_based_size)

    # Apply bounds from configuration
    mesh_size = scale_length / num_elements
    mesh_size = max(mesh_size, formulation.mesh_size_min)
    mesh_size = min(mesh_size, formulation.mesh_size_max)

    return mesh_size
end

function _calc_mesh_size(radius_in::Number, radius_ext::Number, material::Material, num_elements::Int, workspace::FEMWorkspace)
    # Extract material properties
    # rho = to_nominal(material.rho)
    # mu_r = to_nominal(material.mu_r)
    # eps_r = to_nominal(material.eps_r)

    # Extract geometric properties
    thickness = radius_ext - radius_in

    # Extract problem_def parameters
    formulation = workspace.formulation


    # Calculate skin depth & wavelength
    # freq = workspace.frequency
    # skin_depth = calc_skin_depth(rho, mu_r, freq)
    # wavelength = 1 / sqrt(ε₀ * eps_r * μ₀ * mu_r) / freq

    # Calculate mesh size based on part type and properties
    # scale_length = thickness
    # arc_length = 2 * π * radius_ext

    # skin_based_size = skin_depth / num_elements
    # wavelength_based_size = wavelength / num_elements
    # geometry_based_size = scale_length / num_elements
    # arc_length_based_size = arc_length / num_elements
    # @show mesh_size = min(skin_based_size, wavelength_based_size, geometry_based_size, arc_length_based_size)

    mesh_size = thickness / num_elements

    # Apply bounds from configuration
    mesh_size = max(mesh_size, formulation.mesh_size_min)
    mesh_size = min(mesh_size, formulation.mesh_size_max)

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
function config_mesh_options(workspace::FEMWorkspace)

    gmsh.option.setNumber("General.InitialModule", 2)

    # Set mesh algorithm
    gmsh.option.setNumber("Mesh.Algorithm", workspace.formulation.mesh_algorithm)

    # Set mesh optimization parameters
    gmsh.option.setNumber("Mesh.Optimize", 0)
    gmsh.option.setNumber("Mesh.OptimizeNetgen", 0)

    # Set mesh globals
    gmsh.option.setNumber("Mesh.SaveAll", 1)  # Mesh all regions
    gmsh.option.setNumber("Mesh.MeshSizeMin", workspace.formulation.mesh_size_min)
    gmsh.option.setNumber("Mesh.MeshSizeMax", workspace.formulation.mesh_size_max)
    gmsh.option.setNumber("Mesh.MeshSizeFromPoints", 1)
    gmsh.option.setNumber("Mesh.MeshSizeFromParametricPoints", 0)

    gmsh.option.setNumber("Mesh.MeshSizeExtendFromBoundary", 1)
    gmsh.option.setNumber("Mesh.MeshSizeFromCurvature", workspace.formulation.points_per_circumference)


    @debug "Mesh algorithm: $(workspace.formulation.mesh_algorithm)"
    @debug "Mesh size range: [$(workspace.formulation.mesh_size_min), $(workspace.formulation.mesh_size_max)]"
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
function _do_make_mesh(workspace::FEMWorkspace)
    # Generate 2D mesh
    gmsh.model.mesh.generate(2)

    # Get mesh statistics
    nodes = gmsh.model.mesh.getNodes()
    elements = gmsh.model.mesh.getElements()

    num_nodes = length(nodes[1])
    num_elements = sum(length.(elements[2]))

    @info "Mesh generation completed"
    @info "Created mesh with $(num_nodes) nodes and $(num_elements) elements"
end

"""
$(TYPEDSIGNATURES)

Initialize a Gmsh model with appropriate settings.

# Arguments

- `case_id`: Identifier for the model.
- `problem_def`: The [`FEMFormulation`](@ref) containing mesh parameters.
- `solver`: The [`FEMSolver`](@ref) containing visualization parameters.

# Returns

- Nothing. Initializes the Gmsh model.

# Examples

```julia
$(FUNCTIONNAME)("test_case", problem_def, solver)
```
"""
function initialize_gmsh(workspace::FEMWorkspace)
    # Create a new model
    system_id = workspace.problem_def.system.system_id
    gmsh.model.add(system_id)

    # Module launched on startup (0: automatic, 1: geometry, 2: mesh, 3: solver, 4: post-processing)
    gmsh.option.setNumber("General.InitialModule", 0)
    gmsh.option.setString("General.DefaultFileName", system_id * ".geo")

    # Define verbosity level
    gmsh.option.setNumber("General.Verbosity", workspace.opts.verbosity)

    # Set OCC model healing options
    gmsh.option.setNumber("Geometry.AutoCoherence", 1)
    gmsh.option.setNumber("Geometry.OCCFixDegenerated", 1)
    gmsh.option.setNumber("Geometry.OCCFixSmallEdges", 1)
    gmsh.option.setNumber("Geometry.OCCFixSmallFaces", 1)
    gmsh.option.setNumber("Geometry.OCCSewFaces", 1)
    gmsh.option.setNumber("Geometry.OCCMakeSolids", 1)

    # Log settings based on verbosity
    @info "Initialized Gmsh model: $system_id"

end

function make_mesh(workspace::FEMWorkspace)

    # Initialize Gmsh model and set parameters
    initialize_gmsh(workspace)

    # Create geometry
    @info "Creating domain boundaries..."
    make_space_geometry(workspace)

    @info "Creating cable geometry..."
    make_cable_geometry(workspace)

    # Synchronize the model
    gmsh.model.occ.synchronize()

    # Boolean operations
    @info "Performing boolean operations..."
    process_fragments(workspace)

    # Entity identification and entity assignment
    @info "Identifying entities after fragmentation..."
    identify_by_marker(workspace)

    # Physical group assignment
    @info "Assigning physical groups..."
    assign_physical_groups(workspace)

    # Mesh sizing
    @info "Setting up physics-based mesh sizing..."
    config_mesh_options(workspace)

    # Preview pre-meshing configuration if requested
    if workspace.opts.preview_geo
        @info "Launching geometry preview before meshing..."
        preview_mesh(workspace)
    end

    # Mesh generation
    @info "Generating mesh..."
    _do_make_mesh(workspace)

    # Save mesh
    @info "Saving mesh to file: $(workspace.paths[:mesh_file])"
    gmsh.write(workspace.paths[:mesh_file])

    # Save geometry
    @info "Saving geometry to file: $(workspace.paths[:geo_file])"
    gmsh.write(workspace.paths[:geo_file])
end