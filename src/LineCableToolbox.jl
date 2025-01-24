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
using DataStructures
using Serialization


# Module-level constants and utilities
const f₀ = 50 # Base power system frequency
const μ₀ = 4π * 1e-7
const ε₀ = 8.8541878128e-12
const ρ₀ = 1.724e-08 # Annealed copper reference resistivity
const T₀ = 20 # Base temperature
const TOL = 1e-6

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
export @thick,
	Thickness,
	@diam,
	WireArray,
	Strip,
	Tubular,
	ConductorParts,
	Conductor,
	Semicon,
	Insulator,
	CableDesign,
	NominalData,
	CableComponent,
	CableParts,
	add_cable_component!,
	add_conductor_part!,
	cable_parts_data,
	cable_data,
	core_parameters,
	preview_cable_cross_section,
	CablesLibrary,
	save_cables_library,
	add_cable_design!,
	remove_cable_design!,
	get_cable_design,
	display_cables_library

end
