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

    # Get all surfaces and curves
    surfaces = gmsh.model.getEntities(2)  # dim=2 for surfaces
    curves = gmsh.model.getEntities(1)    # dim=1 for curves

    # Perform boolean fragmentation
    gmsh.model.occ.fragment(surfaces, curves)

    # Remove duplicates after fragmentation
    _log(workspace, 2, "Removing duplicate entities after fragmentation...")
    gmsh.model.occ.remove_all_duplicates()

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
            if !(entity_data isa CurveEntity)
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
                    elseif entity_data isa SurfaceEntity
                        push!(workspace.space_regions, fem_entity)
                    end

                    delete!(workspace.unassigned_entities, marker)
                    identified_count += 1
                    _log(workspace, 2, "Marker at $(marker) identified entity $(tag) as $(elementary_name) (tag: $(physical_group_tag))")
                    break
                end
            end
        end
    end

    # Get all remaining curves after fragmentation
    all_curves = gmsh.model.getEntities(1)

    # Update keys to avoid modifying dict during iteration
    markers = collect(keys(workspace.unassigned_entities))

    # For each marker, find which surface contains it
    for marker in markers
        entity_data = workspace.unassigned_entities[marker]
        physical_group_tag = entity_data.core.physical_group_tag
        elementary_name = entity_data.core.elementary_name

        for (dim, tag) in all_curves
            # Check if marker is inside this curve
            if gmsh.model.isInside(dim, tag, marker) == 1
                # Found match - create FEMEntity and add to appropriate container
                fem_entity = FEMEntity(tag, entity_data)

                # Place in appropriate container
                if entity_data isa CurveEntity
                    push!(workspace.boundaries, fem_entity)
                end

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
    # Group entities by physical tag and dimension
    entities_by_physical_group_tag = Dict{Tuple{Int,Int},Vector{Int}}()

    # Process all entity containers
    for container in [workspace.conductors, workspace.insulators, workspace.space_regions, workspace.boundaries]
        for entity in container
            physical_group_tag = entity.data.core.physical_group_tag
            elementary_name = entity.data.core.elementary_name
            dim = entity.data isa CurveEntity ? 1 : 2

            # Key is now a tuple of (physical_group_tag, dimension)
            group_key = (physical_group_tag, dim)

            if !haskey(entities_by_physical_group_tag, group_key)
                entities_by_physical_group_tag[group_key] = Int[]
            end

            # Add this entity to the collection for this physical tag
            push!(entities_by_physical_group_tag[group_key], entity.tag)

            if !isempty(elementary_name)
                # Append the complete name to the shape
                gmsh.model.set_entity_name(dim, entity.tag, elementary_name)
            end
        end
    end

    # Create physical groups for each physical tag
    successful_groups = 0
    failed_groups = 0

    for ((physical_group_tag, dim), entity_tags) in entities_by_physical_group_tag
        try
            physical_group_name = create_physical_group_name(workspace, physical_group_tag)
            _log(workspace, 2, "Creating physical group $(physical_group_name) (tag: $(physical_group_tag), dim: $(dim)) with $(length(entity_tags)) entities")

            # Use the correct dimension when creating the physical group
            gmsh.model.add_physical_group(dim, entity_tags, physical_group_tag, physical_group_name)
            successful_groups += 1
        catch e
            _log(workspace, 0, "Failed to create physical group tag: $(physical_group_tag), dim: $(dim): $(e)")
            failed_groups += 1
        end
    end

    _log(workspace, 1, "Physical groups assigned: $(successful_groups) successful, $(failed_groups) failed out of $(length(entities_by_physical_group_tag)) total")
end

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
