#=
# Tutorial 5 - EMT analytical line parameter calculation (internal & earth model variants)

This tutorial shows how to compute per-unit-length impedance/admittance matrices for a simple
underground bipolar DC (or two-core AC) cable system using the EMT analytical formulation.
It demonstrates how to switch between different internal impedance and earth return models:

1. Scaled Bessel (reference) vs Deri skin approximation vs Simple low-frequency model.
2. Papadopoulos (integral) vs Full Carson series vs Simple Carson vs Deri earth.

The workflow mirrors previous tutorials: build (or load) a cable design, assemble a
`LineCableSystem`, define an `EarthModel`, create a `LineParametersProblem`, pick a
`FormulationSet(:EMT, ...)`, and call `compute!`.
=#

#= **Tutorial outline**
```@contents
Pages = [
    "tutorial5.md",
]
Depth = 2:3
```
=#

# ## Getting started
using LineCableModels
using LineCableModels.Engine.InternalImpedance
using LineCableModels.Engine.EarthImpedance
using LineCableModels.Engine.Transforms: Fortescue
using DataFrames
fullfile(filename) = joinpath(@__DIR__, filename); #hide
set_verbosity!(0); #hide

# ## Minimal cable design (single metallic core + insulation + sheath)
# Build a compact design to keep matrices small and clear.
materials = MaterialsLibrary(add_defaults = true)

# Conductor (simple solid copper 400 mm² equivalent):
A_cond = 400e-6      # m^2
r_cond = sqrt(A_cond/π)
material = get(materials, "copper")
core_grp = ConductorGroup(Tubular(0.0, Thickness(r_cond), material))

# Inner semiconductor + insulation + outer semiconductor (representative XLPE cable):
material_sc_in = get(materials, "semicon1")
material_ins   = get(materials, "pe")
material_sc_out= get(materials, "semicon2")
insu_grp = InsulatorGroup(Semicon(core_grp, Thickness(0.5e-3), material_sc_in))
add!(insu_grp, Insulator, Thickness(12e-3), material_ins)
add!(insu_grp, Semicon, Thickness(0.5e-3), material_sc_out)

# Sheath (aluminum / lead substitute simple tubular) + jacket (PE):
material_sheath = get(materials, "aluminum")
sheath_con = ConductorGroup(Tubular(insu_grp, Thickness(2e-3), material_sheath))
material_jacket = get(materials, "pe")
sheath_insu = InsulatorGroup(Insulator(sheath_con, Thickness(2.5e-3), material_jacket))

core_cc   = CableComponent("core", core_grp, insu_grp)
sheath_cc = CableComponent("sheath", sheath_con, sheath_insu)

cable_id = "Example_400mm2"
nominal = NominalData(
    designation_code = "EX400",
    U0 = 110.0,
    U  = 110.0,
    conductor_cross_section = 400.0,
    screen_cross_section = 150.0,
    resistance = nothing,
    capacitance = nothing,
    inductance = nothing,
)
cable_design = CableDesign(cable_id, core_cc, nominal_data = nominal)
add!(cable_design, sheath_cc)

# Preview geometry (optional):
plt_preview = preview(cable_design)  # hide in docs if needed

# ## Cable system (bipole or two-core) underground
xp, xn, y0 = -0.4, 0.4, -1.0  # 0.8 m spacing, 1 m burial depth
cable_pos_p = CablePosition(cable_design, xp, y0, Dict("core"=>1, "sheath"=>0))
system = LineCableSystem("ExampleBipole", 1000.0, cable_pos_p)
add!(system, cable_design, xn, y0, Dict("core"=>2, "sheath"=>0))

system_df = DataFrame(system)
plt_sys = preview(system, zoom_factor = 0.25)

# ## Earth model
# Constant-frequency earth (single sample) for clarity:
freqs = [50.0]
earth = EarthModel(freqs, 100.0, 10.0, 1.0)

# ## Problem definition
problem = LineParametersProblem(
    system;
    temperature = 20.0,
    earth_props = earth,
    frequencies = freqs,
)

analytical_opts = (
    force_overwrite = false,
    reduce_bundle = false, 
    kron_reduction = false,
    ideal_transposition = false,
    temperature_correction = true,
    verbosity = 2,
    logfile = "C:\\LCMFEMM\\analytical_log.txt",
)

# ## Formulation variants

# 1) Deri internal + Full Carson earth
F_deri_full = FormulationSet(:EMT;
    internal_impedance = DeriSkin(),
    earth_impedance    = FullCarson(),
    options            = analytical_opts,
)

# 2) Simple internal + Simple Carson earth
F_simple = FormulationSet(:EMT;
    internal_impedance = SimpleSkin(),
    earth_impedance    = SimpleCarson(),
    options            = analytical_opts,
)

# 3) Deri internal + Deri earth (both approximations)
F_deri_deri = FormulationSet(:EMT;
    internal_impedance = DeriSkin(),
    earth_impedance    = DeriEarth(),
    options            = analytical_opts,
)

# ## Compute line parameters for each variant
#ws_ref,    lp_ref    = compute!(problem, F_ref)
ws_deri,   lp_deri   = compute!(problem, F_deri_full)
ws_simple, lp_simple = compute!(problem, F_simple)
ws_dd,     lp_dd     = compute!(problem, F_deri_deri)
 
lp_deri.Z
lp_simple.Z
lp_dd.Z

# ## Compare series resistance of core (element (1,1))
R_ref  = real(res_ref.R[1,1])
R_deri = real(res_deri.R[1,1])
R_simp = real(res_simple.R[1,1])
R_dd   = real(res_dd.R[1,1])

println("Series resistance comparison (Ω/km):")
println("  ScaledBessel + Papadopoulos : $(R_ref)")
println("  DeriSkin + FullCarson       : $(R_deri)")
println("  SimpleSkin + SimpleCarson   : $(R_simp)")
println("  DeriSkin + DeriEarth        : $(R_dd)")

# ## Optional: Symmetrical components (only meaningful for 3-phase; here illustrative)
Tv, lp_ref_seq = Fortescue()(lp_ref)  # still callable; will produce 2×2 → same back

# ## Export (if needed)
# export_data(:atp, lp_ref; file_name = fullfile("example_ZY_export.xml"), cable_system = system)

# ## Summary
# This tutorial demonstrated how to:
# 1. Build a minimal cable design and system.
# 2. Define an EMT analytical problem.
# 3. Swap internal and earth impedance formulations.
# 4. Compute and compare resulting line parameters.
