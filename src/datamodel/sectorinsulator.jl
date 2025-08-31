"""
$(TYPEDEF)

Represents an insulating layer surrounding a sector-shaped conductor.

$(TYPEDFIELDS)
"""
struct SectorInsulator{T<:REALSCALAR} <: AbstractInsulatorPart{T}
    "Inner radius (not applicable, defined by inner sector) \\[m\\]."
    radius_in::T
    "Outer radius (equivalent back radius of outer boundary) \\[m\\]."
    radius_ext::T
    "The inner sector conductor that this insulator surrounds."
    inner_sector::Sector{T}
    "The thickness of the insulating layer \\[m\\]."
    thickness::T
    "Material properties of the insulator."
    material_props::Material{T}
    "Operating temperature of the insulator \\[°C\\]."
    temperature::T
    "Cross-sectional area of the insulating layer \\[m²\\]."
    cross_section::T
    "Shunt capacitance (approximated) \\[F/m\\]."
    shunt_capacitance::T
    "Shunt conductance (approximated) \\[S·m\\]."
    shunt_conductance::T
    "Calculated vertices of the outer boundary polygon."
    outer_vertices::Vector{Point{2, T}}
end


function SectorInsulator(
    inner_sector::Sector{T},
    thickness::T,
    material_props::Material{T};
    temperature::T=T₀,
) where {T<:REALSCALAR}

    # 1. Calculate the outer vertices by offsetting the inner sector's geometry
    outer_vertices = _calculate_offset_polygon(inner_sector.params, thickness, inner_sector.rotation_angle_deg)

    # 2. Calculate areas
    inner_area = inner_sector.cross_section
    outer_area = PolygonOps.area(outer_vertices)
    cross_section = outer_area - inner_area

    # 3. Approximate capacitance and conductance using equivalent coaxial circles
    # This is more consistent with the package's approach than a parallel plate model.
    r_eq_in = sqrt(inner_area / π)
    r_eq_ext = sqrt(outer_area / π)
    shunt_capacitance = calc_shunt_capacitance(r_eq_in, r_eq_ext, material_props.eps_r)
    shunt_conductance = calc_shunt_conductance(r_eq_in, r_eq_ext, material_props.rho)

    # 4. Determine outer radius from the new params
    outer_r_back = inner_sector.params.r_back + thickness

    return SectorInsulator{T}(
        inner_sector.radius_ext,
        outer_r_back,
        inner_sector,
        thickness,
        material_props,
        temperature,
        cross_section,
        shunt_capacitance,
        shunt_conductance,
        outer_vertices
    )
end

# --- Geometric Helper Functions (internal) --- 
#NB: This return another full sector not just the insulation -
#---- Parameter calculations are handled by the equivalent area difference (as in the constructor)
#---- Plots.jl handling can be done 
#---- FEM handling not done yet 

function _calculate_offset_polygon(inner_params::SectorParams, thickness::Real, rotation_angle_deg::Real)
    # Create a new set of parameters for the outer boundary by adding the thickness
    outer_params = SectorParams(
        inner_params.n_sectors,
        inner_params.r_back + thickness,
        inner_params.d_sector + thickness,
        inner_params.r_corner + thickness, # Offset corner radius as well
        inner_params.theta_cond_deg
    )

    base_vertices = _calculate_sector_polygon_points(outer_params)
    rotation_angle_rad = deg2rad(rotation_angle_deg)
    rotated_vertices = [_rotate_point(p, rotation_angle_rad) for p in base_vertices]
    return rotated_vertices
end
