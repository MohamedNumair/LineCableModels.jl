export @parameterize, @measurify

"""
    @parameterize(container_expr, union_expr)

Takes a parameterized container expression with a `_` placeholder
(e.g., `Array{_, 3}` or `Vector{_}`) and a Union type (e.g., `REALTYPES`),
and expands it into a Union of concrete container types at compile time.

# Example
```julia
`@parameterize Vector{_} REALTYPES`
...expands to: `Union{Vector{Float64}, Vector{Measurement{Float64}}}`

`@parameterize Array{_, 3} COMPLEXTYPES`
...expands to: `Union{Array{Complex{Float64}, 3}, Array{Complex{Measurement{Float64}}, 3}}`
```
"""
macro parameterize(container_expr, union_expr)
    # Evaluate the Union type from the provided expression 
    local union_type
    try
        # Core.eval gets the *value* of the symbol passed in (e.g., the actual Union type)
        union_type = Core.eval(__module__, union_expr)
    catch e
        error("Expression `$union_expr` could not be evaluated. Make sure it's a defined const or type.")
    end

    # Sanity check
    if !(union_type isa Union)
        error("Second argument must be a Union type. Got a `$(typeof(union_type))` instead.")
    end

    # Base.uniontypes gets the component types, e.g., (Float64, Measurement{Float64})
    component_types = Base.uniontypes(union_type)

    # Define a recursive function to substitute the placeholder `_` 
    function substitute_placeholder(expr, replacement_type)
        # If the current part of the expression is the placeholder symbol,
        # we replace it with the target type (e.g., Float64).
        if expr == :_
            return replacement_type
            # If the current part is another expression (like `Array{_,3}`),
            # we need to recurse into its arguments to find the placeholder.
        elseif expr isa Expr
            # Rebuild the expression with the substituted arguments.
            new_args = [substitute_placeholder(arg, replacement_type) for arg in expr.args]
            return Expr(expr.head, new_args...)
            # Otherwise, it's a literal or symbol we don't need to change (e.g., `:Array` or `3`).
        else
            return expr
        end
    end

    # Build the list of new, concrete types 
    # For each type in the original Union, create a new container expression
    # by calling our substitution function.
    parameterized_types = [substitute_placeholder(container_expr, t) for t in component_types]

    # Wrap the new types in a single `Union{...}` expression and escape 
    final_expr = Expr(:curly, :Union, parameterized_types...)
    return esc(final_expr)
end

"""
    @measurify(function_definition)

Wraps a function definition. If any argument tied to a parametric type `T` is a
`Measurement`, this macro automatically promotes any other arguments of the same
parametric type `T` to `Measurement` with zero uncertainty. Other arguments
(e.g., `i::Int`) are ignored.
"""
macro measurify(def)
    # Normalize to long form
    if def.head == :(=)
        call = def.args[1]
        body = def.args[2]
        def = Expr(:function, call, body)
    elseif def.head == :function
        # ok
    else
        error("@measurify must wrap a function definition")
    end

    sig = def.args[1]
    body = def.args[2]

    # Extract call expr and where-clauses
    call_expr = sig
    where_items = Any[]
    if sig isa Expr && sig.head == :where
        call_expr = sig.args[1]
        where_items = sig.args[2:end]
    end
    fname = call_expr.args[1]

    # Bounds for each where typevar: Dict{Symbol,Any}
    bounds = Dict{Symbol,Any}()
    for w in where_items
        if w isa Symbol
            bounds[w] = :Any
        elseif w isa Expr && w.head == :(<:)
            tv = w.args[1]::Symbol
            ub = w.args[2]
            bounds[tv] = ub
        else
            error("@measurify: unsupported where item: $w")
        end
    end
    typevars = collect(keys(bounds))

    # Split positional vs keyword args in the signature
    posargs = Any[]
    kwexpr = nothing
    for a in call_expr.args[2:end]
        if a isa Expr && a.head == :parameters
            kwexpr = a
        else
            push!(posargs, a)
        end
    end

    # Collect names and find which are promotable (annotated exactly as one of the where typevars)
    names = Symbol[]
    promotable = Symbol[]
    wrapper_posargs = Any[]

    for a in posargs
        if a isa Symbol
            push!(names, a)
            push!(wrapper_posargs, a)  # untyped positional
        elseif a isa Expr && a.head == :(::)
            nm = a.args[1]::Symbol
            ty = a.args[2]
            push!(names, nm)
            if ty isa Symbol && haskey(bounds, ty)
                # replace ::T with ::Bound(T)
                push!(promotable, nm)
                push!(wrapper_posargs, Expr(:(::), nm, bounds[ty]))
            else
                push!(wrapper_posargs, a)
            end
        else
            error("@measurify: unsupported arg form: $a")
        end
    end

    # Build the tight/original method exactly as written
    tight = def

    # Build the loose wrapper signature: same name, same args,
    # but with ::T replaced by ::Bound(T), and NO where-clauses.
    wrapper_call = Expr(:call, fname, wrapper_posargs...)
    if kwexpr !== nothing
        push!(wrapper_call.args, kwexpr)  # keep kw defaults/types as-is
    end

    # Build the call to the tight method (same arg names; keywords forwarded as k=k)
    forward_call = Expr(:call, fname, (:($n) for n in names)...)
    if kwexpr !== nothing
        # transform each kw def into k=k for forwarding
        pairs = Any[]
        for e in kwexpr.args
            kn = e isa Expr && e.head == :(=) ? e.args[1] :
                 e isa Expr && e.head == :(::) ? e.args[1] :
                 e isa Symbol ? e : error("@measurify: bad kw: $e")
            push!(pairs, Expr(:(=), kn, kn))
        end
        push!(forward_call.args, Expr(:parameters, pairs...))
    end

    # If nothing is promotable, wrapper just forwards (harmless)
    promote_tuple = Expr(:tuple, (:($n) for n in promotable)...)

    # make a fresh name for the promoted tuple
    pp = gensym(:promoted)

    # rebinding statements: NO `local`
    rebinding = Any[]
    for (i, nm) in enumerate(promotable)
        push!(rebinding, :($(nm) = $(pp)[$i]))
    end

    wrapper_body = quote
        $(length(promotable) == 0 ? :(nothing) : quote
            $(pp) = promote($(promote_tuple.args...))
            $(rebinding...)
        end)
        $(forward_call)
    end

    loose = Expr(:function, wrapper_call, wrapper_body)

    # @info "measurify input" def
    # ... build `tight`, `loose` ...
    out = Expr(:block, :(Base.@__doc__ $tight), loose)
    # @info "measurify output" out
    return esc(out)

end

"""
$(TYPEDSIGNATURES)

Automatically exports public functions, types, and modules from a module. This is meant for temporary development chores and should never be used in production code.

# Arguments

- None.

# Returns

- An `export` expression containing all public symbols that should be exported.

# Notes

This macro scans the current module for all defined symbols and automatically generates an `export` statement for public functions, types, and submodules, excluding built-in and private names. Private names are considered those starting with an underscore ('_'), as per standard Julia conventions.
	
# Examples

```julia
@autoexport
```
"""
macro autoexport()
    mod = __module__

    # Get all names defined in the module, including unexported ones
    all_names = names(mod; all=true)

    # List of names to explicitly exclude
    excluded_names = Set([:eval, :include, :using, :import, :export, :require])

    # Filter out private names (starting with '_'), module name, built-in functions, and auto-generated method symbols
    public_names = Symbol[]
    for name in all_names
        str_name = string(name)

        startswith(str_name, "@_") && continue  # Skip private macros
        startswith(str_name, "_") && continue  # Skip private names
        name === nameof(mod) && continue  # Skip the module's own name
        name in excluded_names && continue  # Skip built-in functions
        startswith(str_name, "#") && continue  # Skip generated method symbols (e.g., #eval, #include)

        if isdefined(mod, name)
            val = getfield(mod, name)
            if val isa Function || val isa Type || val isa Module
                push!(public_names, name)
            end
        end
    end

    return esc(Expr(:export, public_names...))
end