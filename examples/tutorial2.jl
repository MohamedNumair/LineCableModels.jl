# # Tutorial 2 - Building a cable design

#=
This tutorial demonstrates how to model a typical medium-voltage single-core power cable 
using the [`LineCableModels.jl`](@ref) package. The objective is to build a complete representation of a single-core 18/30 kV cable with a 1000 mm² aluminum conductor and 35 mm² copper screen.
=#

#=
**Tutorial outline**
```@contents
Pages = [
	"tutorial2.md",
]
Depth = 2:3
```
=#

# ## Introduction

#=
Single-core power cables have a complex structure consisting of multiple concentric layers, each with specific geometric and material properties -- for example, a cable of type NA2XS(FL)2Y 18/30 [is shown here](https://www.google.com/search?udm=2&q=%22NA2XS(FL)2Y%2018/30%20kV%20cable%22). Prior to building actual transmission line models that incorporate cables as part of the transmission system, e.g. for EMT simulations, power flow, harmonics, protection studies etc., it is necessary to determine the base (or DC) electrical parameters of the cable itself.

This tutorial covers:

1. Creating a detailed [`CableDesign`](@ref) with all its components.
2. Examining the main electrical parameters (R, L, C) of the cable core [`Conductor`](@ref) and main [`Insulator`](@ref).
3. Examining the equivalent electromagnetic properties of every [`CableComponent`](@ref) (core, sheath, jacket).
4. Saving the cable design to a [`CablesLibrary`](@ref) for future use.
4. Assigning [`CableDesign`](@ref) objects to a [`LineCableSystem`](@ref) and exporting the model to PSCAD for EMT analysis.
=#

# ## Getting started

# Load the package and set up the environment:
push!(LOAD_PATH, joinpath(@__DIR__, "..", "src")) # hide
using LineCableModels
using DataFrames
using Plots

#=
```julia
# Alternatively, use the PlotlyJS backend for interactive plots:
# plotlyjs()
# base_font_size = 12
# title_base_font_size = 14
# leg_base_font_size = 10
# default(
# 	fontfamily = "Computer Modern",
# 	guidefontsize = base_font_size,   # Axis labels (x/y/z)
# 	tickfontsize = base_font_size,    # Tick labels
# 	titlefontsize = title_base_font_size, # Title font size
# 	legendfontsize = leg_base_font_size,  # Legend font size
# )
```
=#

# Load materials library:
materials_db = MaterialsLibrary()
list_materials_library(materials_db)

# ## Cable dimensions
#=
The cable under consideration is a medium-voltage, stranded aluminum conductor cable with XLPE insulation, copper wire concentric screens, water-blocking tape, and PE jacket that is rated for 18/30 kV systems. This information is typically found in the cable datasheet and is fully described in the code type under standards HD 620 10C [CENELEC_HD620_S3_2023](@cite) or DIN VDE 0276-620 [VDE_DIN_VDE_0276_620_2024](@cite):

```
NA2XS(FL)2Y
│ │   │  │
│ │   │  └── 2Y: Outer sheath of polyethylene (PE)
│ │   └── (FL): Longitudinal watertight protection
│ │      
│ └── 2XS: XLPE insulation with screen of copper wires
└── NA: Aluminum conductor
```
=#

# After some research, it is found that a typical cable of this type has the following configuration:
num_co_wires = 61  # number of core wires
num_sc_wires = 49  # number of screen wires
d_core = 38.1e-3   # nominal core overall diameter
d_w = 4.7e-3       # nominal strand diameter of the core
t_sc_in = 0.6e-3   # nominal internal semicon thickness
t_ins = 8e-3       # nominal main insulation thickness
t_sc_out = 0.3e-3  # nominal external semicon thickness
d_ws = .95e-3      # nominal wire screen diameter
t_cut = 0.1e-3     # nominal thickness of the copper tape (around wire screens)
w_cut = 10e-3      # nominal width of copper tape
t_wbt = .3e-3      # nominal thickness of the water blocking tape
t_sct = .3e-3      # nominal thickness of the semiconductive tape
t_alt = .15e-3     # nominal thickness of the aluminum tape
t_pet = .05e-3     # nominal thickness of the pe face in the aluminum tape
t_jac = 2.4e-3     # nominal PE jacket thickness

d_overall = d_core # hide
layers = [] # hide
push!(layers, ("Conductor", missing, d_overall * 1000)) # hide
d_overall += 2 * t_sct # hide
push!(layers, ("Inner semiconductive tape", t_sct * 1000, d_overall * 1000)) # hide
d_overall += 2 * t_sc_in # hide
push!(layers, ("Inner semiconductor", t_sc_in * 1000, d_overall * 1000)) # hide
d_overall += 2 * t_ins # hide
push!(layers, ("Main insulation", t_ins * 1000, d_overall * 1000)) # hide
d_overall += 2 * t_sc_out # hide
push!(layers, ("Outer semiconductor", t_sc_out * 1000, d_overall * 1000)) # hide
d_overall += 2 * t_sct # hide
push!(layers, ("Outer semiconductive tape", t_sct * 1000, d_overall * 1000)) # hide
d_overall += 2 * d_ws # hide
push!(layers, ("Wire screen", d_ws * 1000, d_overall * 1000)) # hide
d_overall += 2 * t_cut # hide
push!(layers, ("Copper tape", t_cut * 1000, d_overall * 1000)) # hide
d_overall += 2 * t_wbt # hide
push!(layers, ("Water-blocking tape", t_wbt * 1000, d_overall * 1000)) # hide
d_overall += 2 * t_alt # hide
push!(layers, ("Aluminum tape", t_alt * 1000, d_overall * 1000)) # hide
d_overall += 2 * t_pet # hide
push!(layers, ("PE with aluminum face", t_pet * 1000, d_overall * 1000)) # hide
d_overall += 2 * t_jac # hide
push!(layers, ("PE jacket", t_jac * 1000, d_overall * 1000)); # hide

# The cable structure is summarized in a table for better visualization, with dimensions in milimiters:
df = DataFrame( # hide
	layer = first.(layers), # hide
	thickness = [ # hide
		ismissing(t) ? "-" : round(t, sigdigits = 2) for t in getindex.(layers, 2) # hide
	], # hide
	diameter = [round(d, digits = 2) for d in getindex.(layers, 3)], # hide
) # hide

# ## Using the cable constructors
#=
!!! note "Object hierarchy"
	The [`LineCableModels.DataModel`](@ref) module implements a carefully designed component hierarchy that mirrors the physical construction of power cables while maintaining the mathematical relationships required for accurate electrical modeling.

```
CableDesign
├── CableComponent <: AbstractCablePart
│   ├── Conductor <: AbstractConductorPart
│   │   ├── WireArray
│   │   ├── Tubular
│   │   ├── Strip
│   │   └── Conductor <: AbstractConductorPart
│   │       ├── WireArray
│   │       ├── …
│   │       └── Any <: AbstractConductorPart
│   ⋮
│   ├── Any <: AbstractConductorPart
│   ├── Semicon
│   ├── Insulator
│   ├── …
│   ⋮
│   └── Any <: AbstractInsulatorPart
⋮
```

### Cable designs

The [`CableDesign`](@ref) object is the main container for all cable components. It encapsulates the entire cable structure and provides methods for calculating overall cable properties.

### Cable components

Each [`CableComponent`](@ref) represents a functional group of the cable (core, sheath, armor, outer), and must contain at least one [`AbstractConductorPart`](@ref) and one [`AbstractInsulatorPart`](@ref). These containers are subsequently used to calculate the equivalent electromagnetic parameters of the coaxial cable layers.

### Conductors

The [`Conductor`](@ref) object represents a specialized container for grouping various [`AbstractConductorPart`](@ref) objects. It calculates equivalent resistance (R) and inductance (L) values for all contained conductive elements, handling the complexity of different geometrical arrangements.

#### AbstractConductorPart implementations

- The [`WireArray`](@ref) object models stranded cores with twisting effects and helical patterns.
- The [`Tubular`](@ref) object represents simple tubular conductors with straightforward parameter calculations.
- The [`Strip`](@ref) object models conductor tapes following helical patterns with rectangular cross-sections.

### Insulators and Semicons

The [`Insulator`](@ref) and the [`Semicon`](@ref) objects represent the insulating and semiconducting layers, primarily tubular in shape, with methods to calculate capacitance (C) and conductance (G).

!!! note "Equivalent circuit parameters"
	The hierarchical structure enables accurate calculation of equivalent circuit parameters by:

	1. Computing geometry-specific parameters at the [`AbstractConductorPart`](@ref) level.
	2. Aggregating these into equivalent parameters at the [`Conductor`](@ref) level.
	3. Further combining these with [`AbstractInsulatorPart`](@ref) properties at the [`CableComponent`](@ref) level.
	4. Converting the composite structure into an equivalent coaxial model by matching lumped circuit quantities (R, L, C, G) to effective electromagnetic properties (ρ, ε, µ, tan δ).
=#

# ## Core and main insulation

#=
The core consists of a 4-layer AAAC stranded conductor with 61 wires arranged in (1/6/12/18/24) pattern, with respective lay ratios of (15/13.5/12.5/11) [CENELEC50182](@cite). Stranded conductors are modeled using the [`WireArray`](@ref) object, which handles the helical pattern and twisting effects via the [`calc_helical_params`](@ref) method.
=#

# Initialize the conductor object and assign the central wire:
material = get_material(materials_db, "aluminum")
core = Conductor(WireArray(0, Diameter(d_w), 1, 0, material))

#=
!!! tip "Convenience methods"
	The [`addto_conductor!`](@ref) method internally passes the `radius_ext` of the existing object to the `radius_in` argument of the new conductor. This enables easy stacking of multiple layers without redundancy. Moreover, the [`Diameter`](@ref) method is a convenience function that converts the diameter to radius at the constructor level. This maintains alignment with manufacturer specifications while enabling internal calculations to use radius values directly. This approach eliminates repetitive unit conversions and potential sources of implementation error.
=#

# Add the subsequent layers of wires and inspect the object:
addto_conductor!(core, WireArray, Diameter(d_w), 6, 15, material)
addto_conductor!(core, WireArray, Diameter(d_w), 12, 13.5, material)
addto_conductor!(core, WireArray, Diameter(d_w), 18, 12.5, material)
addto_conductor!(core, WireArray, Diameter(d_w), 24, 11, material)

#=
### Inner semiconductor

The inner semiconductor layer ensures uniform electric field distribution between
the conductor and insulation, eliminating air gaps and reducing field concentrations. An optional semiconductive tape is often used to ensure core uniformity and enhanced adherence.
=#

#=
!!! tip "Convenience methods"
	The [`Thickness`](@ref) type is a convenience wrapper that simplifies layer construction. When used in a constructor, it automatically calculates the outer radius by adding the thickness to the inner radius (which is inherited from the previous layer's outer radius).
=#

# Inner semiconductive tape:
material = get_material(materials_db, "polyacrylate")
sctape_in = Semicon(core, Thickness(t_sct), material)

# Inner semiconductor (1000 Ω.m as per IEC 840):
material = get_material(materials_db, "semicon1")
semicon_in = Semicon(sctape_in, Thickness(t_sc_in), material)

#=
### Main insulation

XLPE (cross-linked polyethylene) is the standard insulation material for modern
medium and high voltage cables due to its excellent dielectric properties.
=#

# Add the insulation layer:
material = get_material(materials_db, "pe")
main_insu = Insulator(semicon_in, Thickness(t_ins), material)

#=
### Outer semiconductor

Similar to the inner semiconductor, the outer semiconductor provides a uniform
transition from insulation to the metallic screen.
=#

# Outer semiconductor (500 Ω.m as per IEC 840):
material = get_material(materials_db, "semicon2")
semicon_out = Semicon(main_insu, Thickness(t_sc_out), material)

# Outer semiconductive tape:
material = get_material(materials_db, "polyacrylate")
sc_tape_co = Semicon(semicon_out, Thickness(t_sct), material)

# Group all core-related components:
core_parts = [core, sctape_in, semicon_in, main_insu, semicon_out, sc_tape_co]

#=
With the core parts properly defined, the [`CableDesign`](@ref) object is initialized with nominal data from the datasheet. This includes voltage ratings and reference electrical parameters that will be used to benchmark the design.
=#

# Define the nominal values and instantiate the CableDesign with the core_parts:
cable_id = "tutorial2"
datasheet_info = NominalData(
	designation_code = "NA2XS(FL)2Y",
	U0 = 18.0,                        # Phase-to-ground voltage [kV]
	U = 30.0,                         # Phase-to-phase voltage [kV]
	conductor_cross_section = 1000.0, # [mm²]
	screen_cross_section = 35.0,      # [mm²]
	resistance = 0.0291,              # DC resistance [Ω/km]
	capacitance = 0.39,               # Capacitance [μF/km]
	inductance = 0.3,                 # Inductance in trifoil [mH/km]
)
cable_design =
	CableDesign(cable_id, "core", core_parts, nominal_data = datasheet_info)

# At this point, it becomes possible to preview the cable design:
plt1 = preview_cabledesign(cable_design)

# ## Sheath and PE jacket

#=
### Wire screens

The metallic screen (typically copper) serves multiple purposes:
- Provides a return path for fault currents.
- Ensures radial symmetry of the electric field.
- Acts as electrical shielding.
- Provides mechanical protection.
=#

# Build the wire screens on top of the previous layer:
lay_ratio = 10 # typical value for wire screens
material = get_material(materials_db, "copper")
wire_screen =
	Conductor(WireArray(sc_tape_co, Diameter(d_ws), num_sc_wires, lay_ratio, material))

# Add equalizing copper tape that wraps the wire screen:
addto_conductor!(wire_screen, Strip, Thickness(t_cut), w_cut, lay_ratio, material)

# Water blocking tape over screen:
material = get_material(materials_db, "polyacrylate")
wb_tape_scr = Semicon(wire_screen, Thickness(t_wbt), material)

# Group sheath components and assign to design:
sheath_parts = [wire_screen, wb_tape_scr]
addto_design!(cable_design, "sheath", sheath_parts)

# Examine the newly added components:
plt2 = preview_cabledesign(cable_design)

#=
### Outer jacket components

Modern cables often include an aluminum tape as moisture barrier
and PE (polyethylene) outer jacket for mechanical protection.
=#

# Add the aluminum foil (moisture barrier):
material = get_material(materials_db, "aluminum")
alu_tape = Conductor(Tubular(wb_tape_scr, Thickness(t_alt), material))

# PE layer after aluminum foil:
material = get_material(materials_db, "pe")
alu_tape_pe = Insulator(alu_tape, Thickness(t_pet), material)

# PE jacket (outer mechanical protection):
material = get_material(materials_db, "pe")
pe_insu = Insulator(alu_tape_pe, Thickness(t_jac), material)

# Group jacket components and assign to design:
jacket_parts = [alu_tape, alu_tape_pe, pe_insu]
addto_design!(cable_design, "jacket", jacket_parts)

# Inspect the finished cable design:
plt3 = preview_cabledesign(cable_design)

# ## Examining cable parameters (RLC)

#=
This section examines the cable design and compares calculated parameters with datasheet values. [`LineCableModels.jl`](@ref) provides several functions to analyze the design in different levels of detail.
=#

# Compare with datasheet information (R, L, C values):
core_df = cabledesign_todf(cable_design, :core)

# Obtain the equivalent electromagnetic properties of the cable:
components_df = cabledesign_todf(cable_design, :components)

# Get detailed description of all cable parts:
detailed_df = cabledesign_todf(cable_design, :detailed)

# ## Saving the cable design

#=
!!! note "Cables library"
	Designs can be saved to a library for future use. The [`CablesLibrary`](@ref) is a container for storing multiple cable designs, allowing for easy access and reuse in different projects.  Lirabry management is performed using the [`list_cables_library`](@ref), [`store_cables_library!`](@ref), and [`save_cables_library`](@ref) functions.
=#

# Store the cable design and inspect the library contents:
library = CablesLibrary()
store_cables_library!(library, cable_design)
list_cables_library(library)

# Save to file for later use:
output_path = joinpath(dirname(Base.source_path()), "src", "tutorials")
output_path = isdir(output_path) ? output_path : "."
output_file = joinpath(output_path, "cables_library.jls")
save_cables_library(library, file_name = output_file)
if isfile(output_file)
	println("\nMaterials library saved sucessfully!")
end
# ## Defining a cable system

#=
!!! note "Cables systems"
	A cable system is a collection of cables with defined positions, length and environmental characteristics. The [`LineCableSystem`](@ref) object is the main container for all cable systems, and it allows the definition of multiple cables in different configurations (e.g., trifoil, flat etc.). This object is the entry point for all system-related calculations and analyses.
=#

#=
### Earth model 

The earth return path significantly affects cable impedance calculations.
A frequency-dependent earth model with typical soil properties is defined.
=#

# Define a frequency-dependent earth model (10^0 to 10^6 Hz):
f = 10.0 .^ range(0, stop = 6, length = 10)  # Frequency range
earth_params = EarthModel(f, 100.0, 10.0, 1.0)  # 100 Ω·m resistivity, εr=10, μr=1

# Earth model base (DC) properties:
earth_data_df = earth_data(earth_params)

#=
### Three-phase system in trifoil configuration

This section creates a cable system with three identical cables arranged in a trifoil formation.
=#


# Define system center point (underground at 1 m depth) and the trifoil positions
x0 = 0
y0 = -1
xa, ya, xb, yb, xc, yc = trifoil_formation(x0, y0, 0.035)

# Initialize the LineCableSystem with the first cable (phase A):
cabledef = CableDef(cable_design, xa, ya, Dict("core" => 1, "sheath" => 0, "jacket" => 0))
cable_system = LineCableSystem("tutorial2", 20.0, earth_params, 1000.0, cabledef)

# Add remaining cables (phases B and C):
addto_system!(cable_system, cable_design, xb, yb,
	Dict("core" => 2, "sheath" => 0, "jacket" => 0),
)
addto_system!(
	cable_system, cable_design, xc, yc,
	Dict("core" => 3, "sheath" => 0, "jacket" => 0),
)

#=
!!! note "Phase mapping"
	The [`addto_system!`](@ref) function allows the specification of phase mapping for each cable. The `Dict` argument maps the cable components to their respective phases, where `core` is the conductor, `sheath` is the screen, and `jacket` is the outer jacket. The values (1, 2, 3) represent the phase numbers (A, B, C) in this case. Components mapped to phase 0 will be Kron-eliminated (grounded). Components set to the same phase will be bundled into an equivalent phase.
=#

# ### Cable system preview
#
# This section examines the complete three-phase cable system.

# Display system details:
system_df = linecablesystem_todf(cable_system)

# Visualize the cross-section of the three-phase system:
plt4 = preview_linecablesystem(cable_system, zoom_factor = 0.15)

# ## PSCAD Export
#
# The final step exports the model for electromagnetic transient simulations in PSCAD.

# Export to PSCAD input file
export_file = export_pscad_lcp(cable_system, folder_path = output_path)
if isfile(export_file)
	println("\nFile created sucessfully!")
end

# ## Conclusion
#=
This tutorial has demonstrated how to:

1. Create a detailed model of a complex power cable with multiple concentric layers.
2. Calculate and analyze the cable base parameters (R, L, C).
3. Design a three-phase cable system in trifoil arrangement.
4. Export the model for further analysis in specialized software.

[`LineCableModels.jl`](@ref) provides a powerful framework for accurate power cable modeling
with a physically meaningful representation of all cable components. This approach
ensures that electromagnetic parameters are calculated with high precision. Now you can go ahead and run these cable simulations like a boss! 
=#