"""
    LineCableModels.Engine.IEC60287.Solver

Solves the AmpacityProblem using the IEC 60287 formulation.
Implements the complete steady-state ampacity calculation including:
- Multi-layer thermal resistances T1, T2, T3 (IEC 60287-2-1)
- Wire screen degree-of-cover correction factors (IEC 60287-2-1 Section 4.2.4.3.3)
- External thermal resistance T4 for buried (single, trefoil, flat) and in-air
- Skin + proximity effects with magnetic armour factor (GP25)
- Dielectric losses, screen/sheath losses, armour losses
- Iterative solution coupling screen temperature to ampacity

# TB 880 Compliance
- Convergence tolerance on current: 1e-3 A (CIGRE TB 880 par.4)
- Convergence tolerance on screen temperature: 1e-3 degC
- Maximum iterations: 100
- Dielectric losses always included in thermal balance (TB 880 par.3.2)
"""
module Solver

using ....DataModel
using ..IEC60287: AmpacityProblem, IEC60287Formulation, IEC60287CableCondition, iec60287_triage
import ..IEC60287: compute!
using ..Losses
using ..Thermal

export compute_ampacity, compute!

"""
    calculate_ac_permissible_current(delta_theta, Wd, R_ac, lambda1, lambda2, T1, T2, T3, T4, n)

Compute the AC permissible current from the IEC 60287-1-1 master equation (Eq. 3).

# Arguments
- `delta_theta`: Allowable temperature rise theta_max - theta_amb  [K]
- `Wd`:          Dielectric loss per unit length            [W/m]
- `R_ac`:        AC resistance at theta_max                 [Ohm/m]
- `lambda1`:     Screen/sheath loss factor ratio
- `lambda2`:     Armour loss factor ratio
- `T1`:          Thermal resistance conductor to screen     [K.m/W]
- `T2`:          Thermal resistance screen to armour        [K.m/W]
- `T3`:          Thermal resistance armour to outer surface  [K.m/W]
- `T4`:          External thermal resistance               [K.m/W]
- `n`:           Number of conductors per cable

# Returns
- Permissible current `I` [A], clamped to 0.0 when the numerator is <= 0.

# Source
IEC 60287-1-1:2006, Clause 1.4.1.1

# TB 880 Guidance
- Never omit `Wd` even when small (TB 880 par.3.2).
- Pass corrected T1, T3 values when wire-screen degree of cover < 50 percent.
"""
function calculate_ac_permissible_current(delta_theta, Wd, R_ac, lambda1, lambda2,
                                          T1, T2, T3, T4, n)
    num = delta_theta - Wd * (0.5 * T1 + n * (T2 + T3 + T4))
    den = R_ac * T1 +
          n * R_ac * (1 + lambda1) * T2 +
          n * R_ac * (1 + lambda1 + lambda2) * (T3 + T4)
    return num > 0 ? sqrt(num / den) : 0.0
end

"""
    compute_ampacity(problem::AmpacityProblem, formulation::IEC60287Formulation)

Calculates the continuous current rating (ampacity) for the cables in the system
according to IEC 60287-1-1/2-1.

The function uses [`iec60287_triage`](@ref) to flatten the nested `AmpacityProblem`
structure into an [`IEC60287CableCondition`](@ref) and then evaluates the analytical
IEC 60287 equations iteratively until the screen-temperature / current coupling
converges to within the TB 880-compliant tolerances.

Supports:
- Wire screens (WireArray) and tubular sheaths (Tubular)
- Non-magnetic and magnetic (steel) wire armour
- Buried cables: single, trefoil, and flat formation T4
- Cables in air with optional solar radiation

Returns a `Dict{String, NamedTuple}` with detailed intermediate values for validation.
"""
function compute_ampacity(problem::AmpacityProblem, formulation::IEC60287Formulation)
    # -- Triage: flatten nested problem into a flat condition struct --------
    cond = iec60287_triage(problem, formulation)

    results = Dict{String, Any}()

    # =====================================================================
    # 1. GEOMETRY
    # =====================================================================

    Dc       = cond.Dc
    De_cable = cond.De
    s        = cond.s
    f        = cond.f
    omega    = cond.omega
    n_cables = cond.n_cables
    is_trefoil = (cond.formation == :trefoil)
    is_flat    = (cond.formation == :flat)

    # =====================================================================
    # 2. DC RESISTANCE AT 20 degC
    # =====================================================================

    R_dc_20   = cond.rho_c / cond.A_c
    theta_max = cond.theta_max
    theta_amb = cond.theta_amb

    # =====================================================================
    # 3. AC RESISTANCE  (skin + proximity + magnetic armour factor)
    # =====================================================================
    
    # Calculate factors
    # Step 1: DC resistance
    R_dc_th = R_dc_20 * (1 + cond.alpha_c * (theta_max - 20))
    
    # Step 2: Skin effect
    y_s = calc_skin_effect_factor(R_dc_th, f, cond.k_s)
    
    # Step 3: Proximity effect
    y_p = 0.0
    if is_flat
         y_p = calc_proximity_effect_factor_flat(R_dc_th, f, cond.k_p, Dc, s, n_cables)
         @debug "Using Flat Formation Proximity Factor: $y_p"
    else
         y_p = calc_proximity_effect_factor(R_dc_th, f, cond.k_p, Dc, s; is_sector=cond.is_sector)
         @debug "Using Trefoil/Standard Proximity Factor: $y_p"
    end
    
    # Step 4: Magnetic Armour Correction (GP 25)
    # R = R' * [1 + 1.5 * (ys + yp)] if magnetic
    R_ac = 0.0
    if cond.is_magnetic_armour
        R_ac = R_dc_th * (1 + 1.5 * (y_s + y_p))
        @debug "Applying Magnetic Armour Correction (1.5x factors)"
    else
        R_ac = R_dc_th * (1 + y_s + y_p)
    end

    # =====================================================================
    # 4. DIELECTRIC LOSSES
    # =====================================================================

    C_cable = cond.C_cable
    U0      = cond.U0
    Wd      = (C_cable > 0 && U0 > 0) ?
              calc_dielectric_loss(U0, omega, C_cable, cond.tan_delta) : 0.0

    # =====================================================================
    # 5. THERMAL RESISTANCE T1  (conductor to screen, multi-layer)
    # =====================================================================

    T1_prime = 0.0
    for (rho_th, r_in, r_ext) in cond.core_insulator_layers
        T1_prime += calc_layer_thermal_resistance(rho_th, r_in, r_ext)
    end

    # =====================================================================
    # 6. THERMAL RESISTANCE T2 (armour bedding)
    #    When armour is present, T2 = thermal resistance between sheath
    #    and armour (the sheath insulation acts as bedding).
    #    When no armour: T2 = 0.
    # =====================================================================

    T2 = 0.0
    if cond.has_armour && !isempty(cond.armour_bedding_layers)
        for (rho_th, r_in, r_ext) in cond.armour_bedding_layers
            T2 += calc_layer_thermal_resistance(rho_th, r_in, r_ext)
        end
    end

    # =====================================================================
    # 7. THERMAL RESISTANCE T3  (jacket / outer covering, multi-layer)
    #    Without armour: sheath insulation layers -> T3
    #    With armour: armour jacket layers -> T3
    # =====================================================================

    T3_prime = 0.0
    if cond.has_armour && !isempty(cond.armour_jacket_layers)
        # T3 = outer serving over armour
        for (rho_th, r_in, r_ext) in cond.armour_jacket_layers
            T3_prime += calc_layer_thermal_resistance(rho_th, r_in, r_ext)
        end
    else
        # T3 = sheath insulation (no armour)
        for (rho_th, r_in, r_ext) in cond.sheath_insulator_layers
            T3_prime += calc_layer_thermal_resistance(rho_th, r_in, r_ext)
        end
    end

    # =====================================================================
    # 8. CORRECTION FACTORS  (wire-screen cover < 50 percent)
    #    IEC 60287-2-1 Note following Table 1
    # =====================================================================

    T1_corr = 1.0
    T3_corr = 1.0

    d_mean_sc = cond.d_mean_screen
    LF_s      = cond.LF_s

    if cond.has_wire_screen
        DoC = calc_screen_degree_of_cover(cond.d_wire, cond.n_wires,
                                          cond.D_under, LF_s)
        if DoC < 0.5
            T1_corr = 1.07
            T3_corr = 1.6
        end
    end

    T1 = T1_corr * T1_prime
    T3 = T3_corr * T3_prime

    # =====================================================================
    # 9. THERMAL RESISTANCE T4  (external / soil / air)
    # =====================================================================

    L_burial = cond.L_burial
    rho_soil = cond.rho_soil

    T4 = if cond.installation == :buried
        if is_trefoil
            calc_T4_trefoil(rho_soil, L_burial, De_cable)
        elseif is_flat # && n_cables > 1 # handled in calc_T4_flat log logic
            calc_T4_flat(rho_soil, L_burial, De_cable, s, n_cables)
        else
            calc_T4(rho_soil, L_burial, De_cable)
        end
    elseif cond.installation == :in_air
        calc_T4_air(De_cable, theta_amb, theta_max, 10.0)
    # elseif cond.installation == :duct
    #    calc_T4_duct(...)
    else
        calc_T4_air(De_cable, theta_amb, theta_max, 10.0)
    end

    # =====================================================================
    # 10. AMPACITY -- iterative solution for screen/sheath temperature
    # =====================================================================

    n = Float64(cond.num_cores)              # cores per cable
    delta_theta = theta_max - theta_amb

    lambda1 = 0.0
    lambda2 = 0.0

    # Initial guess (no metallic losses)
    I_rated = calculate_ac_permissible_current(delta_theta, Wd, R_ac,
                                                lambda1, lambda2,
                                                T1, T2, T3, T4, n)

    theta_s = theta_max
    R_s = 0.0
    X_s = 0.0
    R_A = 0.0

    has_metallic_sheath = cond.has_wire_screen || cond.has_tubular_sheath

    if has_metallic_sheath || cond.has_armour
        I_prev     = 0.0
        theta_prev = 0.0

        for _iter in 1:cond.max_iter
            # -- Screen/sheath temperature --
            theta_s = theta_max - (I_rated^2 * R_ac + 0.5 * Wd) * T1

            # -- Screen/sheath resistance and loss factor lambda1 --
            if cond.has_wire_screen
                scr = calc_screen_resistance(cond.rho_s, cond.alpha_s,
                                             cond.n_wires, cond.d_wire,
                                             cond.D_under, cond.L_lay, theta_s)
                R_s = scr.R_s
                d_mean_for_loss = d_mean_sc

                slf = calc_sheath_loss_factors(R_s, R_ac, s, d_mean_for_loss, omega;
                                               bonding = cond.bonding_type)
                lambda1 = slf.lambda1
                
                # Add eddy current component for wire screens in flat/spaced formation
                # (although often small, instructed to include if flat)
                if cond.formation == :flat
                     # Note: t_sheath might be 0 for wire screen, need effective thickness or 
                     # calc_sheath_loss_eddy handles it (returns 0 if t_s small).
                     # For wire screens effectively t_s ~ d_wire? Or just use d_wire?
                     # Passing d_wire as thickness for eddy calc approximation if needed, 
                     # but calc_sheath_loss_eddy checks t_s.
                     # Using d_wire as effective thickness for now.
                     lambda1_eddy = calc_sheath_loss_eddy(R_s, R_ac, d_mean_for_loss,
                                                          cond.d_wire, omega, f;
                                                          formation = cond.formation)
                     lambda1 += lambda1_eddy
                end
                
                X_s     = slf.X_s

            elseif cond.has_tubular_sheath
                tsr = calc_tubular_sheath_resistance(cond.R_s_20, cond.alpha_sheath,
                                                      theta_s)
                R_s = tsr.R_s
                d_mean_for_loss = cond.d_mean_sheath

                if cond.num_cores >= 3
                    # 3-core cable with common sheath: eddy current formula + f_A
                    slf = calc_sheath_loss_factors_3core(R_s, R_ac,
                                                         cond.r1, cond.t_i1,
                                                         d_mean_for_loss, omega;
                                                         has_armour = cond.has_armour,
                                                         d_A = cond.d_mean_armour,
                                                         mu_r = cond.mu_r_armour,
                                                         delta_armour = cond.delta_armour)
                    lambda1 = slf.lambda1
                    X_s = zero(Float64)
                else
                    # Single-core with tubular sheath
                    slf = calc_sheath_loss_factors(R_s, R_ac, s, d_mean_for_loss, omega;
                                                   bonding = cond.bonding_type)
                    # Add eddy current component for tubular sheaths (GP6: never neglect)
                    lambda1_eddy = calc_sheath_loss_eddy(R_s, R_ac, d_mean_for_loss,
                                                          cond.t_sheath, omega, f;
                                                          formation = cond.formation)
                    lambda1 = slf.lambda1 + lambda1_eddy
                    X_s     = slf.X_s
                end
            end

            # -- Armour loss factor lambda2 --
            if cond.has_armour
                if cond.num_cores >= 3 && cond.is_magnetic_armour && cond.delta_armour > 0
                    # 3-core cable with steel tape armour (Section 2.4.2.4)
                    alf = calc_armour_loss_factors_steel_tape(R_ac, s,
                                                              cond.d_mean_armour,
                                                              cond.delta_armour,
                                                              cond.mu_r_armour)
                    lambda2 = alf.lambda2
                    R_A     = alf.R_A
                else
                    # Single-core or non-magnetic armour
                    theta_a = theta_s
                    if !isempty(cond.armour_bedding_layers)
                        W_through_T2 = n * (I_rated^2 * R_ac * (1 + lambda1) + Wd)
                        theta_a = theta_s - W_through_T2 * T2
                    end
                    alf = calc_armour_loss_factors(R_ac, cond.R_a_20, cond.alpha_a,
                                                   theta_a,
                                                   cond.d_mean_armour, omega,
                                                   cond.n_armour_wires;
                                                   is_magnetic = cond.is_magnetic_armour)
                    lambda2 = alf.lambda2
                    R_A     = alf.R_A
                end
            end

            # -- Re-evaluate ampacity --
            I_rated = calculate_ac_permissible_current(delta_theta, Wd, R_ac,
                                                        lambda1, lambda2,
                                                        T1, T2, T3, T4, n)

            # TB 880 dual convergence check
            (abs(I_rated - I_prev) < cond.tol_I &&
             abs(theta_s - theta_prev) < cond.tol_theta) && break

            I_prev     = I_rated
            theta_prev = theta_s
        end
    end

    # =====================================================================
    # 11. POST-PROCESS: losses and temperatures at rated current
    # =====================================================================

    Wc   = R_ac * I_rated^2                                  # conductor losses  [W/m]
    Ws   = lambda1 * Wc                                      # screen losses     [W/m]
    Wa   = lambda2 * Wc                                      # armour losses     [W/m]
    WI   = Wc * (1 + lambda1 + lambda2)                      # total ohmic       [W/m]
    Wt   = WI + Wd                                           # total per phase   [W/m]
    Wsys = n_cables * Wt                                     # total system      [W/m]

    theta_c  = theta_max
    theta_s  = theta_c - (Wc + 0.5 * Wd) * T1
    theta_a  = theta_s - n * (Wc * (1 + lambda1) + Wd) * T2
    theta_e  = theta_a - n * (WI + Wd) * T3

    # Solar radiation adjustment (cables in air)
    delta_theta_solar = 0.0
    if cond.installation == :in_air && cond.solar_radiation && cond.H_solar > 0
        delta_theta_solar = calc_solar_radiation_rise(
            cond.sigma_solar, De_cable, cond.H_solar,
            T1, T2, T3, lambda1, lambda2, n)
    end

    # =====================================================================
    # 12. RESULTS NAMED-TUPLE
    # =====================================================================

    cable_id = cond.cable_id

    result = (;
        I_rated,
        # temperatures [degC]
        theta_c, theta_s, theta_a, theta_e, theta_amb, delta_theta,
        delta_theta_solar,
        # resistance [Ohm/m]
        R_dc_20, R_dc_theta = R_dc_th, R_ac, y_s, y_p,
        # losses [W/m]
        Wd, Wc, Ws, Wa, WI, Wt, Wsys,
        # loss factors
        lambda1, lambda2,
        # thermal resistances [K.m/W]
        T1_prime, T1, T1_correction = T1_corr,
        T2,
        T3_prime, T3, T3_correction = T3_corr,
        T4,
        # screen/sheath
        R_s, X_s, d_mean_screen = d_mean_sc, LF_s,
        has_wire_screen = cond.has_wire_screen,
        has_tubular_sheath = cond.has_tubular_sheath,
        # armour
        R_A, has_armour = cond.has_armour,
        is_magnetic_armour = cond.is_magnetic_armour,
        # cable
        Dc, De_cable, s, C_cable, U_e = U0,
        n_cables, formation = cond.formation, f,
        bonding_type = cond.bonding_type,
        installation = cond.installation,
    )

    results[cable_id] = result
    return results
end

function compute!(problem::AmpacityProblem, formulation::IEC60287Formulation)
    return compute_ampacity(problem::AmpacityProblem, formulation::IEC60287Formulation)
end

end