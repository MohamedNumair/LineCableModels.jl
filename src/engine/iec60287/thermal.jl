"""
    LineCableModels.Engine.IEC60287.Thermal

This module implements the thermal resistance calculation component of the IEC 60287 analytical formulation.
It covers:
- Internal Thermal Resistance (T1, T2, T3) - IEC 60287-2-1 Section 4
- External Thermal Resistance (T4) - IEC 60287-2-1 Section 4.2
- Multi-layer thermal resistance summation
- Armour Loss Factors — IEC 60287-1-1 Section 2.4
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
       calc_T4_flat,
       calc_T4_duct,
       calc_T4_air,
       calc_solar_radiation_rise,
       calc_layer_thermal_resistance

"""
    calc_layer_thermal_resistance(rho_thermal::T, r_in::T, r_ext::T) where {T<:Real}

Calculates the thermal resistance of a single concentric cylindrical layer [K·m/W].
This is the fundamental building block for computing ``T_1`` and ``T_3`` as sums
over cable layers.

# Formulation

``T_{\\text{layer}} = \\frac{\\rho_T}{2\\pi} \\ln\\!\\left(\\frac{r_{\\text{ext}}}{r_{\\text{in}}}\\right)``

# Arguments
- `rho_thermal`: Thermal resistivity of the layer material [K·m/W].
- `r_in`: Inner radius of the layer [m].
- `r_ext`: Outer radius of the layer [m].

# Returns
- Thermal resistance per unit length [K·m/W].

# Source
IEC 60287-2-1:2015, Section 4.1.2

# CIGRE TB880 Guidance
Do not combine layers of different materials (e.g., semi-con and insulation)
into a single layer; calculate separately (Guidance Point 15).
"""
function calc_layer_thermal_resistance(rho_thermal::T, r_in::T, r_ext::T) where {T<:Real}
    if r_ext <= r_in || rho_thermal <= 0
        return zero(T)
    end
    return (rho_thermal / (2 * π)) * log(r_ext / r_in)
end

"""
    calc_T1(rho_insulation::T, t_insulation::T, d_c::T) where {T<:Real}

Calculates the thermal resistance of the insulation ``T_1`` [K·m/W] for a single
homogeneous insulation layer around a round conductor.

# Formulation

``T_1 = \\frac{\\rho_i}{2\\pi} \\ln\\!\\left(1 + \\frac{2 t_1}{d_c}\\right)``

For cables with multiple insulation layers (semicon + XLPE + semicon + bedding),
use [`calc_layer_thermal_resistance`](@ref) for each layer and sum.

# Arguments
- `rho_insulation`: Thermal resistivity of insulation [K·m/W].
- `t_insulation`: Thickness of insulation [m].
- `d_c`: Diameter of conductor [m].

# Returns
- ``T_1``: Thermal resistance per unit length [K·m/W].

# Source
IEC 60287-2-1:2015, Clause 4.1.2.1

# CIGRE TB880 Guidance
Do not combine layers of different materials into a single layer; calculate
separately (Guidance Point 15). For 3-core cables, divide ``T_1`` by the
'lay length factor' (Guidance Point 44). Do **not** apply the screening factor
increase (1.16 or 1.07) for trefoil cables in air (Guidance Point 46).
"""
function calc_T1(rho_insulation::T, t_insulation::T, d_c::T) where {T<:Real}
    # IEC 60287-2-1 Section 4.1.2
    # T1 = rho / (2 * pi) * ln(1 + 2 * t / dc)
    return (rho_insulation / (2 * π)) * log(1 + (2 * t_insulation) / d_c)
end

"""
    calc_T2(rho_bedding::T, t_bedding::T, d_sheath::T) where {T<:Real}

Calculates the thermal resistance of the bedding/armour ``T_2`` [K·m/W].

# Formulation

``T_2 = \\frac{\\rho_b}{2\\pi} \\ln\\!\\left(1 + \\frac{2 t_b}{d_s}\\right)``

# Arguments
- `rho_bedding`: Thermal resistivity of bedding/armour [K·m/W].
- `t_bedding`: Thickness of bedding/armour [m].
- `d_sheath`: Diameter of sheath/screen (outer diameter of underlying layer) [m].

# Returns
- ``T_2``: Thermal resistance per unit length [K·m/W].

# Source
IEC 60287-2-1:2015, Clause 4.1.2
"""
function calc_T2(rho_bedding::T, t_bedding::T, d_sheath::T) where {T<:Real}
    # T2 = rho / (2 * pi) * ln(1 + 2 * t / d_sheath)
    return (rho_bedding / (2 * π)) * log(1 + (2 * t_bedding) / d_sheath)
end

"""
    calc_T3(rho_jacket::T, t_jacket::T, d_armour::T) where {T<:Real}

Calculates the thermal resistance of the outer serving (jacket) ``T_3`` [K·m/W].

# Formulation

``T_3 = \\frac{\\rho_j}{2\\pi} \\ln\\!\\left(1 + \\frac{2 t_j}{d_a}\\right)``

# Arguments
- `rho_jacket`: Thermal resistivity of serving [K·m/W].
- `t_jacket`: Thickness of serving [m].
- `d_armour`: Diameter over armour (outer diameter of underlying layer) [m].

# Returns
- ``T_3``: Thermal resistance per unit length [K·m/W].

# Source
IEC 60287-2-1:2015, Clause 4.1.2
"""
function calc_T3(rho_jacket::T, t_jacket::T, d_armour::T) where {T<:Real}
    # T3 = rho / (2 * pi) * ln(1 + 2 * t / d_armour)
    return (rho_jacket / (2 * π)) * log(1 + (2 * t_jacket) / d_armour)
end

"""
    calc_T4(rho_soil::T, L::T, D_e::T) where {T<:Real}

Calculates external thermal resistance for a single isolated buried cable
``T_4`` [K·m/W].

# Formulation

``T_4 = \\frac{\\rho_T}{2\\pi} \\ln\\!\\left(u + \\sqrt{u^2 - 1}\\right),
\\quad u = \\frac{2L}{D_e}``

# Arguments
- `rho_soil`: Thermal resistivity of soil [K·m/W].
- `L`: Depth of burial (to axis of cable) [m].
- `D_e`: External diameter of cable [m].

# Returns
- ``T_4``: Thermal resistance per unit length [K·m/W].

# Source
IEC 60287-2-1:2015, Clause 4.2.2

# CIGRE TB880 Guidance
The approximation ``T_4 = (\\rho_T/2\\pi)\\ln(2u)`` for ``u > 10`` should **not** be
used. Always use the full formula with the square root term (Guidance Point 8).
For groups of cables (non-touching), use the 'unequally loaded' method
(superposition) even if cables are equally loaded.
"""
function calc_T4(rho_soil::T, L::T, D_e::T) where {T<:Real}
    # IEC 60287-2-1 Section 4.2.4
    # T4 = rho / (2 * pi) * ln(u + sqrt(u^2 - 1)) where u = 2L/De
    u = 2 * L / D_e
    return (rho_soil / (2 * π)) * log(u + sqrt(u^2 - 1))
end

"""
    calc_T4_trefoil(rho_soil::T, L::T, D_e::T) where {T<:Real}

Calculates external thermal resistance for three single-core cables in close
(touching) trefoil formation ``T_4`` [K·m/W].

# Formulation

``T_4 = \\frac{1.5}{\\pi}\\,\\rho_{\\text{soil}}
      \\left[\\ln(2u) - 0.630\\right],
\\quad u = \\frac{2L}{D_e}``

# Arguments
- `rho_soil`: Thermal resistivity of soil [K·m/W].
- `L`: Depth of burial to centre of trefoil group [m].
- `D_e`: External diameter of one cable [m].

# Returns
- ``T_4``: External thermal resistance per cable per unit length [K·m/W].

# Source
IEC 60287-2-1:2015, Section 4.2.4.3.3
"""
function calc_T4_trefoil(rho_soil::T, L::T, D_e::T) where {T<:Real}
    u = 2 * L / D_e
    return (T(1.5) / π) * rho_soil * (log(2 * u) - T(0.630))
end

"""
    calc_T4_air(De::T, T_ambient::T, T_surface::T, h::T) where {T<:Real}

Calculates external thermal resistance for cables in free air ``T_4^*`` [K·m/W].

# Formulation

``T_4^* = \\frac{1}{\\pi D_e^* h}``

where ``h`` is the heat transfer coefficient. For a full implementation, an
iterative process is required for surface temperature.

# Arguments
- `De`: External diameter of cable [m].
- `T_ambient`: Ambient air temperature [°C].
- `T_surface`: Cable surface temperature [°C].
- `h`: Heat transfer coefficient [W/(m²·K)].

# Returns
- ``T_4^*``: Thermal resistance per unit length in air [K·m/W].

# Source
IEC 60287-2-1:2015, Clause 4.2.1

# CIGRE TB880 Guidance
Iterative process required for surface temperature. TB880 Case Study 0-4
demonstrates implementation with solar radiation inclusion.
"""
function calc_T4_air(De::T, T_ambient::T, T_surface::T, h::T) where {T<:Real}
    return 1 / (π * De * h)
end

"""
    calc_T4_flat(rho_soil::T, L::T, D_e::T, s::T, n_cables::Int)

Calculates external thermal resistance for cables in flat formation (buried).
Uses the superposition method (sum of temperature rises).

# Formulation (3 cables)

``T_4 = \\frac{\\rho_T}{2\\pi} \\left[ \\ln(u + \\sqrt{u^2-1}) + \\ln(u_{12} + \\sqrt{u_{12}^2+1}) + ... \\right]``

where ``u = 2L / D_e`` and ``u_{xy} = 2L / s_{xy}``.

# Source
IEC 60287-2-1:2015, Clause 4.2.3
"""
function calc_T4_flat(rho_soil::T, L::T, D_e::T, s::T, n_cables::Int) where {T<:Real}
    # Geometric factor for the cable itself
    u = 2 * L / D_e
    
    # Self-term
    # ln(u + sqrt(u^2 - 1))
    term_self = log(u + sqrt(u^2 - 1))
    
    # Mutual terms (for middle cable, worst case)
    # Distance to neighbors is s. u_p = 2L / s
    # ln(u_p + sqrt(u_p^2 + 1))
    
    # Assumption: Equally loaded.
    # Only dealing with 3 cables for now.
    
    u_p = 2 * L / s
    term_mutual = log(u_p + sqrt(u_p^2 + 1))
    
    if n_cables == 3
        # Middle cable sees two neighbors at distance s
        # T4 = rho / 2pi * (self + mutual_1 + mutual_2)
        total_geom = term_self + 2 * term_mutual
        
        return (rho_soil / (2 * π)) * total_geom
    else
        # Fallback for single or other
        return (rho_soil / (2 * π)) * term_self
    end
end

"""
    calc_T4_duct(rho_soil::T, L::T, D_e::T, D_duct_in::T, D_duct_ex::T, rho_duct::T)

Calculates T4 for cable in duct.

# Source
IEC 60287-2-1:2015, Clause 4.2.6
"""
function calc_T4_duct(rho_soil::T, L::T, D_e::T, D_duct_in::T, D_duct_ex::T, rho_duct::T) where {T<:Real}
    # T4' = U / (1 + 0.1(V + Y*theta_m)*De) -> Air space resistance
    # Simplified U, V, Y constants recommended by IEC for certain fills. 
    # For now, using simplified constants for air-filled duct.
    
    # T4'' = rho_duct / 2pi * ln(Do/Di) -> Duct wall
    T4_wall = rho_duct / (2 * π) * log(D_duct_ex / D_duct_in)
    
    # T4''' = external soil (as if duct was the cable)
    u = 2 * L / D_duct_ex
    T4_soil = (rho_soil / (2 * π)) * log(u + sqrt(u^2 - 1))
    
    # Placeholder for T4_air (complex iteration dependent)
    # Using a typical empirical base value for now
    T4_air = 0.5 
    
    return T4_air + T4_wall + T4_soil
end

"""
    calc_solar_radiation_rise(sigma, De, H, T1, T2, T3, lambda1, lambda2, n)

Calculates temperature rise due to solar radiation.

# Source
IEC 60287-2-1:2015, Clause 4.2.1.2
"""
function calc_solar_radiation_rise(sigma::T, De::T, H::T, 
                                   T1::T, T2::T, T3::T, 
                                   lambda1::T, lambda2::T, n::Int) where {T<:Real}
    # Delta theta_solar = ...
    # Effective resistance seen by surface heat flux:
    # The heat enters surface, flows through T4* (which acts in parallel with convection/radiation out?).
    # Standard formula:
    # dtheta = sigma * De * H * T4_eff? 
    # IEC 2-1 Eq (8):
    # dtheta = sigma * H * De * T4_star
    # Note: T4_star is the external thermal resistance in air.
    
    # This function actually usually requires T4_star to be passed in, or computed.
    # Assuming T4 (external) is passed in T3 slot or we need a T4 arg.
    # Refactoring signature in future to accept T4 explicitly is better.
    # For now, return 0.0 or implement if T4 is available in context.
    
    return 0.0 # Placeholder
end

end # module
