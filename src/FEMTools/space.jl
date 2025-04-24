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
    formulation = workspace.formulation
    domain_radius = formulation.domain_radius
    domain_radius_inf = domain_radius * 1.25  # External radius for boundary transform
    mesh_size_default = formulation.mesh_size_default
    earth_layer_idx = workspace.cable_system.earth_props.num_layers

    # Center coordinates
    x_center = 0.0
    y_center = 0.0

    # Create inner domain disk
    _log(workspace, 2, "Creating inner domain disk with radius $(domain_radius) m")
    inner_disk = _draw_disk(x_center, y_center, domain_radius, mesh_size_default)

    # Create outer domain annular region
    _log(workspace, 2, "Creating outer domain annular region with radius $(domain_radius_inf) m")
    outer_shell = _draw_annular(x_center, y_center, domain_radius, domain_radius_inf, mesh_size_default)

    # Create physical tags and names for physical surfaces
    # Above ground (air) - inner domain
    air_layer_idx = 1 # air layer is 1 by default
    surface_type = 0  # global physical medium
    air_boundary_tag = encode_boundary_tag(air_layer_idx, false)
    air_boundary_name = create_boundary_elementary_name(air_layer_idx, false)
    air_region_tag = encode_medium_tag(air_layer_idx, surface_type)
    air_region_name = create_medium_elementary_name(air_layer_idx)

    # Below ground (earth) - inner domain
    earth_boundary_tag = encode_boundary_tag(earth_layer_idx, false)
    earth_boundary_name = create_boundary_elementary_name(earth_layer_idx, false)
    earth_region_tag = encode_medium_tag(earth_layer_idx, surface_type)
    earth_region_name = create_medium_elementary_name(earth_layer_idx)

    # Above ground (air) - domain -> infinity
    surface_type = 2  # infinite shell
    air_infty_tag = encode_boundary_tag(air_layer_idx, true)
    air_infty_name = create_boundary_elementary_name(air_layer_idx, true)
    air_infshell_tag = encode_medium_tag(air_layer_idx, surface_type)
    air_infshell_name = create_infshell_elementary_name(air_layer_idx)

    # Below ground (earth) - domain -> infinity
    earth_infty_tag = encode_boundary_tag(earth_layer_idx, true)
    earth_infty_name = create_boundary_elementary_name(earth_layer_idx, true)
    earth_infshell_tag = encode_medium_tag(earth_layer_idx, surface_type)
    earth_infshell_name = create_infshell_elementary_name(earth_layer_idx)

    # Create markers for the domains
    air_region_marker = _get_midpoint_marker(0, 0, domain_radius)
    earth_region_marker = _get_midpoint_marker(0, 0, -domain_radius)

    air_infshell_marker = _get_midpoint_marker(0, domain_radius, domain_radius_inf)
    earth_infshell_marker = _get_midpoint_marker(0, -domain_radius_inf, -domain_radius)

    # Get materials for the domains
    air_material = get_space_material(workspace, air_layer_idx)
    earth_material = get_space_material(workspace, earth_layer_idx)

    # Create domain entities
    air_region_entity = SpaceEntity(
        CoreEntityData(air_region_tag, air_region_name, mesh_size_default),
        air_material
    )

    air_infshell_entity = SpaceEntity(
        CoreEntityData(air_infshell_tag, air_infshell_name, mesh_size_default),
        air_material
    )

    # Earth regions will be created after boolean fragmentation
    earth_region_entity = SpaceEntity(
        CoreEntityData(earth_region_tag, earth_region_name, mesh_size_default),
        earth_material
    )

    earth_infshell_entity = SpaceEntity(
        CoreEntityData(earth_infshell_tag, earth_infshell_name, mesh_size_default),
        earth_material
    )

    # Add entities to the workspace
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
    earth_interface_tag = encode_interface_tag(interface_idx)
    earth_interface_name = create_interface_elementary_name(interface_idx)

    # # Create marker for the earth interface
    earth_interface_marker = [0.0, 0.0, 0.0]  # At origin

    # # Create domain entity
    # earth_interface_entity = SpaceEntity(
    #     CoreEntityData(earth_interface_tag, earth_interface_name, mesh_size_default),
    #     get_space_material(workspace, earth_layer_idx)  # Earth material
    # )

    # # Add entity to the workspace
    # workspace.unassigned_entities[earth_interface_marker] = earth_interface_entity
    _log(workspace, 1, "Earth interfaces created")

end