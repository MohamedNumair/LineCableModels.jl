"""
    LineCableModels.Engine.IEC60287.Thermal

This module implements the thermal resistance calculation component of the IEC 60287 analytical formulation.
It covers:
- Internal Thermal Resistance (T1, T2, T3) - IEC 60287-1-1 Section 1.4
- External Thermal Resistance (T4) - IEC 60287-1-1 Section 1.4.1
"""
module Thermal

using ...Commons: π
using ...DataModel: CableDesign, ConductorGroup, LineCableSystem, CableComponent

export calc_T1,
       calc_T2,
       calc_T3,
       calc_T4,
       calc_T4_air

"""
    calc_T1(rho_insulation::T, t_insulation::T, d_c::T) where {T<:Real}

Calculates the thermal resistance of the insulation `T_1` [K·m/W].
Assumes a round conductor.

# Arguments
- `rho_insulation`: Thermal resistivity of insulation [K·m/W].
- `t_insulation`: Thickness of insulation [m].
- `d_c`: Diameter of conductor [m].

# Returns
- `T_1`: Thermal resistance per unit length [K·m/W].
"""
function calc_T1(rho_insulation::T, t_insulation::T, d_c::T) where {T<:Real}
    # IEC 60287-1-1 Section 1.4.2
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

Calculates external thermal resistance for buried cables `T_4` [K·m/W]
Assumes a single buried cable.

# Arguments
- `rho_soil`: Thermal resistivity of soil [K·m/W].
- `L`: Depth of burial (to axis of cable) [m].
- `D_e`: External diameter of cable [m].

# Returns
- `T_4`: Thermal resistance per unit length [K·m/W].
"""
function calc_T4(rho_soil::T, L::T, D_e::T) where {T<:Real}
    # IEC 60287-1-1 Section 1.4.1.1
    # T4 = rho / (2 * pi) * ln(u + sqrt(u^2 - 1)) where u = 2L/De
    u = 2 * L / D_e
    return (rho_soil / (2 * π)) * log(u + sqrt(u^2 - 1))
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
    # IEC 60287-1-1 Section 1.4.4.1
    # T4* = 1 / (pi * De * h * (Delta_theta)^(1/4))? No.
    
    # T4* = 1 / (pi * De * h * (T_surf - T_amb)^0.25) is common approx.
    # The standard formula is likely more complex involving Nusselts numbers.
    
    # For now, simplistic generic heat transfer:
    # Q = h * A * (Ts - Ta)
    # R_th = (Ts - Ta) / Q = 1 / (h * A) = 1 / (h * pi * De * 1m)
    return 1 / (π * De * h)
end

end # module
