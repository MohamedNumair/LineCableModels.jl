module LineCableToolbox

# Load required packages
using Measurements
using CSV
using DataFrames
using Colors
using ColorSchemes
using Plots
using Plots.PlotMeasures
using Statistics
using LinearAlgebra

# Define module-level constants
const μ₀ = 4π * 1e-7  # Permeability of free space (H/m)
const ε₀ = 8.8541878128e-12
const TOL = 1e-6

## 1. Materials management
include("Materials.jl")

export init_materials_db,
	get_material,
	save_materials_db,
	display_materials_db,
	get_material_color,
	overlay_colors,
	visualize_gradient,
	overlay_multiple_colors


end
