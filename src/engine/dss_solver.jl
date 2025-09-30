
function compute!(
	problem::LineParametersProblem{T},
	formulation::DSSFormulation,
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
    fₛₖᵢₙ = 1.2 #TODO: maybe add it in the options tuble so it can be specified by the user
    return ws.rdc[i] * fₛₖᵢₙ + 1im * (ω * μ₀) / (8 * π)  
end

function get_Zint(ws, i::Int, k::Int, ::DeriModel)
    f = ws.freq[k]
    w = 2 * pi * f
    mu0 = 4.0 * pi * 1e-7
    rdc_i = ws.rdc[i] 

    if rdc_i == 0.0 return 0.0 + 0.0im end

    alpha = sqrt( (1im * w * mu0) / (pi * rdc_i) )

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


function get_Ze(ws, i::Int, j::Int, k::Int, ::SimpleCarson)
    ω = 2π * ws.freq[k]
    μ₀ = 4π * 1e-7
    return complex(ω * μ₀ / 8.0, (ω * μ₀ / (2 * π)) * log(658.5 * sqrt(ws.rho_g[1,k] / ws.freq[k])))
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

    local dij, theta_ij
    if i == j
        dij = 2.0 * ws.vert[i]
        theta_ij = 0.0
    else
        dij = sqrt((ws.horz[i] - ws.horz[j])^2 + (ws.vert[i] + ws.vert[j])^2)
        theta_ij = acos((ws.vert[i] + ws.vert[j]) / dij)
    end

    mij = (sqrt(2) / 503) * dij * sqrt(f / ws.rho_g[1,k])

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

    return final_result
end

function get_Ze(ws, i::Int, j::Int, k::Int, ::DeriModel)
    ω = 2π * ws.freq[k]
    μ₀ = 4π * 1e-7

    p_earth = sqrt(1im * ω * μ₀ / ws.rho_g[1,k])

    if i == j
        h_term = ws.vert[i] + 1.0 / p_earth
        ln_arg = 2.0 * h_term
    else
        h_term = ws.vert[i] + ws.vert[j] + 2.0 / p_earth
        x_term = ws.horz[i] - ws.horz[j]
        ln_arg = sqrt(h_term^2 + x_term^2)
    end

    return (1im * ω * μ₀ / (2 * π)) * log(ln_arg)
end


function compute_impedance_matrix!(
	Ztmp::AbstractMatrix{Complex{T}},
	ws,
	k::Int,
	formulation::DSSFormulation,
) where {T <: REALSCALAR}

    nph = ws.n_phases
	fill!(Ztmp, zero(Complex{T}))
    ω = 2π * ws.freq[k]
    μ₀ = 4π * 1e-7
    L_factor = 1im * ω * μ₀ / (2.0 * π)

    for i in 1:nph
        z_int = get_Zint(ws, i, k, formulation.internal_impedance)
        z_spacing = L_factor * log(1.0 / ws.gmr[i])
        z_earth = get_Ze(ws, i, i, k, formulation.earth_impedance)
        Ztmp[i, i] = z_int + z_spacing + z_earth

        for j in 1:(i-1)
            d_ij = sqrt((ws.horz[i] - ws.horz[j])^2 + (ws.vert[i] - ws.vert[j])^2)
            z_spacing_mutual = L_factor * log(1.0 / d_ij)
            z_earth_mutual = get_Ze(ws, i, j, k, formulation.earth_impedance)
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
	formulation::DSSFormulation,
) where {T <: REALSCALAR}

    nph = ws.n_phases
    ω = 2π * ws.freq[k]
    ε₀ = 8.854187817e-12

    P = Matrix{Complex{T}}(undef, nph, nph)
    p_factor = 1.0 / (2 * π * ε₀)

    for i in 1:nph
        P[i, i] = p_factor * log((2 * ws.vert[i]) / ws.r_ext[i])

        for j in 1:(i-1)
            d_ij = sqrt((ws.horz[i] - ws.horz[j])^2 + (ws.vert[i] - ws.vert[j])^2)
            d_ij_prime = sqrt((ws.horz[i] - ws.horz[j])^2 + (ws.vert[i] + ws.vert[j])^2)

            val = p_factor * log(d_ij_prime / d_ij)
            P[i, j] = val
            P[j, i] = val
        end
    end

    Yc = 1im * ω * inv(P)
    Ptmp .= Yc

	return nothing
end
