module LineCableToolbox
"""
# LineCableToolbox

- Frequency-domain calculations of impedances (series R and L) and admittances (shunt C and G) of arbitrary line/cable arrangements, accounting for skin effect, conductor and insulation properties, and earth-return impedances with frequency-dependent soil models.

- Uncertainty quantification using the `Measurements.jl` package, to accurately represent and propagate uncertainties related to cross-section information, internal and external radii of conductors and insulation layers, and electromagnetic properties of materials. 

## Features
- Auxiliary functions for uncertainty analysis and quantification
- Materials library
- Consistent data model with constructors for different lines and cables components
"""

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
using SpecialFunctions

# Module-level utilities
include("Utils.jl")
export error_with_bias,
	ubound_error,
	lbound_error,
	percent_error

# Materials library
include("Materials.jl")
export Material,
	MaterialsLibrary,
	add_material!,
	remove_material!,
	save_materials_library,
	display_materials_library,
	get_material

# Lines and cables data model
include("DataModel.jl")
export WireArray,
	Strip,
	Tubular,
	ConductorParts,
	Conductor,
	Semicon,
	Insulator,
	CableComponent,
	CableParts,
	add_conductor_part!,
	preview_conductor_cross_section,
	conductor_data,
	cable_parts_data,
	cable_component_data

end
