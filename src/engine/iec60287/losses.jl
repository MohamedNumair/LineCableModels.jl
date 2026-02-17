"""
    LineCableModels.Engine.IEC60287.Losses

This module implements the loss calculation component of the IEC 60287 analytical formulation.
It covers:
- AC Resistance (Skin and Proximity effects) - IEC 60287-1-1 Section 2.1
- Dielectric Losses - IEC 60287-1-1 Section 2.2
- Sheath and Screen Loss Factors - IEC 60287-1-1 Section 2.3
- Armour Loss Factors - IEC 60287-1-1 Section 2.4
"""
module Losses

using ....Commons: μ₀, π
using ....DataModel: CableDesign, ConductorGroup, LineCableSystem, CableComponent

export calc_ac_resistance,
       calc_skin_effect_factor,
       calc_proximity_effect_factor,
       calc_dielectric_loss,
       calc_sheath_loss_factors,
       calc_armour_loss_factors,
       calc_screen_resistance,
       calc_screen_degree_of_cover,
       calc_capacitance

"""
    calc_skin_effect_factor(R_dc::T, f::T, k_s::T) where {T<:Real}

Calculates the skin effect factor `y_s` according to IEC 60287-1-1 Section 2.1.2.

# Arguments
- `R_dc`: DC resistance of the conductor at operating temperature [Ω/m].
- `f`: Frequency [Hz].
- `k_s`: Skin effect coefficient (see IEC 60287-1-1 Table 2).

# Returns
- `y_s`: Skin effect factor [dimensionless].
"""
function calc_skin_effect_factor(R_dc::T, f::T, k_s::T) where {T<:Real}
    # IEC 60287-1-1 Ed 2.0 Eq (2):
    # x_s^2 = 8*pi*f / R' * 10^-7 * k_s  (R' in Ω/m)
    xs2 = 8 * π * f / R_dc * 1e-7 * k_s
    xs4 = xs2^2

    # Three ranges per standard; for x_s <= 2.8 (i.e. xs2 <= 7.84):
    if xs2 <= T(7.84)
        ys = xs4 / (192 + T(0.8) * xs4)
    elseif xs2 <= T(44.89)  # x_s <= 6.7 → xs2 <= 44.89
        ys = T(-0.136) - T(0.0177) * xs2 + T(0.0563) * xs2 * sqrt(xs2)
    else
        ys = T(0.354) * xs2 - T(0.733)
    end
    return ys
end

"""
    calc_proximity_effect_factor(R_dc::T, f::T, k_p::T, dc::T, s::T) where {T<:Real}

Calculates the proximity effect factor `y_p` for two- or three-core single-core cables
in trefoil or flat formation. IEC 60287-1-1 Section 2.1.3-2.1.4.

# Arguments
- `R_dc`: DC resistance at operating temperature [Ω/m].
- `f`: Frequency [Hz].
- `k_p`: Proximity effect coefficient (IEC 60287-1-1 Table 2).
- `dc`: Diameter of conductor [m].
- `s`: Distance between conductor axes [m].

# Returns
- `y_p`: Proximity effect factor [dimensionless].
"""
function calc_proximity_effect_factor(R_dc::T, f::T, k_p::T, dc::T, s::T) where {T<:Real}
    # IEC 60287-1-1 Section 2.1.3 — Three single-core cables (trefoil)
    # x_p^2 = 8*pi*f / R' * 10^-7 * k_p
    xp2 = 8 * π * f / R_dc * 1e-7 * k_p
    xp4 = xp2^2

    # F1 = xp^4 / (192 + 0.8 * xp^4)  (valid for x_p <= 2.8)
    F1 = xp4 / (192 + T(0.8) * xp4)

    dcs2 = (dc / s)^2  # (d_c / s)^2

    # y_p = F1 * (dc/s)^2 * [0.312 * (dc/s)^2 + 1.18 / (F1 + 0.27)]
    yp = F1 * dcs2 * (T(0.312) * dcs2 + T(1.18) / (F1 + T(0.27)))

    return yp
end

"""
    calc_ac_resistance(R_dc_20::T, alpha::T, theta::T, f::T, k_s::T, k_p::T,
                       dc::T, s::T) where {T<:Real}

Calculates the AC resistance at operating temperature, including skin and proximity effects.
IEC 60287-1-1 Section 2.1.

# Arguments
- `R_dc_20`: DC resistance at 20 °C [Ω/m].
- `alpha`: Temperature coefficient of resistance at 20 °C [1/K].
- `theta`: Operating temperature [°C].
- `f`: Frequency [Hz].
- `k_s`: Skin effect coefficient.
- `k_p`: Proximity effect coefficient.
- `dc`: Conductor diameter [m].
- `s`: Distance between conductor axes [m].

# Returns
- Named tuple `(R_ac, R_dc_theta, y_s, y_p)`.
"""
function calc_ac_resistance(R_dc_20::T, alpha::T, theta::T, f::T, k_s::T, k_p::T,
                            dc::T, s::T) where {T<:Real}
    # Step 1: DC resistance at operating temperature
    R_dc_theta = R_dc_20 * (1 + alpha * (theta - 20))

    # Step 2-3: Skin effect
    y_s = calc_skin_effect_factor(R_dc_theta, f, k_s)

    # Step 4-5: Proximity effect
    y_p = calc_proximity_effect_factor(R_dc_theta, f, k_p, dc, s)

    # Step 6: AC resistance
    R_ac = R_dc_theta * (1 + y_s + y_p)

    return (; R_ac, R_dc_theta, y_s, y_p)
end

"""
    calc_dielectric_loss(U0::T, omega::T, C::T, tandelta::T) where {T<:Real}

Calculates dielectric loss per phase `W_d` [W/m].
IEC 60287-1-1 Section 2.2.

# Arguments
- `U0`: Voltage to earth [V].
- `omega`: Angular frequency [rad/s].
- `C`: Capacitance [F/m].
- `tandelta`: Loss factor.
"""
function calc_dielectric_loss(U0::T, omega::T, C::T, tandelta::T) where {T<:Real}
    return omega * C * U0^2 * tandelta
end

"""
    calc_capacitance(eps_r::T, D_i::T, d_cs::T) where {T<:Real}

Calculates insulation capacitance per unit length [F/m].
IEC 60287-1-1 Section 2.2.

# Arguments
- `eps_r`: Relative permittivity of insulation.
- `D_i`: External diameter of insulation [m].
- `d_cs`: External diameter of conductor screen [m].
"""
function calc_capacitance(eps_r::T, D_i::T, d_cs::T) where {T<:Real}
    return eps_r / (18 * log(D_i / d_cs)) * 1e-9
end

"""
    calc_screen_resistance(rho_s, alpha_s, n_wires, d_wire, D_under, L_lay, theta_s)

Calculates the wire screen AC resistance at given temperature [Ω/m].
IEC 60287-1-1 Section 2.3.

# Arguments
- `rho_s`: Screen material resistivity at 20 °C [Ω·m].
- `alpha_s`: Temperature coefficient at 20 °C [1/K].
- `n_wires`: Number of screen wires.
- `d_wire`: Diameter of each screen wire [m].
- `D_under`: Diameter under screen wires [m].
- `L_lay`: Length of lay of screen wires [m].
- `theta_s`: Screen operating temperature [°C].

# Returns
- Named tuple `(R_s, R_s0, A_s, LF_s, d_mean)`.
"""
function calc_screen_resistance(rho_s::T, alpha_s::T, n_wires::Int, d_wire::T,
                                D_under::T, L_lay::T, theta_s::T) where {T<:Real}
    # Cross-sectional area of screen wires
    A_s = n_wires * π * (d_wire / 2)^2

    # Lay factor
    LF_s = sqrt(1 + (π * (D_under + d_wire))^2 / L_lay^2)

    # Resistance at 20 °C
    R_s0 = LF_s * rho_s / A_s

    # Resistance at operating temperature
    R_s = R_s0 * (1 + alpha_s * (theta_s - 20))

    # Mean diameter of screen
    d_mean = D_under + d_wire

    return (; R_s, R_s0, A_s, LF_s, d_mean)
end

"""
    calc_sheath_loss_factors(R_s, R_ac, s, d_mean, omega; bonding=:solid)

Calculates the sheath/screen loss factor λ₁ for solid bonding (both-end bonding).
IEC 60287-1-1 Section 2.3.1.

# Arguments
- `R_s`: Screen resistance at operating temperature [Ω/m].
- `R_ac`: Conductor AC resistance at operating temperature [Ω/m].
- `s`: Spacing between conductor axes [m].
- `d_mean`: Mean diameter of screen [m].
- `omega`: Angular frequency [rad/s].

# Returns
- Named tuple `(lambda1, lambda1_circ, lambda1_eddy, X_s)`.
"""
function calc_sheath_loss_factors(R_s::T, R_ac::T, s::T, d_mean::T, omega::T;
                                  bonding::Symbol = :solid) where {T<:Real}
    # Reactance per unit length of screen
    X_s = 2 * omega * 1e-7 * log(2 * s / d_mean)

    if bonding == :solid
        # Circulating current losses — IEC 60287-1-1 Eq 2.3.1
        lambda1_circ = (R_s / R_ac) / (1 + (R_s / X_s)^2)
    elseif bonding == :single_point
        lambda1_circ = zero(T)
    elseif bonding == :cross_bonded
        lambda1_circ = zero(T)
    else
        lambda1_circ = zero(T)
    end

    # Eddy current losses — for wire screens without outer covering tape,
    # lambda1_eddy = 0 per IEC 60287-1-1 Section 2.3.3
    lambda1_eddy = zero(T)

    lambda1 = lambda1_circ + lambda1_eddy

    return (; lambda1, lambda1_circ, lambda1_eddy, X_s)
end

"""
    calc_armour_loss_factors(::T) where {T<:Real}

Returns zero armour loss factors (no armour present).

# Returns
- Named tuple `(lambda2,)`.
"""
function calc_armour_loss_factors(::Type{T} = Float64) where {T<:Real}
    return (; lambda2 = zero(T))
end

"""
    calc_screen_degree_of_cover(d_wire, n_wires, D_under, LF_s)

Calculates the degree of cover of wire screen.
IEC 60287-2-1 Section 4.2.4.3.3.

# Arguments
- `d_wire`: Wire diameter [m].
- `n_wires`: Number of screen wires.
- `D_under`: Diameter under screen wires [m].
- `LF_s`: Lay factor of screen wires.

# Returns
- Degree of cover as a fraction (0 to 1).
"""
function calc_screen_degree_of_cover(d_wire::T, n_wires::Int, D_under::T,
                                      LF_s::T) where {T<:Real}
    return (d_wire * n_wires * LF_s) / (π * (D_under + d_wire))
end

end # module
