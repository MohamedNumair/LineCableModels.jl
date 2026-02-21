"""
    LineCableModels.Engine.IEC60853.Transient

Transient thermal functions for IEC 60853-2 cyclic rating:

- Van Wormer coefficient (insulation capacitance apportioning)
- Two-loop Cauer network eigenvalues and apparent thermal resistances
- Internal attainment factor α(τ)
- External attainment factors β(τ) (single cable) and γ(τ) (cable groups)
- Mutual heating coefficient Fμ
"""
module Transient

using SpecialFunctions: expinti

export calc_van_wormer_long,
       calc_van_wormer_jacket,
       calc_cauer_coefficients,
       calc_alpha_t, calc_beta_t, calc_gamma_t,
       calc_F_mu, calc_d_hot,
       calc_theta_R

# ── IEC 60853-2 Table 1: Volumetric Specific Heats [J/(m³·K)] ───────────
const SIGMA_COPPER    = 3.45e6
const SIGMA_ALUMINIUM = 2.5e6
const SIGMA_LEAD      = 1.45e6
const SIGMA_STEEL     = 3.8e6
const SIGMA_XLPE      = 2.4e6
const SIGMA_PE        = 2.4e6
const SIGMA_EPR       = 2.0e6
const SIGMA_PVC       = 1.7e6
const SIGMA_PAPER     = 2.0e6

# Default soil thermal diffusivity [m²/s] (IEC 60853-2 recommendation)
const DELTA_SOIL_DEFAULT = 5.0e-7


"""
    calc_van_wormer_long(D_i, d_c) -> Float64

Van Wormer coefficient ``p_i`` for long-duration transients (IEC 60853-2).

```math
p_i = \\frac{1}{2\\ln(D_i/d_c)} - \\frac{1}{(D_i/d_c)^2 - 1}
```

**Symbol:** ``p_i``  **Clause:** IEC 60853-2, Section 4.3

# Arguments
- `D_i`: Diameter over insulation [m]
- `d_c`: Conductor diameter including semiconductor screens [m]
"""
function calc_van_wormer_long(D_i::Float64, d_c::Float64)
    ratio = D_i / d_c
    p_i = 1.0 / (2.0 * log(ratio)) - 1.0 / (ratio^2 - 1.0)
    @debug "Van Wormer (long): D_i/d_c = $(round(ratio, digits=4)), p_i = $(round(p_i, digits=6))"
    return p_i
end


"""
    calc_van_wormer_jacket(D_e, D_under) -> Float64

Van Wormer coefficient ``p_j`` for the jacket/oversheath layer.

```math
p_j = \\frac{1}{2\\ln(D_e/D_{under})} - \\frac{1}{(D_e/D_{under})^2 - 1}
```

**Symbol:** ``p_j``
"""
function calc_van_wormer_jacket(D_e::Float64, D_under::Float64)
    ratio = D_e / D_under
    if ratio <= 1.0 + 1e-10
        return 0.5
    end
    return 1.0 / (2.0 * log(ratio)) - 1.0 / (ratio^2 - 1.0)
end


"""
    calc_cauer_coefficients(T_A, T_B, Q_A, Q_B) -> (a_0, b_0, T_a0, T_b0)

Two-loop Cauer network eigenvalues and apparent thermal resistances
for IEC 60853-2 partial transient calculations.

```math
M_0 = 0.5\\bigl(Q_A(T_A + T_B) + Q_B\\,T_B\\bigr)
```
```math
N_0 = Q_A\\,T_A\\,Q_B\\,T_B
```
```math
a_0 = \\frac{M_0 + \\sqrt{M_0^2 - N_0}}{N_0},\\quad
b_0 = \\frac{M_0 - \\sqrt{M_0^2 - N_0}}{N_0}
```
```math
T_{a0} = \\frac{1}{a_0 - b_0}
         \\left(\\frac{1}{Q_A} - b_0(T_A + T_B)\\right),\\quad
T_{b0} = T_A + T_B - T_{a0}
```

**Symbols:** ``a_0, b_0, T_{a0}, T_{b0}``
**Clause:** IEC 60853-2, Section 4.2
"""
function calc_cauer_coefficients(T_A::Float64, T_B::Float64,
                                 Q_A::Float64, Q_B::Float64)
    M_0 = 0.5 * (Q_A * (T_A + T_B) + Q_B * T_B)
    N_0 = Q_A * T_A * Q_B * T_B

    @debug "Cauer: M_0 = $(round(M_0, digits=4)) s, N_0 = $(round(N_0, digits=4)) s²"

    discriminant = M_0^2 - N_0
    if discriminant < 0
        @warn "Negative discriminant in Cauer eigenvalue: M_0² - N_0 = $discriminant; using |value|."
        discriminant = abs(discriminant)
    end
    sqrt_disc = sqrt(discriminant)

    a_0  = (M_0 + sqrt_disc) / N_0
    b_0  = (M_0 - sqrt_disc) / N_0
    T_a0 = (1.0 / Q_A - b_0 * (T_A + T_B)) / (a_0 - b_0)
    T_b0 = (T_A + T_B) - T_a0

    @debug "Cauer: a_0 = $(round(a_0, sigdigits=6)) 1/s, b_0 = $(round(b_0, sigdigits=6)) 1/s"
    @debug "Cauer: T_a0 = $(round(T_a0, digits=6)) K·m/W, T_b0 = $(round(T_b0, digits=6)) K·m/W"

    return (a_0, b_0, T_a0, T_b0)
end


"""
    calc_alpha_t(tau, a_0, b_0, T_a0, T_b0, T_A, T_B) -> Float64

Internal (conductor-to-surface) attainment factor ``\\alpha(\\tau)``
per IEC 60853-2.

```math
\\alpha(\\tau) = \\frac{T_{a0}(1 - e^{-a_0\\tau}) +
                       T_{b0}(1 - e^{-b_0\\tau})}{T_A + T_B}
```

**Symbol:** ``\\alpha_t``  **Clause:** IEC 60853-2, Section 4.2.2

# Arguments
- `tau`: Elapsed time [s]
"""
function calc_alpha_t(tau::Float64, a_0::Float64, b_0::Float64,
                      T_a0::Float64, T_b0::Float64,
                      T_A::Float64, T_B::Float64)
    tau <= 0.0 && return 0.0
    numerator  = T_a0 * (1.0 - exp(-a_0 * tau)) +
                 T_b0 * (1.0 - exp(-b_0 * tau))
    return numerator / (T_A + T_B)
end


"""
    calc_beta_t(tau, D_o, L, delta_soil) -> Float64

External (cable surface-to-ambient) attainment factor ``\\beta(\\tau)`` for a
single isolated cable, per IEC 60853-2.

```math
\\beta(\\tau) = \\frac{-\\operatorname{Ei}\\!
  \\left(\\frac{-D_o^2}{16\\tau\\delta_{soil}}\\right) +
  \\operatorname{Ei}\\!
  \\left(\\frac{-L^2}{\\tau\\delta_{soil}}\\right)}
  {2\\ln\\!\\left(\\frac{4L}{D_o}\\right)}
```

**Symbol:** ``\\beta_t``  **Clause:** IEC 60853-2, Section 5.3

# Arguments
- `tau`: Elapsed time [s]
- `D_o`: Cable outer diameter [m]
- `L`: Burial depth to cable centre [m]
- `delta_soil`: Soil thermal diffusivity [m²/s]
"""
function calc_beta_t(tau::Float64, D_o::Float64, L::Float64,
                     delta_soil::Float64 = DELTA_SOIL_DEFAULT)
    tau <= 0.0 && return 0.0
    arg1 = -D_o^2 / (16.0 * tau * delta_soil)
    arg2 = -L^2   / (tau * delta_soil)
    numerator   = -expinti(arg1) + expinti(arg2)
    denominator =  2.0 * log(4.0 * L / D_o)
    return clamp(numerator / denominator, 0.0, 1.0)
end


"""
    calc_gamma_t(tau, D_o, L, N_c, d_hot, F_mu, delta_soil) -> Float64

External attainment factor ``\\gamma(\\tau)`` for a group of ``N_c`` equally
loaded cables, per IEC 60853-2.

```math
\\gamma(\\tau) = \\frac{
  -\\operatorname{Ei}\\!\\left(\\frac{-D_o^2}{16\\tau\\delta}\\right) +
  \\operatorname{Ei}\\!\\left(\\frac{-L^2}{\\tau\\delta}\\right) +
  (N_c - 1)\\!\\left(
    -\\operatorname{Ei}\\!\\left(\\frac{-d_{hot}^2}{16\\tau\\delta}\\right) +
    \\operatorname{Ei}\\!\\left(\\frac{-L^2}{\\tau\\delta}\\right)
  \\right)}
  {2\\ln\\!\\left(\\frac{4L\\,F_\\mu}{D_o}\\right)}
```

**Symbol:** ``\\gamma_t``  **Clause:** IEC 60853-2, Section 5.4
"""
function calc_gamma_t(tau::Float64, D_o::Float64, L::Float64,
                      N_c::Int, d_hot::Float64, F_mu::Float64,
                      delta_soil::Float64 = DELTA_SOIL_DEFAULT)
    tau <= 0.0 && return 0.0
    arg1 = -D_o^2   / (16.0 * tau * delta_soil)
    arg2 = -L^2     / (tau * delta_soil)
    arg3 = -d_hot^2 / (16.0 * tau * delta_soil)

    self_term   = -expinti(arg1) + expinti(arg2)
    mutual_term = -expinti(arg3) + expinti(arg2)

    numerator   = self_term + (N_c - 1) * mutual_term
    denominator = 2.0 * log(4.0 * L * F_mu / D_o)
    return clamp(numerator / denominator, 0.0, 1.0)
end


"""
    calc_F_mu(positions) -> Float64

Mutual heating coefficient ``F_\\mu`` for a group of equally loaded cables.
Cable 1 is taken as the reference (hottest) cable.

```math
F_\\mu = \\prod_{k=2}^{N_c} \\frac{d'_{1k}}{d_{1k}}
```

where ``d'_{1k}`` is the distance from cable 1 to the **image** of cable ``k``
(reflected across the ground surface at ``y = 0``), and ``d_{1k}`` is
the actual distance.

**Symbol:** ``F_\\mu``
"""
function calc_F_mu(positions::Vector{Tuple{Float64, Float64}})
    n = length(positions)
    n <= 1 && return 1.0
    F_mu = 1.0
    for k in 2:n
        x1, y1 = positions[1]
        xk, yk = positions[k]
        d_pk       = sqrt((x1 - xk)^2 + (y1 - yk)^2)
        d_pk_prime = sqrt((x1 - xk)^2 + (y1 + yk)^2)  # image at (xk, -yk)
        if d_pk > 0
            F_mu *= d_pk_prime / d_pk
        end
    end
    @debug "Mutual heating: F_μ = $(round(F_mu, digits=6))"
    return F_mu
end


"""
    calc_d_hot(L, F_mu, N_c) -> Float64

Equivalent spacing from the hottest cable centre representing the mutual
heating effect of all other cables in the group.

```math
d_{hot} = \\frac{4L}{F_\\mu^{1/(N_c - 1)}}
```

**Symbol:** ``d_{hot}``
"""
function calc_d_hot(L::Float64, F_mu::Float64, N_c::Int)
    N_c <= 1 && return 0.0
    return 4.0 * L / F_mu^(1.0 / (N_c - 1))
end


"""
    calc_theta_R(k_t, alpha, attainment_ext) -> Float64

Normalized temperature rise ratio ``\\theta_R`` per IEC 60853-2.

For a single cable:  ``\\theta_R = (1 - k_t + k_t\\,\\beta)\\,\\alpha``
For a cable group:   ``\\theta_R = (1 - k_t + k_t\\,\\gamma)\\,\\alpha``

**Symbol:** ``\\theta_R``
"""
function calc_theta_R(k_t::Float64, alpha::Float64, attainment_ext::Float64)
    return (1.0 - k_t + k_t * attainment_ext) * alpha
end

end # module Transient
