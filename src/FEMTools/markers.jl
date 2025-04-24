"""
Entity marker generation functions for the FEMTools.jl module.
These functions handle the creation of marker points for entity identification.
"""


# function register_marker!(workspace::FEMWorkspace, physical_group_tag::Int, marker::Vector{Float64})
#     workspace.marker_map[marker] = physical_group_tag
# end

"""
$(TYPEDSIGNATURES)

Calculate the coordinates of air gaps in a wire array.

# Arguments

- `num_wires`: Number of wires in the array \\[dimensionless\\].
- `radius_wire`: Radius of each wire \\[m\\].
- `radius_in`: Inner radius of the wire array \\[m\\].

# Returns

- Vector of marker positions (3D coordinates) for air gaps \\[m\\].

# Notes

This function calculates positions for markers that are guaranteed to be in the air gaps
between wires in a wire array. These markers are used to identify the air regions after
boolean fragmentation operations.

# Examples

```julia
markers = $(FUNCTIONNAME)(7, 0.002, 0.01)
```
"""
function _get_air_gap_markers(num_wires::Int, radius_wire::Number, radius_in::Number)
    markers = Vector{Vector{Float64}}()

    # Skip if only one wire (no air gaps)
    if num_wires <= 1
        return markers
    end

    lay_radius = radius_in + radius_wire
    angle_step = 2π / num_wires

    # Create markers between wires
    for i in 0:num_wires-1
        angle = i * angle_step + (angle_step / 2)  # Midway between wires
        r = lay_radius + (radius_wire / 2)  # Slightly outward
        x = r * cos(angle)
        y = r * sin(angle)
        push!(markers, [x, y, 0.0])
    end

    return markers
end

"""
$(TYPEDSIGNATURES)

Create a marker point at the thickness midpoint of an annular shape.

# Arguments

- `x`: X-coordinate of the center \\[m\\].
- `y`: Y-coordinate of the center \\[m\\].
- `radius_in`: Inner radius of the annular part \\[m\\].
- `radius_ext`: Outer radius of the annular part \\[m\\].
- `angle`: Optional angle for the marker position (default is 45 degrees) \\[radians\\].

# Returns

- 3D coordinates of the marker point \\[m\\].

# Examples

```julia
marker = $(FUNCTIONNAME)(0.0, 0.0, 0.01, 0.02)
```
"""
function _get_annular_marker(x::Number, y::Number, radius_in::Number, radius_ext::Number; angle::Number=π / 4) # Defaults to 45 degrees (arbitrary but consistent)

    # Calculate the midpoint radius
    r_mid = (radius_in + radius_ext) / 2

    marker_x = x + r_mid * cos(angle)
    marker_y = y + r_mid * sin(angle)

    return [marker_x, marker_y, 0.0]
end

"""
$(TYPEDSIGNATURES)

Create a marker point at the center of a solid circular shape (disk).

# Arguments

- `x`: X-coordinate of the disk center \\[m\\].
- `y`: Y-coordinate of the disk center \\[m\\].
- `offset`: Optional offset from the center (default is 0.0) \\[m\\].

# Returns

- 3D coordinates of the marker point \\[m\\].

# Examples

```julia
marker = $(FUNCTIONNAME)(0.01, 0.02, 0.002)
```
"""
function _get_disk_marker(x::Number, y::Number; offset::Number=0.0)

    # Place marker slightly offset from center (optionally)
    marker_x = x + offset
    marker_y = y + offset

    return [marker_x, marker_y, 0.0]
end

"""
$(TYPEDSIGNATURES)

Create a marker point in the midpoint of a vertical line.

# Arguments

- `x`: X-coordinate of the center \\[m\\].
- `y_top`: Y-coordinate of the top boundary \\[m\\].
- `y_bottom`: Y-coordinate of the bottom boundary \\[m\\].

# Returns

- 3D coordinates of the marker point \\[m\\].

# Examples

```julia
marker = $(FUNCTIONNAME)(0.0, -0.5, -1.0)
```
"""
function _get_midpoint_marker(x::Number, y_top::Number, y_bottom::Number)
    # Place marker at the midpoint of the layer
    marker_y = (y_top + y_bottom) / 2

    return [x, marker_y, 0.0]
end
