#=
# Tutorial 4 Case 4 - Magnetothermal Analysis of a 33 kV Trefoil Cable (CIGRE TB 880 Case 4)

This case file demonstrates how to model a medium-voltage single-core 33 kV cable with a
240 mm² copper conductor and copper wire screen in a trefoil arrangement, and to perform
magnetothermal FEM analysis using the [`LineCableModels.jl`](@ref) package. The cable design
and arrangement are based on CIGRE Technical Brochure 880, Case Study 4.

The system operates at 50 Hz with both-side bonding of screens (solidly grounded).
=#

#=
## Getting started
=#

# Load the package and set up the environment:
using Revise
using LineCableModels
using LineCableModels.Engine.IEC60287
using DataFrames
using Printf
fullfile(filename) = joinpath(@__DIR__, filename); #hide
set_verbosity!(1); #hide
set_backend!(:gl); #hide


ENV["JULIA_DEBUG"] = "LineCableModels,LineCableModels.Engine.IEC60287"


# Initialize materials library with default values:
materials = MaterialsLibrary(add_defaults = true)
materials_df = DataFrame(materials) 

#=
## Cable dimensions

The cable under consideration is a medium-voltage, 33 kV, stran	ded copper conductor cable
with XLPE insulation, copper wire screen, water-blocking tapes, and HDPE jacket. The cable
design parameters are taken from CIGRE Technical Brochure 880, Case Study 4.

The cable has the following configuration:
=#

#num_co_wires = 91    # number of core wires (1+6+12+18+24+30)
num_sc_wires = 56    # number of screen wires
d_core = 18.4e-3     # nominal core overall diameter [m]
core_n_strands = 6   # number of strands in each layer of the core (1/6/12/18/24/30)
core_n_layers = 4   # number of layers in the core (1/6/12/18/24/30)
d_w = 18.4e-3/(2*(core_n_layers+0.5))        # nominal wire diameter of the core [m]
t_cs = 0.5e-3        # nominal conductor shield (inner semicon) thickness [m]
t_ins = 7.7e-3       # nominal main insulation (XLPE) thickness [m]
t_is = 0.5e-3        # nominal insulation screen (outer semicon) thickness [m]
t_scb = 0.5e-3       # nominal screen bedding thickness (water-blocking tape) [m]
d_ws = 0.9e-3        # nominal screen wire diameter [m]
t_scs = 0.3e-3       # nominal screen serving thickness (water-blocking tape) [m]
t_j = 2.2e-3         # nominal jacket (HDPE) thickness [m]
t_jj = 0.2e-3        # nominal additional jacket layer thickness [m]




#

d_overall = d_core #hide
layers = [] #hide
push!(layers, ("Conductor", missing, d_overall * 1000)) #hide
d_overall += 2 * t_cs #hide
push!(layers, ("Conductor shield", t_cs * 1000, d_overall * 1000)) #hide
d_overall += 2 * t_ins #hide
push!(layers, ("Main insulation (XLPE)", t_ins * 1000, d_overall * 1000)) #hide
d_overall += 2 * t_is #hide
push!(layers, ("Insulation screen", t_is * 1000, d_overall * 1000)) #hide
d_overall += 2 * t_scb #hide
push!(layers, ("Screen bedding", t_scb * 1000, d_overall * 1000)) #hide
d_overall += 2 * d_ws #hide
push!(layers, ("Wire screen", d_ws * 1000, d_overall * 1000)) #hide
d_overall += 2 * t_scs #hide
push!(layers, ("Screen serving", t_scs * 1000, d_overall * 1000)) #hide
d_overall += 2 * t_j #hide
push!(layers, ("HDPE jacket", t_j * 1000, d_overall * 1000)) #hide
d_overall += 2 * t_jj #hide
push!(layers, ("Additional jacket layer", t_jj * 1000, d_overall * 1000)); #hide

# The cable structure is summarized in a table for better visualization, with dimensions in millimeters:
df = DataFrame( #hide
	layer = first.(layers), #hide
	thickness = [ #hide
		ismissing(t) ? "-" : round(t, sigdigits = 2) for t in getindex.(layers, 2) #hide
	], #hide
	diameter = [round(d, digits = 2) for d in getindex.(layers, 3)], #hide
) #hide

#=
## Core and main insulation

The conductor consists of 91 copper round stranded wires arranged in a standard
(1/6/12/18/24/30) pattern. Initialize the conductor object and assign the central wire:
=#

# Compute effective resistivity to match the target DC resistance from the datasheet.
# R_dc = ρ / A  →  ρ = R_dc × A,  where A is the wire-model total conductor cross-section.
n_total_wires = 1 + sum(i * core_n_strands for i in 1:core_n_layers)
A_wire_total  = n_total_wires * π * (d_w / 2)^2
R_dc_20_target = 0.0754e-3                         # [Ω/m] (0.0754 Ω/km from datasheet)
rho_eff = R_dc_20_target * A_wire_total

case_4_core_copper = Material(rho_eff, 1.0, 0.999994, 20.0, 0.00393, 0.0025, 90.0)

core = ConductorGroup(WireArray(0.0, Diameter(d_w), 1, 0.0, case_4_core_copper))

# Add the subsequent layers of wires:
for i in 1:core_n_layers
	add!(core, WireArray, Diameter(d_w), i * core_n_strands, 11.0, case_4_core_copper)
end
core

#=
### Conductor shield (inner semiconductor)

Conductor shield (1000 Ω.m as per IEC 840):
=#

material = get(materials, "semicon1")
main_insu = InsulatorGroup(Semicon(core, Thickness(t_cs), material))

#=
### Main insulation (XLPE)

Add the XLPE insulation layer (εr = 2.5):
=#

material = get(materials, "xlpe")
add!(main_insu, Insulator, Thickness(t_ins), material)

#=
### Insulation screen (outer semiconductor)

Outer semiconductor (500 Ω.m as per IEC 840):
=#

material = get(materials, "semicon2")
add!(main_insu, Semicon, Thickness(t_is), material)

# Screen bedding (water-blocking semi-conducting tape):
material = get(materials, "polyacrylate")
add!(main_insu, Semicon, Thickness(t_scb), material)

# Group core-related components:
core_cc = CableComponent("core", core, main_insu)

cable_id = "33kV_240mm2"
datasheet_info = NominalData(
	designation_code = "CIGRE_TB_880_Case_4",
	U0 = 19.0,                        # Phase-to-ground voltage [kV] (33/√3 ≈ 19.05)
	U = 33.0,                          # Phase-to-phase voltage [kV]
	conductor_cross_section = 240.0,   # [mm²]
	screen_cross_section = 35.63,      # [mm²]
	resistance = 0.0754,               # DC resistance at 20°C [Ω/km]
	capacitance = 0.2377,              # Capacitance [μF/km]
	inductance = 0.3642,               # Inductance [mH/km]
	conductor_diameter = 18.4,         # Nominal conductor diameter [mm]
	overall_diameter = 44.0,           # Nominal overall cable diameter [mm]
)
cable_design = CableDesign(cable_id, core_cc, nominal_data = datasheet_info)

#=
### Copper wire screen

The screen consists of 56 copper round wires of 0.9 mm diameter with a lay length of
240 mm (lay ratio ≈ 6.4, based on L_lay/d_sc = 240/37.7).
=#

lay_ratio_sc = 6.4
material = get(materials, "copper")
screen_con = ConductorGroup(
	WireArray(main_insu, Diameter(d_ws), num_sc_wires, lay_ratio_sc, material))

# Screen serving (water-blocking tape):
material = get(materials, "polyacrylate")
screen_insu = InsulatorGroup(Semicon(screen_con, Thickness(t_scs), material))

# HDPE jacket:
material = get(materials, "pe")
add!(screen_insu, Insulator, Thickness(t_j), material)

# Additional jacket layer (ρ_thermal = 2.5 K.m/W per CIGRE TB 880):
material_jj = Material(1.97e14, 2.3, 1.0, 20.0, 0.0, 2.5, 70.0)
add!(screen_insu, Insulator, Thickness(t_jj), material_jj)

# Group sheath components and assign to design:
sheath_cc = CableComponent("sheath", screen_con, screen_insu)
add!(cable_design, sheath_cc)

# # Inspect the finished cable design:
plt1, _ = preview(cable_design)
plt1 #hide

#=
## Examining the cable parameters (RLC)

=#

# Summarize DC lumped parameters (R, L, C):
core_df = DataFrame(cable_design, :baseparams)

# Obtain the equivalent electromagnetic properties of the cable:
components_df = DataFrame(cable_design, :components)

preview(cable_design) #hide


#=
## Saving the cable design

Load an existing [`CablesLibrary`](@ref) file or create a new one:
=#

library = CablesLibrary()
add!(library, cable_design)
library_df = DataFrame(library)

# Save to file for later use:
library_file = fullfile("cables_library_case4.json")
save(library, file_name = library_file);

#=
## Defining a cable system

=#

#=
### Earth model

Define the earth model. The CIGRE TB 880 Case 4 specifies:
- Soil thermal resistivity: 1.0 K.m/W (thermal conductivity = 1.0 W/(m.K))
- Ambient temperature: 20°C
=#

f = [50.0]  # System frequency [Hz]

# Earth model — homogeneous soil (ρ_thermal = 1.0 K.m/W, θ_ambient = 20 °C):
earth_params = EarthModel(f, 100.0, 10.0, 1.0)   # electrical props ρ_g, ε_r, μ_r (defaults thermal)
earthmodel_df = DataFrame(earth_params)

#=
### Trefoil configuration

The three cables are arranged in a touching trefoil formation at 1.0 m burial depth,
matching the CIGRE TB 880 Case 4 arrangement. The outer diameter of each cable is 44 mm
and the mean distance between phase centers is 44 mm (touching trefoil).
=#

x0, y0 = 0.0, -1.0
# Use actual cable outer radius + tiny clearance to avoid floating-point overlap detection
r_ext = cable_design.components[end].insulator_group.radius_ext

xa, ya, xb, yb, xc, yc = trifoil_formation(x0, y0, (r_ext + 1e-6))

# Initialize the `LineCableSystem` with phase A (top position):
cablepos = CablePosition(cable_design, xa, ya,
	Dict("core" => 1, "sheath" => 0))
cable_system = LineCableSystem("33kV_240mm2_trefoil", 1000.0, cablepos)

# Add phase B (bottom-left):
add!(cable_system, cable_design, xb, yb,
	Dict("core" => 2, "sheath" => 0))

# Add phase C (bottom-right):
add!(cable_system, cable_design, xc, yc,
	Dict("core" => 3, "sheath" => 0))

#=
### Cable system preview

In this section the complete trefoil cable system is examined.
=#

# Display system details:
system_df = DataFrame(cable_system)

# Visualize the cross-section of the three-phase system:
plt2, _ = preview(cable_system, zoom_factor = 2.0)
plt2 #hide

#=
## IEC 60287 Ampacity Calculation

Compute the steady-state continuous current rating using the IEC 60287 analytical
formulation. The solver iteratively determines the conductor current at which the
maximum conductor temperature reaches θ_max = 90 °C.
=#

ambient_temperature = 20.0  # Ambient temperature [°C]

# Define the ampacity problem:
problem = AmpacityProblem(ambient_temperature, cable_system, earth_params)

# Define the IEC 60287 formulation with solid bonding:
F = IEC60287Formulation(bonding_type = :solid, solar_radiation = false)

# Solve for ampacity:
results = compute_ampacity(problem, F)

# Extract results for the cable:
r = results[cable_id]

#=
## Results Summary

Print all intermediate values for validation against CIGRE TB 880 Case 4.
=#

println("=" ^72)
println("  IEC 60287 Ampacity — CIGRE TB 880 Case 4 (33 kV Trefoil)")
println("=" ^72)

println("\n── Cable Geometry ──")
@printf("  Conductor diameter    Dc    = %.1f mm\n", r.Dc * 1e3)
@printf("  Cable outer diameter  De    = %.1f mm\n", r.De_cable * 1e3)
@printf("  Conductor spacing     s     = %.1f mm\n", r.s * 1e3)

println("\n── DC Resistance ──")
@printf("  R_dc(20 °C)  = %.4e Ω/m  →  %.4f Ω/km\n", r.R_dc_20, r.R_dc_20 * 1e3)
@printf("  R_dc(90 °C)  = %.4e Ω/m\n", r.R_dc_theta)

println("\n── AC Resistance ──")
@printf("  Skin effect    y_s = %.5f\n", r.y_s)
@printf("  Proximity      y_p = %.5f\n", r.y_p)
@printf("  R_ac(90 °C)   = %.4e Ω/m  →  %.4f Ω/km\n", r.R_ac, r.R_ac * 1e3)

println("\n── Dielectric Losses ──")
@printf("  U_e (phase-to-earth) = %.2f V\n", r.U_e)
@printf("  C_b (capacitance)    = %.3e F/m  →  %.4f μF/km\n", r.C_cable, r.C_cable * 1e9)
@printf("  W_d = %.4f W/m\n", r.Wd)

println("\n── Thermal Resistances ──")
@printf("  T1' (uncorrected)   = %.4f K.m/W\n", r.T1_prime)
@printf("  T1  (× %.2f)        = %.4f K.m/W\n", r.T1_correction, r.T1)
@printf("  T2                  = %.4f K.m/W\n", r.T2)
@printf("  T3' (uncorrected)   = %.4f K.m/W\n", r.T3_prime)
@printf("  T3  (× %.1f)        = %.4f K.m/W\n", r.T3_correction, r.T3)
@printf("  T4  (trefoil)       = %.4f K.m/W\n", r.T4)

println("\n── Screen / Sheath ──")
@printf("  Screen d_mean       = %.1f mm\n", r.d_mean_screen * 1e3)
@printf("  Lay factor LF_s     = %.4f\n", r.LF_s)
@printf("  R_s (screen, θ_s)   = %.4e Ω/m\n", r.R_s)
@printf("  X_s (screen react.)  = %.4e Ω/m\n", r.X_s)
@printf("  λ₁ (sheath loss)    = %.4f\n", r.lambda1)
@printf("  λ₂ (armour loss)    = %.4f\n", r.lambda2)

println("\n── Temperatures ──")
@printf("  θ_c  (conductor)    = %.2f °C\n", r.theta_c)
@printf("  θ_s  (screen)       = %.2f °C\n", r.theta_s)
@printf("  θ_e  (external)     = %.2f °C\n", r.theta_e)
@printf("  θ_amb (ambient)     = %.2f °C\n", r.theta_amb)

println("\n── Losses at Rated Current ──")
@printf("  W_c  (conductor)    = %.3f W/m\n", r.Wc)
@printf("  W_s  (screen)       = %.3f W/m\n", r.Ws)
@printf("  W_d  (dielectric)   = %.3f W/m\n", r.Wd)
@printf("  W_t  (total/phase)  = %.3f W/m\n", r.Wt)
@printf("  W_sys (total system) = %.3f W/m\n", r.Wsys)

println("\n" * "=" ^72)
@printf("  ★ RATED CURRENT  I_c = %.2f A  (Reference: 537.46 A)\n", r.I_rated)
println("=" ^72)

#=
## Validation

Compare key intermediate values against the CIGRE TB 880 Case 4 reference solution.
=#

ref = (
	I_c     = 537.46,
	R_dc    = 9.6143e-5,
	R_ac    = 9.7629e-5,
	y_s     = 0.00884,
	y_p     = 0.00662,
	T1      = 0.411,
	T3      = 0.1242,
	T4      = 1.8525,
	lambda1 = 0.0435,
	Wc      = 28.202,
	Wd      = 0.108,
	Wsys    = 88.612,
	theta_s = 78.39,
	theta_e = 74.72,
)

println("\n── Validation vs. CIGRE TB 880 ──")
@printf("  I_c :  %.2f A  vs  %.2f A   (Δ = %.2f A)\n", r.I_rated, ref.I_c, r.I_rated - ref.I_c)
@printf("  R_dc:  %.4e  vs  %.4e\n", r.R_dc_theta, ref.R_dc)
@printf("  R_ac:  %.4e  vs  %.4e\n", r.R_ac, ref.R_ac)
@printf("  y_s :  %.5f  vs  %.5f\n", r.y_s, ref.y_s)
@printf("  y_p :  %.5f  vs  %.5f\n", r.y_p, ref.y_p)
@printf("  T1  :  %.4f  vs  %.4f\n", r.T1, ref.T1)
@printf("  T3  :  %.4f  vs  %.4f\n", r.T3, ref.T3)
@printf("  T4  :  %.4f  vs  %.4f\n", r.T4, ref.T4)
@printf("  λ₁  :  %.4f  vs  %.4f\n", r.lambda1, ref.lambda1)
@printf("  W_c :  %.3f  vs  %.3f\n", r.Wc, ref.Wc)
@printf("  W_d :  %.4f  vs  %.3f\n", r.Wd, ref.Wd)
@printf("  Wsys:  %.3f  vs  %.3f\n", r.Wsys, ref.Wsys)
@printf("  θ_s :  %.2f  vs  %.2f\n", r.theta_s, ref.theta_s)
@printf("  θ_e :  %.2f  vs  %.2f\n", r.theta_e, ref.theta_e)
println()
