"""
Primitive drawing functions for the FEMTools.jl module.
These functions handle the creation of geometric entities in Gmsh.
"""

"""
$(TYPEDSIGNATURES)

Draw a point with specified coordinates and mesh size.

# Arguments

- `x`: X-coordinate \\[m\\].
- `y`: Y-coordinate \\[m\\].
- `z`: Z-coordinate \\[m\\].
- `mesh_size`: Target mesh size at this point \\[m\\].

# Returns

- Gmsh point tag \\[dimensionless\\].

# Examples

```julia
point_tag = $(FUNCTIONNAME)(0.0, 0.0, 0.0, 0.01)
```
"""
function _draw_point(x::Number, y::Number, z::Number, mesh_size::Number)
    return gmsh.model.occ.addPoint(x, y, z, mesh_size)
end

"""
$(TYPEDSIGNATURES)

Draw a line between two points.

# Arguments

- `x1`: X-coordinate of the first point \\[m\\].
- `y1`: Y-coordinate of the first point \\[m\\].
- `x2`: X-coordinate of the second point \\[m\\].
- `y2`: Y-coordinate of the second point \\[m\\].
- `mesh_size`: Target mesh size for the line \\[m\\].

# Returns

- Gmsh line tag \\[dimensionless\\].

# Examples

```julia
line_tag = $(FUNCTIONNAME)(0.0, 0.0, 1.0, 0.0, 0.01)
```
"""
function _draw_line(x1::Number, y1::Number, x2::Number, y2::Number, mesh_size::Number)
    p1 = gmsh.model.occ.addPoint(x1, y1, 0.0, mesh_size)
    p2 = gmsh.model.occ.addPoint(x2, y2, 0.0, mesh_size)
    return gmsh.model.occ.addLine(p1, p2)
end

"""
$(TYPEDSIGNATURES)

Draw a circular disk with specified center and radius.

# Arguments

- `x`: X-coordinate of the center \\[m\\].
- `y`: Y-coordinate of the center \\[m\\].
- `radius`: Radius of the disk \\[m\\].
- `mesh_size`: Target mesh size for the disk \\[m\\].

# Returns

- Gmsh surface tag \\[dimensionless\\].

# Examples

```julia
disk_tag = $(FUNCTIONNAME)(0.0, 0.0, 0.5, 0.01)
```
"""
function _draw_disk(x::Number, y::Number, radius::Number, mesh_size::Number)
    return gmsh.model.occ.addDisk(x, y, 0.0, radius, radius)
end

"""
$(TYPEDSIGNATURES)

Draw an annular (ring) shape with specified center, inner radius, and outer radius.

# Arguments

- `x`: X-coordinate of the center \\[m\\].
- `y`: Y-coordinate of the center \\[m\\].
- `radius_in`: Inner radius of the annular shape \\[m\\].
- `radius_ext`: Outer radius of the annular shape \\[m\\].
- `mesh_size`: Target mesh size for the annular shape \\[m\\].

# Returns

- Gmsh surface tag \\[dimensionless\\].

# Examples

```julia
annular_tag = $(FUNCTIONNAME)(0.0, 0.0, 0.3, 0.5, 0.01)
```
"""
function _draw_annular(x::Number, y::Number, radius_in::Number, radius_ext::Number, mesh_size::Number)
    # Create outer disk
    outer_disk = gmsh.model.occ.addDisk(x, y, 0.0, radius_ext, radius_ext)

    # Create inner disk
    inner_disk = gmsh.model.occ.addDisk(x, y, 0.0, radius_in, radius_in)

    # Cut inner disk from outer disk to create annular shape
    annular_obj, _ = gmsh.model.occ.cut([(2, outer_disk)], [(2, inner_disk)])

    # Return the tag of the resulting surface
    if length(annular_obj) > 0
        return annular_obj[1][2]
    else
        error("Failed to create annular shape.")
    end
end

"""
$(TYPEDSIGNATURES)

Draw a rectangle with specified center, width, and height.

# Arguments

- `x`: X-coordinate of the center \\[m\\].
- `y`: Y-coordinate of the center \\[m\\].
- `width`: Width of the rectangle \\[m\\].
- `height`: Height of the rectangle \\[m\\].
- `mesh_size`: Target mesh size for the rectangle \\[m\\].

# Returns

- Gmsh surface tag \\[dimensionless\\].

# Examples

```julia
rect_tag = $(FUNCTIONNAME)(0.0, 0.0, 1.0, 0.5, 0.01)
```
"""
function _draw_rectangle(x::Number, y::Number, width::Number, height::Number, mesh_size::Number)
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
- `mesh_size`: Target mesh size for the arc \\[m\\].

# Returns

- Gmsh curve tag \\[dimensionless\\].

# Examples

```julia
arc_tag = $(FUNCTIONNAME)(1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.01)
```
"""
function _draw_arc(x1::Number, y1::Number, x2::Number, y2::Number, xc::Number, yc::Number, mesh_size::Number)
    p1 = gmsh.model.occ.addPoint(x1, y1, 0.0, mesh_size)
    p2 = gmsh.model.occ.addPoint(x2, y2, 0.0, mesh_size)
    pc = gmsh.model.occ.addPoint(xc, yc, 0.0, mesh_size)

    return gmsh.model.occ.addCircleArc(p1, pc, p2)
end

"""
$(TYPEDSIGNATURES)

Draw a circle with specified center and radius.

# Arguments

- `x`: X-coordinate of the center \\[m\\].
- `y`: Y-coordinate of the center \\[m\\].
- `radius`: Radius of the circle \\[m\\].
- `mesh_size`: Target mesh size for the circle \\[m\\].

# Returns

- Gmsh curve tag \\[dimensionless\\].

# Examples

```julia
circle_tag = $(FUNCTIONNAME)(0.0, 0.0, 0.5, 0.01)
```
"""
function _draw_circle(x::Number, y::Number, radius::Number, mesh_size::Number)
    return gmsh.model.occ.addCircle(x, y, 0.0, radius)
end

"""
$(TYPEDSIGNATURES)

Draw a polygon with specified vertices.

# Arguments

- `vertices`: Array of (x,y) coordinates for the vertices \\[m\\].
- `mesh_size`: Target mesh size for the polygon \\[m\\].

# Returns

- Gmsh surface tag \\[dimensionless\\].

# Examples

```julia
vertices = [(0.0, 0.0), (1.0, 0.0), (0.5, 1.0)]
polygon_tag = $(FUNCTIONNAME)(vertices, 0.01)
```
"""
function _draw_polygon(vertices::Vector{<:Tuple{<:Number,<:Number}}, mesh_size::Number)
    # Create points
    points = Vector{Int}()
    for (x, y) in vertices
        push!(points, gmsh.model.occ.addPoint(x, y, 0.0, mesh_size))
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
