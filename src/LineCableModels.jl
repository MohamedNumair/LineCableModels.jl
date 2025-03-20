module LineCableModels

# Load common dependencies and definitions
include("CommonDeps.jl")

# Submodule `Utils`
include("Utils.jl")
@force using .Utils
@reexport using .Utils

# Submodule `Materials`
include("Materials.jl")
@force using .Materials
@reexport using .Materials

# Submodule `EarthProps`
include("EarthProps.jl")
@force using .EarthProps
@reexport using .EarthProps

# Submodule `DataModel`
include("DataModel.jl")
@force using .DataModel
@reexport using .DataModel

# Submodule `ImportExport`
include("ImportExport.jl")
@force using .ImportExport
@reexport using .ImportExport

# # Lines and cables data model
# include("DataModel.jl")
# export @thick,
# 	Thickness,
# 	@diam,
# 	WireArray,
# 	Strip,
# 	Tubular,
# 	ConductorParts,
# 	Conductor,
# 	Semicon,
# 	Insulator,
# 	CableDesign,
# 	NominalData,
# 	CableComponent,
# 	CableParts,
# 	add_cable_component!,
# 	add_conductor_part!,
# 	cable_parts_data,
# 	cable_data,
# 	core_parameters,
# 	preview_cable_design,
# 	CablesLibrary,
# 	save_cables_library,
# 	store_cable_design!,
# 	remove_cable_design!,
# 	get_cable_design,
# 	display_cables_library,
# 	LineCableSystem,
# 	CableDef,
# 	add_cable_definition!,
# 	preview_system_cross_section,
# 	trifoil_formation,
# 	flat_formation,
# 	cross_section_data

# Import and export data
# include("ImportExport.jl")
# using .ImportExport
# @_autoexport

end