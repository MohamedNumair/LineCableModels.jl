
mtransform(lineparams::LineParameters{T}, S::Symbol) where {T<:COMPLEXSCALAR} = mtransform(lineparams, Val(S))

function mtransform(lineparams::LineParameters{T}, ::Val{:Fortescue}) where {T}
    _, nph, nfreq = size(lineparams.Z.values)
    F = fortescue_F(nph, Float64)           # unitary; inverse is F'
    Z012 = similar(lineparams.Z.values)
    Y012 = similar(lineparams.Y.values)

    for f in 1:nfreq
        Zs = symmetranspose(lineparams.Z.values[:, :, f])  # enforce reciprocity
        Ys = symmetranspose(lineparams.Y.values[:, :, f])

        Zseq = F * Zs * F'       # NOT inv(T)*Z*T — use unitary similarity
        Yseq = F * Ys * F'

        if offdiag_ratio(Zseq) > 1e-4
            @warn "Fortescue: Z not diagonal enough, check your results" rZ = offdiag_ratio(Zseq)
        end
        if offdiag_ratio(Yseq) > 1e-4
            @warn "Fortescue: Y not diagonal enough, check your results" rY = offdiag_ratio(Yseq)
        end

        Z012[:, :, f] = Matrix(Diagonal(diag(Zseq)))
        Y012[:, :, f] = Matrix(Diagonal(diag(Yseq)))
    end
    return LineParameters(Z012, Y012)
end

# Unitary N-point DFT (Fortescue) matrix
function fortescue_F(N::Integer, ::Type{T}=Float64) where {T<:AbstractFloat}
    N ≥ 1 || throw(ArgumentError("N ≥ 1"))
    θ = T(2π) / T(N)
    s = one(T) / sqrt(T(N))
    a = cis(θ)
    return s .* [a^(k * m) for k in 0:N-1, m in 0:N-1]  # F; inverse is F'
end

# Reciprocity symmetrization (power lines want transpose, not adjoint)
symmetranspose(A) = (A .+ transpose(A)) / 2

function isdiag_approx(A; rtol=1e-8, atol=1e-8)
    isapprox(A, Diagonal(diag(A)); rtol=rtol, atol=atol)
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

isdiag_rel(A; τ=1e-4) = offdiag_ratio(A) ≤ τ

function issymmetric_approx(A; rtol=1e-8, atol=1e-8)
    size(A, 1) == size(A, 2) || return false
    return isapprox(A, transpose(A); rtol=rtol, atol=atol)
end