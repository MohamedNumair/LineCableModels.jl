"""
    LineCableModels.Engine.IEC60853.Solver

Computes the IEC 60853-2 cyclic rating factor *M* and peak permissible current
for underground cables subject to a 24-hour cyclic load pattern.
"""
module Solver

using ...IEC60287: AmpacityProblem, IEC60287Formulation, IEC60287CableCondition,
                   iec60287_triage, compute_ampacity
using ..IEC60853: CyclicLoadProfile
using ..Transient

export compute_cyclic_rating


"""
    compute_cyclic_rating(problem, formulation, load_profile) -> Dict

Convenience method: first computes steady-state ampacity via IEC 60287,
then computes the cyclic rating factor.
"""
function compute_cyclic_rating(
    problem::AmpacityProblem,
    formulation::IEC60287Formulation,
    load_profile::CyclicLoadProfile)

    steady = compute_ampacity(problem, formulation)
    return compute_cyclic_rating(problem, formulation, steady, load_profile)
end


"""
    compute_cyclic_rating(problem, formulation, steady_results, load_profile) -> Dict

Compute the IEC 60853-2 cyclic rating factor ``M`` and peak permissible
current from pre-computed steady-state results and a 24-hour load profile.

# Formula (IEC 60853-2)
```math
M = \\frac{1}{\\sqrt{
    \\sum_{i=0}^{N_h - 1} Y_i
    \\left[\\theta_R(i{+}1) - \\theta_R(i)\\right] +
    \\mu\\left[1 - \\theta_R(N_h)\\right]}}
```

where ``\\theta_R(j)`` is the normalized temperature attainment at ``j``
hours, ``Y_i`` are the loss-load ordinates, and ``\\mu`` is the loss-load
factor.

**Symbol:** ``M``  **Clause:** IEC 60853-2, Section 5.5

# Returns
A `Dict{String, NamedTuple}` keyed by cable ID containing `M`, `mu`,
`I_rated`, `I_peak`, and intermediate transient values.
"""
function compute_cyclic_rating(
    problem::AmpacityProblem,
    formulation::IEC60287Formulation,
    steady_results::Dict,
    load_profile::CyclicLoadProfile)

    # ── Triage: flatten geometry ──────────────────────────────────────────
    cc = iec60287_triage(problem, formulation)
    cable_id = cc.cable_id

    # ── Steady-state results ──────────────────────────────────────────────
    r = steady_results[cable_id]
    I_rated   = r.I_rated
    T1        = r.T1;       T2 = r.T2;   T3 = r.T3;   T4 = r.T4
    lambda1   = r.lambda1;  lambda2 = r.lambda2
    theta_c   = r.theta_c;  theta_e = r.theta_e;  theta_amb = r.theta_amb
    De        = r.De_cable;  Dc = r.Dc

    @debug "=" ^60
    @debug "IEC 60853 Cyclic Rating Factor Computation"
    @debug "=" ^60
    @debug "Steady-state: I_rated = $(round(I_rated, digits=2)) A"
    @debug "T1=$(round(T1,digits=4)), T2=$(round(T2,digits=4)), T3=$(round(T3,digits=4)), T4=$(round(T4,digits=4))"
    @debug "λ₁=$(round(lambda1,digits=4)), λ₂=$(round(lambda2,digits=4))"
    @debug "θ_c=$(round(theta_c,digits=2))°C, θ_e=$(round(theta_e,digits=2))°C, θ_amb=$(round(theta_amb,digits=2))°C"

    # ── Temperature rise ratio k_t  (IEC 60853-2) ────────────────────────
    delta_theta_c = theta_c - theta_amb
    delta_theta_e = theta_e - theta_amb
    k_t = delta_theta_e / delta_theta_c
    @debug "k_t = $(round(delta_theta_e,digits=3))/$(round(delta_theta_c,digits=3)) = $(round(k_t,digits=6))"

    # ── Cable geometry for transient calculations ─────────────────────────
    # d_c_t  includes conductor shield;  D_i_t  is outer diameter of core
    # insulation group (everything inside the metallic screen).
    d_c_t = Dc
    D_i_t = De
    if !isempty(cc.core_insulator_layers)
        d_c_t = 2.0 * cc.core_insulator_layers[1][3]     # outer r of 1st layer (semicon)
        D_i_t = 2.0 * cc.core_insulator_layers[end][3]   # outer r of last core layer
    end
    @debug "Transient: d_c_t=$(round(d_c_t*1e3,digits=2)) mm, D_i_t=$(round(D_i_t*1e3,digits=2)) mm, De=$(round(De*1e3,digits=2)) mm"

    # ── Van Wormer coefficient (long-term) ────────────────────────────────
    p_i = Transient.calc_van_wormer_long(D_i_t, d_c_t)

    # ── Thermal capacitances [J/(m·K)] ───────────────────────────────────
    sigma_c  = Transient.SIGMA_COPPER
    sigma_i  = Transient.SIGMA_XLPE
    sigma_sc = Transient.SIGMA_COPPER
    sigma_j  = Transient.SIGMA_PE

    Q_c = sigma_c * π * (Dc / 2.0)^2                     # conductor
    A_i = π / 4.0 * (D_i_t^2 - d_c_t^2)
    Q_i = sigma_i * A_i                                   # insulation

    Q_sc = 0.0                                             # screen / sheath
    if cc.has_wire_screen
        A_sc = cc.n_wires * π * (cc.d_wire / 2.0)^2
        Q_sc = sigma_sc * A_sc
    elseif cc.has_tubular_sheath
        Q_sc = sigma_sc * π * (cc.r_sheath_ext^2 - cc.r_sheath_in^2)
    end

    Q_j = 0.0                                              # jacket layers
    D_under_jacket = D_i_t
    if !isempty(cc.sheath_insulator_layers)
        for (_, r_in, r_ext) in cc.sheath_insulator_layers
            Q_j += sigma_j * π * (r_ext^2 - r_in^2)
        end
        D_under_jacket = 2.0 * cc.sheath_insulator_layers[1][2]
    end
    p_j = Transient.calc_van_wormer_jacket(De, D_under_jacket)

    @debug "Q_c=$(round(Q_c,digits=2)), Q_i=$(round(Q_i,digits=2)), Q_sc=$(round(Q_sc,digits=2)), Q_j=$(round(Q_j,digits=2))"
    @debug "p_i=$(round(p_i,digits=6)), p_j=$(round(p_j,digits=6))"

    # ── Transient thermal resistances ─────────────────────────────────────
    n_c = 1   # single-core cable

    # Loss ratios (IEC 60853-2)
    q_1 = 1.0 + lambda1
    q_2 = 1.0 + lambda1
    q_3 = 1.0 + lambda1 + lambda2

    # T_A = T_1  (long-term, single-core)
    T_A = T1

    # T_B = q_2·T_2 + q_3·T_3   (directly buried, no duct: T_4i = T_4ii = 0)
    T_B = q_2 * T2 + q_3 * T3

    @debug "T_A=$(round(T_A,digits=6)), T_B=$(round(T_B,digits=6))"
    @debug "q_1=$(round(q_1,digits=4)), q_2=$(round(q_2,digits=4)), q_3=$(round(q_3,digits=4))"

    # ── Thermal capacitances A and B (IEC 60853-2) ────────────────────────
    Q_A = Q_c + p_i * Q_i
    Q_B = ((1.0 - p_i) * Q_i + (Q_sc + p_j * Q_j) / q_1) / n_c

    @debug "Q_A=$(round(Q_A,digits=2)), Q_B=$(round(Q_B,digits=2))"

    # ── Cauer network eigenvalues ─────────────────────────────────────────
    a_0, b_0, T_a0, T_b0 = Transient.calc_cauer_coefficients(T_A, T_B, Q_A, Q_B)

    # ── Soil parameters ───────────────────────────────────────────────────
    L          = cc.L_burial
    D_o        = De
    delta_soil = Transient.DELTA_SOIL_DEFAULT
    @debug "Soil: L=$(round(L,digits=3)) m, D_o=$(round(D_o*1e3,digits=2)) mm, δ_soil=$delta_soil m²/s"

    # ── Mutual heating (cable groups) ─────────────────────────────────────
    N_c   = cc.n_cables
    F_mu  = 1.0
    d_hot = 0.0
    if N_c > 1
        positions = Tuple{Float64,Float64}[
            (Float64(c.horz), Float64(c.vert)) for c in problem.system.cables]
        F_mu  = Transient.calc_F_mu(positions)
        d_hot = Transient.calc_d_hot(L, F_mu, N_c)
        @debug "Cable group: N_c=$N_c, F_μ=$(round(F_mu,digits=6)), d_hot=$(round(d_hot,digits=4)) m"
    end

    # ── Compute θ_R at hours 0 … N_h ─────────────────────────────────────
    N_h = 6
    theta_R_vec = Vector{Float64}(undef, N_h + 1)
    theta_R_vec[1] = 0.0   # θ_R(0) = 0

    @debug "\n── Attainment factors ──"
    for j in 1:N_h
        tau   = j * 3600.0   # [s]
        alpha = Transient.calc_alpha_t(tau, a_0, b_0, T_a0, T_b0, T_A, T_B)
        if N_c > 1
            gamma = Transient.calc_gamma_t(tau, D_o, L, N_c, d_hot, F_mu, delta_soil)
            theta_R_vec[j+1] = Transient.calc_theta_R(k_t, alpha, gamma)
            @debug "  t=$(j)h: α=$(round(alpha,digits=6)), γ=$(round(gamma,digits=6)), θ_R=$(round(theta_R_vec[j+1],digits=6))"
        else
            beta = Transient.calc_beta_t(tau, D_o, L, delta_soil)
            theta_R_vec[j+1] = Transient.calc_theta_R(k_t, alpha, beta)
            @debug "  t=$(j)h: α=$(round(alpha,digits=6)), β=$(round(beta,digits=6)), θ_R=$(round(theta_R_vec[j+1],digits=6))"
        end
    end

    # ── Load profile ──────────────────────────────────────────────────────
    mu   = load_profile.mu
    Y_Nh = load_profile.Y_Nh

    @debug "\n── Load profile ──"
    @debug "  μ = $(round(mu,digits=6))"
    @debug "  Y_Nh = $(round.(Y_Nh, digits=4))"

    # ── Compute M factor (IEC 60853-2) ────────────────────────────────────
    #   M = 1 / √( Σ_{i=0}^{N_h-1} Y_i [θ_R(i+1) - θ_R(i)]
    #              + μ [1 - θ_R(N_h)] )
    M_inv_sq = 0.0
    for i in 0:(N_h - 1)
        Yi      = Y_Nh[i + 1]
        d_theta = theta_R_vec[i + 2] - theta_R_vec[i + 1]
        contrib = Yi * d_theta
        M_inv_sq += contrib
        @debug "  i=$i: Y=$(round(Yi,digits=4)) × Δθ_R=$(round(d_theta,digits=6)) = $(round(contrib,digits=6))"
    end

    mu_contrib = mu * (1.0 - theta_R_vec[N_h + 1])
    M_inv_sq  += mu_contrib
    @debug "  μ-term: $(round(mu,digits=4)) × (1 - $(round(theta_R_vec[N_h+1],digits=6))) = $(round(mu_contrib,digits=6))"
    @debug "  Σ = $(round(M_inv_sq,digits=6))"

    if M_inv_sq <= 0
        @warn "M_inv_sq = $M_inv_sq ≤ 0; cyclic rating unconstrained."
        M = Inf
    else
        M = 1.0 / sqrt(M_inv_sq)
    end

    I_peak = M * I_rated

    @debug "\n── IEC 60853 Results ──"
    @debug "  M      = $(round(M, digits=6))"
    @debug "  I_rated= $(round(I_rated, digits=2)) A"
    @debug "  I_peak = $(round(I_peak, digits=2)) A"

    # ── Result bundle ─────────────────────────────────────────────────────
    result = (
        M          = M,
        mu         = mu,
        I_rated    = I_rated,
        I_peak     = I_peak,
        k_t        = k_t,
        p_i        = p_i,
        p_j        = p_j,
        T_A        = T_A,
        T_B        = T_B,
        Q_A        = Q_A,
        Q_B        = Q_B,
        Q_c        = Q_c,
        Q_i        = Q_i,
        Q_sc       = Q_sc,
        Q_j        = Q_j,
        a_0        = a_0,
        b_0        = b_0,
        T_a0       = T_a0,
        T_b0       = T_b0,
        theta_R    = theta_R_vec,
        Y_Nh       = Y_Nh,
        N_h        = N_h,
        N_c        = N_c,
        F_mu       = F_mu,
        d_hot      = d_hot,
        delta_soil = delta_soil,
        theta_c    = theta_c,
        theta_e    = theta_e,
        theta_amb  = theta_amb,
    )

    return Dict(cable_id => result)
end

end # module Solver
