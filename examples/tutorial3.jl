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
cabledef = CableDef(cable_design, xa, ya, Dict("core" => 1, "sheath" => 0, "jacket" => 0))
cable_system = LineCableSystem("tutorial", 20.0, earth_params, 1000.0, cabledef)

# Add remaining cables (phases B and C):
addto_linecablesystem!(cable_system, cable_design, xb, yb,
    Dict("core" => 2, "sheath" => 0, "jacket" => 0),
)
addto_linecablesystem!(
    cable_system, cable_design, xc, yc,
    Dict("core" => 3, "sheath" => 0, "jacket" => 0),
)

display(cable_system)

# Create a FEMProblemDefinition with custom parameters
problem = FEMProblemDefinition(
    domain_radius=5.0,  # 5 m radius
    correct_twisting=true,
    elements_per_scale_length_conductor=3.0,
    elements_per_scale_length_insulator=2.0,
    elements_per_scale_length_semicon=4.0,
    elements_per_scale_length_interfaces=0.1,
    analysis_type=[0, 1],  # Electrostatic and magnetostatic
    mesh_size_min=1e-4,
    mesh_size_max=0.5,
    mesh_size_default=0.01,
    mesh_algorithm=6,  # Frontal-Delaunay
    materials_db=materials_db
)

# Create a FEMSolver with custom parameters
solver = FEMSolver(
    force_remesh=true,  # Force remeshing
    run_solver=false,
    preview_geo=true,  # Preview geometry
    preview_mesh=false,  # Preview the mesh
    base_path=joinpath(@__DIR__, "fem_output"),
    verbosity=2,  # Verbose output
    getdp_executable=joinpath("/home/amartins/Applications/onelab-Linux64", "getdp"),  # Path to GetDP executable
)

# Run the FEM model
workspace = run_fem_model(cable_system, problem, solver, frequency=50.0)

println("FEM model run completed.")
