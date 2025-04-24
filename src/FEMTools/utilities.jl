"""
Utility functions for the FEMTools.jl module.
These functions provide various utilities for file management, logging, etc.
"""

# Define log levels
const LOG_LEVELS = Dict(
    0 => "ERROR",
    1 => "INFO",
    2 => "DEBUG"
)

"""
$(TYPEDSIGNATURES)

Log a message according to the verbosity level.

# Arguments

- `workspace`: The [`FEMWorkspace`](@ref) containing the solver configuration.
- `level`: Message level (0=error, 1=info, 2=debug) \\[dimensionless\\].
- `message`: The message to log.

# Returns

- Nothing. Prints the message to the console.

# Examples

```julia
$(FUNCTIONNAME)(workspace, 1, "Starting mesh generation")
```
"""
function _log(workspace::FEMWorkspace, level::Int, message::String)
    if level <= workspace.solver.verbosity
        timestamp = Dates.format(now(), "yyyy-mm-dd HH:MM:SS")
        prefix = LOG_LEVELS[level]
        println("[$timestamp] $prefix: $message")
    end
end

"""
$(TYPEDSIGNATURES)

Log a message according to the verbosity level.

# Arguments

- `solver`: The [`FEMSolver`](@ref) containing the verbosity setting.
- `level`: Message level (0=error, 1=info, 2=debug) \\[dimensionless\\].
- `message`: The message to log.

# Returns

- Nothing. Prints the message to the console.

# Examples

```julia
$(FUNCTIONNAME)(solver, 1, "Starting mesh generation")
```
"""
function _log(solver::FEMSolver, level::Int, message::String)
    if level <= solver.verbosity
        timestamp = Dates.format(now(), "yyyy-mm-dd HH:MM:SS")
        prefix = LOG_LEVELS[level]
        println("[$timestamp] $prefix: $message")
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
function _setup_paths(solver::FEMSolver, cable_system::LineCableSystem)
    # Create base output directory if it doesn't exist
    if !isdir(solver.base_path)
        mkpath(solver.base_path)
        _log(solver, 1, "Created base output directory: $(solver.base_path)")
    end

    # Set up case-specific paths
    case_id = cable_system.case_id
    case_dir = joinpath(solver.base_path, case_id)

    # Create case directory if needed
    if !isdir(case_dir) && (solver.force_remesh || solver.run_solver)
        mkpath(case_dir)
        _log(solver, 1, "Created case directory: $(case_dir)")
    end

    # Create results directory path
    results_dir = joinpath(case_dir, "results")

    # Create results directory if needed
    if solver.run_solver && !isdir(results_dir)
        mkpath(results_dir)
        _log(solver, 1, "Created results directory: $(results_dir)")
    end

    # Define key file paths
    mesh_file = joinpath(case_dir, "$(case_id).msh")
    geo_file = joinpath(case_dir, "$(case_id).geo_unrolled")
    onelab_file = joinpath(case_dir, "$(case_id)_onelab.json")
    pro_file = joinpath(case_dir, "$(case_id).pro")
    data_file = joinpath(case_dir, "$(case_id)_data.geo")

    # Return compiled dictionary of paths
    paths = Dict{Symbol,String}(
        :base_dir => solver.base_path,
        :case_dir => case_dir,
        :results_dir => results_dir,
        :mesh_file => mesh_file,
        :geo_file => geo_file,
        :onelab_file => onelab_file,
        :pro_file => pro_file,
        :data_file => data_file
    )

    _log(solver, 2, "Paths configured: $(join(["$(k): $(v)" for (k,v) in paths], ", "))")

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
function _cleanup_files(paths::Dict{Symbol,String}, solver::FEMSolver)
    if solver.force_remesh
        # If force_remesh is true, delete mesh-related files
        if isfile(paths[:mesh_file])
            rm(paths[:mesh_file], force=true)
            _log(solver, 1, "Removed existing mesh file: $(paths[:mesh_file])")
        end

        if isfile(paths[:geo_file])
            rm(paths[:geo_file], force=true)
            _log(solver, 1, "Removed existing geometry file: $(paths[:geo_file])")
        end

        if isfile(paths[:onelab_file])
            rm(paths[:onelab_file], force=true)
            _log(solver, 1, "Removed existing ONELAB file: $(paths[:onelab_file])")
        end
    end

    if solver.overwrite_results && solver.run_solver
        # If overwriting results and running solver, clear the results directory
        if isdir(paths[:results_dir])
            for file in readdir(paths[:results_dir])
                filepath = joinpath(paths[:results_dir], file)
                if isfile(filepath)
                    rm(filepath, force=true)
                end
            end
            _log(solver, 1, "Cleared existing results in: $(paths[:results_dir])")
        end
    end
end

"""
$(TYPEDSIGNATURES)

Save content to a file, creating parent directories if needed.

# Arguments

- `filepath`: Path to the file to save.
- `content`: Content to save to the file.

# Returns

- Nothing. Saves the content to the file.

# Examples

```julia
$(FUNCTIONNAME)("path/to/file.txt", "Hello, world!")
```
"""
function _save_file(filepath::String, content::String)
    # Ensure parent directory exists
    parent_dir = dirname(filepath)
    if !isdir(parent_dir)
        mkpath(parent_dir)
    end

    # Write content to file
    open(filepath, "w") do io
        write(io, content)
    end
end

"""
$(TYPEDSIGNATURES)

Check if a file exists and is newer than a reference file.

# Arguments

- `file_path`: Path to the file to check.
- `reference_path`: Path to the reference file.

# Returns

- `true` if the file exists and is newer than the reference file, `false` otherwise.

# Examples

```julia
if $(FUNCTIONNAME)("output.txt", "input.txt")
    println("Output file is up to date")
end
```
"""
function _file_exists_and_is_newer(file_path::String, reference_path::String)
    if !isfile(file_path) || !isfile(reference_path)
        return false
    end

    file_mtime = mtime(file_path)
    ref_mtime = mtime(reference_path)

    return file_mtime > ref_mtime
end
