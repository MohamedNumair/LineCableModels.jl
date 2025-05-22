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
function setup_paths(cable_system::LineCableSystem, formulation::FEMFormulation, opts::FEMOptions)
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

    # Define key file paths
    mesh_file = joinpath(case_dir, "$(case_id).msh")
    geo_file = joinpath(case_dir, "$(case_id).geo_unrolled")
    # data_file = joinpath(case_dir, "$(case_id)_data.geo")

    impedance_res = lowercase(formulation.analysis_type[1].resolution_name)
    impedance_file = joinpath(case_dir, "$(case_id)_$(impedance_res).pro")
    impedances_dir = joinpath(results_dir, impedance_res)

    admittance_res = lowercase(formulation.analysis_type[2].resolution_name)
    admittance_file = joinpath(case_dir, "$(case_id)_$(admittance_res).pro")
    admittance_dir = joinpath(results_dir, admittance_res)

    # # Create results directory if needed
    # if opts.run_solver && !isdir(results_dir)
    #     mkpath(results_dir)
    #     @info "Created main results directory: $(results_dir)"

    #     mkpath(impedances_dir)
    #     @info "Created formulation results directory: $(impedances_dir)"

    #     mkpath(admittance_dir)
    #     @info "Created formulation results directory: $(admittance_dir)"
    # end

    # Return compiled dictionary of paths
    paths = Dict{Symbol,String}(
        :base_dir => opts.base_path,
        :case_dir => case_dir,
        :results_dir => results_dir,
        :mesh_file => mesh_file,
        :geo_file => geo_file,
        :impedance_file => impedance_file,
        :admittance_file => admittance_file,
        # :data_file => data_file
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

function read_results_file(fem_formulation::AbstractImpedanceFormulation, frequency::Float64, workspace::FEMWorkspace; files=["R.dat", "L.dat"])

    results_path = joinpath(workspace.paths[:results_dir], lowercase(fem_formulation.resolution_name))

    # Helper function to read values from either R.dat or L.dat
    function read_values(filepath::String)
        isfile(filepath) || Base.error("File not found: $filepath")
        line = readline(filepath)
        # Parse all numbers and take every other value starting from index 2
        values = parse.(Float64, split(line))[2:2:end]
        n = length(values)
        # Create and fill matrix
        matrix = zeros(Float64, n, n)
        for i in 1:n
            matrix[i, i] = values[i]
        end
        return matrix
    end

    # Read both files
    R = read_values(joinpath(results_path, files[1]))
    L = read_values(joinpath(results_path, files[2]))

    # Calculate complex impedance matrix
    Z = R + im * 2π * frequency * L

    return Z
end

function read_results_file(fem_formulation::AbstractAdmittanceFormulation, frequency::Float64, workspace::FEMWorkspace; files=["C.dat"])
    results_path = joinpath(workspace.paths[:results_dir], lowercase(fem_formulation.resolution_name))

    # Helper function to read values from either R.dat or L.dat
    function read_values(filepath::String)
        isfile(filepath) || Base.error("File not found: $filepath")
        line = readline(filepath)
        # Parse all numbers and take every other value starting from index 2
        values = parse.(Float64, split(line))[2:2:end]
        n = length(values)

        # Get system size from the workspace
        n_phases = workspace.problem_def.system.num_phases

        # Create output matrix
        matrix = zeros(Float64, n_phases, n_phases)

        if n == 1
            # If only one value, replicate it on the main diagonal
            fill!(view(matrix, diagind(matrix)), values[1])
        else
            # Otherwise fill diagonal with provided values
            for i in 1:n
                matrix[i, i] = values[i]
            end
        end
        return matrix
    end

    # Read capacitance file
    C = read_values(joinpath(results_path, files[1]))

    # Calculate complex admittance matrix
    Y = im * 2π * frequency * C

    return Y
end