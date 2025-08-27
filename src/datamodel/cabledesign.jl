import ..LineCableModels: add!



"""
$(TYPEDEF)

Represents the design of a cable, including its unique identifier, nominal data, and components.

$(TYPEDFIELDS)
"""
mutable struct CableDesign
    "Unique identifier for the cable design."
    cable_id::String
    "Informative reference data."
    nominal_data::NominalData
    "Vector of cable components."
    components::Vector{CableComponent}

    @doc """
    $(TYPEDSIGNATURES)

    Constructs a [`CableDesign`](@ref) instance.

    # Arguments

    - `cable_id`: Unique identifier for the cable design.
    - `component`: Initial [`CableComponent`](@ref) for the design.
    - `nominal_data`: Reference data for the cable design. Default: `NominalData()`.

    # Returns

    - A [`CableDesign`](@ref) object with the specified properties.

    # Examples

    ```julia
    conductor_group = ConductorGroup(central_conductor)
    insulator_group = InsulatorGroup(main_insulator)
    component = CableComponent(conductor_group, insulator_group)
    design = $(FUNCTIONNAME)("example", component)
    ```

    # See also

    - [`CableComponent`](@ref)
    - [`ConductorGroup`](@ref)
    - [`InsulatorGroup`](@ref)
    """
    function CableDesign(
        cable_id::String,
        component::CableComponent;
        nominal_data::NominalData=NominalData(),
    )
        return new(cable_id, nominal_data, [component])
    end
end

"""
$(TYPEDSIGNATURES)

Constructs a [`CableDesign`](@ref) instance from conductor and insulator groups.

# Arguments

- `cable_id`: Unique identifier for the cable design.
- `conductor_group`: The [`ConductorGroup`](@ref) for the component.
- `insulator_group`: The [`InsulatorGroup`](@ref) for the component.
- `component_id`: ID for the cable component. Default: "core".
- `nominal_data`: Reference data for the cable design. Default: `NominalData()`.

# Returns

- A [`CableDesign`](@ref) object with the specified properties.

# Examples

```julia
conductor_group = ConductorGroup(central_conductor)
insulator_group = InsulatorGroup(main_insulator)
design = $(FUNCTIONNAME)("example", conductor_group, insulator_group)
```
"""
function CableDesign(
    cable_id::String,
    conductor_group::ConductorGroup,
    insulator_group::InsulatorGroup;
    component_id::String="component1",
    nominal_data::NominalData=NominalData(),
)
    component = CableComponent(component_id, conductor_group, insulator_group)
    return CableDesign(cable_id, nominal_data, [component])
end


"""
$(TYPEDSIGNATURES)

Adds a cable component to an existing [`CableDesign`](@ref).

# Arguments

- `design`: A [`CableDesign`](@ref) object where the component will be added.
- `component`: A [`CableComponent`](@ref) to add to the design.

# Returns

- The modified [`CableDesign`](@ref) object.

# Notes

If a component with the same ID already exists, it will be overwritten, and a warning will be logged.

# Examples

```julia
conductor_group = ConductorGroup(wire_array)
insulator_group = InsulatorGroup(insulation)
component = CableComponent("sheath", conductor_group, insulator_group)
$(FUNCTIONNAME)(design, component)
```

# See also

- [`CableDesign`](@ref)
- [`CableComponent`](@ref)
"""
function add!(
    design::CableDesign,
    component::CableComponent,
)
    # Check for existing component with same ID
    existing_idx = findfirst(comp -> comp.id == component.id, design.components)

    if !isnothing(existing_idx)
        @warn "Component with ID '$(component.id)' already exists in the CableDesign and will be overwritten."
        design.components[existing_idx] = component
    else
        # Add new component to the vector
        push!(design.components, component)
    end

    return design
end

"""
$(TYPEDSIGNATURES)

Adds a cable component to an existing [`CableDesign`](@ref) using separate conductor and insulator groups. Performs as a convenience wrapper to construct the [`CableComponent`](@ref) object with reduced boilerplate.

# Arguments

- `design`: A [`CableDesign`](@ref) object where the component will be added.
- `component_id`: ID for the new component.
- `conductor_group`: A [`ConductorGroup`](@ref) for the component.
- `insulator_group`: An [`InsulatorGroup`](@ref) for the component.

# Returns

- The modified [`CableDesign`](@ref) object.

# Examples

```julia
conductor_group = ConductorGroup(wire_array)
insulator_group = InsulatorGroup(insulation)
$(FUNCTIONNAME)(design, "shield", conductor_group, insulator_group)
```

# See also

- [`CableDesign`](@ref)
- [`CableComponent`](@ref)
"""
function add!(
    design::CableDesign,
    component_id::String,
    conductor_group::ConductorGroup,
    insulator_group::InsulatorGroup,
)
    # Create new component
    component = CableComponent(component_id, conductor_group, insulator_group)

    # Call the main function
    return add!(design, component)
end

include("cabledesign/base.jl")
include("cabledesign/dataframe.jl")
