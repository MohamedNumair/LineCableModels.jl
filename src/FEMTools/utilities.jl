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
function setup_paths(cable_system::LineCableSystem, formulation::FEMFormulation)

    opts = formulation.options
    # Create base output directory if it doesn't exist
    if !isdir(opts.base_path)
        mkpath(opts.base_path)
        @info "Created base output directory: $(opts.base_path)"
    end

    # Set up case-specific paths
    case_id = cable_system.system_id
    case_dir = joinpath(opts.base_path, case_id)

    # Create case directory if needed
    if !isdir(case_dir) && (opts.force_remesh || opts.mesh_only)
        mkpath(case_dir)
        @info "Created case directory: $(case_dir)"
    end

    # Create results directory path
    results_dir = joinpath(case_dir, "results")

    # Define key file paths
    mesh_file = joinpath(case_dir, "$(case_id).msh")
    geo_file = joinpath(case_dir, "$(case_id).geo_unrolled")
    # data_file = joinpath(case_dir, "$(case_id)_data.geo")

    impedance_res = lowercase(formulation.analysis_type[1].resolution_name)
    impedance_file = joinpath(case_dir, "$(case_id)_$(impedance_res).pro")

    admittance_res = lowercase(formulation.analysis_type[2].resolution_name)
    admittance_file = joinpath(case_dir, "$(case_id)_$(admittance_res).pro")

    # Return compiled dictionary of paths
    paths = Dict{Symbol,String}(
        :base_dir => opts.base_path,
        :case_dir => case_dir,
        :results_dir => results_dir,
        :mesh_file => mesh_file,
        :geo_file => geo_file,
        :impedance_file => impedance_file,
        :admittance_file => admittance_file,
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
function cleanup_files(paths::Dict{Symbol,String}, opts::NamedTuple)
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

        # Add cleanup for .pro files in case_dir
        for file in readdir(paths[:case_dir])
            if endswith(file, ".pro")
                filepath = joinpath(paths[:case_dir], file)
                rm(filepath, force=true)
                @info "Removed existing problem file: $filepath"
            end
        end

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

function read_results_file(fem_formulation::Union{AbstractImpedanceFormulation,AbstractAdmittanceFormulation}, workspace::FEMWorkspace; file::Union{String,Nothing}=nothing)

    results_path = joinpath(workspace.paths[:results_dir], lowercase(fem_formulation.resolution_name))

    if isnothing(file)
        file = fem_formulation isa AbstractImpedanceFormulation ? "Z.dat" :
               fem_formulation isa AbstractAdmittanceFormulation ? "Y.dat" :
               throw(ArgumentError("Invalid formulation type: $(typeof(fem_formulation))"))
    end

    filepath = joinpath(results_path, file)

    isfile(filepath) || Base.error("File not found: $filepath")

    # Read all lines from file
    lines = readlines(filepath)
    n_rows = sum([length(c.design_data.components) for c in workspace.problem_def.system.cables])

    # Pre-allocate result matrix
    matrix = zeros(ComplexF64, n_rows, n_rows)

    # Process each line (matrix row)
    for (i, line) in enumerate(lines)
        # Parse all numbers, dropping the initial 0
        values = parse.(Float64, split(line))[2:end]

        # Fill matrix row with complex values
        for j in 1:n_rows
            idx = 2j - 1  # Index for real part
            matrix[i, j] = Complex(values[idx], values[idx+1])
        end
    end

    return matrix
end


# Verbosity Levels in GetDP
# Level	Output Description
# 0	     Silent (no output)
# 1	     Errors only
# 2	     Errors + warnings
# 3	     Errors + warnings + basic info
# 4	     Detailed debugging
# 5	     Full internal tracing
function map_verbosity_to_getdp(verbosity::Int)
    if verbosity >= 2       # Debug
        return 4            # GetDP Debug level
    elseif verbosity == 1   # Info
        return 3            # GetDP Info level
    else                    # Warn
        return 1            # GetDP Errors level
    end
end

# Verbosity Levels in Gmsh
# Level  Output Description
# 0      Silent (no output)
# 1      Errors only
# 2      Warnings
# 3      Direct/Important info
# 4      Information
# 5      Status messages
# 99     Debug
function map_verbosity_to_gmsh(verbosity::Int)
    if verbosity >= 2       # Debug
        return 99           # Gmsh Debug level
    elseif verbosity == 1   # Info
        return 4            # Gmsh Information level
    else                    # Warn
        return 1            # Gmsh Errors level
    end
end