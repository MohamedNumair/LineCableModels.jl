"""
Main.jl: LineCableModels main process.
"""

# Define project ID
project_id = "single_core_1000mm2_30kv"
proj_dir = joinpath(@__DIR__, "projects", project_id)
mkpath(proj_dir);

# Load dependencies 
push!(LOAD_PATH, joinpath(@__DIR__, "src"))
using Measurements
using Statistics
using DataFrames
using Plots
using Revise
using LineCableModels

# Configure plots
plotlyjs()
closeall()  # Close all active plots
base_font_size = 12
title_base_font_size = 14
leg_base_font_size = 10
default(
	fontfamily = "Computer Modern",
	guidefontsize = base_font_size,   # Axis labels (x/y/z)
	tickfontsize = base_font_size,    # Tick labels
	titlefontsize = title_base_font_size, # Title font size
	legendfontsize = leg_base_font_size,  # Legend font size
)

# Load materials library
materials_db = MaterialsLibrary(file_name = joinpath(proj_dir, "materials_library.csv"))
display_materials_library(materials_db)

# Define cable design
cable_id = "NA2XS(FL)2Y18/30"

library = CablesLibrary(file_name = joinpath(proj_dir, "cables_library.jls"))
display_cables_library(library)

if haskey(library.cable_designs, cable_id)
	# Design already exists, load directly
	cable_design = get_cable_design(library, cable_id)
else
	# Build the cable design from file
	include(joinpath(proj_dir, "CableDesign.jl"))
	store_cable_design!(library, cable_design)
	save_cables_library(library, file_name = joinpath(proj_dir, "cables_library.jls"))
end

# Preview cable design and main parameters
println("\n - Comparison with datasheet information:")
display(core_parameters(cable_design))
println("\n - EMT parameters:")
display(cable_data(cable_design))
println("\n - Detailed description of cable parts:")
display(cable_parts_data(cable_design))
preview_cable_design(cable_design)

# Define earth model
f = 10.0 .^ range(0, stop = 6, length = 10)
earth_params = EarthModel(f, 100.0, 10.0, 1.0)
println("\n - Earth model base (DC) properties:")
display(earth_data(earth_params))

# Define system cross-section
x0 = percent_to_uncertain(0, 0)
y0 = percent_to_uncertain(-1, 0)
xa, ya, xb, yb, xc, yc = trifoil_formation(x0, y0, 0.035)

# Initialize the LineCableSystem
cabledef1 = CableDef(cable_design, xa, ya, Dict("core" => 1, "sheath" => 0, "armor" => 0))
cable_system = LineCableSystem("test_case_1", 20.0, earth_params, 1000.0, cabledef1)
add_cable_definition!(cable_system, cable_design, xb, yb)
add_cable_definition!(cable_system, cable_design, xc, yc)

# Preview cross-section
println("\n - Cable system details:")
display(cross_section_data(cable_system))
preview_system_cross_section(cable_system, zoom_factor = 0.25)

# Export to PSCAD input file
export_pscad_lcp(cable_system, folder_path = proj_dir);
