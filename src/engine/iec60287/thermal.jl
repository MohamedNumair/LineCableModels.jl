"""
    LineCableModels.Engine.IEC60287.Thermal

This module implements the thermal resistance calculation component of the IEC 60287 analytical formulation.
It covers:
- Internal Thermal Resistance (T1, T2, T3) - IEC 60287-2-1 Section 4
- External Thermal Resistance (T4) - IEC 60287-2-1 Section 4.2
- Multi-layer thermal resistance summation
- Trefoil and flat formation T4 corrections
"""
module Thermal

using ....Commons: π
using ....DataModel: CableDesign, ConductorGroup, LineCableSystem, CableComponent

export calc_T1,
       calc_T2,
       calc_T3,
       calc_T4,
       calc_T4_trefoil,
       calc_T4_air,
       calc_layer_thermal_resistance

"""
    calc_layer_thermal_resistance(rho_thermal::T, r_in::T, r_ext::T) where {T<:Real}

Calculates the thermal resistance of a single concentric cylindrical layer [K·m/W].
This is the fundamental building block for computing T1 and T3 as sums over cable layers.
IEC 60287-2-1 Section 4.1.2.

# Arguments
- `rho_thermal`: Thermal resistivity of the layer material [K·m/W].
- `r_in`: Inner radius of the layer [m].
- `r_ext`: Outer radius of the layer [m].

# Returns
- Thermal resistance per unit length [K·m/W].
"""
function calc_layer_thermal_resistance(rho_thermal::T, r_in::T, r_ext::T) where {T<:Real}
    if r_ext <= r_in || rho_thermal <= 0
        return zero(T)
    end
    return (rho_thermal / (2 * π)) * log(r_ext / r_in)
end

"""
    calc_T1(rho_insulation::T, t_insulation::T, d_c::T) where {T<:Real}

Calculates the thermal resistance of the insulation `T_1` [K·m/W].
Assumes a single-layer round conductor. For multi-layer T1, use `calc_layer_thermal_resistance`
and sum per layer.

# Arguments
- `rho_insulation`: Thermal resistivity of insulation [K·m/W].
- `t_insulation`: Thickness of insulation [m].
- `d_c`: Diameter of conductor [m].

# Returns
- `T_1`: Thermal resistance per unit length [K·m/W].
"""
function calc_T1(rho_insulation::T, t_insulation::T, d_c::T) where {T<:Real}
    # IEC 60287-2-1 Section 4.1.2
    # T1 = rho / (2 * pi) * ln(1 + 2 * t / dc)
    return (rho_insulation / (2 * π)) * log(1 + (2 * t_insulation) / d_c)
end

"""
    calc_T2(rho_bedding::T, t_bedding::T, d_sheath::T) where {T<:Real}

Calculates the thermal resistance of the bedding/armour `T_2` [K·m/W].

# Arguments
- `rho_bedding`: Thermal resistivity of bedding/armour [K·m/W].
- `t_bedding`: Thickness of bedding/armour [m].
- `d_sheath`: Diameter of sheath/screen (outer diameter of underlying layer) [m].

# Returns
- `T_2`: Thermal resistance per unit length [K·m/W].
"""
function calc_T2(rho_bedding::T, t_bedding::T, d_sheath::T) where {T<:Real}
    # T2 = rho / (2 * pi) * ln(1 + 2 * t / d_sheath)
    return (rho_bedding / (2 * π)) * log(1 + (2 * t_bedding) / d_sheath)
end

"""
    calc_T3(rho_jacket::T, t_jacket::T, d_armour::T) where {T<:Real}

Calculates the thermal resistance of the outer serving (jacket) `T_3` [K·m/W].

# Arguments
- `rho_jacket`: Thermal resistivity of serving [K·m/W].
- `t_jacket`: Thickness of serving [m].
- `d_armour`: Diameter over armour (outer diameter of underlying layer) [m].

# Returns
- `T_3`: Thermal resistance per unit length [K·m/W].
"""
function calc_T3(rho_jacket::T, t_jacket::T, d_armour::T) where {T<:Real}
    # T3 = rho / (2 * pi) * ln(1 + 2 * t / d_armour)
    return (rho_jacket / (2 * π)) * log(1 + (2 * t_jacket) / d_armour)
end

"""
    calc_T4(rho_soil::T, L::T, D_e::T) where {T<:Real}

Calculates external thermal resistance for a single isolated buried cable `T_4` [K·m/W].

# Arguments
- `rho_soil`: Thermal resistivity of soil [K·m/W].
- `L`: Depth of burial (to axis of cable) [m].
- `D_e`: External diameter of cable [m].

# Returns
- `T_4`: Thermal resistance per unit length [K·m/W].
"""
function calc_T4(rho_soil::T, L::T, D_e::T) where {T<:Real}
    # IEC 60287-2-1 Section 4.2.4
    # T4 = rho / (2 * pi) * ln(u + sqrt(u^2 - 1)) where u = 2L/De
    u = 2 * L / D_e
    return (rho_soil / (2 * π)) * log(u + sqrt(u^2 - 1))
end

"""
    calc_T4_trefoil(rho_soil::T, L::T, D_e::T) where {T<:Real}

Calculates external thermal resistance for three single-core cables in close trefoil [K·m/W].
IEC 60287-2-1 Section 4.2.4.3.3.

For close trefoil touching arrangement, where L is the depth to the centre of the trefoil group:

    T₄ = (1.5/π) · ρ_soil · [ln(2u) − 0.630]

where u = 2L/Dₑ.

# Arguments
- `rho_soil`: Thermal resistivity of soil [K·m/W].
- `L`: Depth of burial to centre of trefoil group [m].
- `D_e`: External diameter of one cable [m].

# Returns
- `T_4`: External thermal resistance per cable per unit length [K·m/W].
"""
function calc_T4_trefoil(rho_soil::T, L::T, D_e::T) where {T<:Real}
    u = 2 * L / D_e
    return (T(1.5) / π) * rho_soil * (log(2 * u) - T(0.630))
end

"""
    calc_T4_air(De::T, T_ambient::T, T_surface::T, h::T) where {T<:Real}

Calculates external thermal resistance for cables in free air `T_4*` [K·m/W].

# Arguments
- `De`: External diameter of cable [m].
- `T_ambient`: Ambient air temperature [°C].
- `T_surface`: Cable surface temperature [°C].
- `h`: Heat transfer coefficient [W/(m²·K)].

# Returns
- `T4_star`: Thermal resistance per unit length in air [K·m/W].
"""
function calc_T4_air(De::T, T_ambient::T, T_surface::T, h::T) where {T<:Real}
    return 1 / (π * De * h)
end

end # module
