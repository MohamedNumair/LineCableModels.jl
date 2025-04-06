#=
# Tutorial 1 - Using the  materials library

This tutorial demonstrates how to manage material properties for power cable modeling using the package [`LineCableModels.jl`](@ref). Accurate knowledge of electromagnetic properties is essential for reliable cable design and analysis.

Beyond showcasing the API, this guide serves as a practical reference by providing standard property values from recognized industry sources like CIGRE TB-531 [cigre531](@cite) and IEC 60287 [IEC60287](@cite) that can be stored and consistently applied across multiple design iterations and simulation studies.
=#

#=
**Tutorial outline**
```@contents
Pages = [
	"tutorial1.md",
]
Depth = 2:3
```
=#

# ##   Getting started

# Load the package:
push!(LOAD_PATH, joinpath(@__DIR__, "..", "src")) # hide
using LineCableModels

#=
The [`MaterialsLibrary`](@ref) is a container for storing electromagnetic properties of 
different materials used in power cables. By default, it initializes with several common 
materials with their standard properties.
=#

# Initialize a [`MaterialsLibrary`](@ref) with default values:
materials_db = MaterialsLibrary()

# Inspect the contents of the materials library:
df_initial = list_materialslibrary(materials_db)

#=
The function [`list_materialslibrary`](@ref) returns a `DataFrame` with all materials and their properties, namely: electrical resistivity, relative permittivity, relative permeability, reference temperature, and temperature coefficient.
=#

# ##   Adding new materials
#=
!!! note "Note"
	New materials can be added to the library using the [`Material`](@ref) constructor followed by [`store_materialslibrary!`](@ref).

It might be useful to add other conductor materials with corrected properties based on recognized standards [cigre531](@cite) [IEC60287](@cite).
=#

# Copper with corrected resistivity from IEC 60287-3-2:
copper_corrected = Material(1.835e-8, 1.0, 0.999994, 20.0, 0.00393)
store_materialslibrary!(materials_db, "copper_corrected", copper_corrected)

# Aluminum with corrected resistivity from IEC 60287-3-2:
aluminum_corrected = Material(3.03e-8, 1.0, 0.999994, 20.0, 0.00403)
store_materialslibrary!(materials_db, "aluminum_corrected", aluminum_corrected)

# Lead or lead alloy:
lead = Material(21.4e-8, 1.0, 1.0, 20.0, 0.00400)
store_materialslibrary!(materials_db, "lead", lead)

# Steel:
steel = Material(13.8e-8, 1.0, 300.0, 20.0, 0.00450)
store_materialslibrary!(materials_db, "steel", steel)

# Bronze:
bronze = Material(3.5e-8, 1.0, 1.0, 20.0, 0.00300)
store_materialslibrary!(materials_db, "bronze", bronze)

# Stainless steel:
stainless_steel = Material(70.0e-8, 1.0, 500.0, 20.0, 0.0)
store_materialslibrary!(materials_db, "stainless_steel", stainless_steel)

#=
When modeling cables for EMT analysis, one might be concerned with the impact of insulators and semiconductive layers on cable constants. Common insulation materials and semicons with different dielectric properties are reported in Table 6 of [cigre531](@cite). Let us include some of these materials in the [`MaterialsLibrary`](@ref) to help our future selves.
=#

# EPR (ethylene propylene rubber):
epr = Material(1e15, 3.0, 1.0, 20.0, 0.005)
store_materialslibrary!(materials_db, "epr", epr)

# PVC (polyvinyl chloride):
pvc = Material(1e15, 8.0, 1.0, 20.0, 0.1)
store_materialslibrary!(materials_db, "pvc", pvc)

# Laminated paper propylene:
laminated_paper = Material(1e15, 2.8, 1.0, 20.0, 0.0)
store_materialslibrary!(materials_db, "laminated_paper", laminated_paper)

# Carbon-polyethylene compound (semicon):
carbon_pe = Material(0.06, 1e3, 1.0, 20.0, 0.0)
store_materialslibrary!(materials_db, "carbon_pe", carbon_pe)

# Conductive paper layer (semicon):
conductive_paper = Material(18.5, 8.6, 1.0, 20.0, 0.0)
store_materialslibrary!(materials_db, "conductive_paper", conductive_paper)

# ##  Removing materials
#=
!!! note "Note"
	Materials can be removed from the library with the [`remove_materialslibrary!`](@ref) function.
=#

# Add a duplicate material by accident:
store_materialslibrary!(materials_db, "epr_dupe", epr)

# And now remove it using the [`remove_materialslibrary!`](@ref) function:
remove_materialslibrary!(materials_db, "epr_dupe")

# Examine the updated library after removing the duplicate:
println("Material properties compiled from CIGRE TB-531 and IEC 60287:")
df_final = list_materialslibrary(materials_db)

# ##  Saving the materials library to JSON
output_file = joinpath(@__DIR__, "materials_library.json")
save_materialslibrary(
	materials_db,
	file_name = output_file,
)


# ##  Retrieving materials for use
#=
!!! note "Note"
	To load from an existing CSV file, instantiate a new [`MaterialsLibrary`](@ref) passing the file path as argument. Materials can be retrieved from the library using the [`get_material`](@ref) function.
=#

# Start a new [`MaterialsLibrary`](@ref) and load from the JSON file:
materials_from_json = MaterialsLibrary()
load_materialslibrary!(
	materials_from_json,
	file_name = output_file,
)
# Retrieve a material and display the object:
copper = get_material(materials_from_json, "copper_corrected")

# Access the material properties:
println("\nRetrieved copper_corrected material properties:")
println("Resistivity: $(copper.rho) Ω·m")
println("Relative permittivity: $(copper.eps_r)")
println("Relative permeability: $(copper.mu_r)")
println("Reference temperature: $(copper.T0) °C")
println("Temperature coefficient: $(copper.alpha) 1/°C")

# ##  Conclusion
#=
This tutorial has demonstrated how to:

1. Initialize a [`MaterialsLibrary`](@ref) with default [`Material`](@ref) objects.
2. Add new materials with specific properties.
3. Remove duplicate materials.
4. Save the library to a file for future use.
5. Retrieve materials for use in cable modeling.

The [`MaterialsLibrary`](@ref) provides a flexible and traceable framework to manage material properties for accurate power cable modeling. Custom [`Material`](@ref) objects can be defined and used to match specific manufacturer data or standards requirements.
=#
