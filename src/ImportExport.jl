module ImportExport

# PSCIdGen: Generates unique IDs for PSCAD exports.
mutable struct PSCIdGen
	current::Int
	PSCIdGen(start = 100000000) = new(start)
end

"""
Exports a `LineCableSystem` to a PSCAD-compatible file format.

# Arguments
- `cable_system`: A `LineCableSystem` object representing the cable system to be exported.
- `base_freq`: The base frequency [Hz] used for the PSCAD export. Defaults to `f₀`.
- `folder_path`: The folder path where the PSCAD file will be saved. Defaults to the current working directory.

# Returns
- None. The function writes the exported data to a PSCAD `.pscx` file.



# Examples
```julia
cable_system = LineCableSystem(...)
export_to_pscad(cable_system, base_freq=50)
```

"""
function export_pscad_lcp(
	cable_system::LineCableSystem;
	base_freq = f₀,
	folder_path = pwd(),
)
	# ID generator
	next_id!(gen::PSCIdGen) = (id = gen.current; gen.current += 1; return string(id))

	format_nominal =
		(X; sigdigits = 4, minval = -1e30, maxval = 1e30) -> begin
			value = round(to_nominal(X), sigdigits = sigdigits)

			value = max(value, minval)
			value = min(value, maxval)

			# Explicitly force zero if it's below rounding noise
			if abs(value) < eps(Float64)
				value = 0.0
			end

			return string(value)
		end

	# Initialize ID generator and mapping
	id_gen = PSCIdGen()
	id_map = Dict{String, String}()  # Maps element keys to their generated IDs

	# Create document and root node
	doc = XMLDocument()
	project = ElementNode("project")
	setroot!(doc, project)

	# Set project attributes
	project_id = cable_system.case_id
	project["name"] = project_id
	project["version"] = "5.0.2"
	project["schema"] = ""
	project["Target"] = "EMTDC"

	# Settings paramlist
	settings = addelement!(project, "paramlist")
	settings["name"] = "Settings"
	timestamp = round(Int, datetime2unix(now()))
	settings_params = [
		("creator", "LineCableModels.jl,$timestamp"),
		("time_duration", "0.5"),
		("time_step", "5"),
		("sample_step", "250"),
		("chatter_threshold", ".001"),
		("branch_threshold", ".0005"),
		("StartType", "0"),
		("startup_filename", "\$(Namespace).snp"),
		("PlotType", "0"),
		("output_filename", "\$(Namespace).out"),
		("SnapType", "0"),
		("SnapTime", "0.3"),
		("snapshot_filename", "\$(Namespace).snp"),
		("MrunType", "0"),
		("Mruns", "1"),
		("Scenario", ""),
		("Advanced", "14335"),
		("sparsity_threshold", "200"),
		("Options", "16"),
		("Build", "18"),
		("Warn", "0"),
		("Check", "0"),
		(
			"description",
			"Created with LineCableModels.jl (https://github.com/Electa-Git/LineCableModels.jl)",
		),
		("Debug", "0"),
	]
	for (name, value) in settings_params
		param = addelement!(settings, "param")
		param["name"] = name
		param["value"] = value
	end

	# Empty elements
	addelement!(project, "Layers")
	addelement!(project, "List")["classid"] = "Settings"
	addelement!(project, "bookmarks")

	# GlobalSubstitutions
	global_subs = addelement!(project, "GlobalSubstitutions")
	global_subs["name"] = "Default"
	addelement!(global_subs, "List")["classid"] = "Sub"
	addelement!(global_subs, "List")["classid"] = "ValueSet"
	global_pl = addelement!(global_subs, "paramlist")
	global_param = addelement!(global_pl, "param")
	global_param["name"] = "Current"
	global_param["value"] = ""

	# Definitions section
	definitions = addelement!(project, "definitions")

	# StationDefn
	station = addelement!(definitions, "Definition")
	station_id = next_id!(id_gen)
	id_map["DS"] = station_id
	station_attrs = Dict(
		"classid" => "StationDefn", "name" => "DS", "id" => station_id,
		"group" => "", "url" => "", "version" => "", "build" => "",
		"crc" => "-1", "view" => "false",
	)
	for (k, v) in station_attrs
		station[k] = v
	end

	station_pl = addelement!(station, "paramlist")
	station_pl["name"] = ""
	addelement!(station_pl, "param")["name"] = "Description"
	addelement!(station_pl, "param")["value"] = ""

	schematic = addelement!(station, "schematic")
	schematic["classid"] = "StationCanvas"
	schematic_pl = addelement!(schematic, "paramlist")
	schematic_params = [
		("show_grid", "0"), ("size", "0"), ("orient", "1"),
		("show_border", "0"), ("monitor_bus_voltage", "0"),
		("show_signal", "0"), ("show_virtual", "0"),
		("show_sequence", "0"), ("auto_sequence", "1"),
		("bus_expand_x", "8"), ("bus_expand_y", "8"),
		("bus_length", "4"),
	]
	for (name, value) in schematic_params
		param = addelement!(schematic_pl, "param")
		param["name"] = name
		param["value"] = value
	end

	addelement!(schematic, "grouping")
	wire = addelement!(schematic, "Wire")
	wire_id = next_id!(id_gen)
	wire_attrs = Dict(
		"classid" => "Branch", "id" => wire_id, "name" => "Main",
		"x" => "180", "y" => "180", "w" => "66", "h" => "82",
		"orient" => "0", "disable" => "false", "defn" => "Main",
		"recv" => "-1", "send" => "-1", "back" => "-1",
	)
	for (k, v) in wire_attrs
		wire[k] = v
	end

	for (x, y) in [(0, 0), (0, 18), (54, 54), (54, 72)]
		vertex = addelement!(wire, "vertex")
		vertex["x"] = string(x)
		vertex["y"] = string(y)
	end

	user = addelement!(wire, "User")
	user_id = next_id!(id_gen)
	id_map["Main"] = user_id
	user_attrs = Dict(
		"classid" => "UserCmp", "id" => user_id,
		"name" => "$project_id:Main", "x" => "0", "y" => "0",
		"w" => "0", "h" => "0", "z" => "-1", "orient" => "0",
		"defn" => "$project_id:Main", "link" => "-1", "q" => "4",
		"disable" => "false",
	)
	for (k, v) in user_attrs
		user[k] = v
	end
	user_pl = addelement!(user, "paramlist")
	user_pl["name"] = ""
	user_pl["link"] = "-1"
	user_pl["crc"] = "-1"

	# UserCmpDefn
	user_cmp = addelement!(definitions, "Definition")
	user_cmp_id = next_id!(id_gen)
	user_cmp_attrs = Dict(
		"classid" => "UserCmpDefn", "name" => "Main", "id" => user_cmp_id,
		"group" => "", "url" => "", "version" => "", "build" => "",
		"crc" => "-1", "view" => "false", "date" => "$timestamp",
	)
	for (k, v) in user_cmp_attrs
		user_cmp[k] = v
	end

	user_cmp_pl = addelement!(user_cmp, "paramlist")
	user_cmp_pl["name"] = ""
	addelement!(user_cmp_pl, "param")["name"] = "Description"
	addelement!(user_cmp_pl, "param")["value"] = ""

	form = addelement!(user_cmp, "form")
	form["name"] = ""
	form["w"] = "320"
	form["h"] = "400"
	form["splitter"] = "60"

	graphics = addelement!(user_cmp, "graphics")
	graphics["viewBox"] = "-200 -200 200 200"
	graphics["size"] = "2"

	rect = addelement!(graphics, "Gfx")
	rect_id = next_id!(id_gen)
	rect_attrs = Dict(
		"classid" => "Graphics.Rectangle", "id" => rect_id,
		"x" => "-36", "y" => "-36", "w" => "72", "h" => "72",
	)
	for (k, v) in rect_attrs
		rect[k] = v
	end
	rect_pl = addelement!(rect, "paramlist")
	rect_params = [
		("color", "Black"), ("dasharray", "0"), ("thickness", "0"),
		("port", ""), ("fill_style", "0"), ("fill_fg", "Black"),
		("fill_bg", "Black"), ("cond", "true"),
	]
	for (name, value) in rect_params
		param = addelement!(rect_pl, "param")
		param["name"] = name
		param["value"] = value
	end

	text = addelement!(graphics, "Gfx")
	text_id = next_id!(id_gen)
	text_attrs = Dict(
		"classid" => "Graphics.Text", "id" => text_id,
		"x" => "0", "y" => "0",
	)
	for (k, v) in text_attrs
		text[k] = v
	end
	text_pl = addelement!(text, "paramlist")
	text_params = [
		("text", "%:Name"), ("anchor", "0"), ("full_font", "Tahoma, 13world"),
		("angle", "0"), ("color", "Black"), ("cond", "true"),
	]
	for (name, value) in text_params
		param = addelement!(text_pl, "param")
		param["name"] = name
		param["value"] = value
	end

	user_schematic = addelement!(user_cmp, "schematic")
	user_schematic["classid"] = "UserCanvas"
	user_sch_pl = addelement!(user_schematic, "paramlist")
	user_sch_params = [
		("show_grid", "0"), ("size", "0"), ("orient", "1"),
		("show_border", "0"), ("monitor_bus_voltage", "0"),
		("show_signal", "0"), ("show_virtual", "0"),
		("show_sequence", "0"), ("auto_sequence", "1"),
		("bus_expand_x", "8"), ("bus_expand_y", "8"),
		("bus_length", "4"), ("show_terminals", "0"),
		("virtual_filter", ""), ("animation_freq", "500"),
	]
	for (name, value) in user_sch_params
		param = addelement!(user_sch_pl, "param")
		param["name"] = name
		param["value"] = value
	end

	addelement!(user_schematic, "grouping")
	cable = addelement!(user_schematic, "Wire")
	cable_id = next_id!(id_gen)
	cable_attrs = Dict(
		"classid" => "Cable", "id" => cable_id,
		"name" => "$project_id:CableSystem", "x" => "72", "y" => "36",
		"w" => "107", "h" => "128", "orient" => "0", "disable" => "false",
		"defn" => "$project_id:CableSystem", "recv" => "-1",
		"send" => "-1", "back" => "-1", "crc" => "-1",
	)
	for (k, v) in cable_attrs
		cable[k] = v
	end

	for (x, y) in [(0, 0), (0, 18), (54, 54), (54, 72)]
		vertex = addelement!(cable, "vertex")
		vertex["x"] = string(x)
		vertex["y"] = string(y)
	end

	cable_user = addelement!(cable, "User")
	cable_user_id = next_id!(id_gen)
	id_map["CableSystem"] = cable_user_id
	cable_user_attrs = Dict(
		"classid" => "UserCmp", "id" => cable_user_id,
		"name" => "$project_id:CableSystem", "x" => "0", "y" => "0",
		"w" => "0", "h" => "0", "z" => "-1", "orient" => "0",
		"defn" => "$project_id:CableSystem", "link" => "-1",
		"q" => "4", "disable" => "false",
	)
	for (k, v) in cable_user_attrs
		cable_user[k] = v
	end
	cable_pl = addelement!(cable_user, "paramlist")
	cable_pl["name"] = ""
	cable_pl["link"] = "-1"
	cable_pl["crc"] = "-1"
	cable_params = [
		("Name", "CableSystem_1"), ("R", "#NaN"), ("X", "#NaN"),
		("B", "#NaN"), ("Freq", format_nominal(base_freq)),
		("Length", format_nominal(cable_system.line_length / 1000)),
		("Dim", "0"), ("Mode", "0"), ("CoupleEnab", "0"),
		("CoupleName", "row"), ("CoupleOffset", "0.0 [m]"),
		("CoupleRef", "0"), ("tname", "tandem_segment"),
		("sfault", "0"), ("linc", "10.0 [km]"), ("steps", "3"),
		("gen_cnst", "1"), ("const_path", "%TEMP%\\my_constants_file.tlo"),
		("Date", "$timestamp"),
	]
	for (name, value) in cable_params
		param = addelement!(cable_pl, "param")
		param["name"] = name
		param["value"] = value
	end

	# RowDefn
	row = addelement!(definitions, "Definition")
	row_id = next_id!(id_gen)
	row_attrs = Dict(
		"id" => row_id, "classid" => "RowDefn", "name" => "CableSystem",
		"group" => "", "url" => "", "version" => "RowDefn",
		"build" => "RowDefn", "crc" => "-1", "key" => "",
		"view" => "false", "date" => "$timestamp",
	)
	for (k, v) in row_attrs
		row[k] = v
	end

	row_pl = addelement!(row, "paramlist")
	row_params = [("Description", ""), ("type", "Cable")]
	for (name, value) in row_params
		param = addelement!(row_pl, "param")
		param["name"] = name
		param["value"] = value
	end

	row_schematic = addelement!(row, "schematic")
	row_schematic["classid"] = "RowCanvas"
	row_sch_pl = addelement!(row_schematic, "paramlist")
	row_sch_params = [
		("show_grid", "0"), ("size", "0"), ("orient", "1"),
		("show_border", "0"),
	]
	for (name, value) in row_sch_params
		param = addelement!(row_sch_pl, "param")
		param["name"] = name
		param["value"] = value
	end

	# Add all User components in RowDefn
	fre_phase = addelement!(row_schematic, "User")
	fre_phase_id = next_id!(id_gen)
	fre_phase_attrs = Dict(
		"id" => fre_phase_id, "name" => "master:Line_FrePhase_Options",
		"classid" => "UserCmp", "x" => "576", "y" => "180",
		"w" => "460", "h" => "236", "z" => "-1", "orient" => "0",
		"defn" => "master:Line_FrePhase_Options", "link" => "-1",
		"q" => "4", "disable" => "false",
	)
	for (k, v) in fre_phase_attrs
		fre_phase[k] = v
	end
	fre_pl = addelement!(fre_phase, "paramlist")
	fre_pl["crc"] = "-1"
	fre_params = [
		("Interp1", "1"), ("Output", "0"), ("Inflen", "0"),
		("FS", "0.5"), ("FE", "1.0E6"), ("Numf", "100"),
		("YMaxP", "20"), ("YMaxE", "0.2"), ("AMaxP", "20"),
		("AMaxE", "0.2"), ("MaxRPtol", "2.0e6"), ("W1", "1.0"),
		("W2", "1000.0"), ("W3", "1.0"), ("CPASS", "0"),
		("NFP", "1000"), ("FSP", "0.001"), ("FEP", "1000.0"),
		("DCenab", "0"), ("DCCOR", "1"), ("ECLS", "1"),
		("shntcab", "1.0E-9"), ("ET_PE", "1E-10"), ("MER_PE", "2"),
		("MIT_PE", "5"), ("FDIS", "3"), ("enablf", "1"),
	]
	for (name, value) in fre_params
		param = addelement!(fre_pl, "param")
		param["name"] = name
		param["value"] = value
	end

	addelement!(row_schematic, "grouping")

	# Include coaxial cables
	num_cables = cable_system.num_cables
	dx = 400
	for i in 1:num_cables
		cabledef = cable_system.cables[i]
		coax1 = addelement!(row_schematic, "User")
		coax1_id = next_id!(id_gen)
		coax1_attrs = Dict(
			"classid" => "UserCmp", "name" => "master:Cable_Coax",
			"id" => coax1_id, "x" => "$(234+(i-1)*dx)", "y" => "612",
			"w" => "311", "h" => "493", "z" => "-1", "orient" => "0",
			"defn" => "master:Cable_Coax", "link" => "-1", "q" => "4",
			"disable" => "false",
		)
		for (k, v) in coax1_attrs
			coax1[k] = v
		end
		coax1_pl = addelement!(coax1, "paramlist")
		coax1_pl["link"] = "-1"
		coax1_pl["name"] = ""
		coax1_pl["crc"] = "-1"

		# Extract cable components
		components = collect(values(cabledef.cable.components))
		num_cable_parts = length(components)
		if num_cable_parts > 4
			error(
				"Number of cable parts exceeds the maximum allowed limit of 4 (core/sheath/armor/outer).",
			)
		end

		conn = cabledef.conn  # Phase mapping vector

		# Determine elim flags based on conn
		elim1 = length(conn) >= 2 && conn[2] == 0 ? "1" : "0"
		elim2 = length(conn) >= 3 && conn[3] == 0 ? "1" : "0"
		elim3 = length(conn) >= 4 && conn[4] == 0 ? "1" : "0"

		# Base parameters
		cable_x = cabledef.horz
		cable_y = cabledef.vert
		coax1_params = [
			("CABNUM", "$(i)"),
			("Name", "$(cabledef.cable.cable_id)"),
			("X", format_nominal(cable_x)),
			("OHC", "$(cable_y < 0 ? 0 : 1)"), #placement above/below earth, 0=underground, 1=aerial
			("Y", (cable_y < 0 ? format_nominal(abs(cable_y)) : "0.0")),  #depth (underground)
			("Y2", (cable_y > 0 ? format_nominal(cable_y) : "0.0")), #height (aerial)
			("ShuntA", "1.0e-11 [mho/m]"), #air shunt conductance
			("FLT", format_nominal(base_freq)), #frequency for loss tangents
			("RorT", "0"), #specify 0=radii, 1=thickness
			("LL", "$(2*num_cable_parts-1)"), # layer configuration, 5 for C1 | I1 | C2 | I2 | C3 | I3 -> odd numbers end with insulators
			("CROSSBOND", "0"), #ideal crossbonding
			("GROUPNO", "1"),
			("CBC1", "1"),
			("CBC2", "0"),
			("CBC3", "0"),
			("CBC4", "0"),
			("SHRad", "1"), #show detailed graphic labels
			("LC", "3")] # 3 = specify conductors to eliminate

		# Core (mandatory, index 1)
		core = components[1]  # First component is always present
		push!(
			coax1_params,
			("CONNAM1", uppercasefirst(collect(keys(cabledef.cable.components))[1])),
		)
		push!(coax1_params, ("R1", format_nominal(core.radius_in_con))) # core inner
		push!(coax1_params, ("R2", format_nominal(core.radius_ext_con))) # core outer
		push!(coax1_params, ("RHOC", format_nominal(core.rho_con, sigdigits = 6)))
		push!(coax1_params, ("PERMC", format_nominal(core.mu_con, sigdigits = 6)))

		# First insulation (mandatory, from core)
		push!(coax1_params, ("R3", format_nominal(core.radius_ext_ins))) # 1st insulation
		push!(coax1_params, ("T3", "0.0000")) # thickness not used (RorT=0)
		push!(coax1_params, ("SemiCL", "0")) # assume no semicon for now
		push!(coax1_params, ("SL2", "0.0000"))
		push!(coax1_params, ("SL1", "0.0000"))
		push!(coax1_params, ("EPS1", format_nominal(core.eps_ins, sigdigits = 6)))
		push!(coax1_params, ("PERM1", format_nominal(core.mu_ins, sigdigits = 6)))
		push!(
			coax1_params,
			("LT1", format_nominal(core.loss_factor_ins, sigdigits = 6, maxval = 10.0)),
		)

		# Optional layers (sheath, armor, outer)
		if num_cable_parts >= 2 # Sheath
			sheath = components[2]
			push!(
				coax1_params,
				("CONNAM2", uppercasefirst(collect(keys(cabledef.cable.components))[2])),
			)
			push!(coax1_params, ("R4", format_nominal(sheath.radius_ext_con))) # sheath outer
			push!(coax1_params, ("T4", "0.0000"))
			push!(coax1_params, ("RHOS", format_nominal(sheath.rho_con, sigdigits = 6)))
			push!(coax1_params, ("PERMS", format_nominal(sheath.mu_con, sigdigits = 6)))
			push!(coax1_params, ("elim1", "$elim1"))
			push!(coax1_params, ("R5", format_nominal(sheath.radius_ext_ins))) # 2nd insulation
			push!(coax1_params, ("T5", "0.0000"))
			push!(coax1_params, ("EPS2", format_nominal(sheath.eps_ins, sigdigits = 6)))
			push!(coax1_params, ("PERM2", format_nominal(sheath.mu_ins, sigdigits = 6)))
			push!(
				coax1_params,
				(
					"LT2",
					format_nominal(sheath.loss_factor_ins, sigdigits = 6, maxval = 10.0),
				),
			)
		else
			push!(coax1_params, ("CONNAM2", "none"))
			push!(coax1_params, ("R4", "0.0"))
			push!(coax1_params, ("T4", "0.0000"))
			push!(coax1_params, ("RHOS", "0.0"))
			push!(coax1_params, ("PERMS", "0.0"))
			push!(coax1_params, ("elim1", "0"))
			push!(coax1_params, ("R5", "0.0"))
			push!(coax1_params, ("T5", "0.0000"))
			push!(coax1_params, ("EPS2", "0.0"))
			push!(coax1_params, ("PERM2", "0.0"))
			push!(coax1_params, ("LT2", "0.0000"))
		end

		if num_cable_parts >= 3 # Armor
			armor = components[3]
			push!(
				coax1_params,
				("CONNAM3", uppercasefirst(collect(keys(cabledef.cable.components))[3])),
			)
			push!(coax1_params, ("R6", format_nominal(armor.radius_ext_con))) # armor outer
			push!(coax1_params, ("T6", "0.0000"))
			push!(coax1_params, ("RHOA", format_nominal(armor.rho_con, sigdigits = 6)))
			push!(coax1_params, ("PERMA", format_nominal(armor.mu_con, sigdigits = 6)))
			push!(coax1_params, ("elim2", "$elim2"))
			push!(coax1_params, ("R7", format_nominal(armor.radius_ext_ins))) # 3rd insulation
			push!(coax1_params, ("T7", "0.0000"))
			push!(coax1_params, ("EPS3", format_nominal(armor.eps_ins, sigdigits = 6)))
			push!(coax1_params, ("PERM3", format_nominal(armor.mu_ins, sigdigits = 6)))
			push!(
				coax1_params,
				(
					"LT3",
					format_nominal(armor.loss_factor_ins, sigdigits = 6, maxval = 10.0),
				),
			)
		else
			push!(coax1_params, ("CONNAM3", "none"))
			push!(coax1_params, ("R6", "0.0"))
			push!(coax1_params, ("T6", "0.0000"))
			push!(coax1_params, ("RHOA", "0.0"))
			push!(coax1_params, ("PERMA", "0.0"))
			push!(coax1_params, ("elim2", "0"))
			push!(coax1_params, ("R7", "0.0"))
			push!(coax1_params, ("T7", "0.0000"))
			push!(coax1_params, ("EPS3", "0.0"))
			push!(coax1_params, ("PERM3", "0.0"))
			push!(coax1_params, ("LT3", "0.0000"))
		end

		if num_cable_parts >= 4 # Outer
			outer = components[4]
			push!(
				coax1_params,
				("CONNAM4", uppercasefirst(collect(keys(cabledef.cable.components))[4])),
			)
			push!(coax1_params, ("R8", format_nominal(outer.radius_ext_con))) # outer conductor
			push!(coax1_params, ("T8", "0.0000"))
			push!(coax1_params, ("RHOO", format_nominal(outer.rho_con, sigdigits = 6)))
			push!(coax1_params, ("PERMO", format_nominal(outer.mu_con, sigdigits = 6)))
			push!(coax1_params, ("elim3", "$elim3"))
			push!(coax1_params, ("R9", format_nominal(outer.radius_ext_ins))) # 4th insulation
			push!(coax1_params, ("T9", "0.0000"))
			push!(coax1_params, ("EPS4", format_nominal(outer.eps_ins, sigdigits = 6)))
			push!(coax1_params, ("PERM4", format_nominal(outer.mu_ins, sigdigits = 6)))
			push!(
				coax1_params,
				(
					"LT4",
					format_nominal(outer.loss_factor_ins, sigdigits = 6, maxval = 10.0),
				),
			)
		else
			push!(coax1_params, ("CONNAM4", "none"))
			push!(coax1_params, ("R8", "0.0"))
			push!(coax1_params, ("T8", "0.0000"))
			push!(coax1_params, ("RHOO", "0.0"))
			push!(coax1_params, ("PERMO", "0.0"))
			push!(coax1_params, ("elim3", "0"))
			push!(coax1_params, ("R9", "0.0"))
			push!(coax1_params, ("T9", "0.0000"))
			push!(coax1_params, ("EPS4", "0.0"))
			push!(coax1_params, ("PERM4", "0.0"))
			push!(coax1_params, ("LT4", "0.0000"))
		end

		for (name, value) in coax1_params
			param = addelement!(coax1_pl, "param")
			param["name"] = name
			param["value"] = value
		end
	end

	# Line_Ground
	ground = addelement!(row_schematic, "User")
	ground_id = next_id!(id_gen)
	ground_attrs = Dict(
		"classid" => "UserCmp", "name" => "master:Line_Ground",
		"id" => ground_id, "x" => "504", "y" => "288",
		"w" => "793", "h" => "88", "z" => "-1", "orient" => "0",
		"defn" => "master:Line_Ground", "link" => "-1", "q" => "4",
		"disable" => "false",
	)
	for (k, v) in ground_attrs
		ground[k] = v
	end
	ground_pl = addelement!(ground, "paramlist")
	ground_pl["link"] = "-1"
	ground_pl["name"] = ""
	ground_pl["crc"] = "-1"
	base_rho_g = format_nominal(cable_system.earth_props.layers[end].base_rho_g)
	base_epsr_g = format_nominal(cable_system.earth_props.layers[end].base_epsr_g)
	base_mur_g = format_nominal(cable_system.earth_props.layers[end].base_mur_g)

	ground_params = [
		("EarthForm2", "0"), ("EarthForm", "3"), ("EarthForm3", "2"),
		("GrRho", "0"), ("GRRES", base_rho_g), ("GPERM", base_mur_g),
		("K0", "0.001"), ("K1", "0.01"), ("alpha", "0.7"),
		("GRP", base_epsr_g),
	]
	for (name, value) in ground_params
		param = addelement!(ground_pl, "param")
		param["name"] = name
		param["value"] = value
	end

	# Resource and hierarchy
	addelement!(project, "List")["classid"] = "Resource"

	hierarchy = addelement!(project, "hierarchy")
	call1 = addelement!(hierarchy, "call")
	call1["link"] = id_map["DS"]
	call1["name"] = "$project_id:DS"
	call1["z"] = "-1"
	call1["view"] = "false"
	call1["instance"] = "0"

	call2 = addelement!(call1, "call")
	call2["link"] = id_map["Main"]
	call2["name"] = "$project_id:Main"
	call2["z"] = "-1"
	call2["view"] = "false"
	call2["instance"] = "0"

	call3 = addelement!(call2, "call")
	call3["link"] = id_map["CableSystem"]
	call3["name"] = "$project_id:CableSystem"
	call3["z"] = "-1"
	call3["view"] = "true"
	call3["instance"] = "0"

	# Ensure folder_path exists
	if !isdir(folder_path)
		error("Folder path does not exist: $folder_path")
	end

	# Construct the full file path
	filename = joinpath(folder_path, "$project_id.pscx")

	# Write to file
	try
		write(filename, doc)
		println("File successfully created at: $filename")
	catch e
		println("Failed to create file: ", e)
	end

end

@_autoexport

end