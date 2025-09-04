


# Reciprocity symmetrization (power lines want transpose, not adjoint)
symmetranspose(A) = (A .+ transpose(A)) / 2

function isdiag_approx(A; rtol = 1e-8, atol = 1e-8)
	isapprox(A, Diagonal(diag(A)); rtol = rtol, atol = atol)
end

function offdiag_ratio(A)
	n = size(A, 1)
	n == size(A, 2) || throw(ArgumentError("square"))
	T = real(float(eltype(A)))
	dmax = zero(T)
	odmax = zero(T)
	@inbounds for j in 1:n
		dj = abs(A[j, j])
		dmax = dj > dmax ? dj : dmax
		for i in 1:n
			i == j && continue
			v = abs(A[i, j])
			odmax = v > odmax ? v : odmax
		end
	end
	return odmax / max(dmax, eps(T))
end

isdiag_rel(A; τ = 1e-4) = offdiag_ratio(A) ≤ τ

function issymmetric_approx(A; rtol = 1e-8, atol = 1e-8)
	size(A, 1) == size(A, 2) || return false
	return isapprox(A, transpose(A); rtol = rtol, atol = atol)
end
