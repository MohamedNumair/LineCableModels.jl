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

    # Center coordinates
    x_center = 0.0
    y_center = 0.0

    # Create inner domain disk
    _log(workspace, 2, "Creating inner domain disk with radius $(domain_radius) m")
    inner_disk = _draw_disk(x_center, y_center, domain_radius, mesh_size_default)

    # Create outer domain annular region
    _log(workspace, 2, "Creating outer domain annular region with radius $(domain_radius_inf) m")
    outer_shell = _draw_annular(x_center, y_center, domain_radius, domain_radius_inf, mesh_size_default)

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
    air_region_name = create_physical_group_name(workspace, air_region_tag)#create_space_elementary_name(air_layer_idx)

    # Infinite shell air tag
    air_infshell_tag = encode_physical_group_tag(
        3,                # Surface type 3 = infinite shell
        air_layer_idx,    # Layer 1 = air
        0,                # Component 0 (not a cable component)
        air_material_group, # Material group 2 (insulator)
        air_material_id   # Material ID
    )
    air_infshell_name = create_physical_group_name(workspace, air_infshell_tag) #create_infshell_elementary_name(air_layer_idx)


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
    earth_region_name = create_physical_group_name(workspace, earth_region_tag)  #create_space_elementary_name(earth_layer_idx)


    # Infinite shell earth tag
    earth_infshell_tag = encode_physical_group_tag(
        3,                  # Surface type 3 = infinite shell
        earth_layer_idx,    # Layer 2 = first earth layer
        0,                  # Component 0 (not a cable component)
        earth_material_group, # Material group 1 (conductor)
        earth_material_id   # Material ID
    )
    earth_infshell_name = create_physical_group_name(workspace, earth_infshell_tag)  #create_infshell_elementary_name(earth_layer_idx)


    # Create group tags for boundary curves
    # Above ground (air) - inner domain
    air_boundary_tag = encode_boundary_tag(1, air_layer_idx, 1)
    air_boundary_name = create_physical_group_name(workspace, air_boundary_tag)#create_boundary_elementary_name(air_layer_idx, false)
    air_boundary_marker = [0.0, domain_radius, 0.0]

    # Below ground (earth) - inner domain
    earth_boundary_tag = encode_boundary_tag(1, earth_layer_idx, 1)
    earth_boundary_name = create_physical_group_name(workspace, earth_boundary_tag) #create_boundary_elementary_name(earth_layer_idx, false)
    earth_boundary_marker = [0.0, -domain_radius, 0.0]

    # Above ground (air) - domain -> infinity
    air_infty_tag = encode_boundary_tag(2, air_layer_idx, 1)
    air_infty_name = create_physical_group_name(workspace, air_infty_tag) #create_boundary_elementary_name(air_layer_idx, true)
    air_infty_marker = [0.0, domain_radius_inf, 0.0]

    # Below ground (earth) - domain -> infinity
    earth_infty_tag = encode_boundary_tag(2, earth_layer_idx, 1)
    earth_infty_name = create_physical_group_name(workspace, earth_infty_tag)  #create_boundary_elementary_name(earth_layer_idx, true)
    earth_infty_marker = [0.0, -domain_radius_inf, 0.0]

    # Create markers for the domain surfaces
    air_region_marker = _get_midpoint_marker(0, 0, domain_radius)
    earth_region_marker = _get_midpoint_marker(0, 0, -domain_radius)
    air_infshell_marker = _get_midpoint_marker(0, domain_radius, domain_radius_inf)
    earth_infshell_marker = _get_midpoint_marker(0, -domain_radius_inf, -domain_radius)

    # Create boundary curves
    air_boundary_entity = CurveEntity(
        CoreEntityData(air_boundary_tag, air_boundary_name, mesh_size_default),
        get_space_material(workspace, air_layer_idx)
    )

    earth_boundary_entity = CurveEntity(
        CoreEntityData(earth_boundary_tag, earth_boundary_name, mesh_size_default),
        get_space_material(workspace, earth_layer_idx)
    )

    air_infty_entity = CurveEntity(
        CoreEntityData(air_infty_tag, air_infty_name, mesh_size_default),
        get_space_material(workspace, air_layer_idx)
    )

    earth_infty_entity = CurveEntity(
        CoreEntityData(earth_infty_tag, earth_infty_name, mesh_size_default),
        get_space_material(workspace, earth_layer_idx)
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
    earth_interface_line = _draw_line(-domain_radius_inf, 0.0, domain_radius_inf, 0.0, mesh_size_default)

    # Create physical tag for the earth interface
    interface_idx = 1  # Earth interface index
    earth_interface_tag = encode_boundary_tag(3, interface_idx, 1)
    earth_interface_name = create_physical_group_name(workspace, earth_interface_tag)   #create_interface_elementary_name(interface_idx)

    # Create marker for the earth interface
    earth_interface_marker = [0.0, 0.0, 0.0]

    # Create domain entity
    earth_interface_entity = CurveEntity(
        CoreEntityData(earth_interface_tag, earth_interface_name, mesh_size_default),
        get_space_material(workspace, earth_layer_idx)  # Earth material
    )

    # Add interface to the workspace
    workspace.unassigned_entities[earth_interface_marker] = earth_interface_entity
    _log(workspace, 1, "Earth interfaces created")

end