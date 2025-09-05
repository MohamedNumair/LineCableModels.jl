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

	# --- per-frequency pipeline ------------------------------------------------
	@info "Starting line parameters computation"
	for k in 1:nfreq
		# 0) build raw slice (fill Ztmp, Ytmp in ORIGINAL ordering)
		# _compute_impedance_slice_into!(Ztmp, ws, k, formulation)    # <-- your builder
		# _compute_admittance_slice_into!(Ytmp, ws, k, formulation)   # <-- your builder

		# # 1) reorder
		# _reorder_into!(Zbuf, Ztmp, perm)
		# _reorder_into!(Ybuf, Ytmp, perm)

		# # 2) bundle reduction (in-place)
		# if formulation.options.reduce_bundle
		# 	merge_bundles!(Zbuf, map_r)
		# 	merge_bundles!(Ybuf, map_r)
		# end

		# # 3) kron
		# if kron_map === nothing
		# 	@inbounds Zout[:, :, k] .= Zbuf
		# 	@inbounds Yout[:, :, k] .= Ybuf
		# else
		# 	Zred = kronify(Zbuf, kron_map)   # your function
		# 	Yred = kronify(Ybuf, kron_map)
		# 	@inbounds Zout[:, :, k] .= Zred
		# 	@inbounds Yout[:, :, k] .= Yred
		# end
	end
	@info "Line parameters computation completed successfully"
	return ws, LineParameters(Zout, Yout, ws.freq)
end
