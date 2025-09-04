function compute!(problem::LineParametersProblem{T},
	formulation::EMTFormulation) where {T}

	# Flatten the system into 1D arrays for computation
	ws = init_workspace(problem, formulation)

	ComplexT = Complex{T}

	@info "Preallocating arrays"
	n_frequencies = ws.n_frequencies
	n_phases = ws.n_phases
	Z = zeros(ComplexT, n_phases, n_phases, n_frequencies)
	Y = zeros(ComplexT, n_phases, n_phases, n_frequencies)

	@info "Starting line parameters computation"

	Z = _compute_impedance_matrix_from_ws(ws)
	Y = _compute_admittance_matrix_from_ws(ws)
	# 
	# here the shitshow starts
	# for each frequency
	# calculate temperature corrected terms
	# calc internal impedances
	# calc earth impedances
	# repeat for admitatances
	# do bundle reduction 
	# do kronify if needed
	# modal decomposition if needed



	ZY = LineParameters(Z, Y, ws.freq)   # 3D complex array

	@info "Line parameters computation completed successfully"
	return ws, ZY
end

function reorder_indices(map::AbstractVector{<:Integer})
	n = length(map)
	phases = Int[]                     # encounter order of phases > 0
	firsts = Int[]
	sizehint!(firsts, n)
	zeros = Int[]
	sizehint!(zeros, n)
	tails = Dict{Int, Vector{Int}}()   # phase => remaining indices

	seen = Set{Int}()
	@inbounds for (i, p) in pairs(map)
		if p > 0
			if !(p in seen)
				push!(seen, p)
				push!(phases, p)
				push!(firsts, i)
			else
				push!(get!(tails, p, Int[]), i)
			end
		else
			push!(zeros, i)
		end
	end

	perm = Vector{Int}(undef, n)
	k = 1
	@inbounds begin
		for i in firsts
			perm[k] = i
			k += 1
		end
		for p in phases
			if haskey(tails, p)
				for i in tails[p]
					perm[k] = i
					k += 1
				end
			end
		end
		for i in zeros
			perm[k] = i
			k += 1
		end
	end
	return perm
end

# Non-mutating reorder (2D)
function reorder_M(M::AbstractMatrix, map::AbstractVector{<:Integer})
	n = size(M, 1)
	n == size(M, 2) == length(map) || throw(ArgumentError("shape mismatch"))
	perm = reorder_indices(map)
	return M[perm, perm], map[perm]
end


"""
	kronify(M, phase_map)
	Kron elimination
"""
function kronify(
	M::Matrix{Complex{T}},
	phase_map::Vector{Int},
) where {T <: REALSCALAR}
	keep = findall(!=(0), phase_map)
	eliminate = findall(==(0), phase_map)

	M11 = M[keep, keep]
	M12 = M[keep, eliminate]
	M21 = M[eliminate, keep]
	M22 = M[eliminate, eliminate]

	return M11 - (M12 * inv(M22)) * M21

end

