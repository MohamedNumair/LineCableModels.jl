import ..Utils: coerce_to_T
using ..Validation: required_fields, keyword_fields, coercive_fields

@inline function _rebuild_part_typed_core(p, ::Type{T}) where {T}
    C0 = typeof(p).name.wrapper                       # concrete parametric type (e.g., WireArray)
    order = (required_fields(C0)..., keyword_fields(C0)...)  # positional order for tight kernel
    coer = coercive_fields(C0)                          # only these get coerced to T

    argsT = ntuple(i -> begin
            s = order[i]
            v = getfield(p, s)
            (s in coer) ? coerce_to_T(v, T) : v              # preserve Int/categorical fields
        end, length(order))

    return C0(argsT...)                                  # call the tight numeric constructor
end

# Identity when already at T (no rebuild, preserves ===)
coerce_to_T(p::AbstractConductorPart{T}, ::Type{T}) where {T} = p
# Cross-T rebuild via your existing tight numeric-core helper
coerce_to_T(p::AbstractConductorPart{S}, ::Type{T}) where {S,T} =
    _rebuild_part_typed_core(p, T)
coerce_to_T(g::ConductorGroup{T}, ::Type{T}) where {T} = g
# Cross-T: fieldwise coerce + layer coercion (no recompute)
@inline function coerce_to_T(g::ConductorGroup{S}, ::Type{T}) where {S,T}
    n = length(g.layers)
    layersT = Vector{AbstractConductorPart{T}}(undef, n)
    @inbounds for i in 1:n
        layersT[i] = coerce_to_T(g.layers[i], T)  # uses your part-level coercers
    end
    return ConductorGroup{T}(
        coerce_to_T(g.radius_in, T),
        coerce_to_T(g.radius_ext, T),
        coerce_to_T(g.cross_section, T),
        g.num_wires,                                  # keep Int as-is
        coerce_to_T(g.num_turns, T),
        coerce_to_T(g.resistance, T),
        coerce_to_T(g.alpha, T),
        coerce_to_T(g.gmr, T),
        layersT,
    )
end

@inline coerce_to_T(p::AbstractInsulatorPart{T}, ::Type{T}) where {T} = p
@inline coerce_to_T(p::AbstractInsulatorPart{S}, ::Type{T}) where {S,T} =
    _rebuild_part_typed_core(p, T)
@inline coerce_to_T(g::InsulatorGroup{T}, ::Type{T}) where {T} = g

@inline function coerce_to_T(g::InsulatorGroup{S}, ::Type{T}) where {S,T}
    n = length(g.layers)
    layersT = Vector{AbstractInsulatorPart{T}}(undef, n)
    @inbounds for i in 1:n
        layersT[i] = coerce_to_T(g.layers[i], T)   # uses the part-level coercers above
    end
    return InsulatorGroup{T}(
        coerce_to_T(g.radius_in, T),
        coerce_to_T(g.radius_ext, T),
        coerce_to_T(g.cross_section, T),
        coerce_to_T(g.shunt_capacitance, T),
        coerce_to_T(g.shunt_conductance, T),
        layersT,
    )
end

"Identity: no allocation when already at `T`."
@inline coerce_to_T(n::NominalData{T}, ::Type{T}) where {T} = n

"Cross-T rebuild: fieldwise coercion to `T`, preserving `nothing`."
@inline function coerce_to_T(n::NominalData{S}, ::Type{T}) where {S,T}
    NT = NamedTuple{fieldnames(typeof(n))}(
        (getfield(n, k) === nothing ? nothing : coerce_to_T(getfield(n, k), T)
         for k in fieldnames(typeof(n)))...
    )
    return NominalData{T}(; NT...)
end