@inline _promotion_T(::Type{C}, ntv, _order::Tuple) where {C} =
    resolve_T((getfield(ntv, k) for k in coercive_fields(C))...)

@inline _coerced_args(::Type{C}, ntv, Tp, order::Tuple) where {C} =
    tuple((
        let k = s, v = getfield(ntv, s)
            (s in coercive_fields(C)) ? coerce_to_T(v, Tp) : v
        end
        for s in order
    )...)

# materialize tuple of symbols/defaults from tuple literal or const name
_ctor_materialize(mod, x) = x === :(()) ? () :
                            x isa Expr && x.head === :tuple ? x.args :
                            x isa Symbol ? Base.eval(mod, x) :
                            error("@_ctor: expected tuple literal or const tuple, got $(x)")

using MacroTools: postwalk

macro _ctor(T, REQ, OPT=:(()), DEFS=:(()))
    mod = __module__
    req = Symbol.(_ctor_materialize(mod, REQ))
    opt = Symbol.(_ctor_materialize(mod, OPT))
    dfx = _ctor_materialize(mod, DEFS)
    length(opt) == length(dfx) || error("@_ctor: OPT and DEFS length mismatch")

    # A) signature defaults (escape defaults)
    sig_kws = [Expr(:kw, opt[i], esc(dfx[i])) for i in eachindex(opt)]
    #    forwarding kwargs (variables, not defaults)
    pass_kws = [Expr(:kw, s, s) for s in opt]

    # B) flat order tuple
    order_syms = (req..., opt...)
    order = Expr(:tuple, (QuoteNode.(order_syms))...)

    ex = isempty(sig_kws) ? quote
        function $(T)($(req...))
            ntv = validate!($(T), $(req...))
            Tp = _promotion_T($(T), ntv, $order)
            local __args__ = _coerced_args($(T), ntv, Tp, $order)
            return $(T)(__args__...)
        end
    end : quote
        function $(T)($(req...); $(sig_kws...))
            ntv = validate!($(T), $(req...); $(pass_kws...))   # C) pass vars
            Tp = _promotion_T($(T), ntv, $order)
            local __args__ = _coerced_args($(T), ntv, Tp, $order)
            return $(T)(__args__...)
        end
    end

    # hygiene stays as you had it
    free = Set{Symbol}([:validate!, :_promotion_T, :_coerced_args, T])
    ex2 = postwalk(ex) do node
        node isa Symbol && (node in free) ? esc(node) : node
    end
    return ex2
end

# macro _ctor(T, REQ, OPT=:(()), DEFS=:(()))
#     # NOTE: macros run in caller's module
#     mod = __module__

#     req_syms_any = _ctor_materialize(mod, REQ)
#     opt_syms_any = _ctor_materialize(mod, OPT)
#     def_vals_any = _ctor_materialize(mod, DEFS)

#     req_syms = Symbol.(req_syms_any)
#     opt_syms = Symbol.(opt_syms_any)
#     defs = def_vals_any

#     length(opt_syms) == length(defs) || error("@_ctor: OPT and DEFS length mismatch")

#     # === Build function signature ===
#     # positional args: plain Symbols (no esc here)
#     pos_args = req_syms

#     # keyword defaults: name = (escaped default expr)
#     kw_defs = Any[]
#     for i in eachindex(opt_syms)
#         push!(kw_defs, Expr(:kw, opt_syms[i], esc(defs[i])))
#     end

#     # validate! kwargs: name = name (pass-through)
#     call_kws = Any[]
#     for s in opt_syms
#         push!(call_kws, Expr(:kw, s, s))
#     end

#     # order used for promotion/coercion: REQ ++ OPT
#     order_tuple = Expr(:tuple, (QuoteNode.(vcat(req_syms, opt_syms))...))

#     # build function head: function T(pos...; kw=defaults...)
#     head = isempty(kw_defs) ?
#            Expr(:call, esc(T), pos_args...) :
#            Expr(:call, esc(T), pos_args..., Expr(:parameters, kw_defs...))

#     # ntv = validate!(T, pos...; kw...)
#     validate_call = isempty(call_kws) ?
#                     Expr(:call, :validate!, esc(T), pos_args...) :
#                     Expr(:call, :validate!, esc(T), pos_args..., Expr(:parameters, call_kws...))

#     promote_call = Expr(:call, :_promotion_T, esc(T), :ntv, order_tuple)
#     coerced_call = Expr(:call, :_coerced_args, :ntv, :Tp, order_tuple)

#     # use a gensym so we can splat the coerced tuple
#     args_sym = gensym(:args)

#     body = quote
#         ntv = $validate_call
#         Tp = $promote_call
#         local $args_sym = $coerced_call
#         return $(esc(T))($args_sym...)
#     end

#     return esc(Expr(:function, head, body))
# end
