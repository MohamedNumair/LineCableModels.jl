"""
$(TYPEDEF)

Holds the geometric parameters that define the shape of a sector conductor.

$(TYPEDFIELDS)
"""
struct SectorParams{T<:REALSCALAR}
    "Number of sectors in the full cable (e.g., 3 or 4)."
    n_sectors::Int
    "Back radius of the sector (outermost curve) \\[m\\]."
    r_back::T
    "Depth of the sector from the back to the base \\[m\\]."
    d_sector::T
    "Corner radius for rounding sharp edges \\[m\\]."
    r_corner::T
    "Angular width of the conductor's flat base/sides [degrees]."
    theta_cond_deg::T
end

"""
$(TYPEDEF)

Represents a single sector-shaped conductor with defined geometric and material properties.

$(TYPEDFIELDS)
"""
struct Sector{T<:REALSCALAR} <: AbstractConductorPart{T}
    "Inner radius (not applicable, typically 0 for the central point) \\[m\\]."
    radius_in::T
    "Outer radius (equivalent back radius) \\[m\\]."
    radius_ext::T
    "Geometric parameters defining the sector's shape."
    params::SectorParams{T}
    "Rotation angle of this specific sector around the cable's center [degrees]."
    rotation_angle_deg::T
    "Material properties of the conductor."
    material_props::Material{T}
    "Operating temperature of the conductor \\[°C\\]."
    temperature::T
    "Cross-sectional area of the sector \\[m²\\]."
    cross_section::T
    "Electrical resistance of the sector \\[Ω/m\\]."
    resistance::T
    "Geometric mean radius (GMR) of the sector (approximated) \\[m\\]."
    gmr::T
    "Calculated vertices defining the polygon shape."
    vertices::Vector{Point{2,T}}
end


function Sector(
    params::SectorParams{T},
    rotation_angle_deg::T,
    material_props::Material{T};
    temperature::T=T₀,
) where {T<:REALSCALAR}

    # 1. Calculate the geometry and vertices for a base (unrotated) sector
    base_vertices = _calculate_sector_polygon_points(params)

    # 2. Rotate the vertices to the specified angle
    rotation_angle_rad = deg2rad(rotation_angle_deg)
    rotated_vertices = [_rotate_point(p, rotation_angle_rad) for p in base_vertices]

    # 3. Calculate cross-sectional area using the Shoelace formula
    cross_section = PolygonOps.area(rotated_vertices)
    @debug "(Sector) Calculated cross-sectional area: $(cross_section*1e6) mm²"
    # 4. Calculate DC resistance
    rho_eff = calc_temperature_correction(material_props.alpha, temperature, material_props.T0) * material_props.rho
    resistance = rho_eff / cross_section

    # 5. Approximate GMR based on a circle of equivalent area
    r_equiv = sqrt(cross_section / π)
    gmr = r_equiv * exp(-0.25 * material_props.mu_r) # GMR of an equivalent solid round conductor

    return Sector{T}(
        zero(T),
        params.r_back,
        params,
        rotation_angle_deg,
        material_props,
        temperature,
        cross_section,
        resistance,
        gmr,
        rotated_vertices,
    )
end



# --- Geometric Helper Functions (internal) ---

function _calculate_sector_geometry(p::SectorParams)
    phi_deg = 90.0 - p.theta_cond_deg / 2.0
    phi_rad = deg2rad(phi_deg)

    if abs(cos(phi_rad)) < 1e-9
        error("theta_cond_deg is too close to 180, leading to division by zero. Check parameters.")
    end

    d_base_corner = p.r_corner * (1.0 / cos(phi_rad) - 1.0)
    d_offset = p.r_back - p.d_sector - d_base_corner

    x_base_corner = p.r_corner * sin(phi_rad)
    y_base_corner = x_base_corner * tan(phi_rad) + d_offset
    node_A = Point2f(x_base_corner, y_base_corner)

    k = p.r_corner / cos(phi_rad) + d_offset
    qa = 1.0 + tan(phi_rad)^2
    qb = 2.0 * k * tan(phi_rad)
    qc = k^2 - (p.r_back - p.r_corner)^2

    discriminant = qb^2 - 4.0 * qa * qc
    if discriminant < 0
        error("Cannot calculate side corner center: negative discriminant ($discriminant). Check parameters.")
    end

    x_side_center = (-qb + sqrt(discriminant)) / (2.0 * qa)
    y_side_center = x_side_center * tan(phi_rad) + k

    x_side_lower = x_side_center + p.r_corner * sin(phi_rad)
    y_side_lower = y_side_center - p.r_corner * cos(phi_rad)
    node_B = Point2f(x_side_lower, y_side_lower)

    dist_origin_side_center = sqrt(x_side_center^2 + y_side_center^2)
    if dist_origin_side_center < 1e-9
        error("Side corner center is at the origin, cannot determine upper point direction.")
    end
    x_side_upper = x_side_center * p.r_back / dist_origin_side_center
    y_side_upper = y_side_center * p.r_back / dist_origin_side_center
    node_C = Point2f(x_side_upper, y_side_upper)

    nodes = (
        A=node_A, B=node_B, C=node_C, D=Point2f(-node_C[1], node_C[2]),
        E=Point2f(-node_B[1], node_B[2]), F=Point2f(-node_A[1], node_A[2])
    )
    centers = (
        Back=Point2f(0, 0), Base=Point2f(0, d_offset+  p.r_corner / cos(phi_rad)),
        RightSide=Point2f(x_side_center, y_side_center), LeftSide=Point2f(-x_side_center, y_side_center)
    )
    return (Nodes=nodes, Centers=centers, Params=p)
end

function _generate_arc_points(center, radius, start_angle, end_angle, num_points)
    while end_angle < start_angle
        #@debug "(Sector) end_angle < start_angle: $(rad2deg(end_angle)) < $(rad2deg(start_angle))"
        end_angle += 2pi
        #@debug "(Sector)  Adjusted end_angle to be greater than start_angle: $(rad2deg(end_angle)) > $(rad2deg(start_angle))"
    end
    while end_angle - start_angle > pi
        #@debug "(Sector) overshoot! end_angle - start_angle > π: $(rad2deg(end_angle - start_angle)) > 180"
        end_angle -= 2pi
        #@debug "(Sector) Adjusted end_angle to be less than start_angle: $(rad2deg(end_angle)) < $(rad2deg(start_angle))"
    end
    angle_range = range(start_angle, stop=end_angle, length=num_points)
    return [Point2f(center[1] + radius * cos(a), center[2] + radius * sin(a)) for a in angle_range]
end

function _calculate_sector_polygon_points(params; num_arc_points=20) # increase `num_arc_points` for higher accuracy
    geom = _calculate_sector_geometry(params)
    nodes, centers = geom.Nodes, geom.Centers

    poly_points = Point2f[]
    get_angle(p1, p2) = atan((p1[2] - p2[2]), (p1[1] - p2[1]))
    # Start at F, go to A (Base)
    push!(poly_points, nodes.F)
    if params.r_corner > 1e-9
        start_angle = get_angle(nodes.F, centers.Base)
        end_angle = get_angle(nodes.A, centers.Base)
        append!(poly_points,
            _generate_arc_points(centers.Base, params.r_corner, start_angle, end_angle, num_arc_points)[2:end])
    else
        push!(poly_points, Point2f(0, params.r_back - params.d_sector), nodes.A)
    end

    # Line A to B
    push!(poly_points, nodes.B)

    # Arc B to C (Right Side)
    if params.r_corner > 1e-9
        start_angle = get_angle(nodes.B, centers.RightSide)
        #@debug "Arc from B to C: start_angle=$(rad2deg(start_angle))"
        end_angle = get_angle(nodes.C, centers.RightSide)
        #@debug "Arc from B to C: end_angle=$(rad2deg(end_angle))"
        append!(poly_points, _generate_arc_points(centers.RightSide, params.r_corner, start_angle, end_angle, num_arc_points)[2:end])
    else
        push!(poly_points, nodes.C)
    end

    # Arc C to D (Back)
    start_angle = get_angle(nodes.C, centers.Back)
    end_angle = get_angle(nodes.D, centers.Back)
    append!(poly_points, _generate_arc_points(centers.Back, params.r_back, start_angle, end_angle, num_arc_points)[2:end])

    # Arc D to E (Left Side)
    if params.r_corner > 1e-9
        start_angle = get_angle(nodes.D, centers.LeftSide)
        #@debug "Arc from D to E: start_angle=$(rad2deg(start_angle))"
        end_angle = get_angle(nodes.E, centers.LeftSide)
        #@debug "Arc from D to E: end_angle=$(rad2deg(end_angle))"
        append!(poly_points, _generate_arc_points(centers.LeftSide, params.r_corner, start_angle, end_angle, num_arc_points)[2:end])
    else
        push!(poly_points, nodes.E)
    end

    return poly_points
end

function _rotate_point(p::Point2f, angle_rad::Real)
    cos_a, sin_a = cos(angle_rad), sin(angle_rad)
    return Point2f(p[1] * cos_a - p[2] * sin_a, p[1] * sin_a + p[2] * cos_a)
end