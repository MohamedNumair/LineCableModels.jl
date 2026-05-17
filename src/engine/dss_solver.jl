using SpecialFunctions

function compute!(
	problem::LineParametersProblem{T},
    formulation::DSSFormulationSet,
) where {T <: REALSCALAR}

	@info "Preallocating arrays for DSS formulation"

	ws = init_workspace(problem, formulation)
	nph, nfreq = ws.n_phases, ws.n_frequencies

	Ztmp = Matrix{Complex{T}}(undef, nph, nph)
	Ptmp = Matrix{Complex{T}}(undef, nph, nph)

    Zout = Array{Complex{T}, 3}(undef, nph, nph, nfreq)
	Yout = Array{Complex{T}, 3}(undef, nph, nph, nfreq)

	@info "Starting line parameters computation (DSS)"
	for k in 1:nfreq
		compute_impedance_matrix!(Ztmp, ws, k, formulation)
        @views @inbounds Zout[:, :, k] .= Ztmp
        compute_admittance_matrix!(Ptmp, ws, k, formulation)
        @views @inbounds Yout[:, :, k] .= Ptmp

	end

	@info "Line parameters computation completed successfully (DSS)"
	return ws, LineParameters(Zout, Yout, ws.freq)
end

earth_layer_idx = 2 # assuming single layer earth model for now -- 1 is air, 2 is earth

# --- Internal Bessel function implementations ---
function _bessel_I0(a::Complex)
    maxterm = 1000
    epsilonsqr = 1e-20

    result = 1.0 + 0im           # term 0
    zSQR25 = (a*a) * 0.25
    term = zSQR25
    result += zSQR25             # term 1
    i = 1
    while i <= maxterm
        term *= zSQR25
        i += 1
        term /= i^2
        result += term
        sizesqr = real(term)^2 + imag(term)^2
        if sizesqr < epsilonsqr
            break
        end
    end
    return result
end

function _bessel_I1(x::Complex)
    maxterm = 1000
    epsilonsqr = 1e-20
    
    term = x / 2
    result = term
    incterm = term
    i = 4
    while i <= maxterm
        newterm = x / i
        term *= incterm * newterm
        result += term
        incterm = newterm
        i += 2
        sizesqr = real(term)^2 + imag(term)^2
        if sizesqr < epsilonsqr
            break
        end
    end
    return result
end


function get_Zint(ws, i::Int, k::Int, ::Union{SimpleCarson,FullCarson})
    ω = 2π * ws.freq[k]
    μ₀ = 4π * 1e-7
    μᵣ = ws.mu_cond[i]   # relative permeability of conductor i
    fₛₖᵢₙ = 1.02  # skin-effect correction factor applied to Rdc to approximate Rac
    # WARNING: LineCableModels does not support direct Rac assignment. Rdc × 1.02 is
    # used as a frequency-independent approximation. For frequency-dependent internal
    # impedance (skin effect), use DeriModel as the internal_impedance formulation.
    @warn "SimpleCarson/FullCarson internal impedance uses Rdc × $(fₛₖᵢₙ) as a " *
          "fixed Rac approximation. For accurate skin-effect modelling use DeriModel." maxlog=1
    return ws.rdc[i] * fₛₖᵢₙ + 1im * (ω * μ₀ * μᵣ) / (8 * π)
end

function get_Zint(ws, i::Int, k::Int, ::DeriModel)
    f = ws.freq[k]
    w = 2 * pi * f
    mu0 = 4.0 * pi * 1e-7
    μᵣ = ws.mu_cond[i]   # relative permeability of conductor i
    rdc_i = ws.rdc[i]

    if rdc_i == 0.0 return 0.0 + 0.0im end

    # p·r = √(jω μᵣ μ₀ / (π·Rdc)) — propagation constant × radius [paper eq. internal_impedance_bessel]
    alpha = sqrt( (1im * w * mu0 * μᵣ) / (pi * rdc_i) )

    local i0_i1_ratio::ComplexF64
    if abs(alpha) > 35.0
        i0_i1_ratio = 1.0 + 0.0im
    else
        numerator = _bessel_I0(alpha)
        denominator = _bessel_I1(alpha)
        
        if denominator == 0.0 + 0.0im
            return complex(rdc_i, 0.0)
        end

        i0_i1_ratio = numerator / denominator
    end
    
    z_int = (1/2) * alpha * rdc_i * i0_i1_ratio

    return z_int
end

function get_Zspacing(ws, i::Int, k::Int, ::DSSFormulation)
    ω = 2π * ws.freq[k]
    μ₀ = 4π * 1e-7
    # Uses ws.r_self[i] — the physical self-distance — not GMR.
    # This is consistent with explicit computation of get_Zint:
    #   Z_self = Z_int + j·ωμ₀/(2π)·ln(1/r) + Z_earth
    # OpenDSS uses an equivalent two-branch approach: at power frequencies (40–1000 Hz)
    # it zeros Im(Z_int) and substitutes GMR (= r·exp(-μr/4)) for r, which absorbs the
    # internal inductance via ln(1/GMR) = ln(1/r) + μr/4. Outside that range it uses
    # the physical radius with the full explicit Z_int. Both paths give the same result
    # for non-magnetic conductors (μr = 1). Our approach uses physical radius at all
    # frequencies, which is identical to OpenDSS's non-power-frequency branch.
    # For WireArray with num_wires > 1, ws.r_self[i] is the physical bundle GMR
    # (r_wire · N · R_lay^{N-1})^{1/N} without internal-flux correction.
    # For Tubular and Sector conductors, ws.r_self[i] = ws.r_ext[i] (physical outer radius).
    return 1im * ω * μ₀ / (2.0 * π) * log(1.0 / ws.r_self[i])
end

function get_Zspacing(ws, i::Int, j::Int, k::Int, ::DSSFormulation)
    ω = 2π * ws.freq[k]
    μ₀ = 4π * 1e-7

    @assert length(ws.conductor_groups[i].layers) == 1 "Only single layer conductor groups are supported in DSS formulation for now."
    @assert length(ws.conductor_groups[j].layers) == 1 "Only single layer conductor groups are supported in DSS formulation for now."
    d_ij = calc_gmd(ws.conductor_groups[i].layers[1], ws.conductor_groups[j].layers[1])
    @debug " the dij (gmd) between conductor $i : $(typeof(ws.conductor_groups[i].layers[1])) and $j : $(typeof(ws.conductor_groups[j].layers[1])) is $(d_ij)"

    return 1im * ω * μ₀ / (2.0 * π) * log(1.0 / d_ij)
end

get_Zspacing(ws, i::Int, k::Int, ::Saad) = zero(ws.jω[k])
get_Zspacing(ws, i::Int, j::Int, k::Int, ::Saad) = zero(ws.jω[k])

# Deri formula is the complete combined external+earth impedance (see get_Ze below);
# the external spacing term is therefore zero — consistent with Saad.
get_Zspacing(ws, i::Int, k::Int, ::DeriModel) = zero(ws.jω[k])
get_Zspacing(ws, i::Int, j::Int, k::Int, ::DeriModel) = zero(ws.jω[k])


function get_Ze(ws, i::Int, j::Int, k::Int, ::SimpleCarson)
    ω = 2π * ws.freq[k]
    μ₀ = 4π * 1e-7
    ρ_e = ws.rho_g[earth_layer_idx, k]
    # Equivalent earth-return depth [paper eq. simple_carson_depth]:
    #   De = 2√e / (me · e^γ),  me = √(ω μ₀ / ρe),  γ = Euler–Mascheroni ≈ 0.5772
    # Evaluating the constants gives De ≈ 658.87·√(ρe/f)  [m]
    # (OpenDSS hardcodes 658.8530451057239, which differs by <0.003%)
    m_e = sqrt(ω * μ₀ / ρ_e)
    D_e = 2 * exp(0.5) / (m_e * exp(MathConstants.eulergamma))
    @debug "Z earth SimpleCarson: freq=$(ws.freq[k]), i=$i, j=$j is $(complex(ω * μ₀ / 8.0, (ω * μ₀ / (2π)) * log(D_e)))"
    return complex(ω * μ₀ / 8, (ω * μ₀ / (2π)) * log(D_e))
end

function get_Ze(ws, i::Int, j::Int, k::Int, ::FullCarson)
    b1 = 1.0 / (3.0 * sqrt(2.0))
    b2 = 1.0 / 16.0
    b3 = b1 / (3.0 * 5.0)
    b4 = b2 / (4.0 * 6.0)
    d2 = b2 * π / 4.0
    d4 = b4 * π / 4.0
    c2 = 1.3659315
    c4 = c2 + 1.0 / 4.0 + 1.0 / 6.0

    f = ws.freq[k]
    ω = 2 * π * f
    μ₀ = 4.0 * π * 1e-7

    vert_i = abs(ws.vert[i])
    vert_j = abs(ws.vert[j])

    local dij, theta_ij
    if i == j
       dij = 2.0 * vert_i
       theta_ij = 0.0
    else
       dij = sqrt((ws.horz[i] - ws.horz[j])^2 + (vert_i + vert_j)^2)
       theta_ij = acos((vert_i + vert_j) / dij)
    end

    mij = 2π * sqrt(2e-7) * dij * sqrt(f / ws.rho_g[earth_layer_idx,k])  # = 2.8099e-3 (OpenDSS literal); exact: 2π√(2×10⁻⁷)

    re_part = π / 8.0 - b1 * mij * cos(theta_ij) + b2 * (mij^2) * (log(exp(c2) / mij) * cos(2.0 * theta_ij) + theta_ij * sin(2.0 * theta_ij)) +
            b3 * (mij^3) * cos(3.0 * theta_ij) - d4 * (mij^4) * cos(4.0 * theta_ij)

    term1 = 0.5 * log(1.85138 / mij)
    term2 = b1 * mij * cos(theta_ij)
    term3 = -d2 * (mij^2) * cos(2.0 * theta_ij)
    term4 = b3 * (mij^3) * cos(3.0 * theta_ij)
    term5 = -b4 * (mij^4) * (log(exp(c4) / mij) * cos(4.0 * theta_ij) + theta_ij * sin(4.0 * theta_ij))

    im_part = term1 + term2 + term3 + term4 + term5
    im_part += 0.5 * log(dij)

    result_unscaled = re_part + 1im * im_part
    final_result = result_unscaled * (ω * μ₀ / π)

    @debug "Z earth FullCarson: freq=$(ws.freq[k]), i=$i, j=$j is $final_result"
    return final_result
end

function get_Ze(ws, i::Int, j::Int, k::Int, ::DeriModel)
    ω = 2π * ws.freq[k]
    μ₀ = 4π * 1e-7

    # D_e = 1/γ_e: Deri complex earth-return depth [Ametani (2021), §2.5.3, eq. 2.27-2.28]
    p_earth = sqrt(1im * ω * μ₀ / ws.rho_g[earth_layer_idx,k])
    D_e = 1.0 / p_earth

    local ln_arg
    if i == j
        # S_ii = 2*(h_i + D_e), denominator = physical self-distance (r_self[i]).
        # Using the physical radius here is consistent with the explicit get_Zint
        # (Bessel-based), which already accounts for internal inductance.
        # This matches OpenDSS's non-power-frequency Deri branch, where it also uses
        # physical radius once Im(Z_int) is kept explicitly. At power frequencies
        # OpenDSS instead zeros Im(Z_int) and substitutes GMR — giving the same result
        # for non-magnetic conductors (μr = 1).
        # ws.r_self[i] equals r_ext for Tubular/Sector, and the physical bundle GMR
        # (r_wire·N·R_lay^{N-1})^{1/N} for multi-wire WireArrays.
        S = 2.0 * (abs(ws.vert[i]) + D_e)
        ln_arg = S / ws.r_self[i]
    else
        # S_ij = sqrt((h_i + h_j + 2*D_e)^2 + (x_i - x_j)^2), denominator = GMD_{ij}
        h_term = abs(ws.vert[i]) + abs(ws.vert[j]) + 2.0 * D_e
        x_term = ws.horz[i] - ws.horz[j]
        S = sqrt(h_term^2 + x_term^2)
        @assert length(ws.conductor_groups[i].layers) == 1 "Only single-layer conductor groups are supported in Deri formulation."
        @assert length(ws.conductor_groups[j].layers) == 1 "Only single-layer conductor groups are supported in Deri formulation."
        d_ij = calc_gmd(ws.conductor_groups[i].layers[1], ws.conductor_groups[j].layers[1])
        ln_arg = S / d_ij
    end

    @debug "Z ext-earth DeriModel: freq=$(ws.freq[k]), i=$i, j=$j is $(1im * ω * μ₀ / (2π)) * log($ln_arg)"
    return (1im * ω * μ₀ / (2 * π)) * log(ln_arg)
end

# see [1] A. Ametani, H. Xue, T. Ohno, and H. Khalilnezhad, Electromagnetic Transients in Large HV Cable Networks: Modeling and calculations. Institution of Engineering and Technology, 2021. doi: 10.1049/PBPO204E. Page 18 (§ 2.5.3.4)
function get_Ze(ws, i::Int, j::Int, k::Int, ::Saad)
    ω = 2π * ws.freq[k]
    μ₀ = 4π * 1e-7
    ρ_g = ws.rho_g[earth_layer_idx, k] 

    γ₁ = sqrt(1im * ω * μ₀ / ρ_g)
    h_i = abs(ws.vert[i])
    h_j = abs(ws.vert[j])

    local R_ab
    if i == j
        # Ametani uses the cable outer insulation radius for the self term.
        R_ab = ws.r_ins_ext[i]
    else
        R_ab = abs(ws.horz[i] - ws.horz[j])
    end

    arg = γ₁ * R_ab
    term1 = besselk(0, arg)
    exp_term = exp(-(h_i + h_j) * γ₁)
    denominator = 4.0 + γ₁^2 * R_ab^2
    term2 = (2.0 * exp_term) / denominator

    final_result = (1im * ω * μ₀) / (2 * π) * (term1 + term2)

    @debug "Z external-earth Saad/Pollaczek: freq=$(ws.freq[k]), i=$i, j=$j is $final_result"

    return final_result
end


function compute_impedance_matrix!(
	Ztmp::AbstractMatrix{Complex{T}},
	ws,
	k::Int,
	formulation::DSSFormulationSet,
) where {T <: REALSCALAR}

    nph = ws.n_phases
	fill!(Ztmp, zero(Complex{T}))

    for i in 1:nph
        z_int = get_Zint(ws, i, k, formulation.internal_impedance)
        @debug "Z internal: freq=$(ws.freq[k]), i=$i is $z_int"
        z_spacing = get_Zspacing(ws, i, k, formulation.earth_impedance)
        @debug "Z spacing: freq=$(ws.freq[k]), i=$i is $z_spacing"
        z_earth = get_Ze(ws, i, i, k, formulation.earth_impedance)
        @debug "Z earth self: freq=$(ws.freq[k]), i=$i is $z_earth"
        Ztmp[i, i] = z_int + z_spacing + z_earth
        @inbounds @debug "Ztmp[$i, $i] = $(Ztmp[i, i])"

        for j in 1:(i-1)
            z_spacing_mutual = get_Zspacing(ws, i, j, k, formulation.earth_impedance)
            @debug "Z spacing mutual: freq=$(ws.freq[k]), i=$i, j=$j is $z_spacing_mutual"
            z_earth_mutual = get_Ze(ws, i, j, k, formulation.earth_impedance)
            @debug "Z earth mutual: freq=$(ws.freq[k]), i=$i, j=$j is $z_earth_mutual"
            @inbounds @debug "Ztmp[$i, $j] and Ztmp[$j, $i] = $(z_spacing_mutual + z_earth_mutual)"
            Ztmp[i, j] = z_spacing_mutual + z_earth_mutual
            Ztmp[j, i] = z_spacing_mutual + z_earth_mutual
        end
    end

	return nothing
end

function compute_admittance_matrix!(
	Ptmp::AbstractMatrix{Complex{T}},
	ws,
	k::Int,
    formulation::DSSFormulationSet,
) where {T <: REALSCALAR}

    nph = ws.n_phases
    ω = 2π * ws.freq[k]
    ε₀ = 8.854187817e-12

    P = Matrix{Complex{T}}(undef, nph, nph)
    p_factor = 1.0 / (2 * π * ε₀)

    for i in 1:nph
        vert_i = abs(ws.vert[i])
        P[i, i] = p_factor * log((2 * vert_i) / ws.r_ext[i])

        for j in 1:(i-1)
            vert_j = abs(ws.vert[j])
            d_ij = calc_gmd(ws.conductor_groups[i], ws.conductor_groups[j])
            d_ij_prime = sqrt((ws.horz[i] - ws.horz[j])^2 + (vert_i + vert_j)^2)

            val = p_factor * log(d_ij_prime / d_ij)
            P[i, j] = val
            P[j, i] = val
        end
    end

    Yc = 1im * ω * inv(P)
    Ptmp .= Yc

	return nothing
end
