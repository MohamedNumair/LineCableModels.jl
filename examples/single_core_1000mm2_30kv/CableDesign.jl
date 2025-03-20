"""
CableDesign.jl: Typical design of a single-core cable with 1000 mm² cross-section area and 35 mm² screen area, ref. NA2XS(FL)2Y 18/30 kV.
"""

# Define main dimensions
d_core = 38.1e-3 # nominal core overall diameter
d_w = 4.67e-3 # nominal strand diameter of the core
t_sc_in = 0.6e-3 # nominal internal semicon thickness
t_ins = 8e-3 # nominal main insulation thickness
t_sc_out = 0.3e-3 # nominal external semicon thickness
num_sc_wires = 49 # number of screem wires
d_ws = .94e-3  # nominal wire screen diameter
t_cut = 0.1e-3 # nominal thickness of the copper tape (around wire screens)
w_cut = 10e-3 # nominal width of copper tape
t_wbt = .3e-3 # nominal thickness of the water blocking tape
t_alt = .15e-3 # nominal thickness of the aluminum tape
t_pet = .05e-3 # nominal thickness of the pe face in the aluminum tape
t_jac = 2.4e-3 # nominal PE jacket thickness

# Load measurements with uncertainties, if available
measur_file = joinpath(proj_dir, "MeasuredDims.jl")
if isfile(measur_file)
	include(measur_file)
end

# Stranded conductor core
material = get_material(materials_db, "aluminum")
core = Conductor(WireArray(0, @diam(d_w), 1, 0, material))
add_conductor_part!(core, WireArray, @diam(d_w), 6, 15, material)
add_conductor_part!(core, WireArray, @diam(d_w), 12, 13.5, material)
add_conductor_part!(core, WireArray, @diam(d_w), 18, 12.5, material)
add_conductor_part!(core, WireArray, @diam(d_w), 24, 11, material)

# Inner semiconductive tape (optional)


# Inner semiconductor
material = get_material(materials_db, "semicon1")
semicon_in = Semicon(core, @thick(t_sc_in), material)

# Main insulation
material = get_material(materials_db, "xlpe")
main_insu = Insulator(semicon_in, @thick(t_ins), material)

# Outer semiconductor
material = get_material(materials_db, "semicon2")
semicon_out = Semicon(main_insu, @thick(t_sc_out), material)

# Core semiconductive tape
material = get_material(materials_db, "polyacrylate")
wb_tape_co = Semicon(semicon_out, @thick(t_wbt), material)

core_parts = [core, semicon_in, main_insu, semicon_out, wb_tape_co]

# Initialize CableDesign with the first component
datasheet_info = NominalData(
	conductor_cross_section = 1000.0,   # [mm²]
	screen_cross_section = 35.0,        # [mm²]
	resistance = 0.0291,                # [Ω/km]
	capacitance = 0.39,                 # [μF/km]
	inductance = 0.3,                    # [mH/km]
)

cable_design =
	CableDesign(cable_id, "core", core_parts, nominal_data = datasheet_info)

# Wire screens - Continue building on top of wb_tape_co
lay_ratio = 10 # typical value for wire screens
material = get_material(materials_db, "copper")
wire_screen =
	Conductor(WireArray(wb_tape_co, @diam(d_ws), num_sc_wires, lay_ratio, material))
add_conductor_part!(wire_screen, Strip, @thick(t_cut), w_cut, lay_ratio, material)
# @show wire_screen.resistance
# @show _percent_error(wire_screen.resistance)

# Water blocking tape
material = get_material(materials_db, "polyacrylate")
wb_tape_scr = Semicon(wire_screen, @thick(t_wbt), material)

sheath_parts = [wire_screen, wb_tape_scr]
add_cable_component!(cable_design, "sheath", sheath_parts)

# Jacket - Continue building on top of wb_tape_scr
material = get_material(materials_db, "aluminum")
alu_tape = Conductor(Tubular(wb_tape_scr, @thick(t_alt), material))

# PE layer after aluminum foil 
material = get_material(materials_db, "pe")
alu_tape_pe = Insulator(alu_tape, @thick(t_pet), material)

# PE jacket
material = get_material(materials_db, "xlpe")
pe_insu = Insulator(alu_tape_pe, @thick(t_jac), material)

jacket_parts = [alu_tape, alu_tape_pe, pe_insu]
add_cable_component!(cable_design, "jacket", jacket_parts)