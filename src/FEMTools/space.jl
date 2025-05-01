"""
Domain creation functions for the FEMTools.jl module.
These functions handle the creation of domain boundaries and earth interfaces.
"""

"""
$(TYPEDSIGNATURES)

Create the domain boundaries (inner solid disk and outer annular region) for the simulation.

# Arguments

- `workspace`: The [`FEMWorkspace`](@ref) containing the model parameters.

# Returns

- Nothing. Updates the boundaries vector in the workspace.

# Examples

```julia
$(FUNCTIONNAME)(workspace)
```
"""
function _make_space_geometry(workspace::FEMWorkspace)
    _log(workspace, 1, "Creating domain boundaries...")

    # Extract parameters
    problem_def = workspace.problem_def
    domain_radius = problem_def.domain_radius
    domain_radius_inf = domain_radius * 1.25  # External radius for boundary transform
    mesh_size_default = problem_def.mesh_size_default
    mesh_size_domain = problem_def.mesh_size_max
    mesh_size_inf = 1.25 * problem_def.mesh_size_max

    # Center coordinates
    x_center = 0.0
    y_center = 0.0

    # Create inner domain disk
    num_points_circumference = workspace.problem_def.points_per_circumference
    _log(workspace, 2, "Creating inner domain disk with radius $(domain_radius) m")
    _, _, air_region_marker = _draw_disk(x_center, y_center, domain_radius, mesh_size_domain, num_points_circumference)

    # Create outer domain annular region
    _log(workspace, 2, "Creating outer domain annular region with radius $(domain_radius_inf) m")
    _, _, air_infshell_marker = _draw_annular(x_center, y_center, domain_radius, domain_radius_inf, mesh_size_inf, num_points_circumference)

    # Get earth model from workspace
    earth_model = workspace.cable_system.earth_props
    air_layer_idx = 1 # air layer is 1 by default
    earth_layer_idx = workspace.cable_system.earth_props.num_layers

    # Air layer (Layer 1)
    air_material = get_space_material(workspace, air_layer_idx)
    air_material_id = get_or_register_material_id(workspace, air_material)
    air_material_group = get_material_group(earth_model, air_layer_idx) # Will return 2 (insulator)

    # Physical domain air tag 
    air_region_tag = encode_physical_group_tag(
        2,                # Surface type 2 = physical domain
        air_layer_idx,    # Layer 1 = air
        0,                # Component 0 (not a cable component)
        air_material_group, # Material group 2 (insulator)
        air_material_id   # Material ID
    )
    air_region_name = create_physical_group_name(workspace, air_region_tag)

    # Infinite shell air tag
    air_infshell_tag = encode_physical_group_tag(
        3,                # Surface type 3 = infinite shell
        air_layer_idx,    # Layer 1 = air
        0,                # Component 0 (not a cable component)
        air_material_group, # Material group 2 (insulator)
        air_material_id   # Material ID
    )
    air_infshell_name = create_physical_group_name(workspace, air_infshell_tag)


    # Earth layer (Layer 2+)
    earth_material = get_space_material(workspace, earth_layer_idx)
    earth_material_id = get_or_register_material_id(workspace, earth_material)
    earth_material_group = get_material_group(earth_model, earth_layer_idx) # Will return 1 (conductor)

    # Physical domain earth tag
    earth_region_tag = encode_physical_group_tag(
        2,                  # Surface type 2 = physical domain
        earth_layer_idx,    # Layer 2 = first earth layer
        0,                  # Component 0 (not a cable component)
        earth_material_group, # Material group 1 (conductor)
        earth_material_id   # Material ID
    )
    earth_region_name = create_physical_group_name(workspace, earth_region_tag)

    # Infinite shell earth tag
    earth_infshell_tag = encode_physical_group_tag(
        3,                  # Surface type 3 = infinite shell
        earth_layer_idx,    # Layer 2 = first earth layer
        0,                  # Component 0 (not a cable component)
        earth_material_group, # Material group 1 (conductor)
        earth_material_id   # Material ID
    )
    earth_infshell_name = create_physical_group_name(workspace, earth_infshell_tag)


    # Create group tags for boundary curves - above ground (air) - inner domain
    air_boundary_tag = encode_boundary_tag(1, air_layer_idx, 1)
    air_boundary_name = create_physical_group_name(workspace, air_boundary_tag)
    air_boundary_marker = [0.0, domain_radius, 0.0]

    # Below ground (earth) - inner domain
    earth_boundary_tag = encode_boundary_tag(1, earth_layer_idx, 1)
    earth_boundary_name = create_physical_group_name(workspace, earth_boundary_tag)
    earth_boundary_marker = [0.0, -domain_radius, 0.0]

    # Above ground (air) - domain -> infinity
    air_infty_tag = encode_boundary_tag(2, air_layer_idx, 1)
    air_infty_name = create_physical_group_name(workspace, air_infty_tag)
    air_infty_marker = [0.0, domain_radius_inf, 0.0]

    # Below ground (earth) - domain -> infinity
    earth_infty_tag = encode_boundary_tag(2, earth_layer_idx, 1)
    earth_infty_name = create_physical_group_name(workspace, earth_infty_tag)
    earth_infty_marker = [0.0, -domain_radius_inf, 0.0]

    # Create markers for the domain surfaces
    earth_region_marker = [0.0, -domain_radius * 0.99, 0.0]
    marker_tag = gmsh.model.occ.add_point(earth_region_marker[1], earth_region_marker[2], earth_region_marker[3], mesh_size_domain)
    gmsh.model.set_entity_name(0, marker_tag, "marker_$(round(mesh_size_domain, sigdigits=6))")

    earth_infshell_marker = [0.0, -(domain_radius + 0.99 * (domain_radius_inf - domain_radius)), 0.0]
    marker_tag = gmsh.model.occ.add_point(earth_infshell_marker[1], earth_infshell_marker[2], earth_infshell_marker[3], mesh_size_inf)
    gmsh.model.set_entity_name(0, marker_tag, "marker_$(round(mesh_size_inf, sigdigits=6))")

    # Create boundary curves
    air_boundary_entity = CurveEntity(
        CoreEntityData(air_boundary_tag, air_boundary_name, mesh_size_domain),
        air_material
    )

    earth_boundary_entity = CurveEntity(
        CoreEntityData(earth_boundary_tag, earth_boundary_name, mesh_size_domain),
        earth_material
    )

    air_infty_entity = CurveEntity(
        CoreEntityData(air_infty_tag, air_infty_name, mesh_size_inf),
        air_material
    )

    earth_infty_entity = CurveEntity(
        CoreEntityData(earth_infty_tag, earth_infty_name, mesh_size_inf),
        earth_material
    )

    # Add surfaces to the workspace
    workspace.unassigned_entities[air_boundary_marker] = air_boundary_entity
    workspace.unassigned_entities[air_infty_marker] = air_infty_entity
    workspace.unassigned_entities[earth_boundary_marker] = earth_boundary_entity
    workspace.unassigned_entities[earth_infty_marker] = earth_infty_entity

    # Create domain surfaces
    air_region_entity = SurfaceEntity(
        CoreEntityData(air_region_tag, air_region_name, mesh_size_default),
        air_material
    )

    air_infshell_entity = SurfaceEntity(
        CoreEntityData(air_infshell_tag, air_infshell_name, mesh_size_default),
        air_material
    )

    # Earth regions will be created after boolean fragmentation
    earth_region_entity = SurfaceEntity(
        CoreEntityData(earth_region_tag, earth_region_name, mesh_size_default),
        earth_material
    )

    earth_infshell_entity = SurfaceEntity(
        CoreEntityData(earth_infshell_tag, earth_infshell_name, mesh_size_default),
        earth_material
    )

    # Add surfaces to the workspace
    workspace.unassigned_entities[air_region_marker] = air_region_entity
    workspace.unassigned_entities[air_infshell_marker] = air_infshell_entity
    workspace.unassigned_entities[earth_region_marker] = earth_region_entity
    workspace.unassigned_entities[earth_infshell_marker] = earth_infshell_entity

    _log(workspace, 1, "Domain boundaries created")

    # Create earth interface line (y=0)
    _log(workspace, 2, "Creating earth interface line at y=0")

    # Create line from -domain_radius to +domain_radius at y=0
    num_elements = workspace.problem_def.elements_per_length_interfaces
    earth_interface_mesh_size = calc_mesh_size(0, domain_radius, earth_material, num_elements, workspace)

    _, _, earth_interface_marker = _draw_line(-domain_radius_inf, 0.0, domain_radius_inf, 0.0, earth_interface_mesh_size, round(Int, domain_radius))

    # Create physical tag for the earth interface
    interface_idx = 1  # Earth interface index
    earth_interface_tag = encode_boundary_tag(3, interface_idx, 1)
    earth_interface_name = create_physical_group_name(workspace, earth_interface_tag)

    # Create domain entity
    earth_interface_entity = CurveEntity(
        CoreEntityData(earth_interface_tag, earth_interface_name, earth_interface_mesh_size),
        get_space_material(workspace, earth_layer_idx)  # Earth material
    )

    # Create a transition region between the cables and the surrounding earth
    # TODO: Transition regions should use the specific earth layer properties
    # Issue URL: https://github.com/Electa-Git/LineCableModels.jl/issues/6
    cable_system = workspace.cable_system
    all_cables = collect(1:length(cable_system.cables))
    (cx, cy, bounding_radius, characteristic_len) = _get_system_centroid(cable_system, all_cables)
    n_regions = 3  # number of regions
    r_min = bounding_radius + 1e-3
    r_max = bounding_radius + abs(cy) / 2
    transition_radii = collect(LinRange(r_min, r_max, n_regions))
    mesh_size_min = earth_interface_mesh_size / 100 #characteristic_len / workspace.problem_def.elements_per_length_insulator
    mesh_size_max = earth_interface_mesh_size
    transition_mesh = collect(LinRange(mesh_size_min, mesh_size_max, n_regions))
    _, _, earth_transition_markers = _draw_transition_region(cx, cy, transition_radii, transition_mesh, num_points_circumference)

    # Register transition regions in the workspace
    for k in 1:n_regions
        earth_transition_region = SurfaceEntity(
            CoreEntityData(earth_region_tag, earth_region_name, transition_mesh[k]),
            earth_material
        )
        # Register the surface entity with its corresponding marker
        workspace.unassigned_entities[earth_transition_markers[k]] = earth_transition_region

        # Optional logging
        _log(workspace, 2, "Created transition region $k with radius $(transition_radii[k]) m")
    end

    _log(workspace, 1, "Transition regions created")

    # Add interface to the workspace
    workspace.unassigned_entities[earth_interface_marker] = earth_interface_entity
    _log(workspace, 1, "Earth interfaces created")

end