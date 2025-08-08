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
using LinearAlgebra
using Colors
using Logging
using Logging: AbstractLogger, LogLevel, Info, global_logger
using LoggingExtras: TeeLogger, FileLogger

# GetDP.jl
using GetDP
using GetDP: Problem
using GetDP: get_getdp_executable

# Export public API
export LineParametersProblem
export MeshTransition, FEMFormulation, FEMOptions
export compute!, run_fem_solver, preview_results
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
struct GmshObject{T<:AbstractEntityData}
    "Gmsh entity tag (will be defined after boolean fragmentation)."
    tag::Int32
    "Entity-specific data."
    data::T
end

"""
$(TYPEDSIGNATURES)

Constructs a [`GmshObject`](@ref) instance with automatic type conversion.

# Arguments

- `tag`: Gmsh entity tag (will be converted to Int32)
- `data`: Entity-specific data conforming to [`AbstractEntityData`](@ref)

# Returns

- A [`GmshObject`](@ref) instance with the specified tag and data.

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
function GmshObject(tag::Integer, data::T) where {T<:AbstractEntityData}
    return GmshObject{T}(Int32(tag), data)
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

    function FEMElectrodynamics()
        return new(GetDP.Problem(), "Electrodynamics")
    end
end

"""
$(TYPEDEF)

Defines a mesh transition region for improved mesh quality in earth/air regions around cable systems.

$(TYPEDFIELDS)
"""
struct MeshTransition
    "Center coordinates (x, y) [m]"
    center::Tuple{Float64,Float64}
    "Minimum radius (must be ≥ bounding radius of cables) [m]"
    r_min::Float64
    "Maximum radius [m]"
    r_max::Float64
    "Minimum mesh size factor at r_min [m]"
    mesh_factor_min::Float64
    "Maximum mesh size factor at r_max [m]"
    mesh_factor_max::Float64
    "Number of transition regions [dimensionless]"
    n_regions::Int
    "Earth layer index (1=air, 2+=earth layers from top to bottom, nothing=auto-detect)"
    earth_layer::Union{Int,Nothing}

    function MeshTransition(center, r_min, r_max, mesh_factor_min, mesh_factor_max, n_regions, earth_layer)
        # Basic validation
        r_min >= 0 || Base.error("r_min must be greater than or equal to 0")
        r_max > r_min || Base.error("r_max must be greater than r_min")
        mesh_factor_min > 0 || Base.error("mesh_factor_min must be positive")
        mesh_factor_max <= 1 || Base.error("mesh_factor_max must be smaller than or equal to 1")
        mesh_factor_max > mesh_factor_min || Base.error("mesh_factor_max must be > mesh_factor_min")
        n_regions >= 1 || Base.error("n_regions must be at least 1")

        # Validate earth_layer if provided
        if !isnothing(earth_layer)
            earth_layer >= 1 || Base.error("earth_layer must be >= 1 (1=air, 2+=earth layers)")
        end

        new(center, r_min, r_max, mesh_factor_min, mesh_factor_max, n_regions, earth_layer)
    end
end

# Convenience constructor
function MeshTransition(
    cable_system::LineCableSystem,
    cable_indices::Vector{Int};
    r_min::Float64,
    r_length::Float64,
    mesh_factor_min::Float64,
    mesh_factor_max::Float64,
    n_regions::Int=3,
    earth_layer::Union{Int,Nothing}=nothing
)

    # Validate cable indices
    all(1 <= idx <= length(cable_system.cables) for idx in cable_indices) ||
        Base.error("Cable indices out of bounds")

    isempty(cable_indices) && Base.error("Cable indices cannot be empty")

    # Get centroid and bounding radius
    cx, cy, bounding_radius, _ = get_system_centroid(cable_system, cable_indices)

    # Calculate parameters
    if r_min < bounding_radius
        @warn "r_min ($r_min m) is smaller than bounding radius ($bounding_radius m). Adjusting r_min to match."
        r_min = bounding_radius
    end

    r_max = r_min + r_length

    # Auto-detect layer if not specified
    if isnothing(earth_layer)
        # Simple detection: y >= 0 is air (layer 1), y < 0 is first earth layer (layer 2)
        earth_layer = cy >= 0 ? 1 : 2
        @debug "Auto-detected earth_layer=$earth_layer for transition at ($cx, $cy)"
    end

    # Validate no surface crossing for underground transitions
    if earth_layer > 1 && cy + r_max > 0
        Base.error("Transition region would cross earth surface (y=0). Reduce r_length or use separate transition regions.")
    end

    return MeshTransition(
        (cx, cy),
        r_min,
        r_max,
        mesh_factor_min,
        mesh_factor_max,
        n_regions,
        earth_layer
    )
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
    "Mesh transition regions for improved mesh quality"
    mesh_transitions::Vector{MeshTransition}
    "Mesh algorithm to use \\[dimensionless\\]."
    mesh_algorithm::Int
    "Maximum meshing retries and number of recursive subdivisions \\[dimensionless\\]."
    mesh_max_retries::Int
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
        mesh_transitions::Vector{MeshTransition}=MeshTransition[],
        mesh_algorithm::Int=5,
        mesh_max_retries::Int=20,
        materials_db::MaterialsLibrary=MaterialsLibrary()
    )
        return new(
            domain_radius, domain_radius_inf,
            elements_per_length_conductor, elements_per_length_insulator,
            elements_per_length_semicon, elements_per_length_interfaces,
            points_per_circumference, analysis_type,
            mesh_size_min, mesh_size_max, mesh_size_default,
            mesh_transitions, mesh_algorithm, mesh_max_retries, materials_db
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
    "Build mesh only and preview (no solving)"
    mesh_only::Bool
    "Force mesh regeneration even if file exists"
    force_remesh::Bool
    "Skip user confirmation for overwriting results"
    force_overwrite::Bool
    "Generate field visualization outputs"
    plot_field_maps::Bool
    "Archive temporary files after each frequency run"
    keep_run_files::Bool

    "Base path for output files"
    base_path::String
    "Path to GetDP executable"
    getdp_executable::String
    "Verbosity level"
    verbosity::Int
    "Log file path"
    logfile::Union{String,Nothing}

    function FEMOptions(;
        mesh_only::Bool=false,
        force_remesh::Bool=false,
        force_overwrite::Bool=false,
        plot_field_maps::Bool=true,
        keep_run_files::Bool=false,
        base_path::String="./fem_output",
        getdp_executable::Union{String,Nothing}=nothing,
        verbosity::Int=0,
        logfile::Union{String,Nothing}=nothing
    )
        # Validate GetDP executable
        if isnothing(getdp_executable)
            getdp_executable = GetDP.get_getdp_executable()
        end

        if !isfile(getdp_executable)
            Base.error("GetDP executable not found: $getdp_executable")
        end

        setup_fem_logging(verbosity, logfile)

        return new(mesh_only, force_remesh, force_overwrite, plot_field_maps, keep_run_files, base_path, getdp_executable, verbosity, logfile)
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
    conductors::Vector{GmshObject{<:AbstractEntityData}}
    "Insulator surfaces within cables."
    insulators::Vector{GmshObject{<:AbstractEntityData}}
    "Domain-space physical surfaces (air and earth layers)."
    space_regions::Vector{GmshObject{<:AbstractEntityData}}
    "Domain boundary curves."
    boundaries::Vector{GmshObject{<:AbstractEntityData}}
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
            Vector{GmshObject{<:AbstractEntityData}}(), #conductors
            Vector{GmshObject{<:AbstractEntityData}}(), #insulators
            Vector{GmshObject{<:AbstractEntityData}}(), #space_regions
            Vector{GmshObject{<:AbstractEntityData}}(), #boundaries
            Dict{Vector{Float64},AbstractEntityData}(), #unassigned_entities
            Dict{String,Int}(),  # Initialize empty material registry
            Dict{Int,Material}(), # Maps physical group tags to materials
        )

        # Set up paths
        workspace.paths = setup_paths(problem.system, formulation, opts)

        return workspace
    end
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
    opts::FEMOptions;
    workspace::Union{FEMWorkspace,Nothing}=nothing)

    # Initialize workspace
    workspace = init_workspace(problem, formulation, opts, workspace)

    # Meshing phase
    mesh_needed = !(mesh_exists(workspace, opts))
    if mesh_needed || opts.mesh_only
        @info "Building mesh for system: $(problem.system.system_id)"
        make_mesh!(workspace)
        if opts.mesh_only
            @info "Saving workspace after mesh generation"
            return workspace, nothing
        end

    else
        @info "Using existing mesh"
    end

    # Solving phase - always runs unless mesh_only
    @info "Starting FEM solver"
    line_params = run_solver!(problem, formulation, workspace)

    @info "FEM computation completed successfully"
    return workspace, line_params
end

function init_workspace(problem, formulation, opts, workspace)
    if isnothing(workspace)
        @debug "Creating new workspace"
        workspace = FEMWorkspace(problem, formulation, opts)
    else
        @debug "Reusing existing workspace"
    end

    # Handle existing results - check both current and archived
    results_dir = workspace.paths[:results_dir]
    base_dir = dirname(results_dir)

    # Check current results directory
    current_results_exist = isdir(results_dir) && !isempty(readdir(results_dir))

    # Check for archived frequency results (results_f* pattern)
    archived_results_exist = false
    if isdir(base_dir)
        archived_dirs = filter(d -> startswith(d, "results_f") && isdir(joinpath(base_dir, d)),
            readdir(base_dir))
        archived_results_exist = !isempty(archived_dirs)
    end

    # Handle existing results if any are found
    if current_results_exist || archived_results_exist
        if opts.force_overwrite
            # Remove both current and archived results
            if current_results_exist
                rm(results_dir, recursive=true, force=true)
            end
            if archived_results_exist
                for archived_dir in archived_dirs
                    rm(joinpath(base_dir, archived_dir), recursive=true, force=true)
                end
                @debug "Removed $(length(archived_dirs)) archived result directories"
            end
        else
            # Build informative error message
            error_msg = "Existing results found:\n"
            if current_results_exist
                error_msg *= "  - Current results: $results_dir\n"
            end
            if archived_results_exist
                error_msg *= "  - Archived results: $(length(archived_dirs)) frequency directories\n"
            end
            error_msg *= "Set force_overwrite=true to automatically delete existing results."

            Base.error(error_msg)
        end
    end

    return workspace
end

function mesh_exists(workspace::FEMWorkspace, opts::FEMOptions)
    mesh_file = workspace.paths[:mesh_file]

    # Force remesh overrides everything
    if opts.force_remesh
        @debug "Force remesh requested"
        return false
    end

    # If workspace is empty (no entities), force remesh regardless of file existence
    if isempty(workspace.conductors) && isempty(workspace.insulators) && isempty(workspace.space_regions) && isempty(workspace.boundaries) && isempty(workspace.physical_groups) && isempty(workspace.material_registry)
        @warn "Empty workspace detected - forcing remesh"
        return false
    end

    # Check if mesh file exists
    if !isfile(mesh_file)
        @debug "No existing mesh file found"
        return false
    end

    # Mesh exists - can reuse
    @debug "Existing mesh found and will be reused"
    return true
end

function make_mesh!(workspace::FEMWorkspace)
    try
        gmsh.initialize()
        _do_make_mesh!(workspace)
        @info "Mesh generation completed"

        if workspace.opts.mesh_only
            @info "Mesh-only mode: Opening preview"
            preview_mesh(workspace)
        end

    catch e
        @error "Mesh generation failed" exception = e
        rethrow(e)
    finally
        try
            gmsh.finalize()
        catch fin_err
            @warn "Gmsh finalization error" exception = fin_err
        end
    end
end

function run_solver!(problem::LineParametersProblem,
    formulation::FEMFormulation,
    workspace::FEMWorkspace)

    # Preallocate result matrices
    n_phases = sum(length(c.design_data.components) for c in workspace.problem_def.system.cables)
    n_frequencies = length(problem.frequencies)

    Z = zeros(ComplexF64, n_phases, n_phases, n_frequencies)
    Y = zeros(ComplexF64, n_phases, n_phases, n_frequencies)

    # Solve for each frequency
    for (freq_idx, frequency) in enumerate(problem.frequencies)
        @info "Solving frequency $freq_idx/$n_frequencies: $frequency Hz"

        try
            _do_run_solver!(frequency, freq_idx, formulation, workspace, Z, Y)
        catch e
            @error "Solver failed for frequency $frequency Hz" exception = e
            rethrow(e)
        end

        # Archive results if not cleaning up
        if workspace.opts.keep_run_files
            archive_frequency_results(workspace, frequency)
        end
    end

    return LineParameters(Z, Y)
end

function _do_run_solver!(frequency::Float64, freq_idx::Int,
    formulation::FEMFormulation, workspace::FEMWorkspace,
    Z::Array{ComplexF64,3}, Y::Array{ComplexF64,3})

    # Build and solve both formulations
    for fem_formulation in formulation.analysis_type
        @debug "Processing $(fem_formulation.resolution_name) formulation"

        make_fem_problem!(fem_formulation, frequency, workspace)

        if !run_getdp(workspace, fem_formulation)
            Base.error("$(fem_formulation.resolution_name) solver failed")
        end
    end

    # Extract results into preallocated arrays
    Z[:, :, freq_idx] = read_results_file(formulation.analysis_type[1], workspace)
    Y[:, :, freq_idx] = read_results_file(formulation.analysis_type[2], workspace)
end

function archive_frequency_results(workspace::FEMWorkspace, frequency::Float64)
    try
        results_dir = workspace.paths[:results_dir]
        freq_dir = joinpath(dirname(results_dir), "results_f=$(round(frequency, sigdigits=6))")

        if isdir(results_dir)
            mv(results_dir, freq_dir, force=true)
            @debug "Archived results for f=$frequency Hz"
        end

        # Move solver files
        for ext in [".res", ".pre"]
            case_files = filter(f -> endswith(f, ext),
                readdir(workspace.paths[:case_dir], join=true))
            for f in case_files
                mv(f, joinpath(freq_dir, basename(f)), force=true)
            end
        end
    catch e
        @warn "Failed to archive results for frequency $frequency Hz" exception = e
    end
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
