
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


function get_Zint(ws, i::Int, k::Int, ::Union{SimpleCarson,FullCarson})
    # In DSS model, rac is used directly.
    return ws.rac[i]
end

function get_Zint(ws, i::Int, k::Int, ::DeriModel)
    # TODO: Implement Deri model for internal impedance based on DSS-LineModel.jl
    # This is a placeholder.
    return ws.rac[i]
end


function get_Ze(ws, i::Int, j::Int, k::Int, ::SimpleCarson)
    ω = 2π * ws.freq[k]
    μ₀ = 4π * 1e-7
    return complex(ω * μ₀ / 8.0, (ω * μ₀ / (2 * π)) * log(658.5 * sqrt(ws.rho_g[1,k] / ws.freq[k])))
end

function get_Ze(ws, i::Int, j::Int, k::Int, ::FullCarson)
    # TODO: Implement Full Carson model based on DSS-LineModel.jl
    # This is a placeholder.
    ω = 2π * ws.freq[k]
    μ₀ = 4π * 1e-7
    return complex(ω * μ₀ / 8.0, (ω * μ₀ / (2 * π)) * log(658.5 * sqrt(ws.rho_g[1,k] / ws.freq[k])))
end

function get_Ze(ws, i::Int, j::Int, k::Int, ::DeriModel)
    # TODO: Implement Deri model for earth impedance based on DSS-LineModel.jl
    # This is a placeholder.
    ω = 2π * ws.freq[k]
    μ₀ = 4π * 1e-7
    return complex(ω * μ₀ / 8.0, (ω * μ₀ / (2 * π)) * log(658.5 * sqrt(ws.rho_g[1,k] / ws.freq[k])))
end


function compute_impedance_matrix!(
	Ztmp::AbstractMatrix{Complex{T}},
	ws,
	k::Int,
	formulation::DSSFormulation,
) where {T <: REALSCALAR}

    nph = ws.n_phases
	fill!(Ztmp, zero(Complex{T}))

    for i in 1:nph
        for j in 1:nph
            if i == j
                z_int = get_Zint(ws, i, k, formulation.internal_impedance)
                z_e = get_Ze(ws, i, j, k, formulation.earth_impedance)
                Ztmp[i,j] = z_int + z_e
            else
                z_e = get_Ze(ws, i, j, k, formulation.earth_impedance)
                Ztmp[i,j] = z_e
            end
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

    P = Matrix{T}(undef, nph, nph)

    for i in 1:nph
        for j in 1:nph
            if i == j
                P[i,j] = (1 / (2 * π * ε₀)) * log(2 * ws.vert[i] / ws.r_ext[i])
            else
                dist_ij_sq = (ws.horz[i] - ws.horz[j])^2 + (ws.vert[i] - ws.vert[j])^2
                dist_ij_img_sq = (ws.horz[i] - ws.horz[j])^2 + (ws.vert[i] + ws.vert[j])^2
                P[i,j] = (1 / (2 * π * ε₀)) * log(sqrt(dist_ij_img_sq) / sqrt(dist_ij_sq))
            end
        end
    end

    Yc = 1im * ω * inv(P)
    Ptmp .= Yc

	return nothing
end
