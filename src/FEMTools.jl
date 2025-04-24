"""
    LineCableModels.FEMTools

The [`FEMTools`](@ref) module provides functionality for generating geometric meshes for cable cross-sections, assigning physical properties, and preparing the system for electromagnetic simulation within the [`LineCableModels.jl`](index.md) package.

# Overview

- Defines core types [`FEMFormulation`](@ref), [`FEMSolver`](@ref), and [`FEMWorkspace`](@ref) for managing simulation parameters and state.
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

# Export public API
export FEMFormulation
export FEMSolver
export run_fem_model, preview_mesh, preview_results
export encode_cable_tag, decode_cable_tag


# Main types and implementations

"""
$(TYPEDEF)

Abstract type for entity data to be stored within the FEMWorkspace.
"""
abstract type AbstractEntityData end

"""
$(TYPEDEF)

Abstract base type for all formulation strategies in the FEM simulation framework.
Formulations define the physics-related parameters of the simulation, including domain 
characteristics, meshing parameters, and analysis types.

Concrete implementations should specify the complete set of physics parameters 
needed to define a mathematical model for a simulation.
"""
abstract type AbstractFormulation end

"""
$(TYPEDEF)

Abstract base type for solver methods in the FEM simulation framework.
Solver methods define execution-related parameters such as mesh generation options,
solver configuration, and post-processing settings.

Concrete implementations should define how the solution process is controlled,
including file handling, previewing options, and external tool integration.
"""
abstract type AbstractSolverMethod end

"""
$(TYPEDEF)

Abstract base type for workspace containers in the FEM simulation framework.
Workspace containers maintain the complete state of a simulation, including 
intermediate data structures, identification mappings, and results.

Concrete implementations should provide state tracking for all phases of the 
simulation process from geometry creation through results analysis.
"""
abstract type AbstractWorkspace end

"""
$(TYPEDEF)

Core entity data structure containing common properties for all entity types.

$(TYPEDFIELDS)
"""
struct CoreEntityData
    "Encoded physical tag \\[dimensionless\\]."
    physical_group_tag::Int
    "Human-readable name for the entity."
    elementary_name::String
    "Target mesh size \\[m\\]."
    mesh_size::Float64
    # "Position for identification (3D) \\[m\\]."
    # marker::Vector{Float64}
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

Entity data structure for domain boundaries and regions.

$(TYPEDFIELDS)
"""
struct SpaceEntity <: AbstractEntityData
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
domain_data = SpaceEntity(core_data, material)
entity = $(FUNCTIONNAME)(1, domain_data)
```
"""
function FEMEntity(tag::Integer, data::T) where {T<:AbstractEntityData}
    return FEMEntity{T}(Int32(tag), data)
end

"""
$(TYPEDEF)

Abstract formulation type for FEM simulation parameters.
This contains the physics-related parameters of the simulation.

$(TYPEDFIELDS)
"""
struct FEMFormulation <: AbstractFormulation
    "Domain radius for the simulation \\[m\\]."
    domain_radius::Float64
    "Flag to correct for twisting effects \\[dimensionless\\]."
    correct_twisting::Bool
    "Elements per scale length for conductors \\[dimensionless\\]."
    elements_per_scale_length_conductor::Float64
    "Elements per scale length for insulators \\[dimensionless\\]."
    elements_per_scale_length_insulator::Float64
    "Elements per scale length for semiconductors \\[dimensionless\\]."
    elements_per_scale_length_semicon::Float64
    "Elements per scale length for interfaces \\[dimensionless\\]."
    elements_per_scale_length_interfaces::Float64
    "Analysis types to perform \\[dimensionless\\]."
    analysis_type::Vector{Int}
    "Materials database."
    materials_db::MaterialsLibrary

    "Minimum mesh size \\[m\\]."
    mesh_size_min::Float64
    "Maximum mesh size \\[m\\]."
    mesh_size_max::Float64
    "Default mesh size \\[m\\]."
    mesh_size_default::Float64
    "Mesh algorithm to use \\[dimensionless\\]."
    mesh_algorithm::Int

    """
    $(TYPEDSIGNATURES)

    Constructs a [`FEMFormulation`](@ref) instance with default values.

    # Arguments

    - `domain_radius`: Domain radius for the simulation \\[m\\]. Default: 5.0.
    - `correct_twisting`: Flag to correct for twisting effects \\[dimensionless\\]. Default: true.
    - `elements_per_scale_length_conductor`: Elements per scale length for conductors \\[dimensionless\\]. Default: 3.0.
    - `elements_per_scale_length_insulator`: Elements per scale length for insulators \\[dimensionless\\]. Default: 2.0.
    - `elements_per_scale_length_semicon`: Elements per scale length for semiconductors \\[dimensionless\\]. Default: 4.0.
    - `elements_per_scale_length_interfaces`: Elements per scale length for interfaces \\[dimensionless\\]. Default: 0.1.
    - `analysis_type`: Analysis types to perform \\[dimensionless\\]. Default: [0, 1].
    - `mesh_size_min`: Minimum mesh size \\[m\\]. Default: 1e-4.
    - `mesh_size_max`: Maximum mesh size \\[m\\]. Default: 1.0.
    - `mesh_size_default`: Default mesh size \\[m\\]. Default: 0.1.
    - `mesh_algorithm`: Mesh algorithm to use \\[dimensionless\\]. Default: 6.
    - `materials_db`: Materials database. Default: MaterialsLibrary().

    # Returns

    - A [`FEMFormulation`](@ref) instance with the specified parameters.

    # Examples

    ```julia
    # Create a formulation with default parameters
    formulation = $(FUNCTIONNAME)()

    # Create a formulation with custom parameters
    formulation = $(FUNCTIONNAME)(
        domain_radius=10.0,
        elements_per_scale_length_conductor=5.0,
        mesh_algorithm=2
    )
    ```
    """
    function FEMFormulation(;
        domain_radius::Float64=5.0,
        correct_twisting::Bool=true,
        elements_per_scale_length_conductor::Float64=3.0,
        elements_per_scale_length_insulator::Float64=2.0,
        elements_per_scale_length_semicon::Float64=4.0,
        elements_per_scale_length_interfaces::Float64=0.1,
        analysis_type::Vector{Int}=[0, 1],
        mesh_size_min::Float64=1e-4,
        mesh_size_max::Float64=1.0,
        mesh_size_default::Float64=0.1,
        mesh_algorithm::Int=6,
        materials_db::MaterialsLibrary=MaterialsLibrary()
    )
        return new(
            domain_radius, correct_twisting,
            elements_per_scale_length_conductor, elements_per_scale_length_insulator,
            elements_per_scale_length_semicon, elements_per_scale_length_interfaces,
            analysis_type, materials_db,
            mesh_size_min, mesh_size_max, mesh_size_default, mesh_algorithm
        )
    end
end

"""
$(TYPEDEF)

Solver configuration for FEM simulations.
This contains the execution-related parameters.

$(TYPEDFIELDS)
"""
struct FEMSolver <: AbstractSolverMethod
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

    """
    $(TYPEDSIGNATURES)

    Constructs a [`FEMSolver`](@ref) instance with default values.

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

    - A [`FEMSolver`](@ref) instance with the specified parameters.

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
    function FEMSolver(;
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
        verbosity::Int=1
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

        return new(
            force_remesh, run_solver, overwrite_results,
            run_postprocessing, preview_mesh, preview_geo, plot_results,
            base_path, gmsh_executable, getdp_executable, verbosity
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
    "Cable system being simulated."
    cable_system::LineCableSystem
    "Formulation parameters."
    formulation::FEMFormulation
    "Solver parameters."
    solver::FEMSolver
    "Simulation frequency \\[Hz\\]."
    frequency::Float64

    "Path information."
    paths::Dict{Symbol,String}

    "Conductor surfaces within cables."
    conductors::Vector{FEMEntity{<:AbstractEntityData}}
    "Insulator surfaces within cables."
    insulators::Vector{FEMEntity{<:AbstractEntityData}}
    "Domain-space physical surfaces (air and earth layers)."
    space_regions::Vector{FEMEntity{<:AbstractEntityData}}
    "Layer interface curves/lines."
    interfaces::Vector{FEMEntity{<:AbstractEntityData}}
    "Domain boundary surfaces."
    boundaries::Vector{FEMEntity{<:AbstractEntityData}}
    "Container for all pre-fragmentation entities."
    # unassigned_entities::Vector{AbstractEntityData}
    unassigned_entities::Dict{Vector{Float64},AbstractEntityData}

    # "Mapping from physical tag to material properties."
    # material_map::Dict{Int,Material}
    # "Mapping from physical tag to mesh size."
    # mesh_size_map::Dict{Int,Float64}
    # "Mapping from marker position to physical tag."
    # marker_map::Dict{Vector{Float64},Int}
    # "Mapping from marker position to physical name."
    # name_map::Dict{Vector{Float64},String}

    # "Mapping from fragmented tag to original tag."
    # identified_entities::Dict{Int,Tuple{Int,String}}

    "ONELAB parameters."
    onelab_params::Dict{String,Any}

    "Results storage."
    results::Dict{String,Any}

    """
    $(TYPEDSIGNATURES)

    Constructs a [`FEMWorkspace`](@ref) instance.

    # Arguments

    - `cable_system`: Cable system being simulated.
    - `formulation`: Problem formulation parameters.
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
    function FEMWorkspace(cable_system::LineCableSystem,
        formulation::FEMFormulation,
        solver::FEMSolver;
        frequency::Float64=50.0)

        # Initialize empty workspace
        workspace = new(
            cable_system, formulation, solver, frequency,
            Dict{Symbol,String}(), # Path information.
            Vector{FEMEntity{<:AbstractEntityData}}(), #conductors
            Vector{FEMEntity{<:AbstractEntityData}}(), #insulators
            Vector{FEMEntity{<:AbstractEntityData}}(), #space_regions
            Vector{FEMEntity{<:AbstractEntityData}}(), #interfaces
            Vector{FEMEntity{<:AbstractEntityData}}(), #boundaries
            Dict{Vector{Float64},AbstractEntityData}(), #unassigned_entities
            # Dict{Int,Material}(),
            # Dict{Int,Float64}(),
            # Dict{Vector{Float64},Int}(),
            # Dict{Vector{Float64},String}(),
            # Dict{Int,Tuple{Int,String}}(),
            Dict{String,Any}(),
            Dict{String,Any}()
        )

        # Set up paths
        workspace.paths = _setup_paths(solver, cable_system)

        return workspace
    end
end

"""
$(TYPEDSIGNATURES)

Main function to run the FEM simulation workflow for a cable system.

# Arguments

- `cable_system`: Cable system to simulate.
- `formulation`: Problem formulation parameters.
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
function run_fem_model(cable_system::LineCableSystem,
    formulation::FEMFormulation,
    solver::FEMSolver;
    frequency::Float64=50.0)
    # Create and initialize workspace
    workspace = FEMWorkspace(cable_system, formulation, solver, frequency=frequency)

    # Log start
    _log(workspace, 1, "Starting FEM simulation for cable system: $(cable_system.case_id)")
    _log(workspace, 1, "Configuration: domain_radius=$(formulation.domain_radius) m, mesh_algorithm=$(formulation.mesh_algorithm)")

    # Clean up files based on configuration
    _cleanup_files(workspace.paths, solver)

    # Check if mesh file exists
    mesh_file = workspace.paths[:mesh_file]
    mesh_exists = isfile(mesh_file)

    # Determine if we need to run meshing
    run_mesh = solver.force_remesh || !mesh_exists

    # Determine if we need to run solver
    solver_output_exists = false
    if solver.run_solver && !isempty(workspace.paths[:results_dir])
        # Check for presence of result files
        result_files = readdir(workspace.paths[:results_dir])
        solver_output_exists = !isempty(result_files)
    end
    run_solver = solver.run_solver && (!solver_output_exists || solver.overwrite_results)

    # Determine if we need to run post-processing
    run_postproc = solver.run_postprocessing && run_solver

    try
        # Initialize Gmsh for meshing phase
        if run_mesh
            gmsh.initialize()

            _log(workspace, 1, "Running meshing phase...")

            # Initialize Gmsh model and set parameters
            _initialize_gmsh(cable_system.case_id, formulation, solver)

            # Create geometry
            _log(workspace, 1, "Creating domain boundaries...")
            _make_space_geometry(workspace)

            _log(workspace, 1, "Creating cable geometry...")
            _make_cable_geometry(workspace)

            # Boolean operations
            _log(workspace, 1, "Performing boolean operations...")
            _process_fragments(workspace)

            # Entity identification and entity assignment
            _log(workspace, 1, "Identifying entities after fragmentation...")
            _identify_by_marker(workspace)

            # Physical group assignment
            _log(workspace, 1, "Assigning physical groups...")
            _assign_physical_groups(workspace)

            # # Mesh sizing
            # _log(workspace, 1, "Setting up physics-based mesh sizing...")
            # _config_mesh_sizes(workspace)

            # Preview pre-meshing configuration if requested
            if solver.preview_geo
                _log(workspace, 1, "Launching geometry preview before meshing...")
                preview_mesh(workspace)
            end

            # PHASE 6: Mesh generation
            _log(workspace, 1, "Generating mesh...")
            _mesh_generate(workspace)

            # Save mesh
            _log(workspace, 1, "Saving mesh to file: $(mesh_file)")
            gmsh.write(mesh_file)

            # Save geometry
            _log(workspace, 1, "Saving geometry to file: $(workspace.paths[:geo_file])")
            gmsh.write(workspace.paths[:geo_file])

            # # Save ONELAB parameters
            # _log(workspace, 1, "Saving ONELAB parameters to file: $(workspace.paths[:onelab_file])")
            # onelab_data = gmsh.onelab.get("")
            # open(workspace.paths[:onelab_file], "w") do io
            #     write(io, onelab_data)
            # end

            # Preview mesh if requested
            if solver.preview_mesh
                _log(workspace, 1, "Launching mesh preview...")
                preview_mesh(workspace)
            end

            _log(workspace, 1, "Meshing completed.")
        else
            _log(workspace, 1, "Skipping meshing phase (mesh already exists).")
        end

        # Run solver if needed
        if run_solver
            _log(workspace, 1, "Running solver phase...")
            # To be implemented
            # _run_solver(workspace)
            _log(workspace, 1, "Solver completed.")
        else
            _log(workspace, 1, "Skipping solver phase.")
        end

        # Run post-processing if needed
        if run_postproc
            _log(workspace, 1, "Running post-processing phase...")
            # To be implemented
            # _run_postprocessing(workspace)
            _log(workspace, 1, "Post-processing completed.")
        else
            _log(workspace, 1, "Skipping post-processing phase.")
        end

    catch e
        _log(workspace, 0, "Error in FEM simulation: $e")

        # Print stack trace for debugging
        if solver.verbosity >= 2
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
                _log(workspace, 1, "Gmsh finalized.")
            catch fin_err
                _log(workspace, 0, "Warning: Error during Gmsh finalization: $fin_err")
            end
        end
    end

    return workspace
end

# Include auxiliary files
include("FEMTools/encoding.jl")        # Tag encoding schemes
include("FEMTools/drawing.jl")         # Primitive drawing functions
include("FEMTools/markers.jl")         # Entity marker generation
include("FEMTools/identification.jl")  # Entity identification
include("FEMTools/meshing.jl")         # Mesh generation
include("FEMTools/materials.jl")       # Material handling
include("FEMTools/utilities.jl")       # Various utilities
include("FEMTools/visualization.jl")   # Visualization functions
include("FEMTools/space.jl")           # Domain creation functions
include("FEMTools/cable.jl")           # Cable geometry creation functions

end # module FEMTools
