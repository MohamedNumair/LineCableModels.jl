# Toolbox reference

## Materials library
```@docs
Material
MaterialsLibrary
add_material!
remove_material!
save_materials_library
display_materials_library
get_material
LineCableModels._add_default_materials!
LineCableModels._load_from_csv!
```

## Data entry model
```@docs
LineCableModels._load_cables_from_jls! 
LineCableModels.calc_tubular_resistance
LineCableModels.calc_parallel_equivalent
LineCableModels.calc_shunt_capacitance
LineCableModels.calc_equivalent_gmr
LineCableModels.calc_tubular_gmr
LineCableModels.calc_inductance_trifoil
LineCableModels.calc_wirearray_gmr
LineCableModels.calc_shunt_conductance
LineCableModels.calc_gmd
LineCableModels.get_wirearray_coords
LineCableModels.gmr_to_mu
LineCableModels.calc_tubular_inductance
LineCableModels.calc_strip_resistance
LineCableModels._get_material_color
Thickness
@thick
@diam
WireArray
Strip
Tubular
ConductorParts
Conductor
Semicon
Insulator
CableDesign
NominalData
CableComponent
CableParts
add_cable_component!
add_conductor_part!
cable_parts_data
cable_data
core_parameters
preview_cable_design
CablesLibrary
save_cables_library
store_cable_design!
remove_cable_design!
get_cable_design
display_cables_library
LineCableSystem
CableDef
add_cable_definition!
preview_system_cross_section
trifoil_formation
flat_formation
cross_section_data
```

## Soil properties
```@docs
LineCableModels.EHEMFormulation
ConstantProperties
EarthLayer
EarthModel
EnforceLayer
add_earth_layer!
earth_data
LineCableModels._calculate_earth_properties
LineCableModels._compute_ehem_properties!
LineCableModels.FDPropsFormulation
```

## Import and export
```@docs
export_pscad_model
```

## Utilities
```@docs
bias_to_uncertain
percent_to_uncertain
_to_nominal
_to_upper
_to_lower
_percent_error
LineCableModels._equals
```