"""
$(TYPEDSIGNATURES)

Defines the display representation of a [`CableComponent`](@ref) object for REPL or text output.

# Arguments

- `io`: Output stream.
- `::MIME"text/plain"`: MIME type for plain text output.
- `component`: The [`CableComponent`](@ref) object to be displayed.

# Returns

- Nothing. Modifies `io` by writing text representation of the object.
"""
function Base.show(io::IO, ::MIME"text/plain", component::CableComponent)
    # Calculate total number of parts across both groups
    total_parts =
        length(component.conductor_group.layers) + length(component.insulator_group.layers)

    # Print header
    println(io, "$(total_parts)-element CableComponent \"$(component.id)\":")

    # Display conductor group parts in a tree structure
    print(io, "├─ $(length(component.conductor_group.layers))-element ConductorGroup: [")
    _print_fields(
        io,
        component.conductor_group,
        [:radius_in, :radius_ext, :cross_section, :resistance, :gmr],
    )
    println(io, "]")
    print(io, "│  ", "├─", " Effective properties: [")
    _print_fields(io, component.conductor_props, [:rho, :eps_r, :mu_r, :alpha])
    println(io, "]")

    for (i, part) in enumerate(component.conductor_group.layers)

        prefix = i == length(component.conductor_group.layers) ? "└───" : "├───"

        # Print part information with proper indentation
        print(io, "│  ", prefix, " $(nameof(typeof(part))): [")

        # Print each field with proper formatting
        _print_fields(
            io,
            part,
            [:radius_in, :radius_ext, :cross_section, :resistance, :gmr],
        )

        println(io, "]")
    end

    # Display insulator group parts
    if !isempty(component.insulator_group.layers)
        print(
            io,
            "└─ $(length(component.insulator_group.layers))-element InsulatorGroup: [",
        )
        _print_fields(
            io,
            component.insulator_group,
            [
                :radius_in,
                :radius_ext,
                :cross_section,
                :shunt_capacitance,
                :shunt_conductance,
            ],
        )
        println(io, "]")
        print(io, "   ", "├─", " Effective properties: [")
        _print_fields(io, component.insulator_props, [:rho, :eps_r, :mu_r, :alpha])
        println(io, "]")
        for (i, part) in enumerate(component.insulator_group.layers)
            # Determine prefix based on whether it's the last part
            prefix = i == length(component.insulator_group.layers) ? "└───" : "├───"

            # Print part information with proper indentation
            print(io, "   ", prefix, " $(nameof(typeof(part))): [")

            # Print each field with proper formatting
            _print_fields(
                io,
                part,
                [
                    :radius_in,
                    :radius_ext,
                    :cross_section,
                    :shunt_capacitance,
                    :shunt_conductance,
                ],
            )

            println(io, "]")
        end
    end
end

"""
$(TYPEDSIGNATURES)

Defines the display representation of a [`CableDesign`](@ref) object for REPL or text output.

# Arguments

- `io`: Output stream.
- `::MIME"text/plain"`: MIME type for plain text output.
- `design`: The [`CableDesign`](@ref) object to be displayed.

# Returns

- Nothing. Modifies `io` by writing text representation of the object.
"""
function Base.show(io::IO, ::MIME"text/plain", design::CableDesign)
    # Print header with cable ID and count of components
    print(io, "$(length(design.components))-element CableDesign \"$(design.cable_id)\"")

    # Add nominal values if available
    nominal_values = []
    if design.nominal_data.resistance !== nothing
        push!(
            nominal_values,
            "resistance=$(round(design.nominal_data.resistance, sigdigits=4))",
        )
    end
    if design.nominal_data.inductance !== nothing
        push!(
            nominal_values,
            "inductance=$(round(design.nominal_data.inductance, sigdigits=4))",
        )
    end
    if design.nominal_data.capacitance !== nothing
        push!(
            nominal_values,
            "capacitance=$(round(design.nominal_data.capacitance, sigdigits=4))",
        )
    end

    if !isempty(nominal_values)
        print(io, ", with nominal values: [", join(nominal_values, ", "), "]")
    end
    println(io)

    # For each component, display its properties in a tree structure
    for (i, component) in enumerate(design.components)
        # Determine if this is the last component
        is_last_component = i == length(design.components)

        # Determine component prefix and continuation line
        component_prefix = is_last_component ? "└─" : "├─"
        continuation_line = is_last_component ? "   " : "│  "

        # Print component name and header
        println(io, component_prefix, " Component \"", component.id, "\":")

        # Display conductor group with combined properties
        print(io, continuation_line, "├─ ConductorGroup: [")

        # Combine properties from conductor_group and conductor_props
        conductor_props = [
            "radius_in" => component.conductor_group.radius_in,
            "radius_ext" => component.conductor_group.radius_ext,
            "rho" => component.conductor_props.rho,
            "eps_r" => component.conductor_props.eps_r,
            "mu_r" => component.conductor_props.mu_r,
            "alpha" => component.conductor_props.alpha,
        ]

        # Display combined conductor properties
        displayed_fields = 0
        for (field, value) in conductor_props
            if !(value isa Number && isnan(value))
                if displayed_fields > 0
                    print(io, ", ")
                end
                print(io, "$field=$(round(value, sigdigits=4))")
                displayed_fields += 1
            end
        end
        println(io, "]")

        # Display insulator group with combined properties
        print(io, continuation_line, "└─ InsulatorGroup: [")

        # Combine properties from insulator_group and insulator_props
        insulator_props = [
            "radius_in" => component.insulator_group.radius_in,
            "radius_ext" => component.insulator_group.radius_ext,
            "rho" => component.insulator_props.rho,
            "eps_r" => component.insulator_props.eps_r,
            "mu_r" => component.insulator_props.mu_r,
            "alpha" => component.insulator_props.alpha,
        ]

        # Display combined insulator properties
        displayed_fields = 0
        for (field, value) in insulator_props
            if !(value isa Number && isnan(value))
                if displayed_fields > 0
                    print(io, ", ")
                end
                print(io, "$field=$(round(value, sigdigits=4))")
                displayed_fields += 1
            end
        end
        println(io, "]")
    end
end

"""
$(TYPEDSIGNATURES)

Defines the display representation of an [`AbstractCablePart`](@ref) object for REPL or text output.

# Arguments

- `io`: Output stream.
- `::MIME"text/plain"`: MIME type for plain text output.
- `part`: The [`AbstractCablePart`](@ref) instance to be displayed.

# Returns

- Nothing. Modifies `io` by writing text representation of the object.
"""
function Base.show(io::IO, ::MIME"text/plain", part::T) where {T<:AbstractCablePart}
    # Start output with type name
    print(io, "$(nameof(T)): [")

    # Use _print_fields to display all relevant fields
    _print_fields(
        io,
        part,
        [
            :radius_in,
            :radius_ext,
            :cross_section,
            :resistance,
            :gmr,
            :shunt_capacitance,
            :shunt_conductance,
        ],
    )

    println(io, "]")

    # Display material properties if available
    if hasproperty(part, :material_props)
        print(io, "└─ Material properties: [")
        _print_fields(
            io,
            part.material_props,
            [:rho, :eps_r, :mu_r, :alpha],
        )
        println(io, "]")
    end
end

function Base.show(io::IO, ::MIME"text/plain", system::LineCableSystem)
    # Print top level info
    println(
        io,
        "LineCableSystem \"$(system.system_id)\": [line_length=$(system.line_length), num_cables=$(system.num_cables), num_phases=$(system.num_phases)]",
    )

    # Print cable definitions
    println(io, "└─ $(length(system.cables))-element CablePosition:")

    # Display each cable definition
    for (i, cable_position) in enumerate(system.cables)
        # Cable prefix
        prefix = i == length(system.cables) ? "   └─" : "   ├─"

        # Format connections as a string
        components = [comp.id for comp in cable_position.design_data.components]
        conn_str = join(
            ["$(comp)→$(phase)" for (comp, phase) in zip(components, cable_position.conn)],
            ", ",
        )

        # Print cable info
        println(
            io,
            "$(prefix) CableDesign \"$(cable_position.design_data.cable_id)\": [horz=$(round(cable_position.horz, sigdigits=4)), vert=$(round(cable_position.vert, sigdigits=4)), conn=($(conn_str))]",
        )
    end
end

"""
$(TYPEDSIGNATURES)

Defines the display representation of a [`ConductorGroup`](@ref) or [`InsulatorGroup`](@ref)objects for REPL or text output.

# Arguments

- `io`: Output stream.
- `::MIME"text/plain"`: MIME type for plain text output.
- `group`: The [`ConductorGroup`](@ref) or [`InsulatorGroup`](@ref) instance to be displayed.

# Returns

- Nothing. Modifies `io` by writing text representation of the object.
"""
function Base.show(io::IO, ::MIME"text/plain", group::Union{ConductorGroup,InsulatorGroup})

    print(io, "$(length(group.layers))-element $(nameof(typeof(group))): [")
    _print_fields(
        io,
        group,
        [
            :radius_in,
            :radius_ext,
            :cross_section,
            :resistance,
            :gmr,
            :shunt_capacitance,
            :shunt_conductance,
        ],
    )
    println(io, "]")

    # Tree-like layer representation

    for (i, layer) in enumerate(group.layers)
        # Determine prefix based on whether it's the last layer
        prefix = i == length(group.layers) ? "└─" : "├─"
        # Print layer information with only selected fields
        print(io, prefix, "$(nameof(typeof(layer))): [")
        _print_fields(
            io,
            layer,
            [
                :radius_in,
                :radius_ext,
                :cross_section,
                :resistance,
                :gmr,
                :shunt_capacitance,
                :shunt_conductance,
            ],
        )
        println(io, "]")
    end
end

"""
$(TYPEDSIGNATURES)

Print the specified fields of an object in a compact format.

# Arguments
- `io`: The output stream.
- `obj`: The object whose fields will be displayed.
- `fields_to_show`: Vector of field names (as Symbols) to display.
- `sigdigits`: Number of significant digits for rounding numeric values.

# Returns

- Number of fields that were actually displayed.
"""
function _print_fields(io::IO, obj, fields_to_show::Vector{Symbol}; sigdigits::Int=4)
    displayed_fields = 0
    for field in fields_to_show
        if hasproperty(obj, field)
            value = getfield(obj, field)
            # Skip NaN values
            if value isa Number && isnan(value)
                continue
            end
            # Add comma if not the first item
            if displayed_fields > 0
                print(io, ", ")
            end
            # Format numbers with rounding
            if value isa Number
                print(io, "$field=$(round(value, sigdigits=sigdigits))")
            else
                print(io, "$field=$value")
            end
            displayed_fields += 1
        end
    end
    return displayed_fields
end