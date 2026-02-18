"""
    LineCableModels.Engine.IEC60287.Losses

This module implements the loss calculation component of the IEC 60287 analytical formulation.
It covers:
- AC Resistance (Skin and Proximity effects) - IEC 60287-1-1 Section 2.1
- Dielectric Losses - IEC 60287-1-1 Section 2.2
- Sheath and Screen Loss Factors - IEC 60287-1-1 Section 2.3
- Armour Loss Factors — IEC 60287-1-1 Section 2.4
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

Calculates the skin effect factor ``y_s`` for the conductor.

# Formulation

``x_s = \\sqrt{\\frac{8\\pi f}{R'} \\cdot 10^{-7} \\cdot k_s}``

``y_s = \\frac{x_s^4}{192 + 0.8 x_s^4} \\quad (x_s \\le 2.8)``

Two additional piecewise ranges cover ``2.8 < x_s \\le 6.7`` and ``x_s > 6.7``.

# Arguments
- `R_dc`: DC resistance of the conductor at operating temperature [Ω/m].
- `f`: Frequency [Hz].
- `k_s`: Skin effect coefficient (see IEC 60287-1-1 Table 2).

# Returns
- `y_s`: Skin effect factor [dimensionless].

# Source
IEC 60287-1-1:2006, Clause 2.1.2

# CIGRE TB880 Guidance
Use IEC values for ``k_s``. However, if IEC does not provide a value for a specific
modern conductor design (e.g., specific Milliken constructions), values from
CIGRE TB 272 should be used. The provided formula is accurate for ``x_s \\le 2.8``
(Guidance Point 24).
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

Calculates the proximity effect factor ``y_p`` for three-core cables or three
single-core cables.

# Formulation

``x_p = \\sqrt{\\frac{8\\pi f}{R'} \\cdot 10^{-7} \\cdot k_p}``

``y_p = \\frac{x_p^4}{192 + 0.8 x_p^4} \\left(\\frac{d_c}{s}\\right)^2
        \\cdot \\left[ 0.312 \\left(\\frac{d_c}{s}\\right)^2
        + \\frac{1.18}{\\frac{x_p^4}{192 + 0.8 x_p^4} + 0.27} \\right]``

# Arguments
- `R_dc`: DC resistance at operating temperature [Ω/m].
- `f`: Frequency [Hz].
- `k_p`: Proximity effect coefficient (IEC 60287-1-1 Table 2).
- `dc`: Diameter of conductor [m].
- `s`: Distance between conductor axes [m].

# Returns
- `y_p`: Proximity effect factor [dimensionless].

# Source
IEC 60287-1-1:2006, Clause 2.1.4.1

# CIGRE TB880 Guidance
For sector-shaped conductors, use IEC 60228 to find the min and max diameters of an
equivalent circular conductor and select the one giving the worst-case rating
(Guidance Point 22). For magnetic armoured cables, this factor is multiplied by 1.5
in the final resistance calculation (Guidance Point 25).
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
    calc_ac_resistance(R_dc_20, alpha, theta, f, k_s, k_p, dc, s)

Calculates the AC resistance of the conductor at operating temperature, accounting
for skin and proximity effects.

# Formulation

``R' = R_{\\text{dc,20}} \\left[1 + \\alpha_{20}(\\theta - 20)\\right]``

``R = R' \\cdot (1 + y_s + y_p)``

# Arguments
- `R_dc_20`: DC resistance at 20 °C [Ω/m].
- `alpha`: Temperature coefficient of resistance at 20 °C [1/K].
- `theta`: Maximum operating temperature [°C].
- `f`: Frequency [Hz].
- `k_s`: Skin effect coefficient.
- `k_p`: Proximity effect coefficient.
- `dc`: Conductor diameter [m].
- `s`: Distance between conductor axes [m].

# Returns
- Named tuple `(R_ac, R_dc_theta, y_s, y_p)`.

# Source
IEC 60287-1-1:2006, Clause 2.1

# CIGRE TB880 Guidance
For magnetic armoured or shielded cables (single or three-phase), the skin and
proximity effects must be increased by a factor of 1.5. The formula becomes
``R = R' \\cdot [1 + 1.5(y_s + y_p)]`` (Guidance Point 25).
For three-core or triplex cables, if DC resistance is calculated from cross-section
(not taken from IEC 60228), a 'lay length factor' must be applied to ``R'``
(Guidance Point 23).
"""
function calc_ac_resistance(R_dc_20::T, alpha::T, theta::T, f::T, k_s::T, k_p::T,
                            dc::T, s::T) where {T<:Real}
    # Step 1: DC resistance at operating temperature
    R_dc_theta = R_dc_20 * (1 + alpha * (theta - 20))

    # Step 2: Skin effect factor
    y_s = calc_skin_effect_factor(R_dc_theta, f, k_s)

    # Step 3: Proximity effect factor
    y_p = calc_proximity_effect_factor(R_dc_theta, f, k_p, dc, s)

    # Step 4: AC resistance
    R_ac = R_dc_theta * (1 + y_s + y_p)

    return (; R_ac, R_dc_theta, y_s, y_p)
end

"""
    calc_dielectric_loss(U0, omega, C, tandelta)

Calculates the dielectric losses per phase for AC cables.

# Formulation

``W_d = 2 \\pi f \\cdot C \\cdot U_0^2 \\cdot \\tan\\delta``

equivalently, ``W_d = \\omega \\cdot C \\cdot U_0^2 \\cdot \\tan\\delta``.

# Arguments
- `U0`: Voltage to earth [V].
- `omega`: Angular frequency ``\\omega = 2\\pi f`` [rad/s].
- `C`: Capacitance per unit length [F/m].
- `tandelta`: Loss factor of the insulation ``\\tan\\delta`` [dimensionless].

# Returns
- `W_d`: Dielectric losses per phase [W/m].

# Source
IEC 60287-1-1:2006, Clause 2.2

# CIGRE TB880 Guidance
Dielectric losses must be calculated for **all** voltage levels, ignoring the
voltage thresholds mentioned in IEC 60287-1-1 Table 3 (Guidance Point 7).
For three-core cables, capacitance ``C`` must be corrected by a 'lay length factor'
(Guidance Point 20).
"""
function calc_dielectric_loss(U0::T, omega::T, C::T, tandelta::T) where {T<:Real}
    return omega * C * U0^2 * tandelta
end

"""
    calc_capacitance(eps_r, D_i, d_cs)

Calculates insulation capacitance per unit length [F/m].

# Formulation

``C = \\frac{\\varepsilon_r}{18 \\ln(D_i / d_{cs})} \\times 10^{-9}``

# Arguments
- `eps_r`: Relative permittivity of insulation [dimensionless].
- `D_i`: External diameter of insulation [m].
- `d_cs`: External diameter of conductor screen [m].

# Returns
- Capacitance per unit length [F/m].

# Source
IEC 60287-1-1:2006, Clause 2.2
"""
function calc_capacitance(eps_r::T, D_i::T, d_cs::T) where {T<:Real}
    return eps_r / (18 * log(D_i / d_cs)) * 1e-9
end

"""
    calc_screen_resistance(rho_s, alpha_s, n_wires, d_wire, D_under, L_lay, theta_s)

Calculates the wire screen AC resistance at a given temperature [Ω/m].

# Formulation

The cross-sectional area of the screen wires:

``A_s = n \\cdot \\frac{\\pi d_w^2}{4}``

The lay factor accounts for the helical path:

``\\text{LF}_s = \\sqrt{1 + \\frac{(\\pi d_{\\text{mean}})^2}{L_{\\text{lay}}^2}}``

The resistance at 20 °C per unit cable length:

``R_{s0} = \\text{LF}_s \\cdot \\frac{\\rho_s}{A_s}``

And at operating temperature ``\\theta_s``:

``R_s = R_{s0} \\left[1 + \\alpha_s (\\theta_s - 20)\\right]``

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

# Source
IEC 60287-1-1:2006, Section 2.3

# CIGRE TB880 Guidance
For corrugated sheaths, ``R_s`` must be increased by a corrugation factor ``F_{\\text{cor}}``
(Guidance Point 30).
"""
function calc_screen_resistance(rho_s::T, alpha_s::T, n_wires::Int, d_wire::T,
                                D_under::T, L_lay::T, theta_s::T) where {T<:Real}
    # Cross-sectional area of screen wires
    A_s = n_wires * π * (d_wire / 2)^2

    # Mean diameter of screen
    d_mean = D_under + d_wire

    # Lay factor
    LF_s = sqrt(1 + (π * d_mean)^2 / L_lay^2)

    # Resistance at 20 °C
    R_s0 = LF_s * rho_s / A_s

    # Resistance at operating temperature
    R_s = R_s0 * (1 + alpha_s * (theta_s - 20))

    return (; R_s, R_s0, A_s, LF_s, d_mean)
end

"""
    calc_sheath_loss_factors(R_s, R_ac, s, d_mean, omega; bonding=:solid)

Calculates the sheath/screen loss factor ``\\lambda_1``.

# Formulation

For solid bonding (both-end bonding), the circulating-current component is:

``\\lambda_1' = \\frac{R_s}{R} \\cdot \\frac{1}{1 + \\left(\\frac{R_s}{X}\\right)^2}``

where the reactance per unit length is:

``X = 2\\omega \\cdot 10^{-7} \\ln\\!\\left(\\frac{2s}{d_{\\text{mean}}}\\right)``

For `:single_point` and `:cross_bonded` configurations, ``\\lambda_1' = 0``.

The eddy-current component ``\\lambda_1''`` is set to zero for wire screens
without continuous outer covering tape (IEC 60287-1-1 Section 2.3.3).

# Arguments
- `R_s`: Screen resistance at operating temperature [Ω/m].
- `R_ac`: Conductor AC resistance at operating temperature [Ω/m].
- `s`: Spacing between conductor axes [m].
- `d_mean`: Mean diameter of screen [m].
- `omega`: Angular frequency [rad/s].
- `bonding`: Bonding type (`:solid`, `:single_point`, `:cross_bonded`).

# Returns
- Named tuple `(lambda1, lambda1_circ, lambda1_eddy, X_s)`.

# Source
IEC 60287-1-1:2006, Clause 2.3.1

# CIGRE TB880 Guidance
Eddy current losses should **never** be neglected, even if parameter ``m \\le 0.1``
(contrary to IEC note) (Guidance Point 6). Factor ``F`` (reduction of eddy currents
by circulating currents) should be used for **all** solid bonded arrangements, not
just Milliken conductors (Guidance Point 31).
Use the flowcharts in TB880 Figures 10–20 to select the correct loss calculation
method based on cable design (Guidance Point 26).
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
    calc_armour_loss_factors(::Type{T}) where {T<:Real}

Returns zero armour loss factors (no armour present).

# Returns
- Named tuple `(lambda2,)`.

# Source
IEC 60287-1-1:2006, Clause 2.4
"""
function calc_armour_loss_factors(::Type{T} = Float64) where {T<:Real}
    return (; lambda2 = zero(T))
end

"""
    calc_screen_degree_of_cover(d_wire, n_wires, D_under, LF_s)

Calculates the degree of cover of a wire screen.

# Formulation

``\\text{DoC} = \\frac{d_w \\cdot n \\cdot \\text{LF}_s}{\\pi \\left(D_{\\text{under}} + d_w\\right)}``

# Arguments
- `d_wire`: Wire diameter [m].
- `n_wires`: Number of screen wires.
- `D_under`: Diameter under screen wires [m].
- `LF_s`: Lay factor of screen wires.

# Returns
- Degree of cover as a fraction (0 to 1).

# Source
IEC 60287-2-1, Section 4.2.4.3.3
"""
function calc_screen_degree_of_cover(d_wire::T, n_wires::Int, D_under::T,
                                      LF_s::T) where {T<:Real}
    return (d_wire * n_wires * LF_s) / (π * (D_under + d_wire))
end

end # module
