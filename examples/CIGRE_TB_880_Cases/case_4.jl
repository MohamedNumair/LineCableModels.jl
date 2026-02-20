# TODO: MAKE ALL FUNCTION TAKE NAMED ARGUMENTS STOP AMBIGUITY !!!

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
earth_params = EarthModel(f, 100.0, 10.0, 1.0, 1.0)   # electrical props ρ_g, ε_r, μ_r (defaults thermal)
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



	ambient_temperature = 20 # Ambient temperature [°C]

	# Define the ampacity problem:
	#problem = AmpacityProblem(ambient_temperature, cable_system, earth_params)
	prob = AmpacityProblem(
    20.0, 
    cable_system, 
    earth_params;
    frequency = 50.0, 
    voltage_phase_to_phase = 33.0*1e3,
)
	# Define the IEC 60287 formulation with solid bonding:
	F = IEC60287Formulation(bonding_type = :solid, solar_radiation = false)

	# Solve for ampacity:
	results = compute!(prob, F)

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
	@printf("  ★ RATED CURRENT  I_c = %.5f A  (Reference: 537.46 A)\n", r.I_rated)
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
	@printf("  I_c :  %.4f A  vs  %.4f A   (Δ = %.2f A)\n", r.I_rated, ref.I_c, r.I_rated - ref.I_c)
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



# #=
# ═══════════════════════════════════════════════════════════════════════════════
# ## Part 2: Dynamic Cable Rating (DCR) — Transient Thermal Analysis

# This section builds a lumped-parameter transient thermal model from the
# IEC 60287 steady-state results and cable geometry, following the IEC 60853-2
# two-loop CIGRE approach extended to a three-node RC ladder.

# The model enables:
# - Forward simulation:  given I(t), θ_amb(t)  →  θ_c(t), θ_s(t), θ_e(t)
# - Dynamic rating:      compute I_max(t) s.t. θ_c(t) ≤ θ_max
# - Comparison of Static Thermal Rating (STR) vs Dynamic Cable Rating (DCR)
# ═══════════════════════════════════════════════════════════════════════════════ =#

# # ──────────────────────────────────────────────────────────────────────────────
# # 2.1  Material volumetric heat capacities  cᵥ = ρ_mass × c_p  [J/(m³·K)]
# #      (IEC 60853-2 Table 1 and standard engineering references)
# # ──────────────────────────────────────────────────────────────────────────────

# cv_copper       = 3.45e6   # copper (conductor + screen wires)
# cv_xlpe         = 2.40e6   # cross-linked polyethylene insulation
# cv_pe           = 2.40e6   # polyethylene / HDPE jacket
# cv_semicon      = 2.40e6   # semiconductive compound (≈ polymer matrix)
# cv_polyacrylate = 2.50e6   # water-blocking tapes

# # ──────────────────────────────────────────────────────────────────────────────
# # 2.2  Cable layer radii, areas, and thermal capacitances
# # ──────────────────────────────────────────────────────────────────────────────

# # Layer outer radii [m]  (reconstructed from dimensions defined above)
# r_co  = d_core / 2                  # conductor
# r_cs  = r_co  + t_cs               # inner semicon
# r_ins = r_cs  + t_ins              # XLPE insulation
# r_is  = r_ins + t_is               # outer semicon
# r_scb = r_is  + t_scb              # screen bedding
# r_scw = r_scb + d_ws               # screen wire layer
# r_scs = r_scw + t_scs              # screen serving
# r_jkt = r_scs + t_j                # HDPE jacket
# r_jj  = r_jkt + t_jj              # additional jacket

# # Cross-sectional areas [m²]
# A_conductor      = π * r_co^2
# A_inner_semicon  = π * (r_cs^2  - r_co^2)
# A_insulation     = π * (r_ins^2 - r_cs^2)
# A_outer_semicon  = π * (r_is^2  - r_ins^2)
# A_screen_bedding = π * (r_scb^2 - r_is^2)
# A_screen_wires   = num_sc_wires * π * (d_ws / 2)^2     # actual Cu area
# A_screen_serving = π * (r_scs^2 - r_scw^2)
# A_jacket_hdpe    = π * (r_jkt^2 - r_scs^2)
# A_jacket_add     = π * (r_jj^2  - r_jkt^2)

# # Thermal capacitance per unit length  Q = cᵥ × A  [J/(m·K)]
# Q_co   = cv_copper       * A_conductor
# Q_cs   = cv_semicon      * A_inner_semicon
# Q_xlpe = cv_xlpe         * A_insulation
# Q_is   = cv_semicon      * A_outer_semicon
# Q_scb  = cv_polyacrylate * A_screen_bedding
# Q_scw  = cv_copper       * A_screen_wires
# Q_scs  = cv_polyacrylate * A_screen_serving
# Q_jkt  = cv_pe           * A_jacket_hdpe
# Q_jj   = cv_pe           * A_jacket_add

# # ──────────────────────────────────────────────────────────────────────────────
# # 2.3  Van Wormer coefficient and three-node allocation
# # ──────────────────────────────────────────────────────────────────────────────

# #=
# The Van Wormer coefficient distributes the insulation thermal capacitance
# between the conductor (inner) node and the sheath (outer) node of the
# lumped RC ladder:

#     p = 1 / (2 ln(r_out/r_in))  −  1 / ((r_out/r_in)² − 1)

# Applied here to the main dielectric from conductor shield to screen bedding.
# =#

# ratio_ins = r_ins / r_cs
# p_vw = 1.0 / (2.0 * log(ratio_ins)) - 1.0 / (ratio_ins^2 - 1.0)

# # Lump all dielectric-side thermal capacitance
# Q_dielectric = Q_cs + Q_xlpe + Q_is + Q_scb

# # Three-node allocation:
# #   Node 1 (conductor):  conductor mass  +  inner fraction of insulation
# #   Node 2 (sheath):     outer fraction of insulation  +  screen copper  +  serving
# #   Node 3 (surface):    jacket layers
# Q_node1 = Q_co + p_vw * Q_dielectric
# Q_node2 = (1.0 - p_vw) * Q_dielectric + Q_scw + Q_scs
# Q_node3 = Q_jkt + Q_jj

# # Thermal resistances from IEC 60287 results [K·m/W]
# T_R1  = r.T1                    # conductor → screen
# T_R23 = r.T2 + r.T3             # screen → cable surface  (T2 = 0: no armour)
# T_R4  = r.T4                    # cable surface → ambient (soil)

# # Time constants [s]
# tau_1 = Q_node1 * T_R1
# tau_2 = Q_node2 * T_R23
# tau_3 = Q_node3 * T_R4

# println("\n" * "=" ^72)
# println("  Transient Thermal Model — Three-Node RC Network")
# println("=" ^72)
# @printf("\n  Van Wormer coefficient  p = %.4f\n", p_vw)
# @printf("\n  %-12s  %10s  %10s  %12s  %10s\n",
# 	"Node", "Q [J/m·K]", "R [K·m/W]", "τ = Q·R [s]", "τ [min]")
# println("  " * "─"^58)
# @printf("  %-12s  %10.2f  %10.4f  %12.1f  %10.1f\n",
# 	"1 (conduct.)", Q_node1, T_R1, tau_1, tau_1 / 60)
# @printf("  %-12s  %10.2f  %10.4f  %12.1f  %10.1f\n",
# 	"2 (sheath)",   Q_node2, T_R23, tau_2, tau_2 / 60)
# @printf("  %-12s  %10.2f  %10.4f  %12.1f  %10.1f\n",
# 	"3 (surface)",  Q_node3, T_R4, tau_3, tau_3 / 60)
# println()

# # ──────────────────────────────────────────────────────────────────────────────
# # 2.4  State-space model and time-stepping functions
# # ──────────────────────────────────────────────────────────────────────────────

# #=
# State vector:  x = [Δθ_c, Δθ_s, Δθ_e]   (temperature rises above ambient)

# Thermal ladder ODE:
#     Q₁ dΔθ_c/dt = (W_c + ½W_d) − (Δθ_c − Δθ_s) / T₁
#     Q₂ dΔθ_s/dt = (W_s + ½W_d) + (Δθ_c − Δθ_s) / T₁ − (Δθ_s − Δθ_e) / T₂₃
#     Q₃ dΔθ_e/dt =                (Δθ_s − Δθ_e) / T₂₃ − Δθ_e / T₄

# where:
#     W_c = I² R_ac(θ_c)           conductor losses
#     W_s = λ₁ W_c                 screen circulating-current losses
#     R_ac(θ) = R_dc_20 (1+α(θ−20)) (1+y_s+y_p)

# Time integration uses semi-implicit backward Euler: losses are evaluated at the
# current state, then the linear system is solved exactly for the next state.
# This is unconditionally stable and avoids a nonlinear solve.
# =#

# # Cable conductor temperature coefficient (not in IEC 60287 result tuple)
# alpha_c = cable_design.components[1].conductor_group.alpha
# theta_max = 90.0     # IEC 60287 max conductor temperature [°C]

# """
# 	R_ac_at_theta(theta_c, R_dc_20, alpha_c, y_s, y_p)

# AC resistance [Ω/m] at conductor temperature θ_c, with temperature-dependent
# DC resistance and fixed skin/proximity effect factors.
# """
# function R_ac_at_theta(theta_c, R_dc_20, alpha_c, y_s, y_p)
# 	R_dc = R_dc_20 * (1.0 + alpha_c * (theta_c - 20.0))
# 	return R_dc * (1.0 + y_s + y_p)
# end

# """
# 	thermal_step_implicit!(x, dt, I, theta_amb, p)

# Advance the 3-node thermal state `x = [Δθ_c, Δθ_s, Δθ_e]` by one time step
# `dt` [s] using semi-implicit backward Euler.

# The 3×3 linear system is solved by direct Gaussian elimination (no allocation).
# """
# function thermal_step_implicit!(x, dt, I, theta_amb, p)
# 	(; Q1, Q2, Q3, R1, R23, R4, R_dc_20, ac, y_s, y_p, lam1, Wd) = p

# 	# Evaluate losses at current conductor temperature
# 	theta_c = x[1] + theta_amb
# 	R_ac   = R_ac_at_theta(theta_c, R_dc_20, ac, y_s, y_p)
# 	Wc     = I^2 * R_ac
# 	Ws     = lam1 * Wc

# 	# Heat source vector (per-unit-length, W/m)
# 	q1 = Wc + 0.5 * Wd
# 	q2 = Ws + 0.5 * Wd

# 	# Conductances [W/(m·K)]
# 	g1  = 1.0 / R1
# 	g23 = 1.0 / R23
# 	g4  = 1.0 / R4

# 	# Q⁻¹A matrix coefficients (thermal ladder)
# 	a11 = -g1 / Q1;          a12 =  g1 / Q1
# 	a21 =  g1 / Q2;          a22 = -(g1 + g23) / Q2;  a23 = g23 / Q2
# 	                          a32 =  g23 / Q3;          a33 = -(g23 + g4) / Q3

# 	# RHS:  b = x_old + dt × Q⁻¹ q
# 	b1 = x[1] + dt * q1 / Q1
# 	b2 = x[2] + dt * q2 / Q2
# 	b3 = x[3]

# 	# Coefficient matrix:  M = I − dt × Q⁻¹A
# 	m11 = 1.0 - dt * a11;  m12 = -dt * a12
# 	m21 = -dt * a21;        m22 = 1.0 - dt * a22;  m23 = -dt * a23
# 	                         m32 = -dt * a32;        m33 = 1.0 - dt * a33

# 	# Solve M x_new = b  (3×3 by elimination)
# 	fac  = m21 / m11
# 	m22p = m22 - fac * m12
# 	m23p = m23
# 	b2p  = b2  - fac * b1

# 	fac2 = m32 / m22p
# 	m33p = m33 - fac2 * m23p
# 	b3p  = b3  - fac2 * b2p

# 	x[3] = b3p / m33p
# 	x[2] = (b2p - m23p * x[3]) / m22p
# 	x[1] = (b1 - m12 * x[2]) / m11

# 	return nothing
# end

# # ──────────────────────────────────────────────────────────────────────────────
# # 2.5  High-level simulation functions
# # ──────────────────────────────────────────────────────────────────────────────

# """
# 	simulate_thermal(I_fn, θ_amb_fn, t_hours, dt_s, params)

# Forward-simulate the thermal response for time-varying current `I_fn(t)` [A]
# and ambient temperature `θ_amb_fn(t)` [°C], where `t` is in hours.

# Returns vectors `(θ_c, θ_s, θ_e)` at each point in `t_hours`.
# """
# function simulate_thermal(I_fn, theta_amb_fn, t_hours, dt_s, params)
# 	N = length(t_hours)
# 	theta_c = zeros(N)
# 	theta_s = zeros(N)
# 	theta_e = zeros(N)
# 	x = [0.0, 0.0, 0.0]        # cold start

# 	for k in 1:N
# 		I_k   = I_fn(t_hours[k])
# 		amb_k = theta_amb_fn(t_hours[k])
# 		thermal_step_implicit!(x, dt_s, I_k, amb_k, params)
# 		theta_c[k] = x[1] + amb_k
# 		theta_s[k] = x[2] + amb_k
# 		theta_e[k] = x[3] + amb_k
# 	end

# 	return theta_c, theta_s, theta_e
# end

# """
# 	compute_dcr_rating(θ_amb_fn, t_hours, dt_s, params; θ_max, I_tol)

# Compute the instantaneous dynamic cable rating I_max(t) at each time step.

# At each step, the maximum current is found (bisection) such that the conductor
# temperature at the next step does not exceed θ_max.  The cable thermal state
# evolves assuming the cable is loaded to its dynamic limit at every instant.

# Returns `(I_max, θ_c, θ_s, θ_e)`.
# """
# function compute_dcr_rating(theta_amb_fn, t_hours, dt_s, params;
# 	theta_max = 90.0, I_tol = 0.5)

# 	N = length(t_hours)
# 	I_max   = zeros(N)
# 	theta_c = zeros(N)
# 	theta_s = zeros(N)
# 	theta_e = zeros(N)
# 	x_state = [0.0, 0.0, 0.0]    # cold start

# 	for k in 1:N
# 		amb_k = theta_amb_fn(t_hours[k])

# 		# Bisection for I_max at this step
# 		I_lo, I_hi = 0.0, 2000.0
# 		for _ in 1:50
# 			I_mid = 0.5 * (I_lo + I_hi)
# 			x_try = copy(x_state)
# 			thermal_step_implicit!(x_try, dt_s, I_mid, amb_k, params)
# 			if x_try[1] + amb_k > theta_max
# 				I_hi = I_mid
# 			else
# 				I_lo = I_mid
# 			end
# 			(I_hi - I_lo) < I_tol && break
# 		end

# 		I_max_k  = 0.5 * (I_lo + I_hi)
# 		I_max[k] = I_max_k

# 		# Advance state at the dynamic rating
# 		thermal_step_implicit!(x_state, dt_s, I_max_k, amb_k, params)
# 		theta_c[k] = x_state[1] + amb_k
# 		theta_s[k] = x_state[2] + amb_k
# 		theta_e[k] = x_state[3] + amb_k
# 	end

# 	return I_max, theta_c, theta_s, theta_e
# end

# """
# 	quasi_static_rating(theta_amb, r)

# IEC 60287 continuous rating equation evaluated at a single ambient temperature
# (no thermal inertia — infinite-time limit).
# """
# function quasi_static_rating(theta_amb, r)
# 	dtheta = 90.0 - theta_amb
# 	num = dtheta - r.Wd * (0.5 * r.T1 + (r.T2 + r.T3 + r.T4))
# 	den = r.R_ac * r.T1 +
# 	      r.R_ac * (1 + r.lambda1) * r.T2 +
# 	      r.R_ac * (1 + r.lambda1 + r.lambda2) * (r.T3 + r.T4)
# 	return num > 0 ? sqrt(num / den) : 0.0
# end

# # ──────────────────────────────────────────────────────────────────────────────
# # 2.6  Thermal model parameter bundle
# # ──────────────────────────────────────────────────────────────────────────────

# tp = (
# 	Q1      = Q_node1,
# 	Q2      = Q_node2,
# 	Q3      = Q_node3,
# 	R1      = T_R1,
# 	R23     = T_R23,
# 	R4      = T_R4,
# 	R_dc_20 = r.R_dc_20,
# 	ac      = alpha_c,
# 	y_s     = r.y_s,
# 	y_p     = r.y_p,
# 	lam1    = r.lambda1,
# 	Wd      = r.Wd,
# )

# # ──────────────────────────────────────────────────────────────────────────────
# # 2.7  Scenario A: Step response — validate thermal time constants
# # ──────────────────────────────────────────────────────────────────────────────

# #=
# Apply a sudden step from 0 to I_STR and observe the conductor temperature
# rising toward the steady-state 90 °C.  The shape of the curve reveals the
# three time constants of the RC network.
# =#

# dt_s   = 60.0                          # 1-minute steps [s]
# t_step = collect(0.0:dt_s/3600:48.0)   # 48 hours

# I_str = r.I_rated
# theta_c_step, theta_s_step, theta_e_step = simulate_thermal(
# 	t -> I_str,        # constant STR current
# 	t -> 20.0,         # constant ambient 20 °C
# 	t_step, dt_s, tp)

# println("\n" * "=" ^72)
# println("  Scenario A: Step Response  (I = I_STR = $(@sprintf("%.1f", I_str)) A)")
# println("=" ^72)
# @printf("\n  %-8s  %8s  %8s  %8s\n", "Time", "θ_c [°C]", "θ_s [°C]", "θ_e [°C]")
# println("  " * "─"^36)
# for t_print in [0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 12.0, 24.0, 48.0]
# 	idx = findfirst(t -> t >= t_print, t_step)
# 	idx === nothing && continue
# 	@printf("  %5.1f h   %8.2f  %8.2f  %8.2f\n",
# 		t_step[idx], theta_c_step[idx], theta_s_step[idx], theta_e_step[idx])
# end
# @printf("\n  Steady-state target: θ_c = %.1f °C  (IEC 60287)\n", theta_max)

# # ──────────────────────────────────────────────────────────────────────────────
# # 2.8  Scenario B: Daily load profile — temperature trajectories
# # ──────────────────────────────────────────────────────────────────────────────

# #=
# Realistic MV distribution cable loading with:
#   - Morning peak   around 08:00  (60 % of STR)
#   - Evening peak   around 19:00  (80 % of STR)
#   - Night minimum  around 03:00  (25 % of STR)
#   - PV export dip  around 12:00  (40 % of STR, generation offsets load)

# Daily ambient temperature varies between 15 °C (night) and 25 °C (afternoon).
# =#

# function daily_load(t)
# 	h = mod(t, 24.0)
# 	# Superposition of gaussian peaks (normalised to fraction of STR)
# 	base    = 0.30
# 	morning = 0.30 * exp(-0.5 * ((h - 8.0) / 1.5)^2)
# 	midday  = 0.10 * exp(-0.5 * ((h - 12.0) / 2.0)^2)
# 	evening = 0.50 * exp(-0.5 * ((h - 19.0) / 2.0)^2)
# 	return I_str * (base + morning + midday + evening)
# end

# function daily_ambient(t)
# 	h = mod(t, 24.0)
# 	return 20.0 + 5.0 * sin(2π * (h - 6.0) / 24.0)   # min ≈ 15 °C, max ≈ 25 °C
# end

# # Simulate for 72 hours (3 days) — first two days are warm-up
# t_daily = collect(0.0:dt_s/3600:72.0)
# theta_c_daily, theta_s_daily, theta_e_daily = simulate_thermal(
# 	daily_load, daily_ambient, t_daily, dt_s, tp)

# println("\n" * "=" ^72)
# println("  Scenario B: Daily Load Profile — Temperature Trajectory (Day 3)")
# println("=" ^72)
# @printf("\n  I_peak (evening) ≈ %.0f A  (%.0f %% of STR)\n",
# 	daily_load(19.0), daily_load(19.0) / I_str * 100)
# @printf("  I_min  (night)   ≈ %.0f A  (%.0f %% of STR)\n",
# 	daily_load(3.0), daily_load(3.0) / I_str * 100)
# @printf("\n  %-8s  %8s  %8s  %8s  %8s  %10s\n",
# 	"Hour", "I [A]", "θ_c [°C]", "θ_s [°C]", "θ_amb[°C]", "Margin [K]")
# println("  " * "─"^58)
# # Print hourly values for the 3rd day (hours 48–72)
# for h in 0:2:23
# 	t_print = 48.0 + h
# 	idx = findfirst(t -> t >= t_print, t_daily)
# 	idx === nothing && continue
# 	I_h   = daily_load(t_daily[idx])
# 	amb_h = daily_ambient(t_daily[idx])
# 	@printf("  %5.0f h   %7.0f  %8.2f  %8.2f  %8.1f  %10.1f\n",
# 		h, I_h, theta_c_daily[idx], theta_s_daily[idx],
# 		amb_h, theta_max - theta_c_daily[idx])
# end

# # ──────────────────────────────────────────────────────────────────────────────
# # 2.9  DCR vs STR comparison
# # ──────────────────────────────────────────────────────────────────────────────

# #=
# Compute three rating methodologies over 72 hours:

#  1. STR  =  IEC 60287 continuous rating (single number, constant ambient 20 °C)
#  2. Quasi-static DCR  =  IEC 60287 equation solved at each hour with θ_amb(t)
#  3. Dynamic DCR  =  full transient model, cable loaded to its limit at each step
# =#

# # (a) Quasi-static DCR with daily ambient
# I_qs = [quasi_static_rating(daily_ambient(t), r) for t in t_daily]

# # (b) Dynamic DCR with daily ambient (3 days, report day 3)
# I_dcr, theta_c_dcr, theta_s_dcr, theta_e_dcr = compute_dcr_rating(
# 	daily_ambient, t_daily, dt_s, tp; theta_max = theta_max, I_tol = 0.2)

# println("\n" * "=" ^72)
# println("  DCR vs STR Comparison (Day 3, hourly)")
# println("=" ^72)
# @printf("\n  I_STR (IEC 60287, θ_amb = 20 °C) = %.1f A\n\n", I_str)
# @printf("  %-5s  %8s  %10s  %10s  %10s  %10s\n",
# 	"Hour", "θ_amb", "STR [A]", "QS-DCR [A]", "Dyn-DCR[A]", "Gain [%%]")
# println("  " * "─"^58)
# for h in 0:2:23
# 	t_print = 48.0 + h
# 	idx = findfirst(t -> t >= t_print, t_daily)
# 	idx === nothing && continue
# 	amb_h    = daily_ambient(t_daily[idx])
# 	qs_h     = I_qs[idx]
# 	dcr_h    = I_dcr[idx]
# 	gain_pct = (dcr_h - I_str) / I_str * 100
# 	@printf("  %3.0f h  %7.1f°C  %9.1f  %10.1f  %10.1f  %+9.1f\n",
# 		h, amb_h, I_str, qs_h, dcr_h, gain_pct)
# end

# # ──────────────────────────────────────────────────────────────────────────────
# # 2.10  Summary statistics
# # ──────────────────────────────────────────────────────────────────────────────

# # Day-3 indices
# day3_mask = t_daily .>= 48.0
# I_dcr_day3  = I_dcr[day3_mask]
# I_qs_day3   = I_qs[day3_mask]
# tc_daily_d3 = theta_c_daily[day3_mask]

# println("\n" * "=" ^72)
# println("  Summary — Day 3 Statistics")
# println("=" ^72)

# @printf("\n  %-28s  %10s  %10s  %10s\n", "Metric", "STR", "QS-DCR", "Dyn-DCR")
# println("  " * "─"^62)
# @printf("  %-28s  %10.1f  %10.1f  %10.1f\n",
# 	"Min rating [A]", I_str, minimum(I_qs_day3), minimum(I_dcr_day3))
# @printf("  %-28s  %10.1f  %10.1f  %10.1f\n",
# 	"Mean rating [A]", I_str, sum(I_qs_day3)/length(I_qs_day3),
# 	sum(I_dcr_day3)/length(I_dcr_day3))
# @printf("  %-28s  %10.1f  %10.1f  %10.1f\n",
# 	"Max rating [A]", I_str, maximum(I_qs_day3), maximum(I_dcr_day3))
# @printf("  %-28s  %10s  %10.1f  %10.1f\n",
# 	"Mean gain over STR [%%]", "—",
# 	(sum(I_qs_day3)/length(I_qs_day3) - I_str) / I_str * 100,
# 	(sum(I_dcr_day3)/length(I_dcr_day3) - I_str) / I_str * 100)

# @printf("\n  Peak θ_c under daily load profile:  %.1f °C  (margin: %.1f K)\n",
# 	maximum(tc_daily_d3), theta_max - maximum(tc_daily_d3))
# @printf("  STR design temperature:             %.1f °C\n", theta_max)

# println("\n" * "=" ^72)
# println("  End of Case Study — STR and DCR Analysis Complete")
# println("=" ^72)
# println()
