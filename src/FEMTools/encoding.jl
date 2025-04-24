"""
Functions for physical tag encoding and decoding in the FEMTools.jl module.
Implements the CCOGYYYYY scheme for cable components and EPFXXXXX scheme for
environmental entities.
"""

"""
$(TYPEDSIGNATURES)

Encode cable hierarchy into a single integer ID.
Format: 1CCOGYYYYY where:
- Leading 1: Fixed prefix to ensure consistent length
- CC: Cable ID (01-99)
- O: Component Type (1-9)
- G: Group Type (1-3)
- YYYYY: Sequential Index (00000-99999)

Special case: For Group Type 3 (empty/gap), seq_idx is forced to 0.
FUNDAMENTAL: MUST BE A VALID INT32 NUMERIC VALUE

# Arguments

- `cable`: Cable ID (1-99) \\[dimensionless\\].
- `component`: Component Type (1-9) \\[dimensionless\\].
- `group_type`: Group Type (1-3) \\[dimensionless\\].
- `seq_idx`: Sequential Index (0-99999) \\[dimensionless\\].

# Returns

- Encoded tag as an integer \\[dimensionless\\].

# Examples

```julia
tag = $(FUNCTIONNAME)(1, 2, 1, 5)  # Cable 1, Component 2, Group 1, Seq 5
println(tag)  # Output: 101210005
```
"""
function encode_cable_tag(cable::Int, component::Int, group_type::Int, seq_idx::Int)
    # Input validation with detailed error messages
    if !(1 <= cable <= 99)
        error("Invalid cable ID: $cable. Must be between 1 and 99")
    end

    if !(1 <= component <= 9)
        error("Invalid component: $component. Must be between 1 and 9")
    end

    if !(1 <= group_type <= 3)
        error("""
        CRITICAL ENCODING ERROR: Invalid group_type: $group_type
        Group type must be between 1 and 3:
        - 1: Conductor
        - 2: Insulator
        - 3: Empty/gap
        """)
    end

    if !(1 <= seq_idx <= 99999)
        error("Invalid sequential index: $seq_idx. Must be between 1 and 99999")
    end

    # Special case: If group_type is 3 (Air/Void), force seq_idx to 0
    if group_type == 3
        seq_idx = 0
    end

    # FIXED ENCODING SCHEME: 1CCOGYYYYY 
    # Leading 1 guarantees consistent length and avoids leading zero issues
    tag = 100000000 + (cable * 1000000) + (component * 100000) + (group_type * 10000) + seq_idx

    # Validate the generated tag is within expected range
    tag_str = string(tag)
    if length(tag_str) != 9
        error("Generated tag $tag has invalid length ($(length(tag_str))) for inputs: cable=$cable, component=$component, group_type=$group_type, seq_idx=$seq_idx")
    end

    if tag_str[1] != '1'
        error("Generated tag $tag does not have expected leading digit '1' for inputs: cable=$cable, component=$component, group_type=$group_type, seq_idx=$seq_idx")
    end

    return tag
end

"""
$(TYPEDSIGNATURES)

Decode a cable ID tag into its component parts.

# Arguments

- `tag`: Encoded tag as an integer \\[dimensionless\\].

# Returns

- Tuple of (cable, component, group_type, seq_idx) \\[dimensionless\\].

# Examples

```julia
cable, component, group_type, seq_idx = $(FUNCTIONNAME)(101210005)
println((cable, component, group_type, seq_idx))  # Output: (1, 2, 1, 5)
```
"""
function decode_cable_tag(tag::Int)
    tag_str = string(tag)

    # Validate format
    if length(tag_str) != 9 || tag_str[1] != '1'
        error("Invalid tag format: $tag. Expected 9-digit number starting with 1")
    end

    # Extract parts
    cable = parse(Int, tag_str[2:3])
    component = parse(Int, tag_str[4])
    group_type = parse(Int, tag_str[5])
    seq_idx = parse(Int, tag_str[6:end])

    return (cable, component, group_type, seq_idx)
end

function encode_interface_tag(interface_idx::Int)
    # Entity type: 2 for curve
    entity_type = 2

    # Position: 0 for all interfaces (including air-earth interface)
    # This is because interfaces separate layers, and we consistently
    # associate the interface with the lower medium
    position = 0

    # Function type: 0 for physical interface
    function_type = 0

    # Validate interface index
    if !(1 <= interface_idx <= 9999)
        error("Interface index must be between 1 and 9999")
    end

    # Construct the 7-digit ID
    return entity_type * 1000000 + position * 100000 + function_type * 10000 + interface_idx
end

function encode_boundary_tag(layer_idx::Int, is_infshell::Bool)

    entity_type = 2 # Entity type: 2 for curve


    # Position: 1 for above ground, 0 for below ground
    position = (layer_idx == 1) ? 1 : 0

    # Boundary index: 1 for physical domain, 2 for infinite shell
    boundary_type = is_infshell ? 2 : 1

    # Construct the 7-digit ID
    return entity_type * 1000000 + position * 100000 + boundary_type * 10000 + layer_idx
end

function encode_medium_tag(layer_idx::Int, surface_type::Int=0) # surface type: 0 for  medium global, 1 for a region within the domain (layer/subdivision), 2 for infinite shell

    # Entity type: 3 for surface
    entity_type = 3

    # Position: 1 for above ground, 0 for below ground
    position = (layer_idx == 1) ? 1 : 0

    # Validate layer index
    if !(1 <= layer_idx <= 9999)
        error("Layer index must be between 1 and 9999")
    end

    # Construct the 7-digit ID
    return entity_type * 1000000 + position * 100000 + surface_type * 10000 + layer_idx
end


"""
$(TYPEDSIGNATURES)

Generate a human-readable physical name for a cable component.
Format: cable_X_<component>_<group>_layer_<Y>_<part>[_wire_N][][_phase_M]

# Arguments

- `cable_idx`: Cable index \\[dimensionless\\].
- `component_id`: Component ID (e.g., "core", "sheath") \\[dimensionless\\].
- `group_type`: Group type (1=conductor, 2=insulator, 3=empty) \\[dimensionless\\].
- `part_type`: Part type (e.g., "wire", "strip", "tubular") \\[dimensionless\\].
- `layer_idx`: Layer index \\[dimensionless\\].
- `wire_idx`: Optional wire index \\[dimensionless\\].
- `phase`: Optional phase index \\[dimensionless\\].

# Returns

- Human-readable physical name as a string.

# Examples

```julia
name = $(FUNCTIONNAME)(
    cable_idx=1,
    component_id="core",
    group_type=1,
    part_type="wire",
    layer_idx=2,
    wire_idx=3,
    phase=1
)
println(name)  # Output: "cable_1_core_con_layer_2_wire_wire_3_phase_1"
```
"""
function create_cable_elementary_name(;
    cable_idx::Int,
    component_id::String,
    group_type::Int,  # 1=conductor, 2=insulator, 3=empty
    part_type::String,
    layer_idx::Int,
    wire_idx::Union{Int,Nothing}=nothing,
    phase::Union{Int,Nothing}=nothing
)
    # Convert group_type to string
    group_str = if group_type == 1
        "con"
    elseif group_type == 2
        "ins"
    elseif group_type == 3
        "air"
    else
        error("Invalid group_type: $group_type")
    end

    # Base name without optional parts
    name = "cable_$(cable_idx)_$(component_id)_$(group_str)_layer_$(layer_idx)_$(part_type)"

    # Add wire index if provided
    if !isnothing(wire_idx)
        name *= "_wire_$(wire_idx)"
    end

    # Add phase if provided
    if !isnothing(phase) && phase > 0
        name *= "_phase_$(phase)"
    elseif !isnothing(phase) && phase == 0
        name *= "_ground"
    end

    return name
end

function create_medium_elementary_name(layer_idx::Int)
    if layer_idx < 1
        error("Layer index must be at least 1")
    end

    medium_type = layer_idx == 1 ? "air" : "earth"
    return "layer_$(layer_idx)_$(medium_type)"
end

function create_interface_elementary_name(layer_idx::Int)
    if layer_idx < 1
        error("Layer index must be at least 1")
    end

    if layer_idx == 1
        return "interface_air_earth"
    else
        return "interface_earth_layers_$(layer_idx)_$(layer_idx+1)"
    end
end

function create_boundary_elementary_name(layer_idx::Int, is_infshell::Bool)
    boundary_type = is_infshell ? "domain_infty" : "domain_boundary"
    medium_type = (layer_idx == 1) ? "air" : "earth"

    return "$(boundary_type)_$(medium_type)"
end

function create_infshell_elementary_name(layer_idx::Int)
    medium_type = layer_idx == 1 ? "air" : "earth"
    return "layer_$(layer_idx)_$(medium_type)_infshell"
end

# function register_elementary_name!(workspace::FEMWorkspace, marker::Vector{Float64}, name::String)
#     workspace.name_map[marker] = name
# end