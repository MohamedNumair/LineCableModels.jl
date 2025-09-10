# function compute!(problem::LineParametersProblem{T},
# 	formulation::EMTFormulation) where {T}

# 	# Flatten the system into 1D arrays for computation
# 	ws = init_workspace(problem, formulation)

# 	ComplexT = Complex{T}

# 	@info "Preallocating arrays"
# 	n_frequencies = ws.n_frequencies
# 	n_phases = ws.n_phases
# 	Z = zeros(ComplexT, n_phases, n_phases, n_frequencies)
# 	Y = zeros(ComplexT, n_phases, n_phases, n_frequencies)

# 	@info "Starting line parameters computation"


# 	# 
# 	# here the shitshow starts
# 	# for each frequency
# 	# ---calculate temperature corrected terms
# 	# ---calc internal impedances
# 	# ---calc earth impedances
# 	# ----repeat for admitatances
# 	Z = _compute_impedance_matrix_from_ws(ws)
# 	Y = _compute_admittance_matrix_from_ws(ws)
# 	# do bundle reduction if formulation.options.reduce_bundle == true
# 	# do kronify on all conductors with index 0 if formulation.options.kron_reduction == true
# 	# important: if reduce_bundle == true but kron_reduction == false, then kron reduction should eliminate only the residuals of the bundles, i.e. each equivalent conductor + all conductors with phase 0. This allows for representation of bundled conductors to reduce the model order, but to keep the shield wires explicit for  short circuit studies etc
# 	# modal decomposition 



# 	ZY = LineParameters(Z, Y, ws.freq)   # 3D complex array

# 	@info "Line parameters computation completed successfully"
# 	return ws, ZY
# end

function compute!(
	problem::LineParametersProblem{T},
	formulation::EMTFormulation,
) where {T <: REALSCALAR}

	@info "Preallocating arrays"

	ws = init_workspace(problem, formulation)
	nph, nfreq = ws.n_phases, ws.n_frequencies

	# --- full matrices are built per slice (no 3D alloc) ----------------------
	Zbuf = Matrix{Complex{T}}(undef, nph, nph)   # reordered scratch (mutated by merge_bundles!)
	Ybuf = Matrix{Complex{T}}(undef, nph, nph)
	Ztmp = Matrix{Complex{T}}(undef, nph, nph)   # raw slice coming from builders
	Ytmp = Matrix{Complex{T}}(undef, nph, nph)

	# --- index plan (constant across k) ---------------------------------------
	phase_map = ws.phase_map::Vector{Int}
	perm      = reorder_indices(phase_map)
	map_r     = phase_map[perm]                  # reordered map

	# bundle tails mask (same logic as merge_bundles!, but map-only)
	reduced_map = let m = copy(map_r), seen = Set{Int}()
		@inbounds for (i, p) in pairs(map_r)
			if p > 0 && (p in seen)
				;
				m[i]=0
			else
				;
				p>0 && push!(seen, p)
			end
		end
		m
	end

	# decide what Kron kills
	kron_map = if formulation.options.reduce_bundle
		if formulation.options.kron_reduction
			reduced_map                      # kill tails and keep nonzero labels
		else
			km = copy(reduced_map)           # kill only tails; keep phase-0 explicit
			@inbounds for i in eachindex(km)
				if map_r[i] == 0
					;
					km[i] = -1
				end
			end
			km
		end
	else
		formulation.options.kron_reduction ? map_r : nothing
	end

	nkeep = kron_map === nothing ? nph : count(!=(0), kron_map)
	Zout = Array{Complex{T}, 3}(undef, nkeep, nkeep, nfreq)
	Yout = Array{Complex{T}, 3}(undef, nkeep, nkeep, nfreq)

	# tiny gather helper to avoid per-slice allocs
	@inline function _reorder_into!(dest::AbstractMatrix{Complex{T}},
		src::AbstractMatrix{Complex{T}},
		perm::AbstractVector{Int})
		n = length(perm)
		@inbounds for j in 1:n, i in 1:n
			dest[i, j] = src[perm[i], perm[j]]
		end
		return dest
	end

	# apply temperature correction if needed
	if formulation.options.temperature_correction
		ΔT = ws.temp - T₀
		@. ws.rho_cond *= 1 + ws.alpha_cond * ΔT
	end

	# --- per-frequency pipeline ------------------------------------------------
	@info "Starting line parameters computation"
	for k in 1:nfreq
		# 0) build raw slice (fill Ztmp, Ytmp in ORIGINAL ordering)
		_compute_impedance_slice_into!(Ztmp, ws, k, formulation)
		_compute_admittance_slice_into!(Ytmp, ws, k, formulation)

		# 1) reorder into bundle ordering
		_reorder_into!(Zbuf, Ztmp, perm)
		_reorder_into!(Ybuf, Ytmp, perm)

		# 2) bundle reduction (in-place)
		if formulation.options.reduce_bundle
			merge_bundles!(Zbuf, map_r)
			merge_bundles!(Ybuf, map_r)
		end

		# 3) kron reduction if requested
		if kron_map === nothing
			@inbounds Zout[:, :, k] .= Zbuf
			@inbounds Yout[:, :, k] .= Ybuf
		else
			Zred = kronify(Zbuf, kron_map)
			Yred = kronify(Ybuf, kron_map)
			@inbounds Zout[:, :, k] .= Zred
			@inbounds Yout[:, :, k] .= Yred
		end
	end
	@info "Line parameters computation completed successfully"
	return ws, LineParameters(Zout, Yout, ws.freq)
end

# ---------------------------------------------------------------------------
# Slice builders (analytical EMT)
# ---------------------------------------------------------------------------

@inline function _compute_impedance_slice_into!(Z::AbstractMatrix{Complex{T}}, ws::EMTWorkspace{T}, k::Int, formulation::EMTFormulation) where {T<:REALSCALAR}
	n = ws.n_phases
	ω = 2π*ws.freq[k]
	μ0T = T(μ₀)
	intf = formulation.internal_impedance
	earthf = formulation.earth_impedance
	# Pre-clear (not strictly necessary if fully written)
	@inbounds for j in 1:n, i in 1:n
		Z[i,j] = 0
	end
	@inbounds for i in 1:n
		# internal self
		Zint = intf(:inner, ws.r_in[i], ws.r_ext[i], ws.rho_cond[i], ws.mu_cond[i], ws.freq[k])
		# external spacing (geometric inductive) term log(1/r_eq) using external radius as proxy
		Zext = (im*ω*μ0T/(2π)) * log(1/ws.r_ext[i])
		# earth self: use vertical positions as depth h; h vector length 2 for interface logic
		hvec = T[ws.vert[i], ws.vert[i]]
		Ze = earthf(:self, hvec, zero(T), @view(ws.rho_g[:,k]), @view(ws.eps_g[:,k]), @view(ws.mu_g[:,k]), ws.freq[k])
		Z[i,i] = Zint + Zext + Ze
		for j in 1:i-1
			# mutual spacing
			dij = sqrt((ws.horz[i]-ws.horz[j])^2 + (ws.vert[i]-ws.vert[j])^2)
			Zspacing = (im*ω*μ0T/(2π))*log(1/dij)
			# earth mutual
			hvecm = T[ws.vert[i], ws.vert[j]]
			yij = abs(ws.horz[i]-ws.horz[j])
			Zem = earthf(:mutual, hvecm, yij, @view(ws.rho_g[:,k]), @view(ws.eps_g[:,k]), @view(ws.mu_g[:,k]), ws.freq[k])
			Zij = Zspacing + Zem
			Z[i,j] = Zij
			Z[j,i] = Zij
		end
	end
	return Z
end

@inline function _compute_admittance_slice_into!(Y::AbstractMatrix{Complex{T}}, ws::EMTWorkspace{T}, k::Int, formulation::EMTFormulation) where {T<:REALSCALAR}
	n = ws.n_phases
	ω = 2π*ws.freq[k]
	ε0T = T(ε₀)
	# Potential coefficient (image method) then invert -> capacitance -> admittance
	# Build P (j/ω factor kept inside for numerical stability similar to earlier sketch)
	@inbounds for j in 1:n, i in 1:n
		Y[i,j] = 0
	end
	P = Matrix{Complex{T}}(undef, n, n)
	@inbounds for i in 1:n
		hi = abs(ws.vert[i])
		P[i,i] = (im/ω) * (-1/(2π*ε0T)) * log((2*hi)/ws.r_ins_in[i])
		for j in 1:i-1
			d  = sqrt((ws.horz[i]-ws.horz[j])^2 + (ws.vert[i]-ws.vert[j])^2)
			d′ = sqrt((ws.horz[i]-ws.horz[j])^2 + (ws.vert[i]+ws.vert[j])^2)
			val = (im/ω)*(-1/(2π*ε0T))*log(d′/d)
			P[i,j] = val
			P[j,i] = val
		end
	end
	# invert P -> Y = inv(P)
	Ctry = try
		inv(P)  # Y already (since P included (j/ω) factor); otherwise adjust
	catch
		fill(zero(Complex{T}), n, n)
	end
	@inbounds Y[:,:] = Ctry
	return Y
end
