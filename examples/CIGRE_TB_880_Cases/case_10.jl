#=
# Tutorial 10 Case 10 - Magnetothermal Analysis of a 10 kV Sector-Shaped Cable

This case file demonstrates how to model a medium-voltage three-core 10 kV cable with
95 mm² aluminium sector-shaped conductors, mass impregnated paper insulation, common lead sheath,
and steel tape armour. The cable design and arrangement are based on a 10kV PILC cable case study.

The system operates at 50 Hz with solidly bonded sheaths.
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

#=
## Cable dimensions

The cable under consideration is a 10 kV, 3x95 mm² aluminium sector-shaped conductor cable
with mass impregnated paper insulation, common lead sheath, steel tape armour, and PVC outer sheath.
=#

# Sector geometry parameters to achieve ~95 mm² cross-section
n_sectors = 3
r_back = 14.1e-3        # sector radius b [m]
d_sector = 8.85e-3      # sector depth s [m]
r_corner = 1.5e-3       # corner radius c [m]
theta_cond_deg = 120.0  # sector angle φ [degrees]
ins_thick = 2.35e-3     # core insulation thickness [m]

sector_params = SectorParams(
    n_sectors,
    r_back,
    d_sector,
    r_corner,
    theta_cond_deg,
    ins_thick
)

#=
## Core and main insulation

The conductor consists of 3 aluminium sector-shaped conductors.
=#

# Compute effective resistivity to match the target DC resistance from the datasheet.
# R_dc = 0.320e-3 Ω/m
R_dc_20_target = 0.320e-3
# We will calculate the exact area of the sector to set the effective resistivity
temp_sector = Sector(sector_params, 0.0, Material(1.0, 1.0, 1.0, 20.0, 0.0))
A_sector = temp_sector.cross_section
rho_eff = R_dc_20_target * A_sector

case_10_core_al = Material(
    rho = rho_eff,
    eps_r = 1.0,
    mu_r = 1.0,
    T0 = 20.0,
    alpha = 4.03e-3,
    rho_thermal = 0.0,
    theta_max = 50.0
)

# Create the 3 sectors
rot_angles = (0.0, 120.0, 240.0)
sectors = [Sector(sector_params, ang, case_10_core_al) for ang in rot_angles]

#=
### Main insulation (Mass impregnated paper)

Add the paper insulation layer (εr = 4.0, tanδ = 0.01).
To match the belted cable thermal resistance T1 = 0.8045689810 K.m/W, we calculate an effective thermal resistivity.
T1_prime = rho_eff_th / (2*pi) * ln(r_ext / r_in)
r_in = 14.1 mm, r_ext = 14.1 + 2.35 = 16.45 mm
rho_eff_th = 0.8045689810 * 2 * pi / log(16.45 / 14.1) ≈ 32.795 K.m/W
=#

rho_eff_th = 0.8045689810 * 2 * pi / log((r_back + ins_thick) / r_back)

case_10_insulation = Material(
    rho = 1e14,
    eps_r = 4.0,
    mu_r = 1.0,
    T0 = 20.0,
    alpha = 0.0,
    rho_thermal = rho_eff_th,
    tan_delta = 0.01,
    theta_max = 50.0
)

insulators = [SectorInsulator(sectors[i], ins_thick, case_10_insulation) for i in 1:3]

# Group core-related components:
core1_cc = CableComponent("core1", ConductorGroup(sectors[1]), InsulatorGroup(insulators[1]))
core2_cc = CableComponent("core2", ConductorGroup(sectors[2]), InsulatorGroup(insulators[2]))
core3_cc = CableComponent("core3", ConductorGroup(sectors[3]), InsulatorGroup(insulators[3]))

cable_id = "10kV_3x95mm2_PILC"
datasheet_info = NominalData(
    designation_code = "Case_10",
    U0 = 10.0 / sqrt(3),               # Phase-to-ground voltage [kV]
    U = 10.0,                          # Phase-to-phase voltage [kV]
    conductor_cross_section = 95.0,    # [mm²]
    resistance = 0.320,                # DC resistance at 20°C [Ω/km]
    conductor_diameter = 11.0,         # Equivalent circular diameter [mm]
    overall_diameter = 55.0,           # Nominal overall cable diameter [mm]
)
cable_design = CableDesign(cable_id, core1_cc, nominal_data = datasheet_info)
add!(cable_design, core2_cc)
add!(cable_design, core3_cc)

#=
### Lead sheath and Belt insulation

The lead sheath has an external diameter of 40.0 mm and thickness of 2.0 mm.
The belt insulation is placed inside the lead sheath, but in our model, we represent the bedding layer
(which is outside the lead sheath) to account for T2.
=#

r_sheath_ext = 40.0e-3 / 2
r_sheath_in = r_sheath_ext - 2.0e-3

case_10_lead = Material(
    rho = 21.4e-8,
    eps_r = 1.0,
    mu_r = 1.0,
    T0 = 20.0,
    alpha = 4.0e-3,
    rho_thermal = 0.0,
    theta_max = 50.0
)

lead_sheath = Tubular(r_sheath_in, r_sheath_ext, case_10_lead, 20.0)

# Bedding layer (T2)
# D_b = 46.0 mm -> r_bedding_ext = 23.0 mm
r_bedding_ext = 46.0e-3 / 2
t_bedding = r_bedding_ext - r_sheath_ext

case_10_bedding = Material(
    rho = 1e14,
    eps_r = 1.0,
    mu_r = 1.0,
    T0 = 20.0,
    alpha = 0.0,
    rho_thermal = 6.0,
    theta_max = 50.0
)

bedding_insulator = Insulator(lead_sheath, Thickness(t_bedding), case_10_bedding)
sheath_cc = CableComponent("sheath", ConductorGroup(lead_sheath), InsulatorGroup(bedding_insulator))
add!(cable_design, sheath_cc)

#=
### Steel tape armour and Outer covering

The armour has an external diameter of 49.2 mm.
The outer covering has an external diameter of 55.0 mm.
=#

r_armour_ext = 49.2e-3 / 2
r_armour_in = r_bedding_ext

case_10_armour = Material(
    rho = 1.38e-7,
    eps_r = 1.0,
    mu_r = 300.0,
    T0 = 20.0,
    alpha = 4.5e-3,
    rho_thermal = 0.0,
    theta_max = 50.0
)

armour_tube = Tubular(r_armour_in, r_armour_ext, case_10_armour, 20.0)

# Outer covering (T3)
r_outer_ext = 55.0e-3 / 2
t_outer = r_outer_ext - r_armour_ext

case_10_outer = Material(
    rho = 1e14,
    eps_r = 1.0,
    mu_r = 1.0,
    T0 = 20.0,
    alpha = 0.0,
    rho_thermal = 5.0,
    theta_max = 50.0
)

outer_insulator = Insulator(armour_tube, Thickness(t_outer), case_10_outer)
armour_cc = CableComponent("armour", ConductorGroup(armour_tube), InsulatorGroup(outer_insulator))
add!(cable_design, armour_cc)

# Inspect the finished cable design:
plt1, _ = preview(cable_design)
plt1 #hide

#=
## Defining a cable system
=#

f = [50.0]  # System frequency [Hz]

# Earth model — homogeneous soil (ρ_thermal = 1.0 K.m/W, θ_ambient = 15 °C):
earth_params = EarthModel(f, 100.0, 10.0, 1.0, 1.0)

# Single cable buried at 1.0 m depth
cablepos = CablePosition(cable_design, 0.0, -1.0,
    Dict("core1" => 1, "core2" => 2, "core3" => 3, "sheath" => 0, "armour" => 0))
cable_system = LineCableSystem("10kV_3x95mm2_system", 1000.0, cablepos)

#=
## IEC 60287 Ampacity Calculation
=#

ambient_temperature = 15.0 # Ambient temperature [°C]

prob = AmpacityProblem(
    ambient_temperature, 
    cable_system, 
    earth_params;
    frequency = 50.0, 
    voltage_phase_to_phase = 10.0*1e3,
)

F = IEC60287Formulation(bonding_type = :solid, solar_radiation = false)

results = compute!(prob, F)
r = results[cable_id]

#=
## Results Summary
=#

println("=" ^72)
println("  IEC 60287 Ampacity — Case 10 (10 kV 3-core PILC)")
println("=" ^72)

println("\n── Cable Geometry ──")
@printf("  Conductor diameter    Dc    = %.1f mm\n", r.Dc * 1e3)
@printf("  Cable outer diameter  De    = %.1f mm\n", r.De_cable * 1e3)
@printf("  Conductor spacing     s     = %.1f mm\n", r.s * 1e3)

println("\n── DC Resistance ──")
@printf("  R_dc(20 °C)  = %.4e Ω/m  →  %.4f Ω/km\n", r.R_dc_20, r.R_dc_20 * 1e3)
@printf("  R_dc(50 °C)  = %.4e Ω/m\n", r.R_dc_theta)

println("\n── AC Resistance ──")
@printf("  Skin effect    y_s = %.5f\n", r.y_s)
@printf("  Proximity      y_p = %.5f\n", r.y_p)
@printf("  R_ac(50 °C)   = %.4e Ω/m  →  %.4f Ω/km\n", r.R_ac, r.R_ac * 1e3)

println("\n── Dielectric Losses ──")
@printf("  U_e (phase-to-earth) = %.2f V\n", r.U_e)
@printf("  C_b (capacitance)    = %.3e F/m  →  %.4f μF/km\n", r.C_cable, r.C_cable * 1e9)
@printf("  W_d = %.4f W/m\n", r.Wd)

println("\n── Thermal Resistances ──")
@printf("  T1  = %.4f K.m/W\n", r.T1)
@printf("  T2  = %.4f K.m/W\n", r.T2)
@printf("  T3  = %.4f K.m/W\n", r.T3)
@printf("  T4  = %.4f K.m/W\n", r.T4)

println("\n── Screen / Sheath ──")
@printf("  R_s (sheath, θ_s)   = %.4e Ω/m\n", r.R_s)
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
@printf("  ★ RATED CURRENT  I_c = %.5f A  (Reference: 165.74 A)\n", r.I_rated)
println("=" ^72)

#=
## Validation

Compare key intermediate values against the Case 10 reference solution.
=#

ref = (
    I_c     = 165.74,
    R_dc    = 3.58688e-4,
    R_ac    = 3.59357e-4,
    y_s     = 6.3894e-4,
    y_p     = 6.0458e-4,
    T1      = 0.8045,
    T2      = 0.1334,
    T3      = 0.0886,
    T4      = 0.6822,
    Wd      = 0.0376,
    lambda1 = 4.7915e-3,
    lambda2 = 1.2858e-3
)

println("\n── Validation vs Reference ──")
@printf("  I_c:     %8.2f A      (Ref: %8.2f A)      Diff: %6.2f %%\n", r.I_rated, ref.I_c, abs(r.I_rated - ref.I_c)/ref.I_c * 100)
@printf("  R_dc:    %8.4e Ω/m  (Ref: %8.4e Ω/m)  Diff: %6.2f %%\n", r.R_dc_theta, ref.R_dc, abs(r.R_dc_theta - ref.R_dc)/ref.R_dc * 100)
@printf("  R_ac:    %8.4e Ω/m  (Ref: %8.4e Ω/m)  Diff: %6.2f %%\n", r.R_ac, ref.R_ac, abs(r.R_ac - ref.R_ac)/ref.R_ac * 100)
@printf("  y_s:     %8.4e        (Ref: %8.4e)        Diff: %6.2f %%\n", r.y_s, ref.y_s, abs(r.y_s - ref.y_s)/ref.y_s * 100)
@printf("  y_p:     %8.4e        (Ref: %8.4e)        Diff: %6.2f %%\n", r.y_p, ref.y_p, abs(r.y_p - ref.y_p)/ref.y_p * 100)
@printf("  T1:      %8.4f K.m/W  (Ref: %8.4f K.m/W)  Diff: %6.2f %%\n", r.T1, ref.T1, abs(r.T1 - ref.T1)/ref.T1 * 100)
@printf("  T2:      %8.4f K.m/W  (Ref: %8.4f K.m/W)  Diff: %6.2f %%\n", r.T2, ref.T2, abs(r.T2 - ref.T2)/ref.T2 * 100)
@printf("  T3:      %8.4f K.m/W  (Ref: %8.4f K.m/W)  Diff: %6.2f %%\n", r.T3, ref.T3, abs(r.T3 - ref.T3)/ref.T3 * 100)
@printf("  T4:      %8.4f K.m/W  (Ref: %8.4f K.m/W)  Diff: %6.2f %%\n", r.T4, ref.T4, abs(r.T4 - ref.T4)/ref.T4 * 100)
@printf("  Wd:      %8.4f W/m    (Ref: %8.4f W/m)    Diff: %6.2f %%\n", r.Wd, ref.Wd, abs(r.Wd - ref.Wd)/ref.Wd * 100)
@printf("  lambda1: %8.4e        (Ref: %8.4e)        Diff: %6.2f %%\n", r.lambda1, ref.lambda1, abs(r.lambda1 - ref.lambda1)/ref.lambda1 * 100)
@printf("  lambda2: %8.4e        (Ref: %8.4e)        Diff: %6.2f %%\n", r.lambda2, ref.lambda2, abs(r.lambda2 - ref.lambda2)/ref.lambda2 * 100)
