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
struct Sector{T<:REALSCALAR,U<:Int} <: AbstractConductorPart
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
    vertices::Vector{Point{2, T}}
end