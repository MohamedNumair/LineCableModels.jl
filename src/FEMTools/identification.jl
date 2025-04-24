"""
Entity identification functions for the FEMTools.jl module.
These functions handle the identification of entities after boolean operations.
"""

"""
$(TYPEDSIGNATURES)

Perform boolean fragmentation on all entities in the model.

# Arguments

- `workspace`: The [`FEMWorkspace`](@ref) containing the entities to fragment.

# Returns

- Nothing. Modifies the Gmsh model in place.

# Examples

```julia
$(FUNCTIONNAME)(workspace)
```

# Notes

This function performs boolean fragmentation on all surfaces and curves in the model.
After fragmentation, the original entities are replaced with new entities that respect
the intersections between them. The original entity tags are no longer valid after
this operation.
"""
function _process_fragments(workspace::FEMWorkspace)
    _log(workspace, 1, "Performing boolean fragmentation...")

    # Synchronize the model
    gmsh.model.occ.synchronize()

    # Get all surfaces and curves
    surfaces = gmsh.model.getEntities(2)  # dim=2 for surfaces
    curves = gmsh.model.getEntities(1)    # dim=1 for curves

    # Perform boolean fragmentation
    gmsh.model.occ.fragment(surfaces, curves)

    # Synchronize again after fragmentation
    gmsh.model.occ.synchronize()

    # Get updated counts
    new_surfaces = gmsh.model.getEntities(2)
    new_curves = gmsh.model.getEntities(1)

    _log(workspace, 1, "Boolean fragmentation completed")
    _log(workspace, 2, "Found $(length(surfaces)) surfaces and $(length(curves)) curves before fragmentation")
    _log(workspace, 2, "After fragmentation: $(length(new_surfaces)) surfaces and $(length(new_curves)) curves")
    _log(workspace, 2, "Unique markers in workspace: $(length(workspace.unassigned_entities)) markers")
end

# function _identify_by_marker(workspace::FEMWorkspace)
#     _log(workspace, 1, "Identifying entities after fragmentation...")

#     # Get all surfaces after fragmentation
#     all_surfaces = gmsh.model.getEntities(2)
#     _log(workspace, 2, "Total surfaces after fragmentation: $(length(all_surfaces))")

#     # Track statistics for reporting
#     total_markers = length(workspace.marker_map)
#     identified_count = 0
#     missed_markers = []

#     # For each marker point, find which surface contains it
#     for (marker, physical_group_tag) in workspace.marker_map
#         found_match = false

#         for (dim, tag) in all_surfaces
#             # Check if marker is inside this surface
#             if gmsh.model.isInside(dim, tag, marker) == 1
#                 # Found match - store identification
#                 elementary_name = workspace.name_map[marker]
#                 workspace.identified_entities[tag] = (physical_group_tag, elementary_name)
#                 found_match = true
#                 identified_count += 1
#                 _log(workspace, 2, "Marker at $(marker) identified entity $(tag) as $(elementary_name) (tag: $(physical_group_tag))")
#                 break
#             end
#         end

#         if !found_match
#             _log(workspace, 0, "WARNING: No entity found containing marker at $(marker) for physical tag $(physical_group_tag)")
#             push!(missed_markers, (marker, physical_group_tag))
#         end
#     end

#     # Report identification stats
#     _log(workspace, 1, "Entity identification completed: $(identified_count)/$(total_markers) markers matched ($(length(workspace.identified_entities)) entities identified)")

#     if !isempty(missed_markers)
#         _log(workspace, 0, "WARNING: $(length(missed_markers))/$(total_markers) markers could not be matched to entities")

#         # Show first 5 missed markers with their physical tags
#         if length(missed_markers) > 5
#             _log(workspace, 0, "First 5 missed markers: $(missed_markers[1:5])")
#         else
#             _log(workspace, 0, "Missed markers: $(missed_markers)")
#         end
#     end
# end

function _identify_by_marker(workspace::FEMWorkspace)
    _log(workspace, 1, "Identifying entities after fragmentation...")

    # Get all surfaces after fragmentation
    all_surfaces = gmsh.model.getEntities(2)

    # Track statistics
    total_entities = length(workspace.unassigned_entities)
    identified_count = 0

    # Copy keys to avoid modifying dict during iteration
    markers = collect(keys(workspace.unassigned_entities))

    # For each marker, find which surface contains it
    for marker in markers
        entity_data = workspace.unassigned_entities[marker]
        physical_group_tag = entity_data.core.physical_group_tag
        elementary_name = entity_data.core.elementary_name

        for (dim, tag) in all_surfaces
            # Check if marker is inside this surface
            if gmsh.model.isInside(dim, tag, marker) == 1
                # Found match - create FEMEntity and add to appropriate container
                fem_entity = FEMEntity(tag, entity_data)

                # Place in appropriate container
                if entity_data isa CablePartEntity
                    if entity_data.cable_part isa AbstractConductorPart
                        push!(workspace.conductors, fem_entity)
                    elseif entity_data.cable_part isa AbstractInsulatorPart
                        push!(workspace.insulators, fem_entity)
                    end
                elseif entity_data isa SpaceEntity
                    push!(workspace.space_regions, fem_entity)
                end

                # Remove from unassigned_entities
                delete!(workspace.unassigned_entities, marker)

                identified_count += 1
                _log(workspace, 2, "Marker at $(marker) identified entity $(tag) as $(elementary_name) (tag: $(physical_group_tag))")
                break
            end
        end
    end

    # Report identification stats
    _log(workspace, 1, "Entity identification completed: $(identified_count)/$(total_entities) entities identified")

    if !isempty(workspace.unassigned_entities)
        _log(workspace, 0, "WARNING: $(length(workspace.unassigned_entities))/$(total_entities) markers could not be matched to entities")
    end
end

function _assign_physical_groups(workspace::FEMWorkspace)
    _log(workspace, 1, "Assigning physical groups...")

    # Group entities by physical tag
    entities_by_physical_group_tag = Dict{Int,Vector{Int}}()

    # Process all entity containers
    for container in [workspace.conductors, workspace.insulators, workspace.space_regions]
        for entity in container
            physical_group_tag = entity.data.core.physical_group_tag
            elementary_name = entity.data.core.elementary_name

            if !haskey(entities_by_physical_group_tag, physical_group_tag)
                entities_by_physical_group_tag[physical_group_tag] = Int[]
            end

            # Add this entity to the collection for this physical tag
            push!(entities_by_physical_group_tag[physical_group_tag], entity.tag)

            if !isempty(elementary_name)
                # Append the complete name to the shape
                gmsh.model.set_entity_name(2, entity.tag, elementary_name)
            end

        end
    end

    # Create physical groups for each physical tag
    successful_groups = 0
    failed_groups = 0

    for (physical_group_tag, entity_tags) in entities_by_physical_group_tag
        # Find an entity with this tag to get the name
        physical_group_name = ""

        try
            _log(workspace, 2, "Creating physical group $(physical_group_name) (tag: $(physical_group_tag)) with $(length(entity_tags)) entities")
            gmsh.model.add_physical_group(2, entity_tags, physical_group_tag, physical_group_name)
            successful_groups += 1
        catch e
            _log(workspace, 0, "ERROR: Failed to create physical group tag: $(physical_group_tag): $(e)")
            failed_groups += 1
        end
    end

    _log(workspace, 1, "Physical groups assigned: $(successful_groups) successful, $(failed_groups) failed out of $(length(entities_by_physical_group_tag)) total")
end

# function _assign_physical_groups(workspace::FEMWorkspace)
#     _log(workspace, 1, "Assigning physical groups...")

#     # Group entities by physical tag
#     entities_by_physical_group_tag = Dict{Int,Vector{Int}}()
#     names_by_physical_group_tag = Dict{Int,String}()

#     for (tag, (physical_group_tag, elementary_name)) in workspace.identified_entities
#         if !haskey(entities_by_physical_group_tag, physical_group_tag)
#             entities_by_physical_group_tag[physical_group_tag] = Int[]
#             names_by_physical_group_tag[physical_group_tag] = elementary_name
#         end

#         # Add this entity to the collection for this physical tag
#         push!(entities_by_physical_group_tag[physical_group_tag], tag)

#         # Append the complete name to the shape
#         gmsh.model.set_entity_name(2, tag, elementary_name)
#     end

#     # Create physical groups for each physical tag
#     successful_groups = 0
#     failed_groups = 0

#     for (physical_group_tag, entities) in entities_by_physical_group_tag
#         elementary_name = names_by_physical_group_tag[physical_group_tag]

#         if occursin("_wire_", elementary_name)
#             elementary_name = replace(elementary_name, r"_wire_\d+" => "")
#         end

#         try
#             _log(workspace, 2, "Creating physical group $(elementary_name) (tag: $(physical_group_tag)) with $(length(entities)) entities")
#             gmsh.model.add_physical_group(2, entities, physical_group_tag, elementary_name)
#             successful_groups += 1
#         catch e
#             _log(workspace, 0, "ERROR: Failed to create physical group tag: $(physical_group_tag): $(e)")
#             failed_groups += 1
#         end

#     end

#     for (tag, (physical_group_tag, elementary_name)) in workspace.identified_entities
#         # gmsh.model.set_elementary_name(2, tag, elementary_name)
#         (r, g, b, a) = get_physical_group_color(workspace, physical_group_tag)
#         # gmsh.model.set_color(2, tag, r, g, b, a)
#     end

#     _log(workspace, 1, "Physical groups assigned: $(successful_groups) successful, $(failed_groups) failed out of $(length(entities_by_physical_group_tag)) total")
# end

# """
# $(TYPEDSIGNATURES)

# Identify entities after fragmentation using marker points.

# # Arguments

# - `workspace`: The [`FEMWorkspace`](@ref) containing the marker map.

# # Returns

# - Nothing. Updates the `identified_entities` map in the workspace.

# # Examples

# ```julia
# $(FUNCTIONNAME)(workspace)
# ```

# # Notes

# This function uses the marker points stored in the workspace to identify which
# fragmented entities correspond to the original entities. It does this by checking
# which entity contains each marker point.
# """
# function _identify_by_marker(workspace::FEMWorkspace)
#     _log(workspace, 1, "Identifying entities after fragmentation...")

#     # Get all surfaces after fragmentation
#     all_surfaces = gmsh.model.getEntities(2)

#     # For each marker point, find which surface contains it
#     for (marker, physical_group_tag) in workspace.marker_map
#         found_match = false

#         for (dim, tag) in all_surfaces
#             # Check if marker is inside this surface
#             if gmsh.model.isInside(dim, tag, marker) == 1
#                 # Found match - store identification
#                 elementary_name = workspace.name_map[marker]
#                 workspace.identified_entities[tag] = (physical_group_tag, elementary_name)
#                 found_match = true
#                 break
#             end
#         end

#         if !found_match
#             _log(workspace, 0, "Warning: No entity found containing marker at $(marker)")
#         end
#     end

#     _log(workspace, 1, "Entity identification completed: $(length(workspace.identified_entities)) entities identified")
# end

# """
# $(TYPEDSIGNATURES)

# Assign physical groups to identified entities.

# # Arguments

# - `workspace`: The [`FEMWorkspace`](@ref) containing the identified entities.

# # Returns

# - Nothing. Creates physical groups in the Gmsh model.

# # Examples

# ```julia
# $(FUNCTIONNAME)(workspace)
# ```

# # Notes

# This function creates physical groups for all identified entities, using the
# physical tags and names stored in the workspace. It also applies material
# properties to the ONELAB parameters if available.
# """
# function _assign_physical_groups(workspace::FEMWorkspace)
#     _log(workspace, 1, "Assigning physical groups...")

#     # Group entities by physical tag
#     entities_by_tag = Dict{Tuple{Int,String},Vector{Int}}()

#     for (tag, (physical_group_tag, elementary_name)) in workspace.identified_entities
#         key = (physical_group_tag, elementary_name)
#         if !haskey(entities_by_tag, key)
#             entities_by_tag[key] = Int[]
#         end
#         push!(entities_by_tag[key], tag)
#     end

#     # Create physical groups for each physical tag
#     for ((physical_group_tag, elementary_name), entities) in entities_by_tag
#         # All these entities belong to the same physical group
#         # Add them all at once to avoid duplication
#         gmsh.model.addPhysicalGroup(2, entities, physical_group_tag)
#     end

#     _log(workspace, 1, "Physical groups assigned: $(length(entities_by_tag)) groups")
# end

"""
$(TYPEDSIGNATURES)

Set material properties in ONELAB parameters.

# Arguments

- `tag`: Physical tag of the entity \\[dimensionless\\].
- `name`: Physical name of the entity.
- `material`: Material properties to set.

# Returns

- Nothing. Updates the ONELAB parameters.

# Examples

```julia
$(FUNCTIONNAME)(101210001, "cable_1_core_conductor_1", material)
```
"""
function _set_material_onelab(tag::Int, name::String, material::Material)
    # Convert material properties to strings
    rho = to_nominal(material.rho)
    eps_r = to_nominal(material.eps_r)
    mu_r = to_nominal(material.mu_r)

    # Format values for ONELAB
    rho_str = isinf(rho) ? "Inf" : string(rho)
    eps_r_str = string(eps_r)
    mu_r_str = string(mu_r)

    # Create ONELAB parameter for this material
    param_name = "Materials/$(name)"

    # Set parameters
    gmsh.onelab.setNumber(param_name + "/rho", [rho])
    gmsh.onelab.setNumber(param_name + "/eps_r", [eps_r])
    gmsh.onelab.setNumber(param_name + "/mu_r", [mu_r])

    # Set attributes
    gmsh.onelab.setString(param_name + "/Attributes", ["PhysicalTag=$(tag)"])
end
