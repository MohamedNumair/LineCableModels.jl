# # Tutorial 1: Single-Core Power Cable Modeling and Analysis
#
# This tutorial demonstrates how to model a typical medium-voltage single-core power cable 
# using the LineCableModels.jl package. The objective is to build a complete representation of a 
# NA2XS(FL)2Y 18/30 kV cable with a 1000 mm² aluminum conductor and 35 mm² copper screen.
#
# ## Introduction
#
# Underground power cables have a complex structure consisting of multiple concentric layers, 
# each with specific geometric and material properties. This tutorial covers:
#
# 1. Creating a detailed cable design with all its components
# 2. Examining the electrical parameters (R, L, C, G) of the cable
# 3. Analyzing a three-phase cable system in trifoil formation
# 4. Exporting the model to PSCAD for further electromagnetic transient analysis
#
# ## Loading Required Packages

# First, ensure the package is in the load path and import necessary libraries
push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))
using Plots
using LineCableModels
using DataFrames

# Configuring plots for proper display in Literate.jl generated documentation
# Comment out or modify these settings as needed
# hide
gr()  # Use GR backend which works well with Literate.jl
# default(
# 	size = (600, 400),
# 	dpi = 300,
# 	fontfamily = "Computer Modern",
# 	guidefontsize = 10,
# 	tickfontsize = 10,
# 	titlefontsize = 12,
# 	legendfontsize = 8,
# 	margin = 5Plots.mm,
# )
# hide

# ## Material Properties
#
# LineCableModels.jl provides a materials library with predefined electromagnetic 
# properties for common cable materials. The library contains standard materials used
# in power cable manufacturing.

# Load materials library
materials_db = MaterialsLibrary()
list_materials_library(materials_db)

# ## Creating a Cable Library
#
# A new cable design is created and stored in a cable library for potential reuse.

# Initialize a cables library
library = CablesLibrary()
list_cables_library(library)
cable_id = "tutorial1"

# ## Cable Dimensions
#
# The key dimensions of the cable are defined based on typical values for a 
# NA2XS(FL)2Y 18/30 kV cable with 1000 mm² conductor cross-section.

# Define main dimensions (in meters)
d_core = 38e-3     # nominal core overall diameter
d_w = 4.67e-3      # nominal strand diameter of the core
t_sc_in = 0.6e-3   # nominal internal semicon thickness
t_ins = 8e-3       # nominal main insulation thickness
t_sc_out = 0.3e-3  # nominal external semicon thickness
num_sc_wires = 49  # number of screen wires
d_ws = .94e-3      # nominal wire screen diameter
t_cut = 0.1e-3     # nominal thickness of the copper tape (around wire screens)
w_cut = 10e-3      # nominal width of copper tape
t_wbt = .3e-3      # nominal thickness of the water blocking tape
t_alt = .15e-3     # nominal thickness of the aluminum tape
t_pet = .05e-3     # nominal thickness of the pe face in the aluminum tape
t_jac = 2.4e-3     # nominal PE jacket thickness

# ## Modeling the Cable Core
#
# Power cables typically have stranded conductors for flexibility. The model implements a 
# 5-layer stranded conductor according to the standard structure of aluminum conductors.
# Each layer has a specific number of wires and lay ratio according to standards.

# Stranded conductor core
material = get_material(materials_db, "aluminum")
# Start with central wire
core = Conductor(WireArray(0, Diameter(d_w), 1, 0, material))
# Add first layer (6 wires with lay ratio 15)
addto_conductor!(core, WireArray, Diameter(d_w), 6, 15, material)
# Add second layer (12 wires with lay ratio 13.5)
addto_conductor!(core, WireArray, Diameter(d_w), 12, 13.5, material)
# Add third layer (18 wires with lay ratio 12.5)
addto_conductor!(core, WireArray, Diameter(d_w), 18, 12.5, material)
# Add fourth layer (24 wires with lay ratio 11)
addto_conductor!(core, WireArray, Diameter(d_w), 24, 11, material)

# ## Inner Semiconductor Layer
#
# The inner semiconductor layer ensures uniform electric field distribution between
# the conductor and insulation, eliminating air gaps and reducing field concentrations.

# Inner semiconductor
material = get_material(materials_db, "semicon1")
semicon_in = Semicon(core, Thickness(t_sc_in), material)

# ## Main Insulation
#
# XLPE (cross-linked polyethylene) is the standard insulation material for modern
# medium and high voltage cables due to its excellent dielectric properties.

# Main insulation (XLPE)
material = get_material(materials_db, "xlpe")
main_insu = Insulator(semicon_in, Thickness(t_ins), material)

# ## Outer Semiconductor Layer
#
# Similar to the inner semiconductor, the outer semiconductor provides a uniform
# transition from insulation to the metallic screen.

# Outer semiconductor
material = get_material(materials_db, "semicon2")
semicon_out = Semicon(main_insu, Thickness(t_sc_out), material)

# ## Water Blocking Tape
#
# Water blocking tape prevents water ingress and longitudinal water penetration
# along the cable in case of damage to the outer jacket.

# Core semiconductive tape
material = get_material(materials_db, "polyacrylate")
wb_tape_co = Semicon(semicon_out, Thickness(t_wbt), material)

# Group all core-related components
core_parts = [core, semicon_in, main_insu, semicon_out, wb_tape_co]

# ## Creating the Cable Design with Nominal Data
#
# The CableDesign object is initialized with nominal data from the datasheet.
# This includes voltage ratings and expected electrical parameters.

# Initialize CableDesign with the first component
datasheet_info = NominalData(
	designation_code = "NA2XS(FL)2Y",
	U0 = 18.0,                      # Phase-to-ground voltage [kV]
	U = 30.0,                       # Phase-to-phase voltage [kV]
	conductor_cross_section = 1000.0, # [mm²]
	screen_cross_section = 35.0,      # [mm²]
	resistance = 0.0291,              # DC resistance [Ω/km]
	capacitance = 0.39,               # Capacitance [μF/km]
	inductance = 0.3,                 # Inductance in trifoil [mH/km]
)

cable_design =
	CableDesign(cable_id, "core", core_parts, nominal_data = datasheet_info)

# ## Metallic Screen
#
# The metallic screen (typically copper) serves multiple purposes:
# - Provides a return path for fault currents
# - Ensures radial symmetry of the electric field
# - Acts as electrical shielding
# - Provides mechanical protection

# Wire screens - Continue building on top of wb_tape_co
lay_ratio = 10 # typical value for wire screens
material = get_material(materials_db, "copper")
wire_screen =
	Conductor(WireArray(wb_tape_co, Diameter(d_ws), num_sc_wires, lay_ratio, material))
# Add copper tape that wraps the wire screen
addto_conductor!(wire_screen, Strip, Thickness(t_cut), w_cut, lay_ratio, material)

# Water blocking tape over screen
material = get_material(materials_db, "polyacrylate")
wb_tape_scr = Semicon(wire_screen, Thickness(t_wbt), material)

# Group sheath components and add to design
sheath_parts = [wire_screen, wb_tape_scr]
addto_design!(cable_design, "sheath", sheath_parts)

# ## Outer Jacket Components
#
# Modern cables often include an aluminum tape as moisture barrier
# and PE (polyethylene) outer jacket for mechanical protection.

# Aluminum tape (moisture barrier)
material = get_material(materials_db, "aluminum")
alu_tape = Conductor(Tubular(wb_tape_scr, Thickness(t_alt), material))

# PE layer after aluminum foil 
material = get_material(materials_db, "pe")
alu_tape_pe = Insulator(alu_tape, Thickness(t_pet), material)

# PE jacket (outer mechanical protection)
material = get_material(materials_db, "xlpe")
pe_insu = Insulator(alu_tape_pe, Thickness(t_jac), material)

# Group jacket components and add to design
jacket_parts = [alu_tape, alu_tape_pe, pe_insu]
addto_design!(cable_design, "jacket", jacket_parts)

# ## Analyzing the Cable Design
#
# This section examines the cable design and compares calculated parameters with datasheet values.
# LineCableModels.jl provides several functions to analyze the design in different levels of detail.

# Compare with datasheet information (R, L, C values)
data1 = design_data(cable_design, :core)
println(data1)

# Check EMT (Electromagnetic Transient) parameters for each component
data2 = design_data(cable_design, :components)
data2  # Display the DataFrame

# Get detailed description of all cable parts
data3 = design_data(cable_design, :detailed)
data3  # Display the DataFrame

# Visualize the cross-section of the cable
plt1 = design_preview(cable_design)
plt1  # For Literate.jl to capture the plot output

# Save the cable design to the library
store_cables_library!(library, cable_design)
save_cables_library(library, file_name = joinpath(@__DIR__, "cables_library.jls"))

# ## Earth Model Definition
#
# The earth return path significantly affects cable impedance calculations.
# A frequency-dependent earth model with typical soil properties is defined.

# Create a frequency-dependent earth model (10^0 to 10^6 Hz)
f = 10.0 .^ range(0, stop = 6, length = 10)  # Frequency range
earth_params = EarthModel(f, 100.0, 10.0, 1.0)  # 100 Ω·m resistivity, εr=10, μr=1

# Earth model base (DC) properties:
earth_data_df = earth_data(earth_params)
earth_data_df  # Display the DataFrame

# ## Three-Phase System in Trifoil Configuration
#
# Most power systems use three-phase configurations. This section creates a cable system
# with three identical cables arranged in a trifoil formation.

# Define system center point (underground at 1m depth)
x0 = 0
y0 = -1

# Calculate trifoil positions (three cables in triangular arrangement)
xa, ya, xb, yb, xc, yc = trifoil_formation(x0, y0, 0.035)

# Initialize the LineCableSystem with the first cable (phase A)
# The Dict maps components to phases (1=phase conductor, 0=grounded/neutral)
cabledef = CableDef(cable_design, xa, ya, Dict("core" => 1, "sheath" => 0, "jacket" => 0))
cable_system = LineCableSystem("tutorial1", 20.0, earth_params, 1000.0, cabledef)

# Add remaining cables (phases B and C)
addto_system!(
	cable_system,
	cable_design,
	xb,
	yb,
	Dict("core" => 2, "sheath" => 0, "jacket" => 0),
)
addto_system!(
	cable_system,
	cable_design,
	xc,
	yc,
	Dict("core" => 3, "sheath" => 0, "jacket" => 0),
)

# ## System Analysis
#
# This section examines the complete three-phase cable system.

# Display system details
system_data_df = system_data(cable_system)

# Print as a markdown table
println("```")
println(DataFrame(system_data_df))
println("```")

# Visualize the cross-section of the three-phase system
plt2 = system_preview(cable_system, zoom_factor = 0.25)
plt2  # For Literate.jl to capture the plot output

# ## PSCAD Export
#
# The final step exports the model for electromagnetic transient simulations in PSCAD.

# Export to PSCAD input file
export_pscad_lcp(cable_system, folder_path = @__DIR__);

# ## Conclusion
#
# This tutorial has demonstrated how to:
#
# 1. Create a detailed model of a complex power cable with multiple concentric layers
# 2. Calculate and analyze the cable's electrical parameters
# 3. Design a three-phase cable system in trifoil arrangement
# 4. Export the model for further analysis in specialized software
#
# LineCableModels.jl provides a powerful framework for accurate power cable modeling
# with a physically meaningful representation of all cable components. This approach
# ensures that electromagnetic parameters are calculated with high precision, which
# is essential for transient studies in power systems.