# Export public API
export FormulationSet, DataFrame, add!, load!, export_data, save, preview
export f₀, μ₀, ε₀, ρ₀, T₀, TOL, ΔTmax
export setup_logging!

# General constants
"Base power system frequency, f₀ = 50.0 [Hz]."
const f₀ = 50.0
"Magnetic constant (vacuum permeability), μ₀ = 4π * 1e-7 [H/m]."
const μ₀ = 4π * 1e-7
"Electric constant (vacuum permittivity), ε₀ = 8.8541878128e-12 [F/m]."
const ε₀ = 8.8541878128e-12
"Annealed copper reference resistivity, ρ₀ = 1.724e-08 [Ω·m]."
const ρ₀ = 1.724e-08
"Base temperature for conductor properties, T₀ = 20.0 [°C]."
const T₀ = 20.0
"Maximum tolerance for temperature variations, ΔTmax = 150 [°C]."
const ΔTmax = 150.0
"Default tolerance for floating-point comparisons, TOL = 1e-6."
const TOL = 1e-6

# Define aliases for the type constraints
using Measurements
const BASE_FLOAT = Float64
const REALTYPES = Union{BASE_FLOAT,Measurement{BASE_FLOAT}}
const COMPLEXTYPES = Union{Complex{BASE_FLOAT},Complex{Measurement{BASE_FLOAT}}}
const NUMERICTYPES = Union{REALTYPES,COMPLEXTYPES}

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
    FormulationSet(...)

Constructs a specific formulation object based on the provided keyword arguments.
The system will infer the correct formulation type.
"""
FormulationSet(engine::Symbol; kwargs...) = FormulationSet(Val(engine); kwargs...)

"""
$(TYPEDSIGNATURES)

Returns a standardized identifier string for formulation types.

# Arguments

- A concrete implementation of [`AbstractFormulationSet`](@ref).

# Returns

- A string identifier used consistently across plots, tables, and parametric analyses.

# Examples
```julia
cp = CPEarth()
tag = _get_description(cp)  # Returns "CP model"
```

# Methods

$(_CLEANMETHODLIST)

# See also

- [`AbstractFDEMFormulation`](@ref)
- [`AbstractEHEMFormulation`](@ref)
"""
function _get_description end

function add! end

function load! end

function export_data end

function save end

function preview end

"""
$(TYPEDSIGNATURES)

Determines if the current execution environment is headless (without display capability).

# Returns

- `true` if running in a continuous integration environment or without display access.
- `false` otherwise when a display is available.

# Examples

```julia
if $(FUNCTIONNAME)()
	# Use non-graphical backend
	gr()
else
	# Use interactive backend
	plotlyjs()
end
```
"""
function _is_headless()::Bool
    return haskey(ENV, "CI") || !haskey(ENV, "DISPLAY")
end

function _display_path(file_name)
    return _is_headless() ? basename(file_name) : relpath(file_name) #abspath(file_name)
end

"""
$(TYPEDSIGNATURES)

Checks if the code is running inside a `@testset` by checking if `Test` is loaded
in the current session and then calling `get_testset_depth()`.
"""
function _is_in_testset()
    if isdefined(Main, :Test)
        # If Test is loaded, we can safely access its functions
        return Main.Test.get_testset_depth() > 0
    end
    return false
end

using Logging
using Logging: AbstractLogger, LogLevel, Info, global_logger
using LoggingExtras: TeeLogger, FileLogger
using Dates
using Printf

struct TimestampLogger <: AbstractLogger
    logger::AbstractLogger
end

Logging.min_enabled_level(logger::TimestampLogger) = Logging.min_enabled_level(logger.logger)
Logging.shouldlog(logger::TimestampLogger, level, _module, group, id) =
    Logging.shouldlog(logger.logger, level, _module, group, id)

function Logging.handle_message(logger::TimestampLogger, level, message, _module, group, id,
    filepath, line; kwargs...)
    timestamp = Dates.format(now(), "yyyy-mm-dd HH:MM:SS")
    new_message = "[$timestamp] $message"
    Logging.handle_message(logger.logger, level, new_message, _module, group, id,
        filepath, line; kwargs...)
end

function setup_logging!(verbosity::Int, logfile::Union{String,Nothing}=nothing)
    level = verbosity >= 2 ? Logging.Debug :
            verbosity == 1 ? Logging.Info : Logging.Warn

    # Create console logger
    console_logger = ConsoleLogger(stderr, level)

    if isnothing(logfile)
        # Log to console only
        global_logger(TimestampLogger(console_logger))
    else
        # Try to set up file logging with fallback to console-only
        try
            file_logger = FileLogger(logfile, level)
            combined_logger = TeeLogger(console_logger, file_logger)
            global_logger(TimestampLogger(combined_logger))
        catch e
            @warn "Failed to set up file logging to $(_display_path(logfile)): $e"

            global_logger(TimestampLogger(console_logger))
        end
    end
end

function __init__()
    # Set a default logging level when the package is loaded at runtime.
    # This ensures it overrides any environment-specific loggers.
    setup_logging!(0)
end