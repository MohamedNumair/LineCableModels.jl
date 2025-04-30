"""
Primitive drawing functions for the FEMTools.jl module.
These functions handle the creation of geometric entities in Gmsh.
"""

function _add_mesh_points(;
    radius_ext::Number,
    theta_0::Number,
    theta_1::Number,
    mesh_size::Number,
    radius_in::Number=0.0,
    num_points_ang::Integer=8,
    num_points_rad::Integer=0,
    C::Tuple{Number,Number}=(0.0, 0.0),
    theta_offset::Number=0.0)

    point_tags = Vector{Int}()
    center_x, center_y = C

    # Handle special cases
    if num_points_ang <= 0 && num_points_rad <= 0
        # Single point at center C
        point_tag = gmsh.model.occ.add_point(center_x, center_y, 0.0, mesh_size)
        gmsh.model.set_entity_name(0, point_tag, "mesh_size_$(round(mesh_size, sigdigits=6))")
        return [point_tag]
    end

    # Circular arc (default case or when num_points_rad=0)
    if num_points_rad == 0
        r = radius_ext  # Use external radius as default
        np_ang = max(2, num_points_ang)  # At least 2 points for an arc

        for i in 0:(np_ang-1)
            t_ang = i / (np_ang - 1)
            theta = theta_0 + t_ang * (theta_1 - theta_0) + theta_offset

            x = center_x + r * cos(theta)
            y = center_y + r * sin(theta)

            point_tag = gmsh.model.occ.add_point(x, y, 0.0, mesh_size)
            gmsh.model.set_entity_name(0, point_tag, "mesh_size_$(round(mesh_size, sigdigits=6))")
            push!(point_tags, point_tag)
        end

        return point_tags
    end

    # Radial line (when theta_0 == theta_1)
    if theta_0 == theta_1
        theta = theta_0 + theta_offset
        np_rad = max(2, num_points_rad)

        for j in 0:(np_rad-1)
            t_rad = j / (np_rad - 1)
            r = radius_in + t_rad * (radius_ext - radius_in)

            x = center_x + r * cos(theta)
            y = center_y + r * sin(theta)

            point_tag = gmsh.model.occ.add_point(x, y, 0.0, mesh_size)
            gmsh.model.set_entity_name(0, point_tag, "mesh_size_$(round(mesh_size, sigdigits=6))")
            push!(point_tags, point_tag)
        end

        return point_tags
    end

    # 2D array of points (both radial and angular)
    np_rad = max(2, num_points_rad)
    np_ang = max(2, num_points_ang)

    for j in 0:(np_rad-1)
        t_rad = j / (np_rad - 1)
        r = radius_in + t_rad * (radius_ext - radius_in)

        for i in 0:(np_ang-1)
            t_ang = i / (np_ang - 1)
            theta = theta_0 + t_ang * (theta_1 - theta_0) + theta_offset
            *
            x = center_x + r * cos(theta)
            y = center_y + r * sin(theta)

            point_tag = gmsh.model.occ.add_point(x, y, 0.0, mesh_size)
            gmsh.model.set_entity_name(0, point_tag, "mesh_size_$(round(mesh_size, sigdigits=6))")
            push!(point_tags, point_tag)
        end
    end

    return point_tags
end

"""
$(TYPEDSIGNATURES)

Draw a point with specified coordinates and mesh size.

# Arguments

- `x`: X-coordinate \\[m\\].
- `y`: Y-coordinate \\[m\\].
- `z`: Z-coordinate \\[m\\].

# Returns

- Gmsh point tag \\[dimensionless\\].

# Examples

```julia
point_tag = $(FUNCTIONNAME)(0.0, 0.0, 0.0, 0.01)
```
"""
function _draw_point(x::Number, y::Number, z::Number)
    return gmsh.model.occ.addPoint(x, y, z)
end

"""
$(TYPEDSIGNATURES)

Draw a line between two points.

# Arguments

- `x1`: X-coordinate of the first point \\[m\\].
- `y1`: Y-coordinate of the first point \\[m\\].
- `x2`: X-coordinate of the second point \\[m\\].
- `y2`: Y-coordinate of the second point \\[m\\].

# Returns

- Gmsh line tag \\[dimensionless\\].

# Examples

```julia
line_tag = $(FUNCTIONNAME)(0.0, 0.0, 1.0, 0.0, 0.01)
```
"""
function _draw_line(x1::Number, y1::Number, x2::Number, y2::Number, mesh_size::Number, num_points::Number)

    # Calculate line parameters
    line_length = sqrt((x2 - x1)^2 + (y2 - y1)^2)
    x_center = (x1 + x2) / 2
    y_center = (y1 + y2) / 2

    # Calculate angle in polar coordinates (in radians)
    theta = atan(y2 - y1, x2 - x1)

    # Use the distance as a "domain radius" for placing mesh points
    radius = line_length / 2

    # Create a unique marker for this line
    marker = [x_center, y_center, 0.0]  # Center of the line

    marker_tag = gmsh.model.occ.add_point(marker[1], marker[2], marker[3], mesh_size)
    gmsh.model.set_entity_name(0, marker_tag, "marker_$(round(mesh_size, sigdigits=6))")

    mesh_points = _add_mesh_points(
        radius_in=-radius,
        radius_ext=radius,
        theta_0=theta,
        theta_1=theta,
        mesh_size=mesh_size,
        num_points_ang=0,
        num_points_rad=num_points, # Not strictly a circumference, but the trick works
        C=(x_center, y_center)
    )

    tag = gmsh.model.occ.add_line(mesh_points[1], mesh_points[end])




    return tag, mesh_points, marker
end

"""
$(TYPEDSIGNATURES)

Draw a circular disk with specified center and radius.

# Arguments

- `x`: X-coordinate of the center \\[m\\].
- `y`: Y-coordinate of the center \\[m\\].
- `radius`: Radius of the disk \\[m\\].

# Returns

- Gmsh surface tag \\[dimensionless\\].

# Examples

```julia
disk_tag = $(FUNCTIONNAME)(0.0, 0.0, 0.5, 0.01)
```
"""
function _draw_disk(x::Number, y::Number, radius::Number, mesh_size::Number, num_points::Number)

    tag = gmsh.model.occ.add_disk(x, y, 0.0, radius, radius)

    mesh_points = _add_mesh_points(
        radius_in=radius,
        radius_ext=radius,
        theta_0=0,
        theta_1=2 * pi,
        mesh_size=mesh_size,
        num_points_ang=num_points,
        C=(x, y),
        theta_offset=0 #pi / 15
    )

    marker = [x, y + (radius / 2), 0.0]  # Center of the disk
    marker_tag = gmsh.model.occ.add_point(marker[1], marker[2], marker[3], 2 * mesh_size)
    gmsh.model.set_entity_name(0, marker_tag, "marker_$(round(mesh_size, sigdigits=6))")


    return tag, mesh_points, marker
end


"""
$(TYPEDSIGNATURES)

Draw an annular (ring) shape with specified center, inner radius, and outer radius.

# Arguments

- `x`: X-coordinate of the center \\[m\\].
- `y`: Y-coordinate of the center \\[m\\].
- `radius_in`: Inner radius of the annular shape \\[m\\].
- `radius_ext`: Outer radius of the annular shape \\[m\\].

# Returns

- Gmsh surface tag \\[dimensionless\\].

# Examples

```julia
annular_tag = $(FUNCTIONNAME)(0.0, 0.0, 0.3, 0.5, 0.01)
```
"""
function _draw_annular(x::Number, y::Number, radius_in::Number, radius_ext::Number, mesh_size::Number, num_points::Number; inner_points::Bool=false)
    # Create outer disk
    outer_disk = gmsh.model.occ.add_disk(x, y, 0.0, radius_ext, radius_ext)

    # Create inner disk
    inner_disk = gmsh.model.occ.add_disk(x, y, 0.0, radius_in, radius_in)

    # Cut inner disk from outer disk to create annular shape
    annular_obj, _ = gmsh.model.occ.cut([(2, outer_disk)], [(2, inner_disk)])

    # Return the tag of the resulting surface
    if length(annular_obj) > 0
        tag = annular_obj[1][2]
    else
        error("Failed to create annular shape.")
    end

    mesh_points = _add_mesh_points(
        radius_in=radius_ext,
        radius_ext=radius_ext,
        theta_0=0,
        theta_1=2 * pi,
        mesh_size=mesh_size,
        num_points_ang=num_points,
        C=(x, y),
        theta_offset=0 #pi / 15
    )

    if inner_points
        mesh_points = _add_mesh_points(
            radius_in=radius_in,
            radius_ext=radius_in,
            theta_0=0,
            theta_1=2 * pi,
            mesh_size=mesh_size,
            num_points_ang=num_points,
            C=(x, y),
            theta_offset=pi / 3
        )
    end

    marker = [x, y + ((radius_in + radius_ext) / 2), 0.0]  # Center of the annular shape

    marker_tag = gmsh.model.occ.add_point(marker[1], marker[2], marker[3], mesh_size)
    gmsh.model.set_entity_name(0, marker_tag, "marker_$(round(mesh_size, sigdigits=6))")

    return tag, mesh_points, marker
end


"""
$(TYPEDSIGNATURES)

Draw a rectangle with specified center, width, and height.

# Arguments

- `x`: X-coordinate of the center \\[m\\].
- `y`: Y-coordinate of the center \\[m\\].
- `width`: Width of the rectangle \\[m\\].
- `height`: Height of the rectangle \\[m\\].

# Returns

- Gmsh surface tag \\[dimensionless\\].

# Examples

```julia
rect_tag = $(FUNCTIONNAME)(0.0, 0.0, 1.0, 0.5, 0.01)
```
"""
function _draw_rectangle(x::Number, y::Number, width::Number, height::Number)
    # Calculate corner coordinates
    x1 = x - width / 2
    y1 = y - height / 2
    x2 = x + width / 2
    y2 = y + height / 2

    # Create rectangle
    return gmsh.model.occ.addRectangle(x1, y1, 0.0, width, height)
end

"""
$(TYPEDSIGNATURES)

Draw a circular arc between two points with a specified center.

# Arguments

- `x1`: X-coordinate of the first point \\[m\\].
- `y1`: Y-coordinate of the first point \\[m\\].
- `x2`: X-coordinate of the second point \\[m\\].
- `y2`: Y-coordinate of the second point \\[m\\].
- `xc`: X-coordinate of the center \\[m\\].
- `yc`: Y-coordinate of the center \\[m\\].

# Returns

- Gmsh curve tag \\[dimensionless\\].

# Examples

```julia
arc_tag = $(FUNCTIONNAME)(1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.01)
```
"""
function _draw_arc(x1::Number, y1::Number, x2::Number, y2::Number, xc::Number, yc::Number)
    p1 = gmsh.model.occ.addPoint(x1, y1, 0.0)
    p2 = gmsh.model.occ.addPoint(x2, y2, 0.0)
    pc = gmsh.model.occ.addPoint(xc, yc, 0.0)

    return gmsh.model.occ.addCircleArc(p1, pc, p2)
end

"""
$(TYPEDSIGNATURES)

Draw a circle with specified center and radius.

# Arguments

- `x`: X-coordinate of the center \\[m\\].
- `y`: Y-coordinate of the center \\[m\\].
- `radius`: Radius of the circle \\[m\\].

# Returns

- Gmsh curve tag \\[dimensionless\\].

# Examples

```julia
circle_tag = $(FUNCTIONNAME)(0.0, 0.0, 0.5, 0.01)
```
"""
function _draw_circle(x::Number, y::Number, radius::Number)
    return gmsh.model.occ.addCircle(x, y, 0.0, radius)
end

"""
$(TYPEDSIGNATURES)

Draw a polygon with specified vertices.

# Arguments

- `vertices`: Array of (x,y) coordinates for the vertices \\[m\\].

# Returns

- Gmsh surface tag \\[dimensionless\\].

# Examples

```julia
vertices = [(0.0, 0.0), (1.0, 0.0), (0.5, 1.0)]
polygon_tag = $(FUNCTIONNAME)(vertices, 0.01)
```
"""
function _draw_polygon(vertices::Vector{<:Tuple{<:Number,<:Number}})
    # Create points
    points = Vector{Int}()
    for (x, y) in vertices
        push!(points, gmsh.model.occ.addPoint(x, y, 0.0))
    end

    # Create lines
    lines = Vector{Int}()
    for i in 1:length(points)
        next_i = i % length(points) + 1
        push!(lines, gmsh.model.occ.addLine(points[i], points[next_i]))
    end

    # Create curve loop
    curve_loop = gmsh.model.occ.addCurveLoop(lines)

    # Create surface
    return gmsh.model.occ.addPlaneSurface([curve_loop])
end
