push!(LOAD_PATH, joinpath(@__DIR__, "src"))
using Revise
using LineCableModels

materials_db = MaterialsLibrary()
material = get_material(materials_db, "aluminum")

d_w = .94e-3  # nominal wire screen diameter
@show wa = WireArray(0, Diameter(d_w), 1, 0, material)
@show wa2 = WireArray(wa, Diameter(d_w), 6, 0, material)
@show wa2.radius_in
@show wa.radius_ext

