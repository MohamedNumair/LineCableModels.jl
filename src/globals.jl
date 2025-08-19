# Export public API
export FormulationSet, DataFrame, add!, load!, export_data, save, preview
export f₀, μ₀, ε₀, ρ₀, T₀, TOL, ΔTmax
export setup_logging!
export BASE_FLOAT, REALTYPES, COMPLEXTYPES

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

using Reexport, ForceImport

# Define aliases for the type constraints
using Measurements
const BASE_FLOAT = Float64
const REALTYPES = Union{BASE_FLOAT,Measurement{BASE_FLOAT}}
const COMPLEXTYPES = Union{Complex{BASE_FLOAT},Complex{Measurement{BASE_FLOAT}}}

using DocStringExtensions, Pkg
"""
Override `DocStringExtensions.format` for `_CLEANMETHODLIST`.
"""
struct _CleanMethodList <: DocStringExtensions.Abbreviation end
"Modified `_CLEANMETHODLIST` abbreviation with sanitized file paths."
const _CLEANMETHODLIST = _CleanMethodList()
function DocStringExtensions.format(::_CleanMethodList, buf, doc)
    local binding = doc.data[:binding]
    local typesig = doc.data[:typesig]
    local modname = doc.data[:module]
    local func = Docs.resolve(binding)
    local groups = DocStringExtensions.methodgroups(func, typesig, modname; exact=false)
    if !isempty(groups)
        println(buf)
        local pkg_root = Pkg.pkgdir(modname) # Use Pkg.pkgdir here
        if pkg_root === nothing
            @warn "Could not determine package root for module $modname using _CLEANMETHODLIST. Paths will be shown as basenames."
        end
        for group in groups
            println(buf, "```julia")
            for method in group
                DocStringExtensions.printmethod(buf, binding, func, method)
                println(buf)
            end
            println(buf, "```\n")
            if !isempty(group)
                local method = group[1]
                local file = string(method.file)
                local line = method.line
                local path =
                    if pkg_root !== nothing && !isempty(file) &&
                       startswith(file, pkg_root)
                        basename(file) # relpath(file, pkg_root)
                    # elseif !isempty(file) && isfile(file)
                    # 	basename(file)
                    else
                        string(method.file) # Fallback
                    end
                local URL = DocStringExtensions.url(method)
                isempty(URL) || println(buf, "defined at [`$path:$line`]($URL).")
            end
            println(buf)
        end
        println(buf)
    end
    return nothing
end

"""
    FormulationSet(...)

Constructs a specific formulation object based on the provided keyword arguments.
The system will infer the correct formulation type.
"""
FormulationSet(engine::Symbol; kwargs...) = FormulationSet(Val(engine); kwargs...)

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

_coerce_RealT(args...) =
    any(x -> x isa Measurement, args) ? Measurement{BASE_FLOAT} : BASE_FLOAT

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