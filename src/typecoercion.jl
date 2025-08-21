
export resolve_T, coerce_to_T

# --- Does a TYPE contain Measurements anywhere? ---

# Direct hit
_hasmeas_type(::Type{<:Measurement}) = true

# Arrays → look at element type
_hasmeas_type(::Type{<:AbstractArray{S}}) where {S} = _hasmeas_type(S)

# Tuples (includes Vararg via parameter pack)
_hasmeas_type(::Type{<:Tuple{}}) = false
_hasmeas_type(::Type{T}) where {T<:Tuple} =
    any(_hasmeas_type, Base.unwrap_unionall(T).parameters)


# NamedTuples: second parameter is a Tuple of field types
_hasmeas_type(::Type{NamedTuple{N,T}}) where {N,T} = _hasmeas_type(T)

# Unions
_hasmeas_type(T::Union) = _hasmeas_type(T.a) || _hasmeas_type(T.b)

# Concrete structs: recurse on field types
_hasmeas_type(T::DataType) = isconcretetype(T) && any(_hasmeas_type, fieldtypes(T))

# Fallback default
_hasmeas_type(::Type) = false

# Public: decide the canonical numeric T for a bag of arguments
resolve_T(args...) = any(a -> _hasmeas_type(typeof(a)), args) ? Measurement{BASE_FLOAT} : BASE_FLOAT








# # Scalar element coercion (number or measurement)
# _meas_inner(::Type{Measurement{S}}) where {S} = S

# # _coerce_elt_to_T(x, ::Type{T}) where {T} = convert(T, x)  # generic fallback for pure numbers

# # Deterministic -> Measurement (sigma = 0)
# _coerce_elt_to_T(x::Number, ::Type{T}) where {T<:Measurement} = zero(T) + x

# # Measurement -> Measurement{BASE_FLOAT} (keep sigma)
# _coerce_elt_to_T(m::Measurement, ::Type{T}) where {T<:Measurement} =
#     measurement(_meas_inner(T)(value(m)), _meas_inner(T)(uncertainty(m)))

# # Measurement -> plain Real (drop sigma, keep nominal)
# _coerce_elt_to_T(m::Measurement, ::Type{R}) where {R<:Real} = convert(R, value(m))

# # ---------- containers ----------
# coerce_to_T(x, ::Type{T}) where {T} = _coerce_elt_to_T(x, T)  # scalar fast path

# coerce_to_T(A::AbstractArray, ::Type{T}) where {T} = broadcast(y -> _coerce_elt_to_T(y, T), A)

# coerce_to_T(t::Tuple, ::Type{T}) where {T} = map(y -> coerce_to_T(y, T), t)

# coerce_to_T(nt::NamedTuple, ::Type{T}) where {T} = begin
#     vals2 = map(v -> coerce_to_T(v, T), values(nt))
#     NamedTuple{keys(nt)}(vals2)
# end

# ---------- Element coercion ----------
_meas_inner(::Type{Measurement{S}}) where {S} = S

# Number → plain float
_coerce_elt_to_T(x::Number, ::Type{R}) where {R<:AbstractFloat} = convert(R, x)

# Number → Measurement (σ = 0)
_coerce_elt_to_T(x::Number, ::Type{M}) where {M<:Measurement} = zero(M) + x

# Measurement → Measurement{BASE_FLOAT} (preserve σ)
_coerce_elt_to_T(m::Measurement, ::Type{M}) where {M<:Measurement} =
    measurement(_meas_inner(M)(value(m)), _meas_inner(M)(uncertainty(m)))

# Measurement → plain float (drop σ)
_coerce_elt_to_T(m::Measurement, ::Type{R}) where {R<:AbstractFloat} = convert(R, value(m))

# Pass-through non-numeric leaves
_coerce_elt_to_T(::Nothing, ::Type{T}) where {T} = nothing
_coerce_elt_to_T(::Missing, ::Type{T}) where {T} = missing
_coerce_elt_to_T(x::Bool, ::Type{M}) where {M<:Measurement} = x
_coerce_elt_to_T(x::Bool, ::Type{R}) where {R<:AbstractFloat} = x
_coerce_elt_to_T(x::Union{Symbol,String,Function,DataType}, ::Type{T}) where {T} = x

# Final fallback: identity
_coerce_elt_to_T(x, ::Type{T}) where {T} = x

# ---------- Public coercion API (containers + scalars) ----------
coerce_to_T(x::Number, ::Type{T}) where {T} = _coerce_elt_to_T(x, T)

# coerce_to_T(A::AbstractArray, ::Type{T}) where {T} =
#     broadcast(y -> _coerce_elt_to_T(y, T), A)
coerce_to_T(A::AbstractArray, ::Type{T}) where {T} =
    broadcast(y -> coerce_to_T(y, T), A)

coerce_to_T(t::Tuple, ::Type{T}) where {T} =
    map(y -> coerce_to_T(y, T), t)

coerce_to_T(nt::NamedTuple, ::Type{T}) where {T} =
    NamedTuple{keys(nt)}(map(v -> coerce_to_T(v, T), values(nt)))

coerce_to_T(x, ::Type{T}) where {T} =
    _coerce_elt_to_T(x, T)  # other leaves: identity or element coercion

