# Export public API
export FormulationSet, DataFrame, add!, load!, export_data, save, preview
export f₀, μ₀, ε₀, ρ₀, T₀, TOL, ΔTmax
export setup_logging!

# General constants
"Base power system frequency, f₀ = 50 [Hz]."
const f₀ = 50.0
"Magnetic constant (vacuum permeability), μ₀ = 4π * 1e-7 [H/m]."
const μ₀ = 4π * 1e-7
"Electric constant (vacuum permittivity), ε₀ = 8.8541878128e-12 [F/m]."
const ε₀ = 8.8541878128e-12
"Annealed copper reference resistivity, ρ₀ = 1.724e-08 [Ω·m]."
const ρ₀ = 1.724e-08
"Base temperature for conductor properties, T₀ = 20 [°C]."
const T₀ = 20.0
"Maximum tolerance for temperature variations, ΔTmax = 150 [°C]."
const ΔTmax = 150.0
"Default tolerance for floating-point comparisons, TOL = 1e-6."
const TOL = 1e-6

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
            @warn "Failed to set up file logging to $logfile: $e"
            global_logger(TimestampLogger(console_logger))
        end
    end
end

function __init__()
    # Set a default logging level when the package is loaded at runtime.
    # This ensures it overrides any environment-specific loggers.
    setup_logging!(0)
end