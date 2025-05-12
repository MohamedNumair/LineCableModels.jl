"""
Utility functions for the FEMTools.jl module.
These functions provide various utilities for file management, logging, etc.
"""

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

function setup_fem_logging(verbosity::Int, logfile::Union{String,Nothing}=nothing)
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

"""
$(TYPEDSIGNATURES)

Set up directory structure and file paths for a FEM simulation.

# Arguments

- `solver`: The [`FEMSolver`](@ref) containing the base path.
- `cable_system`: The [`LineCableSystem`](@ref) containing the case ID.

# Returns

- A dictionary of paths for the simulation.

# Examples

```julia
paths = $(FUNCTIONNAME)(solver, cable_system)
```
"""
function setup_paths(cable_system::LineCableSystem, opts::FEMOptions)
    # Create base output directory if it doesn't exist
    if !isdir(opts.base_path)
        mkpath(opts.base_path)
        @info "Created base output directory: $(opts.base_path)"
    end

    # Set up case-specific paths
    case_id = cable_system.system_id
    case_dir = joinpath(opts.base_path, case_id)

    # Create case directory if needed
    if !isdir(case_dir) && (opts.force_remesh || opts.run_solver)
        mkpath(case_dir)
        @info "Created case directory: $(case_dir)"
    end

    # Create results directory path
    results_dir = joinpath(case_dir, "results")

    # Create results directory if needed
    if opts.run_solver && !isdir(results_dir)
        mkpath(results_dir)
        @info "Created results directory: $(results_dir)"
    end

    # Define key file paths
    mesh_file = joinpath(case_dir, "$(case_id).msh")
    geo_file = joinpath(case_dir, "$(case_id).geo_unrolled")
    impedance_file = joinpath(case_dir, "$(case_id)_impedance.pro")
    admittance_file = joinpath(case_dir, "$(case_id)_admittance.pro")
    data_file = joinpath(case_dir, "$(case_id)_data.geo")

    # Return compiled dictionary of paths
    paths = Dict{Symbol,String}(
        :base_dir => opts.base_path,
        :case_dir => case_dir,
        :results_dir => results_dir,
        :mesh_file => mesh_file,
        :geo_file => geo_file,
        :impedance_file => impedance_file,
        :admittance_file => admittance_file,
        :data_file => data_file
    )

    @debug "Paths configured: $(join(["$(k): $(v)" for (k,v) in paths], ", "))"

    return paths
end

"""
$(TYPEDSIGNATURES)

Clean up files based on configuration flags.

# Arguments

- `paths`: Dictionary of paths for the simulation.
- `solver`: The [`FEMSolver`](@ref) containing the configuration flags.

# Returns

- Nothing. Deletes files as specified by the configuration.

# Examples

```julia
$(FUNCTIONNAME)(paths, solver)
```
"""
function cleanup_files(paths::Dict{Symbol,String}, opts::FEMOptions)
    if opts.force_remesh
        # If force_remesh is true, delete mesh-related files
        if isfile(paths[:mesh_file])
            rm(paths[:mesh_file], force=true)
            @info "Removed existing mesh file: $(paths[:mesh_file])"
        end

        if isfile(paths[:geo_file])
            rm(paths[:geo_file], force=true)
            @info "Removed existing geometry file: $(paths[:geo_file])"
        end
    end

    if opts.overwrite_results && opts.run_solver
        # If overwriting results and running solver, clear the results directory
        if isdir(paths[:results_dir])
            for file in readdir(paths[:results_dir])
                filepath = joinpath(paths[:results_dir], file)
                if isfile(filepath)
                    rm(filepath, force=true)
                end
            end
            @info "Cleared existing results in: $(paths[:results_dir])"
        end
    end
end

