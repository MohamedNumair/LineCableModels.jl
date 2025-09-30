
# # Tutorial 5: DSS Formulation for Line Parameters

# This tutorial demonstrates how to use the `:DSS` formulation to compute the series impedance and shunt admittance matrices of a simple 4-wire overhead line system. This formulation is a simplified, analytical approach based on the methods used in Distribution System Simulator (DSS) software.

# ## 1. Load Packages and Set Up Environment

# First, we load the necessary packages.
using LineCableModels
using DataFrames

# For reproducibility, we can set a verbosity level.
set_verbosity!(1);

# ## 2. Define Cable and System Geometry

# We start by defining the materials and the cable design. For this example, we will model a simple single-core conductor.
materials = MaterialsLibrary(add_defaults=true)
AL = get(materials, "aluminum")
PE = get(materials, "pe")

d_core = 0.00245 * 2 # diameter in m
ins_Thick = 0.00245 / 4 # insulation thickness in m

# We model the conductor as a solid wire.
core = ConductorGroup(WireArray(0.0, Diameter(d_core), 1, 0.0, AL))
main_insu = InsulatorGroup(Insulator(core, Thickness(ins_Thick), PE))
core_cc = CableComponent("core", core, main_insu)

# We create a `CableDesign` with some nominal data.
cable_id = "MyCable"
datasheet_info = NominalData(
    designation_code="MyCable-1x1000",
    U0=0.23,                        # Phase-to-ground voltage [kV]
    U=0.4,                          # Phase-to-phase voltage [kV]
    conductor_cross_section=1000.0, # [mm²]
    resistance=0.738027,            # DC resistance [Ω/km]
    capacitance=11.4153,            # Capacitance [μF/km]
    inductance=0.250846,            # Inductance [mH/km]
)
cable_design = CableDesign(cable_id, core_cc, nominal_data=datasheet_info)

# Now, we define the layout of the 4-wire system (3 phases + 1 neutral).
x_a = 0.0;     y_a = 5.8075;
x_b = -0.0075; y_b = 5.8075;
x_c = -0.0075; y_c = 5.800;
x_n = 0.0;     y_n = 5.800;

# We create the `LineCableSystem`.
cablepos = CablePosition(cable_design, x_a, y_a, Dict("core" => 1))
cable_system = LineCableSystem("MySystem", 1000.0, cablepos)

add!(cable_system, cable_design, x_b, y_b, Dict("core" => 2))
add!(cable_system, cable_design, x_c, y_c, Dict("core" => 3))
add!(cable_system, cable_design, x_n, y_n, Dict("core" => 4))

# We can preview the system layout.
preview(cable_system)

# ## 3. Define the Problem and Formulation

# We define the earth properties and the frequency for the analysis.
f = [50.0]
earth = EarthModel(f, 100.0, 1.0, 1.0) # 100 Ω·m resistivity




# We create the `LineParametersProblem`.
problem = LineParametersProblem(cable_system;
    temperature=20.0,
    earth_props=earth,
    frequencies=f
)

# Now, we select the `:DSS` formulation.
dss_formulation = FormulationSet(:DSS, 
    internal_impedance=LineCableModels.Engine.DeriModel(),
    earth_impedance=LineCableModels.Engine.DeriModel(),
    options = LineCableModels.Engine.DSSOptions()

);

# ## 4. Compute Line Parameters

# We can now compute the line parameters using the `compute!` function.
workspace, line_params = compute!(problem, dss_formulation)

line_params.Z
