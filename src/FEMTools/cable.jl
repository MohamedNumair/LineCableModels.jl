"""
Cable geometry creation functions for the FEMTools.jl module.
These functions handle the creation of cable components.
"""

"""
$(TYPEDSIGNATURES)

Create the cable geometry for all cables in the system.

# Arguments

- `workspace`: The [`FEMWorkspace`](@ref) containing the model parameters.

# Returns

- Nothing. Updates the conductors and insulators vectors in the workspace.

# Examples

```julia
$(FUNCTIONNAME)(workspace)
```
"""
function _make_cable_geometry(workspace::FEMWorkspace)
    _log(workspace, 1, "Creating cable geometry...")

    # Get the cable system
    cable_system = workspace.cable_system

    # Process each cable in the system
    for (cable_idx, cabledef) in enumerate(cable_system.cables)
        _log(workspace, 1, "Processing cable $(cable_idx) at position ($(cabledef.horz), $(cabledef.vert))")

        # Get the cable design
        cable_design = cabledef.cable

        # Get the phase assignments
        phase_assignments = cabledef.conn

        # Process each component in the cable
        for (comp_idx, component) in enumerate(cable_design.components)
            # Get the component ID
            comp_id = component.id

            # Get the phase assignment for this component
            phase = comp_idx <= length(phase_assignments) ? phase_assignments[comp_idx] : 0

            _log(workspace, 2, "Processing component $(comp_id) (phase $(phase))")

            # Process conductor group
            if !isnothing(component.conductor_group)
                _log(workspace, 2, "Processing conductor group for component $(comp_id)")

                # Process each layer in the conductor group
                for (layer_idx, layer) in enumerate(component.conductor_group.layers)
                    _log(workspace, 2, "Processing conductor layer $(layer_idx)")

                    # Create the cable part
                    _make_cablepart!(workspace, layer, cable_idx, comp_idx, comp_id, phase, layer_idx)
                end
            end

            # Process insulator group
            if !isnothing(component.insulator_group)
                _log(workspace, 2, "Processing insulator group for component $(comp_id)")

                # Process each layer in the insulator group
                for (layer_idx, layer) in enumerate(component.insulator_group.layers)
                    _log(workspace, 2, "Processing insulator layer $(layer_idx)")

                    # Create the cable part
                    _make_cablepart!(workspace, layer, cable_idx, comp_idx, comp_id, phase, layer_idx)
                end
            end
        end
    end

    _log(workspace, 1, "Cable geometry created")
end

"""
$(TYPEDSIGNATURES)

Create a cable part entity for all tubular shapes.

# Arguments

- `workspace`: The [`FEMWorkspace`](@ref) containing the model parameters.
- `part`: The [`AbstractCablePart`](@ref) to create.
- `cable_idx`: The index of the cable.
- `comp_idx`: The index of the component.
- `comp_id`: The ID of the component.
- `phase`: The phase assignment.
- `layer_idx`: The index of the layer.

# Returns

- Nothing. Updates the conductors or insulators vector in the workspace.

# Examples

```julia
$(FUNCTIONNAME)(workspace, part, 1, 1, "core", 1, 1)
```
"""
function _make_cablepart!(workspace::FEMWorkspace, part::AbstractCablePart,
    cable_idx::Int, comp_idx::Int, comp_id::String,
    phase::Int, layer_idx::Int)

    # Get the cable definition
    cabledef = workspace.cable_system.cables[cable_idx]

    # Get the center coordinates
    x_center = cabledef.horz
    y_center = cabledef.vert

    # Determine material group directly from part type
    material_group = get_material_group(part)

    # Get or register material ID
    material_id = get_or_register_material_id(workspace, part.material_props)

    # Create physical tag with new encoding scheme
    physical_group_tag = encode_physical_group_tag(
        1,              # Surface type 1 = cable component
        cable_idx,      # Cable number
        comp_idx,       # Component number
        material_group, # Material group from part type
        material_id     # Material ID from registry
    )

    # Calculate mesh size for this part
    mesh_size = calc_mesh_size(part, workspace)

    # Create physical name
    part_type = lowercase(string(nameof(typeof(part))))
    elementary_name = create_cable_elementary_name(
        cable_idx=cable_idx,
        component_id=comp_id,
        group_type=material_group,
        part_type=part_type,
        layer_idx=layer_idx,
        phase=phase
    )

    # Extract parameters
    radius_in = to_nominal(part.radius_in)
    radius_ext = to_nominal(part.radius_ext)

    # Create annular shape and assign marker
    if radius_in ≈ 0
        # Solid disk
        marker = _get_disk_marker(x_center, y_center)
        entity_tag = _draw_disk(x_center, y_center, radius_ext, mesh_size)
    else
        # Annular shape
        marker = _get_annular_marker(x_center, y_center, radius_in, radius_ext)
        entity_tag = _draw_annular(x_center, y_center, radius_in, radius_ext, mesh_size)
    end

    # Create entity data
    core_data = CoreEntityData(physical_group_tag, elementary_name, mesh_size)
    entity_data = CablePartEntity(core_data, part)

    # Add to workspace in the unassigned container for subsequent processing
    workspace.unassigned_entities[marker] = entity_data

end

"""
$(TYPEDSIGNATURES)

Specialized method to create individual wire entities for `WireArray` parts.

# Arguments

- `workspace`: The [`FEMWorkspace`](@ref) containing the model parameters.
- `part`: The [`WireArray`](@ref)  to create.
- `cable_idx`: The index of the cable.
- `comp_idx`: The index of the component.
- `comp_id`: The ID of the component.
- `phase`: The phase assignment.
- `layer_idx`: The index of the layer.

# Returns

- Nothing. Updates the conductors vector in the workspace.

# Examples

```julia
$(FUNCTIONNAME)(workspace, part, 1, 1, "core", 1, 1)
```
"""
function _make_cablepart!(workspace::FEMWorkspace, part::WireArray,
    cable_idx::Int, comp_idx::Int, comp_id::String,
    phase::Int, layer_idx::Int)

    # Get the cable definition
    cabledef = workspace.cable_system.cables[cable_idx]

    # Get the center coordinates
    x_center = cabledef.horz
    y_center = cabledef.vert

    # Determine material group directly from part type
    material_group = get_material_group(part)

    # Get or register material ID
    material_id = get_or_register_material_id(workspace, part.material_props)

    # Create physical tag with new encoding scheme
    physical_group_tag = encode_physical_group_tag(
        1,              # Surface type 1 = cable component
        cable_idx,      # Cable number
        comp_idx,       # Component number
        material_group, # Material group from part type
        material_id     # Material ID from registry
    )

    # Calculate mesh size for this part
    mesh_size = calc_mesh_size(part, workspace)

    #
    # First handle the wires
    #

    # Create physical name
    part_type = lowercase(string(nameof(typeof(part))))

    # Extract parameters
    radius_in = to_nominal(part.radius_in)

    radius_wire = to_nominal(part.radius_wire)
    num_wires = part.num_wires
    lay_radius = num_wires == 1 ? 0 : to_nominal(part.radius_in)

    # Calculate wire positions
    wire_positions = calc_wirearray_coords(num_wires, radius_wire, lay_radius, C=(x_center, y_center))


    # Create wires
    for (wire_idx, (wx, wy)) in enumerate(wire_positions)
        # Create wire marker
        marker = _get_disk_marker(wx, wy)

        # Create wire disk
        entity_tag = _draw_disk(wx, wy, radius_wire, mesh_size)

        # Create wire name
        elementary_name = create_cable_elementary_name(
            cable_idx=cable_idx,
            component_id=comp_id,
            group_type=material_group,
            part_type=part_type,
            layer_idx=layer_idx,
            phase=phase,
            wire_idx=wire_idx
        )

        # Create entity data
        core_data = CoreEntityData(physical_group_tag, elementary_name, mesh_size)
        entity_data = CablePartEntity(core_data, part)

        # Add to workspace
        workspace.unassigned_entities[marker] = entity_data
    end

    #
    # Then those nasty air gaps, the cause of this entire suffering
    #

    # Air gaps will be determined from the boolean fragmentation operation and do not need to be drawn. Only the markers are needed.
    markers_air_gap = _get_air_gap_markers(num_wires, radius_wire, radius_in)

    # Adjust air gap markers to cable center
    for marker in markers_air_gap
        marker[1] += x_center
        marker[2] += y_center
    end

    # Determine material group - air gaps map to insulators
    material_group = 2

    # Get air material
    air_material = get_air_material(workspace)

    # Get or register material ID
    material_id = get_or_register_material_id(workspace, air_material)

    # Create physical tag with new encoding scheme
    physical_group_tag_air_gap = encode_physical_group_tag(
        1,              # Surface type 1 = cable component
        cable_idx,      # Cable number
        comp_idx,       # Component number
        material_group, # Material group from part type
        material_id     # Material ID from registry
    )

    # Calculate mesh size for this part
    mesh_size = calc_mesh_size(part, workspace)

    for marker in markers_air_gap
        # elementary names are not assigned to the air gaps because they are not drawn and appear as a result of the boolean operation
        core_data = CoreEntityData(physical_group_tag_air_gap, "", mesh_size)
        entity_data = SurfaceEntity(core_data, air_material)

        # Add to unassigned entities with type information
        workspace.unassigned_entities[marker] = entity_data
    end

end