#=
# Tutorial 3 - Computing line parameters

This case file demonstrates how to model an armored high-voltage single-core power cable 
using the [`LineCableModels.jl`](@ref) package. The objective is to build a complete representation of a single-core 525 kV cable with a 1600 mm² copper conductor, 1.2 mm tubular lead sheath and 68 x 6 mm galvanized steel armor, based on the design described in [Karmokar2025](@cite).
=#

#=
**Tutorial outline**
```@contents
Pages = [
	"tutorial3.md",
]
Depth = 2:3
```
=#

#=
## Introduction
HVDC cables are constructed around a central conductor enclosed by a triple-extruded insulation system (inner/outer semi-conductive layers and main insulation). A metallic screen and protective outer sheath are then applied for land cables. Subsea designs add galvanized steel wire armor over this structure to provide mechanical strength against water pressure. A reference design for a 525 kV HVDC cable [is shown here](https://nkt.widen.net/content/pnwgwjfudf/pdf/Extruded_DC_525kV_DS_EN_DEHV_HV_DS_DE-EN.pdf).
=#

#=
## Getting started
=#

# Load the package and set up the environment:
push!(LOAD_PATH, joinpath(@__DIR__, "..", "src")) # hide
using DataFrames
using LineCableModels

# Initialize materials library with default values:
materials_db = MaterialsLibrary(add_defaults=true)

# Include the required materials for this design:
lead = Material(21.4e-8, 1.0, 0.999983, 20.0, 0.00400) # Lead or lead alloy
store_materialslibrary!(materials_db, "lead", lead)
steel = Material(13.8e-8, 1.0, 300.0, 20.0, 0.00450) # Steel
store_materialslibrary!(materials_db, "steel", steel)
pp = Material(1e15, 2.8, 1.0, 20.0, 0.0) # Laminated paper propylene
store_materialslibrary!(materials_db, "pp", pp)

# Inspect the contents of the materials library:
list_materialslibrary(materials_db)

#=
## Cable dimensions

The cable under consideration is a high-voltage, stranded copper conductor cable with XLPE insulation, water-blocking tape, lead tubular screens, PE inner sheath, PP bedding, steel armor and PP jacket, rated for 525 kV HVDC systems. This information is typically found in the cable datasheet and is based on the design studied in [Karmokar2025](@cite).

The cable is found to have the following configuration:
=#

num_co_wires = 127 # number of core wires
num_ar_wires = 68  # number of armor wires
d_core = 0.0463    # nominal core overall diameter
d_w = 3.6649e-3    # nominal strand diameter of the core (minimum value to match datasheet)
t_sc_in = 2e-3     # nominal internal semicon thickness 
t_ins = 26e-3      # nominal main insulation thickness
t_sc_out = 1.8e-3  # nominal external semicon thickness
t_wbt = .3e-3      # nominal thickness of the water blocking tape
t_sc = 3.3e-3      # nominal lead screen thickness
t_pe = 3e-3        # nominal PE inner sheath thickness
t_bed = 3e-3       # nominal thickness of the PP bedding
d_wa = 5.827e-3    # nominal armor wire diameter
t_jac = 10e-3      # nominal PP jacket thickness

d_overall = d_core # hide
layers = [] # hide
push!(layers, ("Conductor", missing, d_overall * 1000)) # hide
d_overall += 2 * t_sc_in # hide
push!(layers, ("Inner semiconductor", t_sc_in * 1000, d_overall * 1000)) # hide
d_overall += 2 * t_ins # hide
push!(layers, ("Main insulation", t_ins * 1000, d_overall * 1000)) # hide
d_overall += 2 * t_sc_out # hide
push!(layers, ("Outer semiconductor", t_sc_out * 1000, d_overall * 1000)) # hide
d_overall += 2 * t_wbt # hide
push!(layers, ("Swellable tape", t_wbt * 1000, d_overall * 1000)) # hide
d_overall += 2 * t_sc # hide
push!(layers, ("Lead screen", t_sc * 1000, d_overall * 1000)) # hide
d_overall += 2 * t_pe # hide
push!(layers, ("PE inner sheath", t_pe * 1000, d_overall * 1000)) # hide
d_overall += 2 * t_bed # hide
push!(layers, ("PP bedding", t_bed * 1000, d_overall * 1000)) # hide
d_overall += 2 * d_wa # hide
push!(layers, ("Stranded wire armor", d_wa * 1000, d_overall * 1000)) # hide
d_overall += 2 * t_jac # hide
push!(layers, ("PP jacket", t_jac * 1000, d_overall * 1000)); # hide


# The cable structure is summarized in a table for better visualization, with dimensions in milimiters:
df = DataFrame( # hide
    layer=first.(layers), # hide
    thickness=[ # hide
        ismissing(t) ? "-" : round(t, sigdigits=2) for t in getindex.(layers, 2) # hide
    ], # hide
    diameter=[round(d, digits=2) for d in getindex.(layers, 3)], # hide
) # hide

#=
## Core and main insulation

Initialize the conductor object and assign the central wire:
=#

material = get_material(materials_db, "copper")
n = 6
core = ConductorGroup(WireArray(0, Diameter(d_w), 1, 0, material))

# Add the subsequent layers of wires and inspect the object:
addto_conductorgroup!(core, WireArray, Diameter(d_w), 1 * n, 11, material)
addto_conductorgroup!(core, WireArray, Diameter(d_w), 2 * n, 11, material)
addto_conductorgroup!(core, WireArray, Diameter(d_w), 3 * n, 11, material)
addto_conductorgroup!(core, WireArray, Diameter(d_w), 4 * n, 11, material)
addto_conductorgroup!(core, WireArray, Diameter(d_w), 5 * n, 11, material)
addto_conductorgroup!(core, WireArray, Diameter(d_w), 6 * n, 11, material)

#=
### Inner semiconductor

Inner semiconductor (1000 Ω.m as per IEC 840):
=#

material = get_material(materials_db, "semicon1")
main_insu = InsulatorGroup(Semicon(core, Thickness(t_sc_in), material))

#=
### Main insulation

Add the insulation layer:
=#

material = get_material(materials_db, "pe")
addto_insulatorgroup!(main_insu, Insulator, Thickness(t_ins), material)

#=
### Outer semiconductor

Outer semiconductor (500 Ω.m as per IEC 840):
=#

material = get_material(materials_db, "semicon2")
addto_insulatorgroup!(main_insu, Semicon, Thickness(t_sc_out), material)

# Water blocking (swellable) tape:
material = get_material(materials_db, "polyacrylate")
addto_insulatorgroup!(main_insu, Semicon, Thickness(t_wbt), material)

# Group core-related components:
core_cc = CableComponent("core", core, main_insu)

cable_id = "525kV_1600mm2"
datasheet_info = NominalData(
    designation_code="(N)2XH(F)RK2Y",
    U0=500.0,                        # Phase (pole)-to-ground voltage [kV]
    U=525.0,                         # Phase (pole)-to-phase (pole) voltage [kV]
    conductor_cross_section=1600.0,  # [mm²]
    screen_cross_section=1000.0,     # [mm²]
    resistance=NaN,                  # DC resistance [Ω/km]
    capacitance=NaN,                 # Capacitance [μF/km]
    inductance=NaN,                  # Inductance in trifoil [mH/km]
)
cable_design = CableDesign(cable_id, core_cc, nominal_data=datasheet_info)

# At this point, it becomes possible to preview the cable design:
plt1 = preview_cabledesign(cable_design)

#=
### Lead screen/sheath

Build the wire screens on top of the previous layer:
=#

material = get_material(materials_db, "lead")
screen_con =
    ConductorGroup(Tubular(main_insu, Thickness(t_sc), material))

# PE inner sheath:
material = get_material(materials_db, "pe")
screen_insu = InsulatorGroup(Insulator(screen_con, Thickness(t_pe), material))

# PP bedding:
material = get_material(materials_db, "pp")
addto_insulatorgroup!(screen_insu, Insulator, Thickness(t_bed), material)

# Group sheath components and assign to design:
sheath_cc = CableComponent("sheath", screen_con, screen_insu)
addto_cabledesign!(cable_design, sheath_cc)

# Examine the newly added components:
plt2 = preview_cabledesign(cable_design)

#=
### Armor and outer jacket components

=#

# Add the armor wires on top of the previous layer:
lay_ratio = 10 # typical value for wire screens
material = get_material(materials_db, "steel")
armor_con =
    ConductorGroup(WireArray(screen_insu, Diameter(d_wa), num_ar_wires, lay_ratio, material))

# PP layer after armor:
material = get_material(materials_db, "pp")
armor_insu = InsulatorGroup(Insulator(armor_con, Thickness(t_jac), material))

# Assign the armor parts directly to the design:
addto_cabledesign!(cable_design, "armor", armor_con, armor_insu)

# Inspect the finished cable design:
plt3 = preview_cabledesign(cable_design)

#=
## Examining the cable parameters (RLC)

In this section, the cable design is examined and the calculated parameters are compared with datasheet values. [`LineCableModels.jl`](@ref) provides methods to analyze the design in different levels of detail.
=#

# Summarize DC lumped parameters (R, L, C):
core_df = cabledesign_todf(cable_design, :baseparams)
display(core_df)

# Obtain the equivalent electromagnetic properties of the cable:
components_df = cabledesign_todf(cable_design, :components)
display(components_df)

#=
## Saving the cable design

Load an existing [`CablesLibrary`](@ref) file or create a new one:
=#


library = CablesLibrary()
library_file = joinpath(@__DIR__, "cables_library.json")
load_cableslibrary!(library, file_name=library_file)
store_cableslibrary!(library, cable_design)
list_cableslibrary(library)

# Save to file for later use:

save_cableslibrary(library, file_name=library_file);

#=
### Defining a cable system

=#

#=
### Earth model 

Define a frequency-dependent earth model (1 Hz to 1 MHz):
=#

f = 10.0 .^ range(0, stop=6, length=10)  # Frequency range
earth_params = EarthModel(f, 100.0, 10.0, 1.0)  # 100 Ω·m resistivity, εr=10, μr=1

# Earth model base (DC) properties:
earthmodel_df = earthmodel_todf(earth_params)
display(earthmodel_df)

#=
### Underground bipole configuration

=#

xp = -0.5
xn = 0.5
y0 = -1.0

# Initialize the `LineCableSystem` with positive pole:
cablepos = CablePosition(cable_design, xp, y0, Dict("core" => 1, "sheath" => 0, "armor" => 0))
cable_system = LineCableSystem("525kV_1600mm2_bipole", 1000.0, cablepos)

# Add remaining cables (phases B and C):
addto_linecablesystem!(cable_system, cable_design, xn, y0,
    Dict("core" => 2, "sheath" => 0, "armor" => 0),
)

#=
### Cable system preview

In this section the complete bipole cable system is examined.
=#

# Display system details:
system_df = linecablesystem_todf(cable_system)
display(system_df)

# Visualize the cross-section of the three-phase system:
plt4 = preview_linecablesystem(cable_system, zoom_factor=0.15)

#=
## PSCAD export

The final step showcases how to export the model for electromagnetic transient simulations in PSCAD.

=#

# Export to PSCAD input file:
output_file = joinpath(@__DIR__, "$(cable_system.system_id)_export.pscx")
export_file = export_pscad_lcp(cable_system, earth_params, file_name=output_file);

#=
## FEM calculations

=#

# Define a LineParametersProblem with the cable system and earth model
f = 1e-3
problem = LineParametersProblem(
    cable_system,
    temperature=20.0,  # Operating temperature
    earth_props=earth_params,
    frequencies=[f],  # Frequency for the analysis
)

# Create a FEMFormulation with custom mesh definitions
skin_depth_earth = abs(sqrt(earth_params.layers[end].rho_g[1] / (1im * (2 * pi * f[1]) * earth_params.layers[end].mu_g[1])))
domain_radius = clamp(skin_depth_earth, 5.0, 5000.0)

mesh_transition1 = MeshTransition(
    cable_system,
    [1],
    r_min=0.0,
    r_length=0.25,
    mesh_factor_min=0.01 / (domain_radius / 5),
    mesh_factor_max=0.25 / (domain_radius / 5),
    n_regions=5
)

mesh_transition2 = MeshTransition(
    cable_system,
    [2],
    r_min=0.0,
    r_length=0.25,
    mesh_factor_min=0.01 / (domain_radius / 5),
    mesh_factor_max=0.25 / (domain_radius / 5),
    n_regions=5
)

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
    mesh_transitions=[mesh_transition1, mesh_transition2],
    mesh_size_default=domain_radius / 10,
    mesh_algorithm=5,
    mesh_max_retries=20,
    materials_db=materials_db
)

# Define runtime FEMOptions 
opts = FEMOptions(
    force_remesh=true,  # Force remeshing
    force_overwrite=true,
    plot_field_maps=false,
    mesh_only=false,  # Preview the mesh
    base_path=joinpath(@__DIR__, "fem_output"),
    keep_run_files=true,  # Archive files after each run
    verbosity=2,  # Verbose output
)

# Run the FEM model
@time workspace, line_params = compute!(problem, formulation, opts)

if !opts.mesh_only
    println("\nR = $(round(real(line_params.Z[1,1,1])*1000, sigdigits=4)) Ω/km")
    println("L = $(round(imag(line_params.Z[1,1,1])/(2π*f)*1e6, sigdigits=4)) mH/km")
    println("C = $(round(imag(line_params.Y[1,1,1])/(2π*f)*1e9, sigdigits=4)) μF/km")
end