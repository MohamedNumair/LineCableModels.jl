"""
$(TYPEDEF)

Represents an insulating layer surrounding a sector-shaped conductor.

$(TYPEDFIELDS)
"""
struct SectorInsulator{T<:REALSCALAR} <: AbstractInsulatorPart
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