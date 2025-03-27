# # Tutorial 1 - Using the materials library

#=
This tutorial demonstrates how to manage material properties for power cable modeling. Knowledge of materials commonly used in cable designs forms the essential basis for accurate power cable modeling. This tutorial serves as a practical reference, providing property values from recognized sources, namely CIGRE TB-531 [cigre531](@cite) and IEC 60287 [IEC60287](@cite), that can be stored and retrieved for consistent use across design iterations and simulation studies.
=#

# ## Loading required packages

# Ensure the package is in the load path and import necessary libraries:
push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))
using LineCableModels

# ## Initializing a [`MaterialsLibrary`](@ref)

#=
The [`MaterialsLibrary`](@ref) is a container for storing electromagnetic properties of 
different materials used in power cables. By default, it initializes with several common 
materials with their standard properties.
=#

# Initialize a materials library with default materials
materials_db = MaterialsLibrary()

# Inspect the contents of the materials library
println("Initial contents of the materials library:")
df_initial = list_materials_library(materials_db)

# The function returns a DataFrame with all materials and their properties
# This shows materials like copper, aluminum, XLPE, etc. with their
# electrical resistivity, relative permittivity, relative permeability,
# reference temperature, and temperature coefficient

# ## Adding New Materials to the Library
#
# New materials can be added to the library using the `Material` constructor followed by
# `store_materials_library!`. Let's add some standard materials from IEC standards.

# Define new materials based on IEC 60287 standards

# Copper with corrected resistivity from IEC 60287-3-2
copper_corrected = Material(1.835e-8, 1.0, 0.999994, 20.0, 0.00393)
store_materials_library!(materials_db, "copper_corrected", copper_corrected)

# Aluminum with corrected resistivity from IEC 60287-3-2
aluminum_corrected = Material(3.03e-8, 1.0, 0.999994, 20.0, 0.00403)
store_materials_library!(materials_db, "aluminum_corrected", aluminum_corrected)

# Lead or lead alloy
lead = Material(21.4e-8, 1.0, 1.0, 20.0, 0.00400)
store_materials_library!(materials_db, "lead", lead)

# Steel
steel = Material(13.8e-8, 1.0, 300.0, 20.0, 0.00450)
store_materials_library!(materials_db, "steel", steel)

# Bronze
bronze = Material(3.5e-8, 1.0, 1.0, 20.0, 0.00300)
store_materials_library!(materials_db, "bronze", bronze)

# Stainless steel
stainless_steel = Material(70.0e-8, 1.0, 500.0, 20.0, 0.0)
store_materials_library!(materials_db, "stainless_steel", stainless_steel)

# Insulation materials with different dielectric properties

# EPR (Ethylene Propylene Rubber)
epr = Material(1e15, 3.0, 1.0, 20.0, 0.0)
store_materials_library!(materials_db, "epr", epr)

# PVC (Polyvinyl Chloride)
pvc = Material(1e15, 8.0, 1.0, 20.0, 0.0)
store_materials_library!(materials_db, "pvc", pvc)

# Impregnated paper
impregnated_paper = Material(1e15, 3.5, 1.0, 20.0, 0.0)
store_materials_library!(materials_db, "impregnated_paper", impregnated_paper)

# Laminated paper propylene
laminated_paper = Material(1e15, 2.8, 1.0, 20.0, 0.0)
store_materials_library!(materials_db, "laminated_paper", laminated_paper)

# Carbon-polyethylene compound (semiconductor material)
carbon_pe = Material(0.06, 1e3, 1.0, 20.0, 0.0)
store_materials_library!(materials_db, "carbon_pe", carbon_pe)

# Conductive paper layer
conductive_paper = Material(18.5, 8.6, 1.0, 20.0, 0.0)
store_materials_library!(materials_db, "conductive_paper", conductive_paper)

# Examine the updated library
println("\nUpdated contents of the materials library:")
df_updated = list_materials_library(materials_db)

# ## Checking for Duplicate Materials
#
# The default library already contains some common materials. Let's check for duplicates
# and remove them if necessary.

# Check if copper and aluminum already exist in the default library
# (Note: these are already included but with slightly different values)
println("\nChecking for duplicate materials:")

# Remove duplicate materials (keeping the corrected versions)
if "copper" in names(df_updated)
	println("Removing duplicate 'copper' entry (keeping corrected version)")
	remove_materials_library!(materials_db, "copper")
end

if "aluminum" in names(df_updated)
	println("Removing duplicate 'aluminum' entry (keeping corrected version)")
	remove_materials_library!(materials_db, "aluminum")
end

# Check the final library after removing duplicates
println("\nFinal contents of the materials library after removing duplicates:")
df_final = list_materials_library(materials_db)

# ## Saving the Materials Library to a File
#
# The materials library can be saved to a CSV file for later use.

# Save the materials library to a CSV file
output_path = joinpath(@__DIR__, "materials_library.csv")
save_materials_library(materials_db, file_name = output_path)
println("\nMaterials library saved to: $output_path")

# ## Retrieving Materials for Use in Cable Modeling
#
# Materials can be retrieved from the library using the `get_material` function.
# This is useful when building cable models as demonstrated in other tutorials.

# Retrieve a material for use in cable modeling
copper_material = get_material(materials_db, "copper_corrected")
println("\nRetrieved copper_corrected material properties:")
println("Resistivity: $(copper_material.rho) Ω·m")
println("Relative permittivity: $(copper_material.eps_r)")
println("Relative permeability: $(copper_material.mu_r)")
println("Reference temperature: $(copper_material.T0) °C")
println("Temperature coefficient: $(copper_material.alpha) 1/°C")

# ## Conclusion
#
# This tutorial has demonstrated how to:
#
# 1. Initialize a materials library with default materials
# 2. Add new materials with specific properties
# 3. Check for and remove duplicate materials
# 4. Save the library to a file for future use
# 5. Retrieve materials for use in cable modeling
#
# The materials library provides a flexible way to manage material properties
# for accurate power cable modeling. The properties can be customized to match
# specific manufacturer data or standards requirements.