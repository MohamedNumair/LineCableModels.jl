# This file is supposed to be the test case for the FEMTools.jl module implementation.
push!(LOAD_PATH, joinpath(@__DIR__, "..", "src")) # hide
using Revise
using LineCableModels

materials_db = MaterialsLibrary(add_defaults=false)
load_materialslibrary!(materials_db, file_name=joinpath(@__DIR__, "materials_library.json"))

cables_library = CablesLibrary()
load_cableslibrary!(cables_library, file_name=joinpath(@__DIR__, "cables_library.json"))

# Retrieve the reloaded design
cable_design = get_cabledesign(cables_library, "tutorial")

f = 10.0 .^ range(0, stop=6, length=10)  # Frequency range
earth_params = EarthModel(f, 100.0, 10.0, 1.0)  # 100 Ω·m resistivity, εr=10, μr=1

# Define system center point (underground at 1 m depth) and the trifoil positions
x0 = 0
y0 = -1
xa, ya, xb, yb, xc, yc = trifoil_formation(x0, y0, 0.035)

# Initialize the `LineCableSystem` with the first cable (phase A):
cablepos = CablePosition(cable_design, xa, ya, Dict("core" => 1, "sheath" => 0, "jacket" => 0))
cable_system = LineCableSystem("tutorial", 1000.0, cablepos)

# Add remaining cables (phases B and C):
addto_linecablesystem!(cable_system, cable_design, xb, yb,
    Dict("core" => 2, "sheath" => 0, "jacket" => 0),
)
addto_linecablesystem!(
    cable_system, cable_design, xc, yc,
    Dict("core" => 3, "sheath" => 0, "jacket" => 0),
)

display(cable_system)

# Define a LineParametersProblem with the cable system and earth model
f = 50.0
problem = LineParametersProblem(
    cable_system,
    temperature=20.0,  # Operating temperature
    earth_props=earth_params,
    frequencies=[f],  # Frequency for the analysis
)

# Create a FEMFormulation with custom mesh definitions
domain_radius = 5.0
formulation = FEMFormulation(
    domain_radius=domain_radius,
    domain_radius_inf=domain_radius * 1.25,
    elements_per_length_conductor=1,
    elements_per_length_insulator=2,
    elements_per_length_semicon=1,
    elements_per_length_interfaces=5,
    points_per_circumference=16,
    analysis_type=(FEMDarwin(), FEMElectrodynamics()),
    mesh_size_min=1e-6,
    mesh_size_max=domain_radius / 5,
    mesh_size_default=domain_radius / 10,
    mesh_algorithm=5,
    materials_db=materials_db
)

# Define runtime FEMOptions 
opts = FEMOptions(
    force_remesh=false,  # Force remeshing
    force_overwrite=true,
    plot_field_maps=false,
    mesh_only=false,  # Preview the mesh
    base_path=joinpath(@__DIR__, "fem_output"),
    keep_run_files=true,  # Archive files after each run
    verbosity=3,  # Verbose output
    getdp_executable=joinpath("/home/amartins/Applications/onelab-Linux64", "getdp"), # Path to GetDP executable
)

# Run the FEM model
@time workspace, line_params = compute!(problem, formulation, opts)

println("\nR = $(round(real(line_params.Z[1,1,1])*1000, sigdigits=4)) Ω/km")
println("L = $(round(imag(line_params.Z[1,1,1])/(2π*f)*1e6, sigdigits=4)) mH/km")
println("C = $(round(imag(line_params.Y[1,1,1])/(2π*f)*1e9, sigdigits=4)) μF/km")

# @time _, line_params = compute!(problem, formulation, opts, workspace=workspace)