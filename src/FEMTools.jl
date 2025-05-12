"""
    LineCableModels.FEMTools

The [`FEMTools`](@ref) module provides functionality for generating geometric meshes for cable cross-sections, assigning physical properties, and preparing the system for electromagnetic simulation within the [`LineCableModels.jl`](index.md) package.

# Overview

- Defines core types [`FEMFormulation`](@ref), [`FEMOptions`](@ref), and [`FEMWorkspace`](@ref) for managing simulation parameters and state.
- Implements a physical tag encoding system (CCOGYYYYY scheme for cable components, EPFXXXXX for domain regions).
- Provides primitive drawing functions for geometric elements.
- Creates a two-phase workflow: creation → fragmentation → identification.
- Maintains all state in a structured [`FEMWorkspace`](@ref) object.

# Dependencies

$(IMPORTS)

# Exports

$(EXPORTS)
"""
module FEMTools

# Load common dependencies
include("CommonDeps.jl")
using ..Utils
using ..Materials
using ..EarthProps
using ..DataModel

# Module-specific dependencies
using Gmsh
using Printf
using Dates
using Measurements
using Colors
using Logging
using Logging: AbstractLogger, LogLevel, Info, global_logger
using LoggingExtras: TeeLogger, FileLogger

# GetDP.jl
using GetDP
using GetDP: Problem

# Export public API
export LineParametersProblem
export FEMFormulation, FEMOptions
export compute!
export FEMElectrodynamics, FEMDarwin

# Main types and implementations
include("ProblemDefs.jl")

"""
$(TYPEDEF)

Abstract type for entity data to be stored within the FEMWorkspace.
"""
abstract type AbstractEntityData end

"""
$(TYPEDEF)

Core entity data structure containing common properties for all entity types.

$(TYPEDFIELDS)
"""
struct CoreEntityData
    "Encoded physical tag \\[dimensionless\\]."
    physical_group_tag::Int
    "Name of the elementary surface."
    elementary_name::String
    "Target mesh size \\[m\\]."
    mesh_size::Float64
end

"""
$(TYPEDEF)

Entity data structure for cable parts.

$(TYPEDFIELDS)
"""
struct CablePartEntity{T<:AbstractCablePart} <: AbstractEntityData
    "Core entity data."
    core::CoreEntityData
    "Reference to original cable part."
    cable_part::T
end

"""
$(TYPEDEF)

Entity data structure for domain surfaces external to cable parts.

$(TYPEDFIELDS)
"""
struct SurfaceEntity <: AbstractEntityData
    "Core entity data."
    core::CoreEntityData
    "Material properties of the domain."
    material::Material
end

"""
$(TYPEDEF)

Entity data structure for domain curves (boundaries and layer interfaces).

$(TYPEDFIELDS)
"""
struct CurveEntity <: AbstractEntityData
    "Core entity data."
    core::CoreEntityData
    "Material properties of the domain."
    material::Material
end

"""
$(TYPEDEF)

Entity container that associates Gmsh entity with metadata.

$(TYPEDFIELDS)
"""
struct FEMEntity{T<:AbstractEntityData}
    "Gmsh entity tag (will be defined after boolean fragmentation)."
    tag::Int32
    "Entity-specific data."
    data::T
end

"""
$(TYPEDSIGNATURES)

Constructs a [`FEMEntity`](@ref) instance with automatic type conversion.

# Arguments

- `tag`: Gmsh entity tag (will be converted to Int32)
- `data`: Entity-specific data conforming to [`AbstractEntityData`](@ref)

# Returns

- A [`FEMEntity`](@ref) instance with the specified tag and data.

# Notes

This constructor automatically converts any integer tag to Int32 for compatibility with the Gmsh C API, which uses 32-bit integers for entity tags.

# Examples

```julia
# Create domain entity with tag and data
core_data = CoreEntityData([0.0, 0.0, 0.0])
domain_data = SurfaceEntity(core_data, material)
entity = $(FUNCTIONNAME)(1, domain_data)
```
"""
function FEMEntity(tag::Integer, data::T) where {T<:AbstractEntityData}
    return FEMEntity{T}(Int32(tag), data)
end

mutable struct FEMDarwin <: AbstractImpedanceFormulation
    problem::GetDP.Problem
    resolution_name::String

    function FEMDarwin()
        return new(GetDP.Problem(), "Darwin")
    end

end

mutable struct FEMElectrodynamics <: AbstractAdmittanceFormulation
    problem::GetDP.Problem
    resolution_name::String
    # sources::Int64  # New field for linecablesystem
    function FEMElectrodynamics()
        # electro = new(problem, "Electrodynamics", num_sources)
        # create_electrodynamic_problem(electro.problem, num_sources, electro.resolution_name)

        return new(GetDP.Problem(), "Electrodynamics")
    end
end


function _run_solver(workspace)
    """
            Verbosity Levels in GetDP
            Level	Output Description
            0	     Silent (no output)
            1	     Errors only
            2	     Errors + warnings
            3	     Errors + warnings + basic info
            4	     Detailed debugging
            5	     Full internal tracing
    """
    mesh_file = workspace.paths[:mesh_file]
    pro_file_path = workspace.paths[:pro_file]
    all_problemns = build_getdp_problem(workspace)

    write_multiple_problems(all_problemns, pro_file_path)

    # Set up paths
    getdp_exe_path = workspace.opts.getdp_executable

    # Write all problems to files
    @info "Running opts..."
    for formulation in workspace.formulation.analysis_type
        # Run solver for each formulation
        solve_cmd = "$getdp_exe_path $pro_file_path -msh $mesh_file -solve $(formulation.resolution_name) -v$(workspace.opts.verbosity == 0 ? 2 : 3)"

        @info "Solving... (Resolution = $(formulation.resolution_name))"

        try
            gmsh.onelab.run("GetDP", solve_cmd)
            @info "Solve successful!"
            # gmsh.fltk.run()
        catch e
            println("Solve failed: ", e)
        end
    end
end

"""
$(TYPEDEF)

Abstract problem definition type for FEM simulation parameters.
This contains the physics-related parameters of the simulation.

$(TYPEDFIELDS)
"""
struct FEMFormulation <: AbstractFormulation
    "Radius of the physical domain \\[m\\]."
    domain_radius::Float64
    "Outermost radius to apply the infinity transform \\[m\\]."
    domain_radius_inf::Float64
    "Elements per characteristic length for conductors \\[dimensionless\\]."
    elements_per_length_conductor::Int
    "Elements per characteristic length for insulators \\[dimensionless\\]."
    elements_per_length_insulator::Int
    "Elements per characteristic length for semiconductors \\[dimensionless\\]."
    elements_per_length_semicon::Int
    "Elements per characteristic length for interfaces \\[dimensionless\\]."
    elements_per_length_interfaces::Int
    "Points per circumference length (2π radians) \\[dimensionless\\]."
    points_per_circumference::Int
    "Analysis types to perform \\[dimensionless\\]."
    analysis_type::Tuple{AbstractImpedanceFormulation,AbstractAdmittanceFormulation}

    "Minimum mesh size \\[m\\]."
    mesh_size_min::Float64
    "Maximum mesh size \\[m\\]."
    mesh_size_max::Float64
    "Default mesh size \\[m\\]."
    mesh_size_default::Float64
    "Mesh algorithm to use \\[dimensionless\\]."
    mesh_algorithm::Int

    "Materials database."
    materials_db::MaterialsLibrary

    """
    $(TYPEDSIGNATURES)

    Constructs a [`FEMFormulation`](@ref) instance with default values.

    # Arguments

    - `domain_radius`: Domain radius for the simulation \\[m\\]. Default: 5.0.
    - `elements_per_length_conductor`: Elements per scale length for conductors \\[dimensionless\\]. Default: 3.0.
    - `elements_per_length_insulator`: Elements per scale length for insulators \\[dimensionless\\]. Default: 2.0.
    - `elements_per_length_semicon`: Elements per scale length for semiconductors \\[dimensionless\\]. Default: 4.0.
    - `elements_per_length_interfaces`: Elements per scale length for interfaces \\[dimensionless\\]. Default: 0.1.
    - `analysis_type`: 
    - `mesh_size_min`: Minimum mesh size \\[m\\]. Default: 1e-4.
    - `mesh_size_max`: Maximum mesh size \\[m\\]. Default: 1.0.
    - `mesh_size_default`: Default mesh size \\[m\\]. Default: `domain_radius/10`.
    - `mesh_algorithm`: Mesh algorithm to use \\[dimensionless\\]. Default: 6.
    - `materials_db`: Materials database. Default: MaterialsLibrary().

    # Returns

    - A [`FEMFormulation`](@ref) instance with the specified parameters.

    # Examples

    ```julia
    # Create a problem definition with default parameters
    formulation = $(FUNCTIONNAME)()

    # Create a problem definition with custom parameters
    formulation = $(FUNCTIONNAME)(
        domain_radius=10.0,
        elements_per_length_conductor=5.0,
        mesh_algorithm=2
    )
    ```
    """
    function FEMFormulation(;
        domain_radius::Float64=5.0,
        domain_radius_inf::Float64=6.25,
        elements_per_length_conductor::Int=3,
        elements_per_length_insulator::Int=2,
        elements_per_length_semicon::Int=4,
        elements_per_length_interfaces::Int=3,
        points_per_circumference::Int=16,
        analysis_type::Tuple{AbstractImpedanceFormulation,AbstractAdmittanceFormulation}=(FEMDarwin(), FEMElectrodynamics()),
        mesh_size_min::Float64=1e-4,
        mesh_size_max::Float64=1.0,
        mesh_size_default::Float64=domain_radius / 10,
        mesh_algorithm::Int=5,
        materials_db::MaterialsLibrary=MaterialsLibrary()
    )
        return new(
            domain_radius, domain_radius_inf,
            elements_per_length_conductor, elements_per_length_insulator,
            elements_per_length_semicon, elements_per_length_interfaces,
            points_per_circumference, analysis_type,
            mesh_size_min, mesh_size_max, mesh_size_default,
            mesh_algorithm, materials_db
        )
    end
end

"""
$(TYPEDEF)

Solver configuration for FEM simulations.
This contains the execution-related parameters.

$(TYPEDFIELDS)
"""
struct FEMOptions <: FormulationOptions
    "Flag to force remeshing \\[dimensionless\\]."
    force_remesh::Bool
    "Flag to run the solver \\[dimensionless\\]."
    run_solver::Bool
    "Flag to overwrite existing results \\[dimensionless\\]."
    overwrite_results::Bool

    "Flag to run postprocessing \\[dimensionless\\]."
    run_postprocessing::Bool
    "Flag to preview the mesh \\[dimensionless\\]."
    preview_mesh::Bool
    "Flag to preview the geometry \\[dimensionless\\]."
    preview_geo::Bool
    "Flag to plot results \\[dimensionless\\]."
    plot_results::Bool

    "Base path for output files."
    base_path::String
    "Path to Gmsh executable."
    gmsh_executable::String
    "Path to GetDP executable."
    getdp_executable::String
    "Verbosity level \\[dimensionless\\]."
    verbosity::Int
    "Path to the log file."
    logfile::Union{String,Nothing}

    """
    $(TYPEDSIGNATURES)

    Constructs a [`FEMOptions`](@ref) instance with default values.

    # Arguments

    - `force_remesh`: Flag to force remeshing \\[dimensionless\\]. Default: false.
    - `run_solver`: Flag to run the solver \\[dimensionless\\]. Default: true.
    - `overwrite_results`: Flag to overwrite existing results \\[dimensionless\\]. Default: false.
    - `run_postprocessing`: Flag to run postprocessing \\[dimensionless\\]. Default: true.
    - `preview_mesh`: Flag to preview the mesh \\[dimensionless\\]. Default: false.
    - `preview_geo`: Flag to preview the geometry \\[dimensionless\\]. Default: false.
    - `plot_results`: Flag to plot results \\[dimensionless\\]. Default: true.
    - `base_path`: Base path for output files. Default: "./fem_output".
    - `gmsh_executable`: Path to Gmsh executable. Default: from environment.
    - `getdp_executable`: Path to GetDP executable. Default: from environment.
    - `verbosity`: Verbosity level \\[dimensionless\\]. Default: 1.

    # Returns

    - A [`FEMOptions`](@ref) instance with the specified parameters.

    # Examples

    ```julia
    # Create a solver with default parameters
    solver = $(FUNCTIONNAME)()

    # Create a solver with custom parameters
    solver = $(FUNCTIONNAME)(
        force_remesh=true,
        preview_mesh=true,
        verbosity=2
    )
    ```
    """
    function FEMOptions(;
        force_remesh::Bool=false,
        run_solver::Bool=true,
        overwrite_results::Bool=false,
        run_postprocessing::Bool=true,
        preview_mesh::Bool=false,
        preview_geo::Bool=false,
        plot_results::Bool=true,
        base_path::String="./fem_output",
        gmsh_executable::Union{String,Nothing}=nothing,
        getdp_executable::Union{String,Nothing}=nothing,
        verbosity::Int=0,
        logfile::Union{String,Nothing}=nothing
    )
        # Get executables from environment if not provided
        if isnothing(gmsh_executable)
            gmsh_executable = get(ENV, "GMSH_EXECUTABLE", "")
        end

        if isnothing(getdp_executable)
            getdp_executable = get(ENV, "GETDP_EXECUTABLE", "")
            if isempty(getdp_executable)
                error("GetDP executable path is required but not provided and not found in ENV[\"GETDP_EXECUTABLE\"]")
            end
        end

        # Validate GetDP executable
        if !isfile(getdp_executable)
            error("GetDP executable not found at path: $getdp_executable")
        end

        setup_fem_logging(verbosity, logfile)

        return new(
            force_remesh, run_solver, overwrite_results,
            run_postprocessing, preview_mesh, preview_geo, plot_results,
            base_path, gmsh_executable, getdp_executable, verbosity, logfile
        )
    end
end

"""
$(TYPEDEF)

FEMWorkspace - The central workspace for FEM simulations.
This is the main container that maintains all state during the simulation process.

$(TYPEDFIELDS)
"""
mutable struct FEMWorkspace
    "Line parameters problem definition."
    problem_def::LineParametersProblem
    "Formulation parameters."
    formulation::FEMFormulation
    "Computation options."
    opts::FEMOptions

    "Path information."
    paths::Dict{Symbol,String}

    "Conductor surfaces within cables."
    conductors::Vector{FEMEntity{<:AbstractEntityData}}
    "Insulator surfaces within cables."
    insulators::Vector{FEMEntity{<:AbstractEntityData}}
    "Domain-space physical surfaces (air and earth layers)."
    space_regions::Vector{FEMEntity{<:AbstractEntityData}}
    "Domain boundary curves."
    boundaries::Vector{FEMEntity{<:AbstractEntityData}}
    "Container for all pre-fragmentation entities."
    unassigned_entities::Dict{Vector{Float64},AbstractEntityData}
    "Container for all material names used in the model."
    material_registry::Dict{String,Int}
    "Container for unique physical groups."
    physical_groups::Dict{Int,Material}

    """
    $(TYPEDSIGNATURES)

    Constructs a [`FEMWorkspace`](@ref) instance.

    # Arguments

    - `cable_system`: Cable system being simulated.
    - `formulation`: Problem definition parameters.
    - `solver`: Solver parameters.
    - `frequency`: Simulation frequency \\[Hz\\]. Default: 50.0.

    # Returns

    - A [`FEMWorkspace`](@ref) instance with the specified parameters.

    # Examples

    ```julia
    # Create a workspace
    workspace = $(FUNCTIONNAME)(cable_system, formulation, solver)
    ```
    """
    function FEMWorkspace(problem::LineParametersProblem, formulation::FEMFormulation, opts::FEMOptions)

        # Initialize empty workspace
        workspace = new(
            problem, formulation, opts,
            Dict{Symbol,String}(), # Path information.
            Vector{FEMEntity{<:AbstractEntityData}}(), #conductors
            Vector{FEMEntity{<:AbstractEntityData}}(), #insulators
            Vector{FEMEntity{<:AbstractEntityData}}(), #space_regions
            Vector{FEMEntity{<:AbstractEntityData}}(), #boundaries
            Dict{Vector{Float64},AbstractEntityData}(), #unassigned_entities
            Dict{String,Int}(),  # Initialize empty material registry
            Dict{Int,Material}(), # Maps physical group tags to materials
        )

        # Set up paths
        workspace.paths = setup_paths(problem.system, opts)
        cleanup_files(workspace.paths, opts)

        return workspace
    end
end

function set_problem!(problem::GetDP.Problem, workspace::FEMWorkspace, ::Val{:baseparams})::Vector{<:AbstractFEMFormulation}
    darwin_prob = deepcopy(problem)
    electr_prob = deepcopy(problem)

    # Darwin
    darwin_obj = FEMDarwin(darwin_prob)

    # Electrodynamics
    num_sources = length(workspace.problem_def.system.cables)
    electro_obj = FEMElectrodynamics(electr_prob, num_sources)

    make_file!(darwin_obj.problem)
    make_file!(electro_obj.problem)
    return [darwin_obj, electro_obj]
end

"""
$(TYPEDSIGNATURES)

Main function to run the FEM simulation workflow for a cable system.

# Arguments

- `cable_system`: Cable system to simulate.
- `formulation`: Problem definition parameters.
- `solver`: Solver parameters.
- `frequency`: Simulation frequency \\[Hz\\]. Default: 50.0.

# Returns

- A [`FEMWorkspace`](@ref) instance with the simulation results.

# Examples

```julia
# Run a FEM simulation
workspace = $(FUNCTIONNAME)(cable_system, formulation, solver)
```
"""
function compute!(problem::LineParametersProblem,
    formulation::FEMFormulation,
    opts::FEMOptions; workspace::Union{FEMWorkspace,Nothing}=nothing)

    # Create and initialize workspace
    if isnothing(workspace) || !isa(workspace, FEMWorkspace)
        workspace = FEMWorkspace(problem, formulation, opts)
        is_empty_workspace = true
    end

    # Log start
    @info "Starting FEM simulation for cable system: $(problem.system.system_id)"

    # Check if mesh file exists
    mesh_exists = isfile(workspace.paths[:mesh_file])

    # Determine if we need to run meshing
    run_mesh = opts.force_remesh || !mesh_exists || is_empty_workspace

    # Determine if we need to run solver
    solver_output_exists = false
    if opts.run_solver && !isempty(workspace.paths[:results_dir])
        # Check for presence of result files
        result_files = readdir(workspace.paths[:results_dir])
        solver_output_exists = !isempty(result_files)
    end
    run_solver = opts.run_solver && (!solver_output_exists || opts.overwrite_results)

    # Determine if we need to run post-processing
    run_postproc = opts.run_postprocessing && run_solver

    try
        # Initialize Gmsh for meshing phase
        if run_mesh
            gmsh.initialize()

            @info "Building mesh..."
            make_mesh!(workspace)

            # Preview mesh if requested
            if opts.preview_mesh
                @info "Launching mesh preview..."
                preview_mesh(workspace)
            end

            @info "Meshing completed."
        else
            @info "Skipping meshing phase (mesh already exists)."
        end

        # Run solver if requested and/or needed
        if run_solver
            @info "Running GetDP solver..."
            for (i, frequency) in enumerate(problem.frequencies)
                @info "Solving for frequency $i: $frequency Hz"
                for fem_formulation in formulation.analysis_type
                    @debug "Processing formulation: $(fem_formulation.resolution_name)"
                    make_fem_problem!(fem_formulation, frequency, workspace)
                    solve_cmd = "$(opts.getdp_executable) $(fem_formulation.problem.filename) -msh $(workspace.paths[:mesh_file]) -solve $(fem_formulation.resolution_name) -v$(opts.verbosity == 0 ? 2 : 3)"

                    @info "Solving... (Resolution = $(fem_formulation.resolution_name))"

                    try
                        gmsh.onelab.run("GetDP", solve_cmd)
                        @info "Solve successful!"
                        # gmsh.fltk.run()
                    catch e
                        println("Solve failed: ", e)
                    end

                end
            end
            @info "All solver runs completed."
        else
            @info "Skipping solver run."
        end

        # Run post-processing if needed
        if run_postproc
            @info "Running post-processing..."
            # To be implemented
            # _run_postprocessing(workspace)
            @info "Post-processing completed."
        else
            @info "Skipping post-processing."
        end

    catch e
        @warn "Error in FEM simulation: $e"

        # Print stack trace for debugging
        if opts.verbosity >= 2
            for (exc, bt) in Base.catch_stack()
                showerror(stderr, exc, bt)
                println(stderr)
            end
        end

        # Re-throw the error after cleanup
        rethrow(e)
    finally
        # Finalize Gmsh
        if @isdefined(gmsh) && isdefined(gmsh, :finalize)
            try
                gmsh.finalize()
                @info "Gmsh finalized."
            catch fin_err
                @warn "Error during Gmsh finalization: $fin_err"
            end
        end
    end

    return workspace
end

# Include auxiliary files
include("FEMTools/encoding.jl")        # Tag encoding schemes
include("FEMTools/drawing.jl")         # Primitive drawing functions
include("FEMTools/identification.jl")  # Entity identification
include("FEMTools/meshing.jl")         # Mesh generation
include("FEMTools/materials.jl")       # Material handling
include("FEMTools/utilities.jl")       # Various utilities
include("FEMTools/visualization.jl")   # Visualization functions
include("FEMTools/space.jl")           # Domain creation functions
include("FEMTools/cable.jl")           # Cable geometry creation functions
include("FEMTools/solver.jl")          # Solver functions

end # module FEMTools
