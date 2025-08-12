"""
	LineCableModels.ImportExport

The [`ImportExport`](@ref) module provides methods for serializing and deserializing data structures in [`LineCableModels.jl`](index.md), and data exchange with external programs.

# Overview

This module provides functionality for:

- Saving and loading cable designs and material libraries to/from JSON and other formats.
- Exporting cable system models to PSCAD format.
- Serializing custom types with special handling for measurements and complex numbers.

The module implements a generic serialization framework with automatic type reconstruction
and proper handling of Julia-specific types like `Measurement` objects and `Inf`/`NaN` values.

# Dependencies

$(IMPORTS)

# Exports

$(EXPORTS)
"""
module ImportExport

# Load common dependencies
include("common_deps.jl")
using ..Utils
using ..Materials
using ..EarthProps
using ..DataModel
using ..LineCableModels # For physical constants (f₀, μ₀, ε₀, ρ₀, T₀, TOL, ΔTmax)

# Module-specific dependencies
using Measurements
using EzXML # For PSCAD export
using Dates # For PSCAD export
using JSON3
using Serialization # For .jls format


function _display_path(file_name)
    return DataModel._is_headless() ? basename(file_name) : abspath(file_name)
end

#=
Generates sequential IDs, used for simulation element identification (e.g., PSCAD).
Starts from 100,000,000 and increments.
=#
let current_id = 100000000
    global _next_id = () -> (id = current_id; current_id += 1; string(id))
end

"""
$(TYPEDSIGNATURES)

Exports a [`LineCableSystem`](@ref) to a PSCAD-compatible file format.

# Arguments

- `cable_system`: A [`LineCableSystem`](@ref) object representing the cable system to be exported.
- `earth_props`: An [`EarthModel`](@ref) object containing the earth properties.
- `base_freq`: The base frequency \\[Hz\\] used for the PSCAD export.
- `file_name`: The path to the output file (default: "*_export.pscx")

# Returns

- The absolute path of the saved file, or `nothing` on failure.

# Examples

```julia
cable_system = LineCableSystem(...)
earth_model = EarthModel(...)
$(FUNCTIONNAME)(cable_system, earth_model, base_freq=50)
```

# See also

- [`LineCableSystem`](@ref)
"""
function export_pscad_lcp(
    cable_system::LineCableSystem,
    earth_props::EarthModel;
    base_freq=f₀,
    file_name::String="$(cable_system.system_id)_export.pscx",
)::Union{String,Nothing}

    file_name = isabspath(file_name) ? file_name : joinpath(@__DIR__, file_name)

    # Sets attributes on an existing EzXML.Node from a dictionary.
    function _set_attributes!(element::EzXML.Node, attrs::Dict{String,String})
        # Loop through the dictionary and set each attribute on the element
        for (k, v) in attrs
            element[k] = v
        end
    end

    # Adds <param> child elements to an existing <paramlist> EzXML.Node
    # from a vector of ("name", "value") tuples.
    function _add_params_to_list!(
        list_element::EzXML.Node,
        params::Vector{Tuple{String,String}},
    )
        # Ensure the target element is actually a paramlist for clarity, though not strictly necessary for EzXML
        # if nodename(list_element) != "paramlist"
        #     @warn "Attempting to add params to a non-paramlist node: $(nodename(list_element))"
        # end
        # Loop through the vector and add each parameter as a child element
        for (name, value) in params
            param = addelement!(list_element, "param")
            param["name"] = name
            param["value"] = value
        end
    end

    # --- Initial Setup (Identical to original) ---
    # Local Ref for ID generation ensures it's unique to this function call if nested
    current_id = Ref(100000000)
    _next_id() = string(current_id[] += 1)

    # Formatting function (ensure to_nominal is defined or handle types appropriately)
    format_nominal =
        (X; sigdigits=4, minval=-1e30, maxval=1e30) -> begin

            local_value = round(to_nominal(X), sigdigits=sigdigits)

            local_value = max(min(local_value, maxval), minval)
            if abs(local_value) < eps(Float64)
                local_value = 0.0
            end
            return string(local_value)
        end

    id_map = Dict{String,String}() # Stores IDs needed for linking (Instance IDs in this case)
    doc = XMLDocument()
    project = ElementNode("project")
    setroot!(doc, project)
    project_id = cable_system.system_id

    # --- Project Attributes (Identical) ---
    project["name"] = project_id
    project["version"] = "5.0.2"
    project["schema"] = ""
    project["Target"] = "EMTDC"

    # --- Settings (Use Helper for Params) ---
    settings = addelement!(project, "paramlist")
    settings["name"] = "Settings" # Set name attribute directly as in original
    timestamp = string(round(Int, datetime2unix(now())))
    settings_params = [
        ("creator", "LineCableModels.jl,$timestamp"), ("time_duration", "0.5"),
        ("time_step", "5"), ("sample_step", "250"), ("chatter_threshold", ".001"),
        ("branch_threshold", ".0005"), ("StartType", "0"),
        ("startup_filename", "\$(Namespace).snp"), ("PlotType", "0"),
        ("output_filename", "\$(Namespace).out"), ("SnapType", "0"),
        ("SnapTime", "0.3"), ("snapshot_filename", "\$(Namespace).snp"),
        ("MrunType", "0"), ("Mruns", "1"), ("Scenario", ""), ("Advanced", "14335"),
        ("sparsity_threshold", "200"), ("Options", "16"), ("Build", "18"),
        ("Warn", "0"), ("Check", "0"),
        (
            "description",
            "Created with LineCableModels.jl (https://github.com/Electa-Git/LineCableModels.jl)",
        ),
        ("Debug", "0"),
    ]
    _add_params_to_list!(settings, settings_params) # Use helper to add <param> children

    # --- Empty Elements (Identical) ---
    addelement!(project, "Layers")
    addelement!(project, "List")["classid"] = "Settings"
    addelement!(project, "bookmarks")

    # --- GlobalSubstitutions (Identical Structure) ---
    global_subs = addelement!(project, "GlobalSubstitutions")
    global_subs["name"] = "Default"
    addelement!(global_subs, "List")["classid"] = "Sub"
    addelement!(global_subs, "List")["classid"] = "ValueSet"
    global_pl = addelement!(global_subs, "paramlist") # No name attribute
    # Add the single parameter directly as in original
    global_param = addelement!(global_pl, "param")
    global_param["name"] = "Current"
    global_param["value"] = ""

    # --- Definitions Section (Identical Start) ---
    definitions = addelement!(project, "definitions")

    # --- StationDefn (Use Helpers for Attrs/Params) ---
    station = addelement!(definitions, "Definition")
    station_id = _next_id()
    id_map["DS_Defn"] = station_id # Map Definition ID
    station_attrs = Dict(
        "classid" => "StationDefn", "name" => "DS", "id" => station_id,
        "group" => "", "url" => "", "version" => "", "build" => "",
        "crc" => "-1", "view" => "false",
    )
    _set_attributes!(station, station_attrs) # Use helper

    station_pl = addelement!(station, "paramlist")
    station_pl["name"] = "" # Keep empty name attribute exactly as original
    # Add Description param directly as original
    desc_param_st = addelement!(station_pl, "param")
    desc_param_st["name"] = "Description"
    desc_param_st["value"] = ""

    schematic = addelement!(station, "schematic")
    schematic["classid"] = "StationCanvas"
    schematic_pl = addelement!(schematic, "paramlist") # No name attribute
    schematic_params = [
        ("show_grid", "0"), ("size", "0"), ("orient", "1"), ("show_border", "0"),
        ("monitor_bus_voltage", "0"), ("show_signal", "0"), ("show_virtual", "0"),
        ("show_sequence", "0"), ("auto_sequence", "1"), ("bus_expand_x", "8"),
        ("bus_expand_y", "8"), ("bus_length", "4"),
    ]
    _add_params_to_list!(schematic_pl, schematic_params) # Use helper

    addelement!(schematic, "grouping") # Identical

    # --- Station Schematic: Wire/User Instance for "Main" (Use Helpers) ---
    wire = addelement!(schematic, "Wire")
    wire_id = _next_id()
    wire_attrs = Dict(
        "classid" => "Branch", "id" => wire_id, "name" => "Main", "x" => "180",
        "y" => "180",
        "w" => "66", "h" => "82", "orient" => "0", "disable" => "false",
        "defn" => "Main",
        "recv" => "-1", "send" => "-1", "back" => "-1",
    )
    _set_attributes!(wire, wire_attrs) # Use helper

    # Keep vertex loop identical
    for (x, y) in [(0, 0), (0, 18), (54, 54), (54, 72)]
        vertex = addelement!(wire, "vertex")
        vertex["x"] = string(x)
        vertex["y"] = string(y)
    end

    user = addelement!(wire, "User") # User instance nested in Wire
    user_id = _next_id()
    id_map["Main"] = user_id # Original maps the *instance* ID here for hierarchy link
    user_attrs = Dict(
        "classid" => "UserCmp", "id" => user_id, "name" => "$project_id:Main",
        "x" => "0", "y" => "0", "w" => "0", "h" => "0", "z" => "-1", "orient" => "0",
        "defn" => "$project_id:Main", # Links to definition named "Main" (implicitly in same project)
        "link" => "-1", "q" => "4", "disable" => "false",
    )
    _set_attributes!(user, user_attrs) # Use helper

    user_pl = addelement!(user, "paramlist")
    # Original sets attributes directly on paramlist and adds no <param> children - replicate exactly:
    user_pl["name"] = ""
    user_pl["link"] = "-1"
    user_pl["crc"] = "-1"

    # --- UserCmpDefn "Main" (Use Helpers) ---
    user_cmp = addelement!(definitions, "Definition")
    user_cmp_id = _next_id() # This is the definition ID
    id_map["Main_Defn"] = user_cmp_id # Map Definition ID separately
    user_cmp_attrs = Dict(
        "classid" => "UserCmpDefn", "name" => "Main", "id" => user_cmp_id,
        "group" => "",
        "url" => "", "version" => "", "build" => "", "crc" => "-1", "view" => "false",
        "date" => timestamp,
    )
    _set_attributes!(user_cmp, user_cmp_attrs) # Use helper

    user_cmp_pl = addelement!(user_cmp, "paramlist")
    user_cmp_pl["name"] = "" # Empty name attribute
    # Add Description param directly
    desc_param_ucmp = addelement!(user_cmp_pl, "param")
    desc_param_ucmp["name"] = "Description"
    desc_param_ucmp["value"] = ""

    # Form (Identical)
    form = addelement!(user_cmp, "form")
    form["name"] = ""
    form["w"] = "320"
    form["h"] = "400"
    form["splitter"] = "60"

    # Graphics (Identical Structure)
    graphics = addelement!(user_cmp, "graphics")
    graphics["viewBox"] = "-200 -200 200 200"
    graphics["size"] = "2"

    # Graphics Rectangle (Use Helpers)
    rect = addelement!(graphics, "Gfx")
    rect_id = _next_id()
    rect_attrs = Dict(
        "classid" => "Graphics.Rectangle", "id" => rect_id, "x" => "-36", "y" => "-36",
        "w" => "72", "h" => "72",
    )
    _set_attributes!(rect, rect_attrs) # Use helper
    rect_pl = addelement!(rect, "paramlist") # No name attribute
    rect_params = [
        ("color", "Black"), ("dasharray", "0"), ("thickness", "0"), ("port", ""),
        ("fill_style", "0"), ("fill_fg", "Black"), ("fill_bg", "Black"),
        ("cond", "true"),
    ]
    _add_params_to_list!(rect_pl, rect_params) # Use helper

    # Graphics Text (Use Helpers)
    text = addelement!(graphics, "Gfx")
    text_id = _next_id()
    text_attrs = Dict("classid" => "Graphics.Text", "id" => text_id, "x" => "0", "y" => "0")
    _set_attributes!(text, text_attrs) # Use helper
    text_pl = addelement!(text, "paramlist") # No name attribute
    text_params = [
        ("text", "%:Name"), ("anchor", "0"), ("full_font", "Tahoma, 13world"),
        ("angle", "0"), ("color", "Black"), ("cond", "true"),
    ]
    _add_params_to_list!(text_pl, text_params) # Use helper

    # --- UserCmpDefn "Main" Schematic (Use Helpers) ---
    user_schematic = addelement!(user_cmp, "schematic")
    user_schematic["classid"] = "UserCanvas"
    user_sch_pl = addelement!(user_schematic, "paramlist") # No name attribute
    user_sch_params = [
        ("show_grid", "0"), ("size", "0"), ("orient", "1"), ("show_border", "0"),
        ("monitor_bus_voltage", "0"), ("show_signal", "0"), ("show_virtual", "0"),
        ("show_sequence", "0"), ("auto_sequence", "1"), ("bus_expand_x", "8"),
        ("bus_expand_y", "8"), ("bus_length", "4"), ("show_terminals", "0"),
        ("virtual_filter", ""), ("animation_freq", "500"),
    ]
    _add_params_to_list!(user_sch_pl, user_sch_params) # Use helper

    addelement!(user_schematic, "grouping") # Identical

    # --- UserCmpDefn "Main" Schematic: CableSystem Instance (Use Helpers) ---
    cable = addelement!(user_schematic, "Wire") # Wire instance
    cable_id = _next_id()
    cable_attrs = Dict(
        "classid" => "Cable", "id" => cable_id, "name" => "$project_id:CableSystem",
        "x" => "72", "y" => "36", "w" => "107", "h" => "128", "orient" => "0",
        "disable" => "false", "defn" => "$project_id:CableSystem", # Links to definition named "CableSystem"
        "recv" => "-1", "send" => "-1", "back" => "-1", "crc" => "-1",
    )
    _set_attributes!(cable, cable_attrs) # Use helper

    # Keep vertex loop identical
    for (x, y) in [(0, 0), (0, 18), (54, 54), (54, 72)]
        vertex = addelement!(cable, "vertex")
        vertex["x"] = string(x)
        vertex["y"] = string(y)
    end

    cable_user = addelement!(cable, "User") # User instance nested in Wire
    cable_user_id = _next_id()
    id_map["CableSystem"] = cable_user_id # Original maps this *instance* ID for hierarchy link
    cable_user_attrs = Dict(
        "classid" => "UserCmp", "id" => cable_user_id,
        "name" => "$project_id:CableSystem",
        "x" => "0", "y" => "0", "w" => "0", "h" => "0", "z" => "-1", "orient" => "0",
        "defn" => "$project_id:CableSystem", # Links to definition named "CableSystem"
        "link" => "-1", "q" => "4", "disable" => "false",
    )
    _set_attributes!(cable_user, cable_user_attrs) # Use helper

    cable_pl = addelement!(cable_user, "paramlist")
    # Original sets attributes on paramlist AND adds params - replicate exactly
    cable_pl["name"] = ""
    cable_pl["link"] = "-1"
    cable_pl["crc"] = "-1"
    cable_params = [ # Instance parameters
        ("Name", "LineCableSystem_1"), ("R", "#NaN"), ("X", "#NaN"), ("B", "#NaN"),
        ("Freq", format_nominal(base_freq)),
        ("Length", format_nominal(cable_system.line_length / 1000)), # Assumes field exists
        ("Dim", "0"), ("Mode", "0"), ("CoupleEnab", "0"), ("CoupleName", "row"),
        ("CoupleOffset", "0.0 [m]"), ("CoupleRef", "0"), ("tname", "tandem_segment"),
        ("sfault", "0"), ("linc", "10.0 [km]"), ("steps", "3"), ("gen_cnst", "1"),
        ("const_path", "%TEMP%\\my_constants_file.tlo"), ("Date", timestamp),
    ]
    _add_params_to_list!(cable_pl, cable_params) # Use helper

    # --- RowDefn "CableSystem" (Use Helpers) ---
    row = addelement!(definitions, "Definition")
    row_id = _next_id()
    id_map["CableSystem_Defn"] = row_id # Map definition ID separately
    row_attrs = Dict(
        "id" => row_id, "classid" => "RowDefn", "name" => "CableSystem", "group" => "",
        "url" => "", "version" => "RowDefn", "build" => "RowDefn", "crc" => "-1",
        "key" => "", "view" => "false", "date" => timestamp,
    )
    _set_attributes!(row, row_attrs) # Use helper

    row_pl = addelement!(row, "paramlist") # No name attribute
    row_params = [("Description", ""), ("type", "Cable")]
    _add_params_to_list!(row_pl, row_params) # Use helper

    row_schematic = addelement!(row, "schematic")
    row_schematic["classid"] = "RowCanvas"
    row_sch_pl = addelement!(row_schematic, "paramlist") # No name attribute
    row_sch_params =
        [("show_grid", "0"), ("size", "0"), ("orient", "1"), ("show_border", "0")]
    _add_params_to_list!(row_sch_pl, row_sch_params) # Use helper

    # --- Components in RowDefn "CableSystem" Schematic ---

    # FrePhase Component (Use Helpers)
    fre_phase = addelement!(row_schematic, "User")
    fre_phase_id = _next_id()
    fre_phase_attrs = Dict(
        "id" => fre_phase_id, "name" => "master:Line_FrePhase_Options",
        "classid" => "UserCmp",
        "x" => "576", "y" => "180", "w" => "460", "h" => "236", "z" => "-1",
        "orient" => "0",
        "defn" => "master:Line_FrePhase_Options", "link" => "-1", "q" => "4",
        "disable" => "false",
    )
    _set_attributes!(fre_phase, fre_phase_attrs) # Use helper

    fre_pl = addelement!(fre_phase, "paramlist")
    # Original sets crc attribute only on paramlist, replicate exactly
    fre_pl["crc"] = "-1"
    fre_params = [ # Actual params
        ("Interp1", "1"), ("Output", "0"), ("Inflen", "0"), ("FS", "0.5"),
        ("FE", "1.0E6"),
        ("Numf", "100"), ("YMaxP", "20"), ("YMaxE", "0.2"), ("AMaxP", "20"),
        ("AMaxE", "0.2"),
        ("MaxRPtol", "2.0e6"), ("W1", "1.0"), ("W2", "1000.0"), ("W3", "1.0"),
        ("CPASS", "0"),
        ("NFP", "1000"), ("FSP", "0.001"), ("FEP", "1000.0"), ("DCenab", "0"),
        ("DCCOR", "1"),
        ("ECLS", "1"), ("shntcab", "1.0E-9"), ("ET_PE", "1E-10"), ("MER_PE", "2"),
        ("MIT_PE", "5"), ("FDIS", "3"), ("enablf", "1"),
    ]
    _add_params_to_list!(fre_pl, fre_params) # Use helper

    addelement!(row_schematic, "grouping") # Identical

    # --- Coaxial Cables Loop (Use Helpers, keep logic identical) ---
    num_cables = cable_system.num_cables
    dx = 400
    for i in 1:num_cables
        cable_position = cable_system.cables[i]
        coax1 = addelement!(row_schematic, "User")
        coax1_id = _next_id()
        coax1_attrs = Dict(
            "classid" => "UserCmp", "name" => "master:Cable_Coax", "id" => coax1_id,
            "x" => "$(234+(i-1)*dx)", "y" => "612", "w" => "311", "h" => "493",
            "z" => "-1",
            "orient" => "0", "defn" => "master:Cable_Coax", "link" => "-1", "q" => "4",
            "disable" => "false",
        )
        _set_attributes!(coax1, coax1_attrs) # Use helper

        coax1_pl = addelement!(coax1, "paramlist")
        # Original sets attributes on paramlist AND adds params - replicate exactly
        coax1_pl["link"] = "-1"
        coax1_pl["name"] = ""
        coax1_pl["crc"] = "-1"

        # --- Parameter Calculation (Identical Logic from Original) ---
        component_ids = collect(keys(cable_position.design_data.components))
        num_cable_parts = length(component_ids)
        if num_cable_parts > 4
            error(
                "Cable $(cable_position.design_data.cable_id) has $num_cable_parts parts, exceeding the limit of 4 (core/sheath/armor/outer).",
            )
        end
        conn = cable_position.conn
        elim1 = length(conn) >= 2 && conn[2] == 0 ? "1" : "0"
        elim2 = length(conn) >= 3 && conn[3] == 0 ? "1" : "0"
        elim3 = length(conn) >= 4 && conn[4] == 0 ? "1" : "0"
        cable_x = cable_position.horz
        cable_y = cable_position.vert

        # Build the parameter list exactly as in the original's logic
        coax1_params_vector = Vector{Tuple{String,String}}() # Renamed variable
        # Base parameters
        push!(coax1_params_vector, ("CABNUM", "$i"))
        push!(coax1_params_vector, ("Name", "$(cable_position.design_data.cable_id)"))
        push!(coax1_params_vector, ("X", format_nominal(cable_x)))
        push!(coax1_params_vector, ("OHC", "$(cable_y < 0 ? 0 : 1)"))
        push!(
            coax1_params_vector,
            ("Y", (cable_y < 0 ? format_nominal(abs(cable_y)) : "0.0")),
        )
        push!(coax1_params_vector, ("Y2", (cable_y > 0 ? format_nominal(cable_y) : "0.0")))
        push!(coax1_params_vector, ("ShuntA", "1.0e-11 [mho/m]"))
        push!(coax1_params_vector, ("FLT", format_nominal(base_freq)))
        push!(coax1_params_vector, ("RorT", "0"))
        push!(coax1_params_vector, ("LL", "$(2*num_cable_parts-1)"))
        push!(coax1_params_vector, ("CROSSBOND", "0"))
        push!(coax1_params_vector, ("GROUPNO", "1"))
        push!(
            coax1_params_vector,
            ("CBC1", "1"),
            ("CBC2", "0"),
            ("CBC3", "0"),
            ("CBC4", "0"),
        )
        push!(coax1_params_vector, ("SHRad", "1"))
        push!(coax1_params_vector, ("LC", "3"))

        # Component parameters (Keep identical logic)
        ω = 2 * π * base_freq
        for (idx, component_id) in enumerate(component_ids)
            component = cable_position.design_data.components[component_id]
            C_eq = component.insulator_group.shunt_capacitance
            G_eq = component.insulator_group.shunt_conductance
            loss_factor = C_eq > 1e-18 ? G_eq / (ω * C_eq) : 0.0 # Avoid NaN/Inf

            sig_digits_props = 6
            max_loss_tangent = 10.0

            if idx == 1 # Core
                push!(coax1_params_vector, ("CONNAM1", uppercasefirst(component.id)))
                push!(
                    coax1_params_vector,
                    ("R1", format_nominal(component.conductor_group.radius_in)),
                )
                push!(
                    coax1_params_vector,
                    ("R2", format_nominal(component.conductor_group.radius_ext)),
                )
                push!(
                    coax1_params_vector,
                    (
                        "RHOC",
                        format_nominal(
                            component.conductor_props.rho,
                            sigdigits=sig_digits_props,
                        ),
                    ),
                )
                push!(
                    coax1_params_vector,
                    (
                        "PERMC",
                        format_nominal(
                            component.conductor_props.mu_r,
                            sigdigits=sig_digits_props,
                        ),
                    ),
                )
                push!(
                    coax1_params_vector,
                    ("R3", format_nominal(component.insulator_group.radius_ext)),
                )
                push!(coax1_params_vector, ("T3", "0.0000"))
                push!(coax1_params_vector, ("SemiCL", "0"))
                push!(coax1_params_vector, ("SL2", "0.0000"))
                push!(coax1_params_vector, ("SL1", "0.0000"))
                push!(
                    coax1_params_vector,
                    (
                        "EPS1",
                        format_nominal(
                            component.insulator_props.eps_r,
                            sigdigits=sig_digits_props,
                        ),
                    ),
                )
                push!(
                    coax1_params_vector,
                    (
                        "PERM1",
                        format_nominal(
                            component.insulator_props.mu_r,
                            sigdigits=sig_digits_props,
                        ),
                    ),
                )
                push!(
                    coax1_params_vector,
                    (
                        "LT1",
                        format_nominal(
                            loss_factor,
                            sigdigits=sig_digits_props,
                            maxval=max_loss_tangent,
                        ),
                    ),
                )
            elseif idx == 2 # Sheath
                push!(coax1_params_vector, ("CONNAM2", uppercasefirst(component.id)))
                push!(
                    coax1_params_vector,
                    ("R4", format_nominal(component.conductor_group.radius_ext)),
                )
                push!(coax1_params_vector, ("T4", "0.0000"))
                push!(
                    coax1_params_vector,
                    (
                        "RHOS",
                        format_nominal(
                            component.conductor_props.rho,
                            sigdigits=sig_digits_props,
                        ),
                    ),
                )
                push!(
                    coax1_params_vector,
                    (
                        "PERMS",
                        format_nominal(
                            component.conductor_props.mu_r,
                            sigdigits=sig_digits_props,
                        ),
                    ),
                )
                push!(coax1_params_vector, ("elim1", elim1))
                push!(
                    coax1_params_vector,
                    ("R5", format_nominal(component.insulator_group.radius_ext)),
                )
                push!(coax1_params_vector, ("T5", "0.0000"))
                push!(
                    coax1_params_vector,
                    (
                        "EPS2",
                        format_nominal(
                            component.insulator_props.eps_r,
                            sigdigits=sig_digits_props,
                        ),
                    ),
                )
                push!(
                    coax1_params_vector,
                    (
                        "PERM2",
                        format_nominal(
                            component.insulator_props.mu_r,
                            sigdigits=sig_digits_props,
                        ),
                    ),
                )
                push!(
                    coax1_params_vector,
                    (
                        "LT2",
                        format_nominal(
                            loss_factor,
                            sigdigits=sig_digits_props,
                            maxval=max_loss_tangent,
                        ),
                    ),
                )
            elseif idx == 3 # Armor
                push!(coax1_params_vector, ("CONNAM3", uppercasefirst(component.id)))
                push!(
                    coax1_params_vector,
                    ("R6", format_nominal(component.conductor_group.radius_ext)),
                )
                push!(coax1_params_vector, ("T6", "0.0000"))
                push!(
                    coax1_params_vector,
                    (
                        "RHOA",
                        format_nominal(
                            component.conductor_props.rho,
                            sigdigits=sig_digits_props,
                        ),
                    ),
                )
                push!(
                    coax1_params_vector,
                    (
                        "PERMA",
                        format_nominal(
                            component.conductor_props.mu_r,
                            sigdigits=sig_digits_props,
                        ),
                    ),
                )
                push!(coax1_params_vector, ("elim2", elim2))
                push!(
                    coax1_params_vector,
                    ("R7", format_nominal(component.insulator_group.radius_ext)),
                )
                push!(coax1_params_vector, ("T7", "0.0000"))
                push!(
                    coax1_params_vector,
                    (
                        "EPS3",
                        format_nominal(
                            component.insulator_props.eps_r,
                            sigdigits=sig_digits_props,
                        ),
                    ),
                )
                push!(
                    coax1_params_vector,
                    (
                        "PERM3",
                        format_nominal(
                            component.insulator_props.mu_r,
                            sigdigits=sig_digits_props,
                        ),
                    ),
                )
                push!(
                    coax1_params_vector,
                    (
                        "LT3",
                        format_nominal(
                            loss_factor,
                            sigdigits=sig_digits_props,
                            maxval=max_loss_tangent,
                        ),
                    ),
                )
            elseif idx == 4 # Outer
                push!(coax1_params_vector, ("CONNAM4", uppercasefirst(component.id)))
                push!(
                    coax1_params_vector,
                    ("R8", format_nominal(component.conductor_group.radius_ext)),
                )
                push!(coax1_params_vector, ("T8", "0.0000"))
                push!(
                    coax1_params_vector,
                    (
                        "RHOO",
                        format_nominal(
                            component.conductor_props.rho,
                            sigdigits=sig_digits_props,
                        ),
                    ),
                )
                push!(
                    coax1_params_vector,
                    (
                        "PERMO",
                        format_nominal(
                            component.conductor_props.mu_r,
                            sigdigits=sig_digits_props,
                        ),
                    ),
                )
                push!(coax1_params_vector, ("elim3", elim3))
                push!(
                    coax1_params_vector,
                    ("R9", format_nominal(component.insulator_group.radius_ext)),
                )
                push!(coax1_params_vector, ("T9", "0.0000"))
                push!(
                    coax1_params_vector,
                    (
                        "EPS4",
                        format_nominal(
                            component.insulator_props.eps_r,
                            sigdigits=sig_digits_props,
                        ),
                    ),
                )
                push!(
                    coax1_params_vector,
                    (
                        "PERM4",
                        format_nominal(
                            component.insulator_props.mu_r,
                            sigdigits=sig_digits_props,
                        ),
                    ),
                )
                push!(
                    coax1_params_vector,
                    (
                        "LT4",
                        format_nominal(
                            loss_factor,
                            sigdigits=sig_digits_props,
                            maxval=max_loss_tangent,
                        ),
                    ),
                )
            end
        end

        # Default empty values (Keep identical logic)
        if num_cable_parts < 2
            append!(
                coax1_params_vector,
                [
                    ("CONNAM2", "none"),
                    ("R4", "0.0"),
                    ("T4", "0.0000"),
                    ("RHOS", "0.0"),
                    ("PERMS", "0.0"),
                    ("elim1", "0"),
                    ("R5", "0.0"),
                    ("T5", "0.0000"),
                    ("EPS2", "0.0"),
                    ("PERM2", "0.0"),
                    ("LT2", "0.0000"),
                ],
            )
        end
        if num_cable_parts < 3
            append!(
                coax1_params_vector,
                [
                    ("CONNAM3", "none"),
                    ("R6", "0.0"),
                    ("T6", "0.0000"),
                    ("RHOA", "0.0"),
                    ("PERMA", "0.0"),
                    ("elim2", "0"),
                    ("R7", "0.0"),
                    ("T7", "0.0000"),
                    ("EPS3", "0.0"),
                    ("PERM3", "0.0"),
                    ("LT3", "0.0000"),
                ],
            )
        end
        if num_cable_parts < 4
            append!(
                coax1_params_vector,
                [
                    ("CONNAM4", "none"),
                    ("R8", "0.0"),
                    ("T8", "0.0000"),
                    ("RHOO", "0.0"),
                    ("PERMO", "0.0"),
                    ("elim3", "0"),
                    ("R9", "0.0"),
                    ("T9", "0.0000"),
                    ("EPS4", "0.0"),
                    ("PERM4", "0.0"),
                    ("LT4", "0.0000"),
                ],
            )
        end

        # Add all collected parameters to the paramlist created earlier
        _add_params_to_list!(coax1_pl, coax1_params_vector) # Use helper

    end # End Coax cable loop

    # --- Line_Ground Component (Use Helpers) ---
    ground = addelement!(row_schematic, "User")
    ground_id = _next_id()
    ground_attrs = Dict(
        "classid" => "UserCmp", "name" => "master:Line_Ground", "id" => ground_id,
        "x" => "504", "y" => "288", "w" => "793", "h" => "88", "z" => "-1",
        "orient" => "0",
        "defn" => "master:Line_Ground", "link" => "-1", "q" => "4", "disable" => "false",
    )
    _set_attributes!(ground, ground_attrs) # Use helper

    ground_pl = addelement!(ground, "paramlist")
    # Original sets attributes on paramlist AND adds params - replicate exactly
    ground_pl["link"] = "-1"
    ground_pl["name"] = ""
    ground_pl["crc"] = "-1"

    earth_layer = earth_props.layers[end]
    ground_params_vector = [ # Renamed variable
        ("EarthForm2", "0"), ("EarthForm", "3"), ("EarthForm3", "2"), ("GrRho", "0"),
        ("GRRES", format_nominal(earth_layer.base_rho_g)),
        ("GPERM", format_nominal(earth_layer.base_mur_g)),
        ("K0", "0.001"), ("K1", "0.01"), ("alpha", "0.7"),
        ("GRP", format_nominal(earth_layer.base_epsr_g)),
    ]
    _add_params_to_list!(ground_pl, ground_params_vector) # Use helper

    # --- Resource List and Hierarchy (Identical Nested Structure from Original) ---
    addelement!(project, "List")["classid"] = "Resource"

    hierarchy = addelement!(project, "hierarchy")
    # Nested calls exactly as in the original, linking to INSTANCE IDs from id_map
    call1 = addelement!(hierarchy, "call")
    # The link should be to the Station Definition ID, not an instance
    call1["link"] = id_map["DS_Defn"] # Corrected link
    call1["name"] = "$project_id:DS"
    call1["z"] = "-1"
    call1["view"] = "false"
    call1["instance"] = "0"

    call2 = addelement!(call1, "call")
    call2["link"] = id_map["Main"] # Links to Main User INSTANCE ID (as per original id_map usage)
    call2["name"] = "$project_id:Main"
    call2["z"] = "-1"
    call2["view"] = "false"
    call2["instance"] = "0"

    call3 = addelement!(call2, "call")
    call3["link"] = id_map["CableSystem"] # Links to CableSystem User INSTANCE ID (as per original id_map usage)
    call3["name"] = "$project_id:CableSystem"
    call3["z"] = "-1"
    call3["view"] = "true"
    call3["instance"] = "0"

    try
        # Use pretty print option for debugging comparisons if needed
        # open(filename, "w") do io; prettyprint(io, doc); end
        write(file_name, doc) # Standard write
        if isfile(file_name)
            println("PSCAD file saved to: ", _display_path(file_name))
        end
        return file_name
    catch e
        println("ERROR: Failed to write PSCAD file '$(_display_path(file_name))': ", e)
        isa(e, SystemError) && println("SystemError details: ", e.extrainfo)
        return nothing
        rethrow(e) # Rethrow to indicate failure clearly
    end
end

"""
$(TYPEDSIGNATURES)

Defines which fields of a given object should be serialized to JSON.
This function acts as a trait. Specific types should overload this method
to customize which fields are needed for reconstruction.

# Arguments

- `obj`: The object whose serializable fields are to be determined.

# Returns

- A tuple of symbols representing the fields of `obj` that should be serialized.

# Methods

$(_CLEANMETHODLIST)
"""
function _serializable_fields end

# Default fallback: Serialize all fields. This might include computed fields
# that are not needed for reconstruction. Overload for specific types.
_serializable_fields(obj::T) where {T} = fieldnames(T)

# Define exactly which fields are needed to reconstruct each object.
# These typically match the constructor arguments or the minimal set
# required by the reconstruction logic (e.g., for groups).

# Core Data Types
_serializable_fields(::Material) = (:rho, :eps_r, :mu_r, :T0, :alpha)
_serializable_fields(::NominalData) = (
    :designation_code,
    :U0,
    :U,
    :conductor_cross_section,
    :screen_cross_section,
    :armor_cross_section,
    :resistance,
    :capacitance,
    :inductance,
)

# Layer Types (Conductor Parts)
_serializable_fields(::WireArray) = (
    :radius_in, # Needed for first layer reconstruction
    :radius_wire,
    :num_wires,
    :lay_ratio,
    :material_props,
    :temperature,
    :lay_direction,
)
_serializable_fields(::Tubular) = (
    :radius_in, # Needed for first layer reconstruction
    :radius_ext,
    :material_props,
    :temperature,
)
_serializable_fields(::Strip) = (
    :radius_in, # Needed for first layer reconstruction
    :radius_ext,
    :width,
    :lay_ratio,
    :material_props,
    :temperature,
    :lay_direction,
)

# Layer Types (Insulator Parts)
_serializable_fields(::Insulator) = (
    :radius_in, # Needed for first layer reconstruction
    :radius_ext,
    :material_props,
    :temperature,
)
_serializable_fields(::Semicon) = (
    :radius_in, # Needed for first layer reconstruction
    :radius_ext,
    :material_props,
    :temperature,
)

# Group Types - Only serialize the layers needed for reconstruction.
_serializable_fields(::ConductorGroup) = (:layers,)
_serializable_fields(::InsulatorGroup) = (:layers,)

# Component & Design Types
_serializable_fields(::CableComponent) = (:id, :conductor_group, :insulator_group)
# For CableDesign, we need components and nominal data. ID is handled as the key.
_serializable_fields(::CableDesign) = (:cable_id, :nominal_data, :components)

# Library Types
_serializable_fields(::CablesLibrary) = (:cable_designs,)
_serializable_fields(::MaterialsLibrary) = (:materials,)


#=
Serializes a Julia value into a JSON-compatible representation.
Handles special types like Measurements, Inf/NaN, Symbols, and custom structs
using the `_serializable_fields` trait.

# Arguments
- `value`: The Julia value to serialize.

# Returns
- A JSON-compatible representation (Dict, Vector, Number, String, Bool, Nothing).
=#
function _serialize_value(value)
    if isnothing(value)
        return nothing
    elseif value isa Measurements.Measurement
        # Explicitly mark Measurements for robust deserialization
        return Dict(
            "__type__" => "Measurement",
            "value" => _serialize_value(Measurements.value(value)),
            "uncertainty" => _serialize_value(Measurements.uncertainty(value)),
        )
    elseif value isa Number && !isfinite(value)
        # Handle Inf and NaN
        local val_str
        if isinf(value)
            val_str = value > 0 ? "Inf" : "-Inf"
        elseif isnan(value)
            val_str = "NaN"
        else
            # Should not happen based on !isfinite, but defensive
            @warn "Unhandled non-finite number: $value. Serializing as string."
            return string(value)
        end
        return Dict("__type__" => "SpecialFloat", "value" => val_str)
    elseif value isa Number || value isa String || value isa Bool
        # Basic JSON types pass through
        return value
    elseif value isa Symbol
        # Convert Symbols to strings
        return string(value)
    elseif value isa AbstractDict
        # Recursively serialize dictionary values
        # Use string keys for JSON compatibility
        return Dict(string(k) => _serialize_value(v) for (k, v) in value)
    elseif value isa Union{AbstractVector,Tuple}
        # Recursively serialize array/tuple elements
        return [_serialize_value(v) for v in value]
    elseif !isprimitivetype(typeof(value)) && fieldcount(typeof(value)) > 0
        # Handle custom structs using _serialize_obj
        return _serialize_obj(value)
    else
        # Fallback for unhandled types - serialize as string with a warning
        @warn "Serializing unsupported type $(typeof(value)) to string: $value"
        return string(value)
    end
end

"""
$(TYPEDSIGNATURES)

Serializes a Julia value into a JSON-compatible representation.
Handles special types like Measurements, Inf/NaN, Symbols, and custom structs
using the [`_serializable_fields`](@ref) trait.

# Arguments
- `value`: The Julia value to serialize.

# Returns
- A JSON-compatible representation (Dict, Vector, Number, String, Bool, Nothing).
"""
function _serialize_obj(obj)
    T = typeof(obj)
    # Get fully qualified type name (e.g., Main.MyModule.MyType)
    try
        mod = parentmodule(T)
        typeName = nameof(T)
        type_str = string(mod, ".", typeName)

        result = Dict{String,Any}()
        result["__julia_type__"] = type_str

        # Get the fields to serialize using the trait function
        fields_to_include = _serializable_fields(obj)

        # Iterate only through the fields specified by the trait
        for field in fields_to_include
            if hasproperty(obj, field)
                value = getfield(obj, field)
                result[string(field)] = _serialize_value(value) # Recursively serialize
            else
                # This indicates an issue with the _serializable_fields definition for T
                @warn "Field :$field specified by _serializable_fields(::$T) not found in object. Skipping."
            end
        end
        return result
    catch e
        @error "Error determining module or type name for object of type $T: $e. Cannot serialize."
        # Return a representation indicating the error
        return Dict(
            "__error__" => "Serialization failed for type $T",
            "__details__" => string(e),
        )
    end
end


"""
$(TYPEDSIGNATURES)

Resolves a fully qualified type name string (e.g., \"Module.Type\")
into a Julia `Type` object. Assumes the type is loaded in the current environment.

# Arguments
- `type_str`: The string representation of the type.

# Returns
- The corresponding Julia `Type` object.

# Throws
- `Error` if the type cannot be resolved.
"""
function _resolve_type(type_str::String)
    try
        return Core.eval(Main, Meta.parse(type_str))
        # Alternative using getfield (might be slightly safer but less flexible with nested modules):
        # parts = split(type_str, '.')
        # current_module = Main
        # for i in 1:length(parts)-1
        #     current_module = getfield(current_module, Symbol(parts[i]))
        # end
        # return getfield(current_module, Symbol(parts[end]))
    catch e
        @error "Could not resolve type '$type_str'. Ensure module structure is correct and type is loaded in Main."
        rethrow(e)
    end
end

"""
$(TYPEDSIGNATURES)

Deserializes a value from its JSON representation back into a Julia value.
Handles special type markers for `Measurements`, `Inf`/`NaN`, and custom structs
identified by `__julia_type__`. Ensures plain dictionaries use Symbol keys.

# Arguments
- `value`: The JSON-parsed value (Dict, Vector, Number, String, Bool, Nothing).

# Returns
- The deserialized Julia value.
"""
function _deserialize_value(value)
    if value isa Dict
        # Check for special type markers first
        if haskey(value, "__type__")
            type_marker = value["__type__"]
            if type_marker == "Measurement"
                # Reconstruct Measurement
                val = _deserialize_value(get(value, "value", nothing))
                unc = _deserialize_value(get(value, "uncertainty", nothing))
                if isa(val, Number) && isa(unc, Number)
                    return val ± unc
                else
                    @warn "Could not reconstruct Measurement from non-numeric parts: value=$(typeof(val)), uncertainty=$(typeof(unc)). Returning original Dict."
                    return value # Return original dict if parts are invalid
                end
            elseif type_marker == "SpecialFloat"
                # Reconstruct Inf/NaN
                val_str = get(value, "value", "")
                if val_str == "Inf"
                    return Inf
                end
                if val_str == "-Inf"
                    return -Inf
                end
                if val_str == "NaN"
                    return NaN
                end
                @warn "Unknown SpecialFloat value: '$val_str'. Returning original Dict."
                return value
            else
                @warn "Unknown __type__ marker: '$type_marker'. Processing as regular dictionary."
                # Fall through to regular dictionary processing
            end
        end

        # Check for Julia object marker
        if haskey(value, "__julia_type__")
            type_str = value["__julia_type__"]
            try
                T = _resolve_type(type_str)
                # Delegate object construction to _deserialize_obj
                return _deserialize_obj(value, T)
            catch e
                # Catch errors specifically from _deserialize_obj or _resolve_type
                @error "Failed to resolve or deserialize type '$type_str': $e. Returning original Dict."
                # Optionally print stack trace for debugging
                # showerror(stderr, e, catch_backtrace())
                # println(stderr)
                return value # Return original dict on error
            end
        end

        # If no special markers, process as a regular dictionary
        # Recursively deserialize values, using SYMBOL keys
        # *** FIX APPLIED HERE ***
        return Dict(Symbol(k) => _deserialize_value(v) for (k, v) in value)

    elseif value isa Vector
        # Recursively deserialize array elements
        return [_deserialize_value(v) for v in value]
    else
        # Basic JSON types (Number, String, Bool, Nothing) pass through
        return value
    end
end

"""
$(TYPEDSIGNATURES)

Deserializes a dictionary (parsed from JSON) into a Julia object of type `T`.
Attempts keyword constructor first, then falls back to positional constructor
if the keyword attempt fails with a specific `MethodError`.

# Arguments
- `dict`: Dictionary containing the serialized object data. Keys should match field names.
- `T`: The target Julia `Type` to instantiate.

# Returns
- An instance of type `T`.

# Throws
- `Error` if construction fails by both methods.
"""
function _deserialize_obj(dict::Dict, ::Type{T}) where {T}
    # Prepare a dictionary mapping field symbols to deserialized values
    deserialized_fields = Dict{Symbol,Any}()
    for (key_str, val) in dict
        # Skip metadata keys
        if key_str == "__julia_type__" || key_str == "__type__"
            continue
        end
        key_sym = Symbol(key_str)
        # Ensure value is deserialized before storing
        deserialized_fields[key_sym] = _deserialize_value(val)
    end

    # --- Attempt 1: Keyword Constructor ---
    try
        # Convert Dict{Symbol, Any} to pairs for keyword constructor T(; pairs...)
        # Ensure kwargs only contain keys that are valid fieldnames for T
        # This prevents errors if extra keys were present in JSON
        valid_keys = fieldnames(T)
        kwargs = pairs(filter(p -> p.first in valid_keys, deserialized_fields))

        # @info "Attempting keyword construction for $T with kwargs: $(collect(kwargs))" # Debug logging
        if !isempty(kwargs) || hasmethod(T, Tuple{}, Symbol[]) # Check if kw constructor exists or if kwargs are empty
            return T(; kwargs...)
        else
            # If no kwargs and no zero-arg kw constructor, trigger fallback
            error(
                "No keyword arguments provided and no zero-argument keyword constructor found for $T.",
            )
        end
    catch e
        # Check if the error is specifically a MethodError for the keyword call
        is_kw_meth_error =
            e isa MethodError && (e.f === Core.kwcall || (e.f === T && isempty(e.args))) # Check for kwcall or zero-arg method error

        if is_kw_meth_error
            # @info "Keyword construction failed for $T (as expected for types without kw constructor). Trying positional." # Debug logging
            # Fall through to positional attempt
        else
            # Different error during keyword construction (e.g., type mismatch inside constructor)
            @error "Keyword construction failed for type $T with unexpected error: $e"
            println(stderr, "Input dictionary: $dict")
            println(stderr, "Deserialized fields (kwargs used): $(deserialized_fields)")
            rethrow(e) # Rethrow unexpected errors
        end
    end

    # --- Attempt 2: Positional Constructor (Fallback) ---
    # @info "Attempting positional construction for $T" # Debug logging
    fields_in_order = fieldnames(T)
    positional_args = []

    try
        # Check if the number of deserialized fields matches the number of struct fields
        # This is a basic check for suitability of positional constructor
        # It might be too strict if optional fields were omitted in JSON for keyword constructor types
        # but for true positional types, all fields should generally be present.
        # if length(deserialized_fields) != length(fields_in_order)
        #     error("Number of fields in JSON ($(length(deserialized_fields))) does not match number of fields in struct $T ($(length(fields_in_order))). Cannot use positional constructor.")
        # end

        for field_sym in fields_in_order
            if haskey(deserialized_fields, field_sym)
                push!(positional_args, deserialized_fields[field_sym])
            else
                # If a field is missing, positional construction will fail.
                error(
                    "Cannot attempt positional construction for $T: Missing required field '$field_sym' in input data.",
                )
            end
        end

        # @info "Positional args for $T: $positional_args" # Debug logging
        return T(positional_args...)
    catch e
        # Catch errors during positional construction (e.g., MethodError, TypeError)
        @error "Positional construction failed for type $T with args: $positional_args. Error: $e"
        println(stderr, "Input dictionary: $dict")
        println(
            stderr,
            "Deserialized fields used for positional args: $(deserialized_fields)",
        )
        # Check argument count mismatch again, although the loop above should ensure it if no error occurred there
        if length(positional_args) != length(fields_in_order)
            println(
                stderr,
                "Mismatch between number of args provided ($(length(positional_args))) and fields expected ($(length(fields_in_order))).",
            )
        end
        # Rethrow the error after providing context. This indicates neither method worked.
        rethrow(e)
    end

    # This line should ideally not be reached
    error(
        "Failed to construct object of type $T using both keyword and positional methods.",
    )
end

"""
$(TYPEDSIGNATURES)

Saves a [`CablesLibrary`](@ref) to a file.
The format is determined by the file extension:
- `.json`: Saves using the custom JSON serialization.
- `.jls`: Saves using Julia native binary serialization.

# Arguments
- `library`: The [`CablesLibrary`](@ref) instance to save.
- `file_name`: The path to the output file (default: "cables_library.json").

# Returns
- The absolute path of the saved file, or `nothing` on failure.
"""
function save_cableslibrary(
    library::CablesLibrary;
    file_name::String="cables_library.json",
)::Union{String,Nothing}

    file_name = isabspath(file_name) ? file_name : joinpath(@__DIR__, file_name)

    _, ext = splitext(file_name)
    ext = lowercase(ext)

    try
        if ext == ".jls"
            return _save_cableslibrary_jls(library, file_name)
        elseif ext == ".json"
            return _save_cableslibrary_json(library, file_name)
        else
            @warn "Unrecognized file extension '$ext' for CablesLibrary. Defaulting to .json format."
            # Ensure filename has .json extension if defaulting
            if ext != ".json"
                file_name = file_name * ".json"
            end
            return _save_cableslibrary_json(library, file_name)
        end
    catch e
        @error "Error saving CablesLibrary to '$(_display_path(file_name))': $e"
        showerror(stderr, e, catch_backtrace())
        println(stderr)
        return nothing
    end
end

"""
$(TYPEDSIGNATURES)

Saves the [`CablesLibrary`](@ref) using Julia native binary serialization.
This format is generally not portable across Julia versions or machine architectures
but can be faster and preserves exact types.

# Arguments
- `library`: The [`CablesLibrary`](@ref) instance.
- `file_name`: The output file path (should end in `.jls`).

# Returns
- The absolute path of the saved file.
"""
function _save_cableslibrary_jls(library::CablesLibrary, file_name::String)::String
    # Note: Serializing the whole library object directly might be problematic
    # if the library struct itself changes. Serializing the core data (designs) is safer.
    serialize(file_name, library.cable_designs)
    println("Cables library saved using Julia serialization to: ", _display_path(file_name))
    return abspath(file_name)
end

"""
$(TYPEDSIGNATURES)

Saves the [`CablesLibrary`](@ref) to a JSON file using the custom serialization logic.

# Arguments
- `library`: The [`CablesLibrary`](@ref) instance.
- `file_name`: The output file path (should end in `.json`).

# Returns
- The absolute path of the saved file.
"""
function _save_cableslibrary_json(library::CablesLibrary, file_name::String)::String
    # Use the generic _serialize_value, which will delegate to _serialize_obj
    # for the library object, which in turn uses _serializable_fields(::CablesLibrary)
    serialized_library = _serialize_value(library)

    open(file_name, "w") do io
        # Use JSON3.pretty for human-readable output
        # allow_inf=true is needed if Measurements or other fields might contain Inf
        JSON3.pretty(io, serialized_library, allow_inf=true)
    end
    if isfile(file_name)
        println("Cables library saved to: ", _display_path(file_name))
    end
    return abspath(file_name)
end

"""
$(TYPEDSIGNATURES)

Saves a [`MaterialsLibrary`](@ref) to a JSON file.

# Arguments
- `library`: The [`MaterialsLibrary`](@ref) instance to save.
- `file_name`: The path to the output JSON file (default: "materials_library.json").

# Returns
- The absolute path of the saved file, or `nothing` on failure.
"""
function save_materialslibrary(
    library::MaterialsLibrary;
    file_name::String="materials_library.json",
)::Union{String,Nothing}
    # TODO: Add jls serialization to materials library.
    # Issue URL: https://github.com/Electa-Git/LineCableModels.jl/issues/3
    file_name = isabspath(file_name) ? file_name : joinpath(@__DIR__, file_name)


    _, ext = splitext(file_name)
    ext = lowercase(ext)
    if ext != ".json"
        @warn "MaterialsLibrary only supports .json saving. Forcing extension for file '$file_name'."
        file_name = first(splitext(file_name)) * ".json"
    end

    try

        return _save_materialslibrary_json(library, file_name)

    catch e
        @error "Error saving MaterialsLibrary to '$(_display_path(file_name))': $e"
        showerror(stderr, e, catch_backtrace())
        println(stderr)
        return nothing
    end
end

"""
$(TYPEDSIGNATURES)

Internal function to save the [`MaterialsLibrary`](@ref) to JSON.

# Arguments
- `library`: The [`MaterialsLibrary`](@ref) instance.
- `file_name`: The output file path.

# Returns
- The absolute path of the saved file.
"""
function _save_materialslibrary_json(library::MaterialsLibrary, file_name::String)::String
    # Check if the library has the materials field initialized correctly
    if !isdefined(library, :materials) || !(library.materials isa AbstractDict)
        error("MaterialsLibrary does not have a valid 'materials' dictionary. Cannot save.")
    end

    # Use the generic _serialize_value, which handles the dictionary and its Material contents
    serialized_library_data = _serialize_value(library.materials) # Serialize the dict directly

    open(file_name, "w") do io
        JSON3.pretty(io, serialized_library_data, allow_inf=true)
    end
    if isfile(file_name)
        println("Materials library saved to: ", _display_path(file_name))
    end

    return abspath(file_name)
end

"""
$(TYPEDSIGNATURES)

Loads cable designs from a file into an existing [`CablesLibrary`](@ref) object.
Modifies the library in-place.
The format is determined by the file extension:
- `.json`: Loads using the custom JSON deserialization and reconstruction.
- `.jls`: Loads using Julia's native binary deserialization.

# Arguments
- `library`: The [`CablesLibrary`](@ref) instance to populate (modified in-place).
- `file_name`: Path to the file to load (default: "cables_library.json").

# Returns
- The modified [`CablesLibrary`](@ref) instance.
"""
function load_cableslibrary!(
    library::CablesLibrary; # Type annotation ensures it's the correct object
    file_name::String="cables_library.json",
)::CablesLibrary # Return the modified library
    if !isfile(file_name)
        @warn "Cables library file not found: '$(_display_path(file_name))'. Library remains unchanged."
        # Ensure the library has the necessary field, even if empty
        if !isdefined(library, :cable_designs) || !(library.cable_designs isa AbstractDict)
            library.cable_designs = Dict{String,CableDesign}()
        end
        return library
    end

    _, ext = splitext(file_name)
    ext = lowercase(ext)

    try
        if ext == ".jls"
            _load_cableslibrary_jls!(library, file_name)
        elseif ext == ".json"
            _load_cableslibrary_json!(library, file_name)
        else
            @warn "Unrecognized file extension '$ext' for CablesLibrary. Attempting to load as .json."
            _load_cableslibrary_json!(library, file_name)
        end
    catch e
        @error "Error loading CablesLibrary from '$(_display_path(file_name))': $e"
        showerror(stderr, e, catch_backtrace())
        println(stderr)
        # Optionally clear the library or leave it partially loaded depending on desired robustness
        # empty!(library.cable_designs)
    end
    return library # Return the modified library
end

"""
$(TYPEDSIGNATURES)

Loads cable designs from a Julia binary serialization file (`.jls`)
into the provided library object.

# Arguments
- `library`: The [`CablesLibrary`](@ref) instance to modify.
- `file_name`: The path to the `.jls` file.

# Returns
- Nothing. Modifies `library` in-place.
"""
function _load_cableslibrary_jls!(library::CablesLibrary, file_name::String)
    loaded_data = deserialize(file_name)

    if isa(loaded_data, Dict{String,CableDesign})
        # Replace the existing designs
        library.cable_designs = loaded_data
        println(
            "Cables library successfully loaded via Julia deserialization from: ",
            _display_path(file_name),
        )
    else
        # This indicates the .jls file did not contain the expected dictionary structure
        @error "Invalid data format in '$(_display_path(file_name))'. Expected Dict{String, CableDesign}, got $(typeof(loaded_data)). Library not loaded."
        # Ensure library.cable_designs exists if it was potentially wiped before load attempt
        if !isdefined(library, :cable_designs) || !(library.cable_designs isa AbstractDict)
            library.cable_designs = Dict{String,CableDesign}()
        end
    end
    return nothing
end

"""
$(TYPEDSIGNATURES)

Loads cable designs from a JSON file into the provided library object
using the detailed, sequential reconstruction logic.

# Arguments
- `library`: The [`CablesLibrary`](@ref) instance to modify.
- `file_name`: The path to the `.json` file.

# Returns
- Nothing. Modifies `library` in-place.
"""
function _load_cableslibrary_json!(library::CablesLibrary, file_name::String)
    # Ensure library structure is initialized
    if !isdefined(library, :cable_designs) || !(library.cable_designs isa AbstractDict)
        @warn "Library's 'cable_designs' field was not initialized or not a Dict. Initializing."
        library.cable_designs = Dict{String,CableDesign}()
    else
        # Clear existing designs before loading (common behavior)
        empty!(library.cable_designs)
    end

    # Load the entire JSON structure
    json_data = open(file_name, "r") do io
        JSON3.read(io, Dict{String,Any}) # Read the top level as a Dict
    end

    # The JSON might store designs directly under "cable_designs" key,
    # or the top level might be the dictionary of designs itself.
    local designs_to_process::Dict
    if haskey(json_data, "cable_designs") && json_data["cable_designs"] isa AbstractDict
        # Standard case: designs are under the "cable_designs" key
        designs_to_process = json_data["cable_designs"]
    elseif haskey(json_data, "__julia_type__") &&
           occursin("CablesLibrary", json_data["__julia_type__"]) &&
           haskey(json_data, "cable_designs")
        # Case where the entire library object was serialized
        designs_to_process = json_data["cable_designs"]
    elseif all(
        v ->
            v isa AbstractDict && haskey(v, "__julia_type__") &&
                occursin("CableDesign", v["__julia_type__"]),
        values(json_data),
    )
        # Fallback: Assume the top-level dict *is* the designs dict
        @info "Assuming top-level JSON object in '$(_display_path(file_name))' is the dictionary of cable designs."
        designs_to_process = json_data
    else
        @error "JSON file '$(_display_path(file_name))' does not contain a recognizable 'cable_designs' dictionary or structure."
        return nothing # Exit loading process
    end

    println("Loading cable designs from JSON: '$(_display_path(file_name))'...")
    num_loaded = 0
    num_failed = 0

    # Process each cable design entry using manual reconstruction
    for (cable_id, design_data) in designs_to_process
        if !(design_data isa AbstractDict)
            @warn "Skipping entry '$cable_id': Invalid data format (expected Dictionary, got $(typeof(design_data)))."
            num_failed += 1
            continue
        end
        try
            # Reconstruct the design using the dedicated function
            reconstructed_design =
                _reconstruct_cabledesign(string(cable_id), design_data)
            # Store the fully reconstructed design in the library
            library.cable_designs[string(cable_id)] = reconstructed_design
            num_loaded += 1
        catch e
            num_failed += 1
            @error "Failed to reconstruct cable design '$cable_id': $e"
            # Show stacktrace for detailed debugging, especially for MethodErrors during construction
            showerror(stderr, e, catch_backtrace())
            println(stderr) # Add newline for clarity
        end
    end

    println(
        "Finished loading from '$(_display_path(file_name))'. Successfully loaded $num_loaded cable designs, failed to load $num_failed.",
    )
    return nothing
end

"""
$(TYPEDSIGNATURES)

Helper function to reconstruct a [`ConductorGroup`](@ref) or [`InsulatorGroup`](@ref) object with the first layer of the respective [`AbstractCablePart`](@ref). Subsequent layers are added using `addto_*` methods.

# Arguments
- `layer_data`: Dictionary containing the data for the first layer, parsed from JSON.

# Returns
- A reconstructed [`ConductorGroup`](@ref) object with the initial [`AbstractCablePart`](@ref).

# Throws
- Error if essential data is missing or the layer type is unsupported.
"""
function _reconstruct_partsgroup(layer_data::Dict)
    if !haskey(layer_data, "__julia_type__")
        error("Layer data missing '__julia_type__' key: $layer_data")
    end
    type_str = layer_data["__julia_type__"]
    LayerType = _resolve_type(type_str)

    # Use generic deserialization for the whole layer data first.
    # _deserialize_value now returns Dict{Symbol, Any} for plain dicts
    local deserialized_layer_dict::Dict{Symbol,Any}
    try
        # Temporarily remove type key to avoid recursive loop in _deserialize_value -> _deserialize_obj
        temp_data = filter(p -> p.first != "__julia_type__", layer_data)
        deserialized_layer_dict = _deserialize_value(temp_data) # Should return Dict{Symbol, Any}
    catch e
        # This fallback might not be strictly needed anymore if _deserialize_value is robust,
        # but kept for safety. It also needs to produce Dict{Symbol, Any}.
        @error "Initial deserialization failed for first layer data ($type_str): $e. Trying manual field extraction."
        deserialized_layer_dict = Dict{Symbol,Any}()
        for (k_str, v) in layer_data # k_str is String from JSON parsing
            if k_str != "__julia_type__"
                deserialized_layer_dict[Symbol(k_str)] = _deserialize_value(v) # Deserialize value, use Symbol key
            end
        end
    end

    # Ensure the result is Dict{Symbol, Any}
    if !(deserialized_layer_dict isa Dict{Symbol,Any})
        error(
            "Internal error: deserialized_layer_dict is not Dict{Symbol, Any}, but $(typeof(deserialized_layer_dict))",
        )
    end

    # Extract necessary fields using get with Symbol keys
    radius_in = get(deserialized_layer_dict, :radius_in, missing)
    material_props = get(deserialized_layer_dict, :material_props, missing)
    temperature = get(deserialized_layer_dict, :temperature, T₀) # Use default T₀ if missing

    # Check for essential properties common to most first layers
    ismissing(radius_in) &&
        error("Missing 'radius_in' for first layer type $LayerType in data: $layer_data")
    ismissing(material_props) && error(
        "Missing 'material_props' for first layer type $LayerType in data: $layer_data",
    )
    !(material_props isa Material) && error(
        "'material_props' did not deserialize to a Material object for first layer type $LayerType. Got: $(typeof(material_props))",
    )

    # Type-specific reconstruction using POSITIONAL constructors + Keywords
    # This requires knowing the exact constructor signatures.
    try
        if LayerType == WireArray
            radius_wire = get(deserialized_layer_dict, :radius_wire, missing)
            num_wires = get(deserialized_layer_dict, :num_wires, missing) # Should be Int
            lay_ratio = get(deserialized_layer_dict, :lay_ratio, missing)
            lay_direction = get(deserialized_layer_dict, :lay_direction, 1) # Default lay_direction
            # Validate required fields
            any(ismissing, (radius_wire, num_wires, lay_ratio)) && error(
                "Missing required field(s) (radius_wire, num_wires, lay_ratio) for WireArray first layer.",
            )
            # Ensure num_wires is Int
            num_wires_int = isa(num_wires, Int) ? num_wires : Int(num_wires)
            return WireArray(
                radius_in,
                radius_wire,
                num_wires_int,
                lay_ratio,
                material_props;
                temperature=temperature,
                lay_direction=lay_direction,
            )
        elseif LayerType == Tubular
            radius_ext = get(deserialized_layer_dict, :radius_ext, missing)
            ismissing(radius_ext) && error("Missing 'radius_ext' for Tubular first layer.")
            return Tubular(radius_in, radius_ext, material_props; temperature=temperature)
        elseif LayerType == Strip
            radius_ext = get(deserialized_layer_dict, :radius_ext, missing)
            width = get(deserialized_layer_dict, :width, missing)
            lay_ratio = get(deserialized_layer_dict, :lay_ratio, missing)
            lay_direction = get(deserialized_layer_dict, :lay_direction, 1)
            any(ismissing, (radius_ext, width, lay_ratio)) && error(
                "Missing required field(s) (radius_ext, width, lay_ratio) for Strip first layer.",
            )
            return Strip(
                radius_in,
                radius_ext,
                width,
                lay_ratio,
                material_props;
                temperature=temperature,
                lay_direction=lay_direction,
            )
        elseif LayerType == Insulator
            radius_ext = get(deserialized_layer_dict, :radius_ext, missing)
            ismissing(radius_ext) &&
                error("Missing 'radius_ext' for Insulator first layer.")
            return Insulator(
                radius_in,
                radius_ext,
                material_props;
                temperature=temperature,
            )
        elseif LayerType == Semicon
            radius_ext = get(deserialized_layer_dict, :radius_ext, missing)
            ismissing(radius_ext) && error("Missing 'radius_ext' for Semicon first layer.")
            return Semicon(radius_in, radius_ext, material_props; temperature=temperature)
        else
            error("Unsupported layer type for first layer reconstruction: $LayerType")
        end
    catch e
        @error "Construction failed for first layer of type $LayerType with data: $deserialized_layer_dict. Error: $e"
        rethrow(e)
    end
end

"""
$(TYPEDSIGNATURES)

Reconstructs a complete [`CableDesign`](@ref) object from its dictionary representation (parsed from JSON).
This function handles the sequential process of building cable designs:
 1. Deserialize [`NominalData`](@ref).
 2. Iterate through components.
 3. For each component:
    a. Reconstruct the first layer of the conductor group.
    b. Create the [`ConductorGroup`](@ref) with the first layer.
    c. Add subsequent conductor layers using [`addto_conductorgroup!`](@ref).
    d. Repeat a-c for the [`InsulatorGroup`](@ref).
    e. Create the [`CableComponent`](@ref).
 4. Create the [`CableDesign`](@ref) with the first component.
 5. Add subsequent components using [`addto_cabledesign!`](@ref).

# Arguments
- `cable_id`: The identifier string for the cable design.
- `design_data`: Dictionary containing the data for the cable design.

# Returns
- A fully reconstructed [`CableDesign`](@ref) object.

# Throws
- Error if reconstruction fails at any step.
"""
function _reconstruct_cabledesign(
    cable_id::String,
    design_data::Dict,
)::CableDesign
    println("Reconstructing CableDesign: $cable_id")

    # 1. Reconstruct NominalData using generic deserialization
    local nominal_data::NominalData
    if haskey(design_data, "nominal_data")
        # Ensure the input to _deserialize_value is the Dict for NominalData
        nominal_data_dict = design_data["nominal_data"]
        if !(nominal_data_dict isa AbstractDict)
            error(
                "Invalid format for 'nominal_data' in $cable_id: Expected Dictionary, got $(typeof(nominal_data_dict))",
            )
        end
        nominal_data_val = _deserialize_value(nominal_data_dict)
        if !(nominal_data_val isa NominalData)
            # This error check relies on _deserialize_value returning the original dict on failure
            error(
                "Field 'nominal_data' did not deserialize to a NominalData object for $cable_id. Got: $(typeof(nominal_data_val))",
            )
        end
        nominal_data = nominal_data_val
        println("  Reconstructed NominalData")
    else
        @warn "Missing 'nominal_data' for $cable_id. Using default NominalData()."
        nominal_data = NominalData() # Use default if missing
    end

    # 2. Process Components Sequentially
    components_data = get(design_data, "components", [])
    if isempty(components_data) || !(components_data isa AbstractVector)
        error("Missing or invalid 'components' array in design data for $cable_id")
    end

    reconstructed_components = CableComponent[] # Store fully built components

    for (idx, comp_data) in enumerate(components_data)
        if !(comp_data isa AbstractDict)
            @warn "Component data at index $idx for $cable_id is not a dictionary. Skipping."
            continue
        end
        comp_id = get(comp_data, "id", "UNKNOWN_COMPONENT_ID_$idx")
        println("  Processing Component $idx: $comp_id")

        # --- 2.1 Build Conductor Group ---
        local conductor_group::ConductorGroup
        conductor_group_data = get(comp_data, "conductor_group", Dict())
        cond_layers_data = get(conductor_group_data, "layers", [])

        if isempty(cond_layers_data) || !(cond_layers_data isa AbstractVector)
            error("Component '$comp_id' has missing or invalid conductor group layers.")
        end

        # - Create the FIRST layer object
        # Ensure the input to _reconstruct_partsgroup is the Dict for the layer
        first_layer_dict = cond_layers_data[1]
        if !(first_layer_dict isa AbstractDict)
            error(
                "Invalid format for first conductor layer in component '$comp_id': Expected Dictionary, got $(typeof(first_layer_dict))",
            )
        end
        first_cond_layer = _reconstruct_partsgroup(first_layer_dict)

        # - Initialize ConductorGroup using its constructor with the first layer
        conductor_group = ConductorGroup(first_cond_layer)
        println("    Created ConductorGroup with first layer: $(typeof(first_cond_layer))")

        # - Add remaining layers using addto_conductorgroup!
        for i in 2:lastindex(cond_layers_data)
            layer_data = cond_layers_data[i]
            if !(layer_data isa AbstractDict)
                @warn "Conductor layer data at index $i for component $comp_id is not a dictionary. Skipping."
                continue
            end

            # Extract Type and necessary arguments for addto_conductorgroup!
            LayerType = _resolve_type(layer_data["__julia_type__"])
            material_props = _deserialize_value(get(layer_data, "material_props", missing))
            ismissing(material_props) &&
                error("Missing 'material_props' for conductor layer $i in $comp_id")
            !(material_props isa Material) && error(
                "'material_props' did not deserialize to Material for conductor layer $i in $comp_id. Got: $(typeof(material_props))",
            )

            # Prepare args and kwargs based on LayerType for addto_conductorgroup!
            args = []
            kwargs = Dict{Symbol,Any}()
            kwargs[:temperature] = _deserialize_value(get(layer_data, "temperature", T₀))
            if haskey(layer_data, "lay_direction") # Only add if present
                kwargs[:lay_direction] =
                    _deserialize_value(get(layer_data, "lay_direction", 1))
            end

            # Extract type-specific arguments needed by addto_conductorgroup!
            try
                if LayerType == WireArray
                    radius_wire =
                        _deserialize_value(get(layer_data, "radius_wire", missing))
                    num_wires = get(layer_data, "num_wires", missing) # Should be Int
                    lay_ratio = _deserialize_value(get(layer_data, "lay_ratio", missing))
                    any(ismissing, (radius_wire, num_wires, lay_ratio)) && error(
                        "Missing required field(s) for WireArray layer $i in $comp_id",
                    )
                    num_wires_int = isa(num_wires, Int) ? num_wires : Int(num_wires)
                    args = [radius_wire, num_wires_int, lay_ratio, material_props]
                elseif LayerType == Tubular
                    radius_ext = _deserialize_value(get(layer_data, "radius_ext", missing))
                    ismissing(radius_ext) &&
                        error("Missing 'radius_ext' for Tubular layer $i in $comp_id")
                    args = [radius_ext, material_props]
                elseif LayerType == Strip
                    radius_ext = _deserialize_value(get(layer_data, "radius_ext", missing))
                    width = _deserialize_value(get(layer_data, "width", missing))
                    lay_ratio = _deserialize_value(get(layer_data, "lay_ratio", missing))
                    any(ismissing, (radius_ext, width, lay_ratio)) &&
                        error("Missing required field(s) for Strip layer $i in $comp_id")
                    args = [radius_ext, width, lay_ratio, material_props]
                else
                    error("Unsupported layer type '$LayerType' for addto_conductorgroup!")
                end

                # Call addto_conductorgroup! with Type, args..., and kwargs...
                addto_conductorgroup!(conductor_group, LayerType, args...; kwargs...)
                println("      Added conductor layer $i: $LayerType")
            catch e
                @error "Failed to add conductor layer $i ($LayerType) to component $comp_id: $e"
                println(stderr, "      Layer Data: $layer_data")
                println(stderr, "      Args: $args")
                println(stderr, "      Kwargs: $kwargs")
                rethrow(e)
            end
        end # End loop for conductor layers

        # --- 2.2 Build Insulator Group (Analogous logic) ---
        local insulator_group::InsulatorGroup
        insulator_group_data = get(comp_data, "insulator_group", Dict())
        insu_layers_data = get(insulator_group_data, "layers", [])

        if isempty(insu_layers_data) || !(insu_layers_data isa AbstractVector)
            error("Component '$comp_id' has missing or invalid insulator group layers.")
        end

        # - Create the FIRST layer object
        first_layer_dict_insu = insu_layers_data[1]
        if !(first_layer_dict_insu isa AbstractDict)
            error(
                "Invalid format for first insulator layer in component '$comp_id': Expected Dictionary, got $(typeof(first_layer_dict_insu))",
            )
        end
        first_insu_layer = _reconstruct_partsgroup(first_layer_dict_insu)

        # - Initialize InsulatorGroup
        insulator_group = InsulatorGroup(first_insu_layer)
        println("    Created InsulatorGroup with first layer: $(typeof(first_insu_layer))")

        # - Add remaining layers using addto_insulatorgroup!
        for i in 2:lastindex(insu_layers_data)
            layer_data = insu_layers_data[i]
            if !(layer_data isa AbstractDict)
                @warn "Insulator layer data at index $i for component $comp_id is not a dictionary. Skipping."
                continue
            end

            LayerType = _resolve_type(layer_data["__julia_type__"])
            material_props = _deserialize_value(get(layer_data, "material_props", missing))
            ismissing(material_props) &&
                error("Missing 'material_props' for insulator layer $i in $comp_id")
            !(material_props isa Material) && error(
                "'material_props' did not deserialize to Material for insulator layer $i in $comp_id. Got: $(typeof(material_props))",
            )

            args = []
            kwargs = Dict{Symbol,Any}()
            kwargs[:temperature] = _deserialize_value(get(layer_data, "temperature", T₀))
            # lay_direction is not typically used for insulators

            try
                # All insulator types (Semicon, Insulator) take radius_ext, material_props
                # for the addto_insulatorgroup! method.
                if LayerType in [Semicon, Insulator]
                    radius_ext = _deserialize_value(get(layer_data, "radius_ext", missing))
                    ismissing(radius_ext) &&
                        error("Missing 'radius_ext' for $LayerType layer $i in $comp_id")
                    args = [radius_ext, material_props]
                else
                    error("Unsupported layer type '$LayerType' for addto_insulatorgroup!")
                end

                # Call addto_insulatorgroup! with Type, args..., and kwargs...
                addto_insulatorgroup!(insulator_group, LayerType, args...; kwargs...)
                println("      Added insulator layer $i: $LayerType")
            catch e
                @error "Failed to add insulator layer $i ($LayerType) to component $comp_id: $e"
                println(stderr, "      Layer Data: $layer_data")
                println(stderr, "      Args: $args")
                println(stderr, "      Kwargs: $kwargs")
                rethrow(e)
            end
        end # End loop for insulator layers

        # --- 2.3 Create the CableComponent object ---
        component = CableComponent(comp_id, conductor_group, insulator_group)
        push!(reconstructed_components, component)
        println("    Created CableComponent: $comp_id")

    end # End loop through components_data

    # 3. Create the final CableDesign object using the first component
    if isempty(reconstructed_components)
        error("Failed to reconstruct any valid components for cable design '$cable_id'")
    end
    # Use the CableDesign constructor which takes the first component
    cable_design =
        CableDesign(cable_id, reconstructed_components[1]; nominal_data=nominal_data)
    println(
        "  Created initial CableDesign with component: $(reconstructed_components[1].id)",
    )

    # 4. Add remaining components to the design sequentially using addto_cabledesign!
    for i in 2:lastindex(reconstructed_components)
        try
            addto_cabledesign!(cable_design, reconstructed_components[i])
            println(
                "  Added component $(reconstructed_components[i].id) to CableDesign '$cable_id'",
            )
        catch e
            @error "Failed to add component '$(reconstructed_components[i].id)' to CableDesign '$cable_id': $e"
            rethrow(e)
        end
    end

    println("Finished Reconstructing CableDesign: $cable_id")
    return cable_design
end

"""
$(TYPEDSIGNATURES)

Loads materials from a JSON file into an existing [`MaterialsLibrary`](@ref) object.
Modifies the library in-place.

# Arguments
- `library`: The [`MaterialsLibrary`](@ref) instance to populate (modified in-place).
- `file_name`: Path to the JSON file to load (default: \"materials_library.json\").

# Returns
- The modified [`MaterialsLibrary`](@ref) instance.

# See also
- [`MaterialsLibrary`](@ref)
"""
function load_materialslibrary!(
    library::MaterialsLibrary;
    file_name::String="materials_library.json",
)::MaterialsLibrary

    if !isfile(file_name)
        @warn "Materials library file not found: '$(_display_path(file_name))'. Library remains unchanged."
        # Ensure the library has the necessary field, even if empty
        if !isdefined(library, :materials) || !(library.materials isa AbstractDict)
            library.materials = Dict{String,Material}()
        end
        return library
    end

    # Only JSON format is supported now
    _, ext = splitext(file_name)
    ext = lowercase(ext)
    if ext != ".json"
        @error "MaterialsLibrary loading only supports .json files. Cannot load '$(_display_path(file_name))'."
        return library
    end

    try
        _load_materialslibrary_json!(library, file_name)
    catch e
        @error "Error loading MaterialsLibrary from '$(_display_path(file_name))': $e"
        showerror(stderr, e, catch_backtrace())
        println(stderr)
        # Optionally clear or leave partially loaded
        # empty!(library.materials)
    end
    return library
end

"""
$(TYPEDSIGNATURES)

Internal function to load materials from JSON into the library.

# Arguments
- `library`: The [`MaterialsLibrary`](@ref) instance to modify.
- `file_name`: The path to the JSON file.

# Returns
- Nothing. Modifies `library` in-place.

# See also
- [`MaterialsLibrary`](@ref)
- [`Material`](@ref)
- [`store_materialslibrary!`](@ref)
- [`_deserialize_value`](@ref)
"""
function _load_materialslibrary_json!(library::MaterialsLibrary, file_name::String)
    # Ensure library structure is initialized
    if !isdefined(library, :materials) || !(library.materials isa AbstractDict)
        @warn "Library's 'materials' field was not initialized or not a Dict. Initializing."
        library.materials = Dict{String,Material}()
    else
        # Clear existing materials before loading
        empty!(library.materials)
    end

    # Load and parse the JSON data (expecting a Dict of material_name => material_data)
    json_data = open(file_name, "r") do io
        JSON3.read(io, Dict{String,Any})
    end


    println("Loading materials from JSON: '$(_display_path(file_name))'...")
    num_loaded = 0
    num_failed = 0

    # Process each material entry
    for (name::String, material_data::Any) in json_data
        if !(material_data isa AbstractDict)
            @warn "Skipping material '$name': Invalid data format (expected Dictionary, got $(typeof(material_data)))."
            num_failed += 1
            continue
        end
        try
            # Use the generic _deserialize_value function.
            # It will detect __julia_type__ and call _deserialize_obj for Material.
            deserialized_material = _deserialize_value(material_data)

            # **Crucial Check:** Verify the deserialized object is actually a Material
            if deserialized_material isa Material
                # Use store_materialslibrary! (assuming it exists in Utils or DataModel)
                # to add the material correctly, potentially handling duplicates.
                # If store_materialslibrary! doesn't exist, use direct assignment:
                # library.materials[name] = deserialized_material
                store_materialslibrary!(library, name, deserialized_material) # Assumes this function exists
                num_loaded += 1
            else
                # This path is taken if _deserialize_obj failed and returned the original Dict
                @warn "Skipping material '$name': Failed to deserialize into Material object. Data received: $material_data"
                # The error from _deserialize_obj inside _deserialize_value would have already been logged.
                num_failed += 1
            end
        catch e
            # Catch errors that might occur outside _deserialize_value (e.g., in store_materialslibrary!)
            num_failed += 1
            @error "Error processing material entry '$name': $e"
            showerror(stderr, e, catch_backtrace())
            println(stderr)
        end
    end

    println(
        "Finished loading materials from '$(_display_path(file_name))'. Successfully loaded $num_loaded materials, failed to load $num_failed.",
    )
    return nothing
end


# --- Auto Export ---
Utils.@_autoexport

end # module ImportExport
