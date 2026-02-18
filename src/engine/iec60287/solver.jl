"""
    LineCableModels.Engine.IEC60287.Solver

Solves the AmpacityProblem using the IEC 60287 formulation.
Implements the complete steady-state ampacity calculation including:
- Multi-layer thermal resistances T1, T3 (IEC 60287-2-1)
- Wire screen degree-of-cover correction factors (IEC 60287-2-1 Section 4.2.4.3.3)
- External thermal resistance T4 for trefoil formation
- Skin + proximity effects, dielectric losses, screen circulating-current losses
- Iterative solution coupling screen temperature to ampacity

# TB 880 Compliance
- Convergence tolerance on current: 1 × 10⁻³ A (CIGRE TB 880 §4)
- Convergence tolerance on screen temperature: 1 × 10⁻³ °C
- Maximum iterations: 100
- Dielectric losses always included in thermal balance (TB 880 §3.2)
"""
module Solver

using ....Commons: π, T₀
using ....DataModel
using ..IEC60287: AmpacityProblem, IEC60287Formulation, IEC60287CableCondition, iec60287_triage
using ..Losses
using ..Thermal

export compute_ampacity

"""
    calculate_ac_permissible_current(delta_theta, Wd, R_ac, lambda1, lambda2, T1, T2, T3, T4, n)

Compute the AC permissible current from the IEC 60287-1-1 master equation (Eq. 3):

```math
I = \\sqrt{\\frac{\\Delta\\theta - W_d \\left[\\frac{1}{2} T_1 + n (T_2 + T_3 + T_4)\\right]}
          {R T_1 + n R (1 + \\lambda_1) T_2 + n R (1 + \\lambda_1 + \\lambda_2)(T_3 + T_4)}}
```

# Arguments
- `delta_theta`: Allowable temperature rise θ_max − θ_amb  [K]
- `Wd`:          Dielectric loss per unit length            [W/m]
- `R_ac`:        AC resistance at θ_max                    [Ω/m]
- `lambda1`:     Screen/sheath loss factor ratio λ₁
- `lambda2`:     Armour loss factor ratio λ₂
- `T1`:          Thermal resistance conductor → screen     [K·m/W]
- `T2`:          Thermal resistance screen → armour        [K·m/W]
- `T3`:          Thermal resistance armour → outer surface  [K·m/W]
- `T4`:          External thermal resistance               [K·m/W]
- `n`:           Number of conductors per cable

# Returns
- Permissible current `I` [A], clamped to 0.0 when the numerator is ≤ 0.

# TB 880 Guidance
- Never omit `Wd` even when small (TB 880 §3.2).
- Pass corrected T1, T3 values when wire-screen degree of cover < 50 %.
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

Returns a `Dict{String, NamedTuple}` with detailed intermediate values for validation.
"""
function compute_ampacity(problem::AmpacityProblem, formulation::IEC60287Formulation)
# ── Triage: flatten nested problem into a flat condition struct ────────
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
n_cables = length(problem.system.cables)
is_trefoil = (n_cables == 3)

# =====================================================================
# 2. DC RESISTANCE AT 20 °C
# =====================================================================

R_dc_20   = cond.rho_c / cond.A_c
theta_max = cond.theta_max
theta_amb = cond.theta_amb

# =====================================================================
# 3. AC RESISTANCE  (skin + proximity)
# =====================================================================

ac = calc_ac_resistance(R_dc_20, cond.alpha_c, theta_max, f,
                        cond.k_s, cond.k_p, Dc, s)
R_ac    = ac.R_ac
R_dc_th = ac.R_dc_theta
y_s     = ac.y_s
y_p     = ac.y_p

# =====================================================================
# 4. DIELECTRIC LOSSES
# =====================================================================

C_cable = cond.C_cable
U0      = cond.U0
Wd      = (C_cable > 0 && U0 > 0) ?
          calc_dielectric_loss(U0, omega, C_cable, cond.tan_delta) : 0.0

# =====================================================================
# 5. THERMAL RESISTANCE T1  (conductor → screen, multi-layer)
# =====================================================================

T1_prime = 0.0
for (rho_th, r_in, r_ext) in cond.core_insulator_layers
T1_prime += calc_layer_thermal_resistance(rho_th, r_in, r_ext)
end

# =====================================================================
# 6. THERMAL RESISTANCE T2 (armour bedding)
# =====================================================================

T2 = 0.0              # no armour in this cable

# =====================================================================
# 7. THERMAL RESISTANCE T3  (jacket / outer covering, multi-layer)
# =====================================================================

T3_prime = 0.0
for (rho_th, r_in, r_ext) in cond.sheath_insulator_layers
T3_prime += calc_layer_thermal_resistance(rho_th, r_in, r_ext)
end

# =====================================================================
# 8. CORRECTION FACTORS  (wire-screen cover < 50 %)
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
# 9. THERMAL RESISTANCE T4  (external / soil)
# =====================================================================

L_burial = cond.L_burial
rho_soil = cond.rho_soil

T4 = if L_burial > 0
is_trefoil ? calc_T4_trefoil(rho_soil, L_burial, De_cable) :
             calc_T4(rho_soil, L_burial, De_cable)
else
calc_T4_air(De_cable, theta_amb, theta_max, 10.0)
end

# =====================================================================
# 10. AMPACITY — iterative solution for screen temperature
# =====================================================================

n = 1.0              # single core per cable
delta_theta = theta_max - theta_amb

lambda1 = 0.0
lambda2 = 0.0

# Initial guess (no screen losses)
I_rated = calculate_ac_permissible_current(delta_theta, Wd, R_ac,
                                            lambda1, lambda2,
                                            T1, T2, T3, T4, n)

theta_s = theta_max
R_s = 0.0
X_s = 0.0

if cond.has_wire_screen
I_prev     = 0.0
theta_prev = 0.0

for _iter in 1:cond.max_iter
# Screen temperature
theta_s = theta_max - (I_rated^2 * R_ac + 0.5 * Wd) * T1

# Screen resistance at θ_s
scr = calc_screen_resistance(cond.rho_s, cond.alpha_s, cond.n_wires,
                             cond.d_wire, cond.D_under,
                             cond.L_lay, theta_s)
R_s = scr.R_s

# Sheath loss factor
slf = calc_sheath_loss_factors(R_s, R_ac, s, d_mean_sc, omega;
                               bonding = cond.bonding_type)
lambda1 = slf.lambda1
X_s     = slf.X_s

# Re-evaluate ampacity
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

Wc  = R_ac * I_rated^2                                 # conductor losses  [W/m]
Ws  = lambda1 * Wc                                     # screen losses     [W/m]
WI  = Wc * (1 + lambda1 + lambda2)                     # total ohmic       [W/m]
Wt  = WI + Wd                                          # total per phase   [W/m]
Wsys = n_cables * Wt                                   # total system      [W/m]

theta_c  = theta_max
theta_s  = theta_c - (Wc + 0.5 * Wd) * T1
theta_e  = theta_s -
           n * (Wc * (1 + lambda1) + Wd) * T2 -
           n * (WI + Wd) * T3

# =====================================================================
# 12. RESULTS NAMED-TUPLE
# =====================================================================

cable_id = problem.system.cables[1].design_data.cable_id

result = (;
I_rated,
# temperatures [°C]
theta_c, theta_s, theta_e, theta_amb, delta_theta,
# resistance [Ω/m]
R_dc_20, R_dc_theta = R_dc_th, R_ac, y_s, y_p,
# losses [W/m]
Wd, Wc, Ws, WI, Wt, Wsys,
# loss factors
lambda1, lambda2,
# thermal resistances [K·m/W]
T1_prime, T1, T1_correction = T1_corr,
T2,
T3_prime, T3, T3_correction = T3_corr,
T4,
# screen
R_s, X_s, d_mean_screen = d_mean_sc, LF_s,
# cable
Dc, De_cable, s, C_cable, U_e = U0,
n_cables, is_trefoil, f,
bonding_type = cond.bonding_type,
)

results[cable_id] = result
return results
end

end # module