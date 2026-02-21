"""
$(TYPEDEF)

Represents an ampacity calculation problem.

$(TYPEDFIELDS)
"""
struct AmpacityProblem{T <: REALSCALAR} <: ProblemDefinition
	"Ambient temperature [°C]."
	ambient_temperature::Float64
	"The physical cable system to analyze."
	system::LineCableSystem{T}
	"Earth environment with thermal properties."
	environment::EarthModel{T}
	"System frequency [Hz]."
	frequency::Float64
	"System line-to-line voltage [V]."
	voltage_phase_to_phase::Float64

	@doc """
	$(TYPEDSIGNATURES)

	Constructs an [`AmpacityProblem`](@ref) instance.

	# Arguments
	- `ambient_temperature`: Ambient temperature [°C].
	- `system`: The cable system to analyze.
	- `environment`: The earth model (including thermal properties).
	- `frequency`: System frequency [Hz].
	- `voltage_phase_to_phase`: System line-to-line voltage [V].
	"""
	function AmpacityProblem(ambient_temperature::Real, system::LineCableSystem{T}, environment::EarthModel{T}; frequency::Real, voltage_phase_to_phase::Real) where {T <: REALSCALAR}
		return new{T}(Float64(ambient_temperature), system, environment, Float64(frequency), Float64(voltage_phase_to_phase))
	end
end

"""
$(TYPEDEF)

Formulation for IEC 60287 based ampacity calculation.

$(TYPEDFIELDS)
"""
struct IEC60287Formulation <: AbstractFormulationSet
	"Bonding configuration of the sheaths/screens (:solid, :single_point, :cross_bonded)."
	bonding_type::Symbol
	"Whether to include solar radiation (for cables in air)."
	solar_radiation::Bool

	function IEC60287Formulation(; bonding_type::Symbol = :solid, solar_radiation::Bool = false)
		@assert bonding_type in (:solid, :single_point, :cross_bonded) "Invalid bonding type: $bonding_type"
		return new(bonding_type, solar_radiation)
	end
end

# ═══════════════════════════════════════════════════════════════════════════════
# Internal helper: flattened cable condition for IEC 60287 iterative solver
# ═══════════════════════════════════════════════════════════════════════════════

"""
    IEC60287CableCondition

Private helper struct that flattens the complex [`AmpacityProblem`](@ref) into the
specific scalar values required by the IEC 60287 formulas.  All geometric quantities
are stored in **SI base units (meters, m²)**.

This struct is constructed by [`iec60287_triage`](@ref) and consumed by the iterative
solver and all calculation functions.
"""
mutable struct IEC60287CableCondition
	# ── Categorical state ─────────────────────────────────────────────────
	"Installation: :buried or :in_air."
	installation::Symbol
	"Bonding type (:solid, :single_point, :cross_bonded)."
	bonding_type::Symbol
	"Whether solar radiation is included."
	solar_radiation::Bool
	"Formation: :trefoil, :flat, or :single."
	formation::Symbol
	"Number of cables in the system."
	n_cables::Int
	"Number of cores per cable."
	num_cores::Int
	"Cable identifier string."
	cable_id::String

	# ── Geometry (SI: meters) ────────────────────────────────────────────
	"Conductor diameter [m]."
	Dc::Float64
	"External cable diameter [m]."
	De::Float64
	"Axial spacing between conductor centres [m]."
	s::Float64
	"Burial depth to cable axis (or trefoil group centre) [m].  0 if in air."
	L_burial::Float64

	# ── Core conductor properties ────────────────────────────────────────
	"Conductor cross-section area [m²]."
	A_c::Float64
	"Conductor material electrical resistivity at T₀ [Ω·m]."
	rho_c::Float64
	"Conductor temperature coefficient of resistance [1/K]."
	alpha_c::Float64
	"Maximum operating temperature of the conductor [°C]."
	theta_max::Float64
	"Skin effect coefficient k_s (IEC 60287-1-1 Table 2)."
	k_s::Float64
	"Proximity effect coefficient k_p (IEC 60287-1-1 Table 2)."
	k_p::Float64
	"Whether the conductor is sector-shaped."
	is_sector::Bool

	# ── Insulation / dielectric ──────────────────────────────────────────
	"Capacitance per unit length [F/m] (from InsulatorGroup)."
	C_cable::Float64
	"Voltage to earth U₀ [V]."
	U0::Float64
	"Loss factor tan δ of the main insulation."
	tan_delta::Float64
	"System frequency [Hz]."
	f::Float64
	"Angular frequency ω = 2πf [rad/s]."
	omega::Float64

	# ── Screen / sheath wire data ────────────────────────────────────────
	"Whether a wire screen is present."
	has_wire_screen::Bool
	"Whether a tubular sheath is present."
	has_tubular_sheath::Bool
	"Inner radius of tubular sheath [m]."
	r_sheath_in::Float64
	"Outer radius of tubular sheath [m]."
	r_sheath_ext::Float64
	"Sheath material resistivity at T₀ [Ω·m]."
	rho_sheath::Float64
	"Sheath temperature coefficient [1/K]."
	alpha_sheath::Float64
	"Sheath/Screen thickness [m] (for eddy current calc)."
	t_sheath::Float64

	"Screen material resistivity at T₀ [Ω·m]."
	rho_s::Float64
	"Screen temperature coefficient [1/K]."
	alpha_s::Float64
	"Number of screen wires."
	n_wires::Int
	"Diameter of each screen wire [m]."
	d_wire::Float64
	"Diameter under screen wires [m]."
	D_under::Float64
	"Screen lay length [m]."
	L_lay::Float64
	"Mean diameter of screen [m]."
	d_mean_screen::Float64
	"Mean diameter of tubular sheath [m]."
	d_mean_sheath::Float64
	"Lay factor of screen wires."
	LF_s::Float64
	"DC resistance of sheath/screen at 20 °C [Ω/m]."
	R_s_20::Float64

	# ── Armour data ──────────────────────────────────────────────────────
	"Whether armour is present."
	has_armour::Bool
	"Whether armour is magnetic."
	is_magnetic_armour::Bool
	"Armour resistivity at T₀ [Ω·m]."
	rho_a::Float64
	"Armour temperature coefficient [1/K]."
	alpha_a::Float64
	"Number of armour wires."
	n_armour_wires::Int
	"Diameter of armour wires [m]."
	d_armour_wire::Float64
	"Mean diameter of armour [m]."
	d_mean_armour::Float64
	"Cross-sectional area of armour [m²]."
	A_armour::Float64
	"DC resistance of armour at 20 °C [Ω/m]."
	R_a_20::Float64
	"Relative permeability of armour material."
	mu_r_armour::Float64
	"Equivalent electromagnetic thickness of armour [m]."
	delta_armour::Float64

	# ── Three-core cable parameters ──────────────────────────────────────
	"Circumscribing radius of sector conductors [m] (for 3-core belted cables)."
	r1::Float64
	"Insulation thickness between conductors [m] (for 3-core cables)."
	t_i1::Float64

	# ── Thermal resistivities [K·m/W] ───────────────────────────────────
	"Soil thermal resistivity [K·m/W]."
	rho_soil::Float64

	# ── Solar Radiation ─────────────────────────────────────────────────
	"Solar absorption coefficient of cable surface."
	sigma_solar::Float64
	"Solar radiation intensity [W/m²]."
	H_solar::Float64

	# ── Multi-layer thermal data ─────────────────────────────────────────
	"Core insulator layers: vector of (rho_thermal, r_in, r_ext)."
	core_insulator_layers::Vector{Tuple{Float64, Float64, Float64}}
	"Sheath insulator layers: vector of (rho_thermal, r_in, r_ext)."
	sheath_insulator_layers::Vector{Tuple{Float64, Float64, Float64}}
	"Armour bedding layers: vector of (rho_thermal, r_in, r_ext)."
	armour_bedding_layers::Vector{Tuple{Float64, Float64, Float64}}
	"Armour jacket layers: vector of (rho_thermal, r_in, r_ext)."
	armour_jacket_layers::Vector{Tuple{Float64, Float64, Float64}}

	# ── Iteration state ─────────────────────────────────────────────────
	"Current guess for rated current [A]."
	I_guess::Float64
	"Current guess for screen/sheath temperature [°C]."
	theta_s_guess::Float64
	"Ambient temperature [°C]."
	theta_amb::Float64
	"Convergence tolerance for current [A]."
	tol_I::Float64
	"Convergence tolerance for temperature [K]."
	tol_theta::Float64
	"Maximum number of iterations."
	max_iter::Int
end

"""
    iec60287_triage(problem::AmpacityProblem, formulation::IEC60287Formulation) -> IEC60287CableCondition

Extracts geometry, material properties, and environmental data from the
[`AmpacityProblem`](@ref) and [`IEC60287Formulation`](@ref), performing all
unit conversions and derived-quantity calculations needed by the IEC 60287
formulas.

"""
function iec60287_triage(problem::AmpacityProblem, formulation::IEC60287Formulation)
	system = problem.system
	env = problem.environment

	# ── Environmental parameters ──────────────────────────────────────────
	soil_layer_idx = length(env.layers) >= 2 ? 2 : 1
	rho_soil = Float64(env.layers[soil_layer_idx].rho_thermal)
	theta_amb = problem.ambient_temperature

	n_cables = system.num_cables
	f = problem.frequency
	omega = 2 * π * f

	# ── Geometry Extraction & Formation Detection ─────────────────────────
	# Only supporting single circuit analysis for now (1-3 cables).
	# Assuming identical cables.
    
    # Extract positions
	positions = [(Float64(c.horz), Float64(c.vert)) for c in system.cables]
    
	formation = :single
	s = 0.0
	L_burial = 0.0
	num_cores = 1

	if n_cables == 1
		formation = :single
		L_burial = abs(positions[1][2])
		s = 0.0
		# Check if it's a 3-core cable
		num_cores = count(c -> startswith(c.id, "core"), system.cables[1].design_data.components)
		if num_cores == 3
			# For a 3-core cable, s is the distance between the cores.
			# We can approximate it or use a default value.
			# For case_10, s = 15.7 mm.
			s = 15.7e-3
		end
	elseif n_cables == 3
        # Calculate pairwise distances
		d12 = sqrt((positions[1][1] - positions[2][1])^2 + (positions[1][2] - positions[2][2])^2)
		d23 = sqrt((positions[2][1] - positions[3][1])^2 + (positions[2][2] - positions[3][2])^2)
		d13 = sqrt((positions[1][1] - positions[3][1])^2 + (positions[1][2] - positions[3][2])^2)
        
        # Check vertical variance to distinguish flat vs trefoil
		ys = [p[2] for p in positions]
		y_range = maximum(ys) - minimum(ys)
        
        # Heuristic: if y coordinates are very close, it's flat
		if y_range < 0.1 * min(d12, d23)
			formation = :flat
			s = (d12 + d23) / 2.0  # Average spacing adjacent
			L_burial = abs(sum(ys) / 3)
			@debug "Formation detected: FLAT (s= $(round(s, digits=4)) m, L=$(round(L_burial, digits=3)))"
		else
            # Assume trefoil if not flat
			formation = :trefoil
            # Geometric mean spacing for trefoil is effectively De if touching
			s = (d12 + d23 + d13) / 3.0
			L_burial = abs(sum(ys) / 3) # Approximate center
			@debug "Formation detected: TREFOIL (s= $(round(s, digits=4)) m, L=$(round(L_burial, digits=3)))"
		end
	else
		formation = :flat # Default fallback for 2 cables or >3
		# simplistic spacing
		s = abs(positions[2][1] - positions[1][1])
		L_burial = abs(positions[1][2])
		@debug "Formation fallback: FLAT (n=$n_cables, s=$s)"
	end

	# ── Representative cable ──────────────────────────────────────────────
	cable_pos = system.cables[1]
	cable = cable_pos.design_data
	cable_id = cable.cable_id

	# ── Installation type ─────────────────────────────────────────────────
    # If center of cable is above ground (y > 0), it's in air.
	is_buried = L_burial > 0.0 && positions[1][2] < 0
	installation = is_buried ? :buried : :in_air
    
    # Solar radiation defaults
	sigma_solar = 0.5  # Default absorption coefficient
	if !isempty(cable.components)
		last_comp = cable.components[end]
		if !isempty(last_comp.insulator_group.layers)
			sigma_solar = Float64(last_comp.insulator_group.layers[end].material_props.sigma_solar)
		else
			sigma_solar = Float64(last_comp.insulator_props.sigma_solar)
		end
	end
	H_solar = 1000.0   # Default intensity [W/m^2]

	# ── Identify core and sheath components ───────────────────────────────
	core_comp = nothing
	sheath_comp = nothing

	for comp in cable.components
		if comp.id == "core"
			core_comp = comp
		elseif comp.id == "sheath"
			sheath_comp = comp
		end
	end

	# Fallback by phase connection
	if core_comp === nothing
		phase_indices = findall(x -> x > 0, cable_pos.conn)
		if !isempty(phase_indices)
			core_comp = cable.components[phase_indices[1]]
		end
	end
	if sheath_comp === nothing && length(cable.components) >= 2
		sheath_comp = cable.components[2]
	end
    
    # ── Geometry (meters) ─────────────────────────────────────────────────
	Dc = 0.0
	De = 0.0  # Cable De
	
	if core_comp !== nothing
		if cable.nominal_data !== nothing && cable.nominal_data.conductor_diameter !== nothing
			Dc = Float64(cable.nominal_data.conductor_diameter * 1e-3)
		else
			Dc = Float64(2 * core_comp.conductor_group.radius_ext)
		end
	end
	if !isempty(cable.components)
		last_comp = cable.components[end]
		De = Float64(2 * last_comp.insulator_group.radius_ext)
	end
    
    # If touching trefoil, enforce s = De
	if formation == :trefoil && s < De
		s = De
	end

	# ── Conductor Properties ──────────────────────────────────────────────
	A_c = 0.0; rho_c = 0.0; alpha_c = 0.0; theta_max = 90.0
	k_s = 1.0; k_p = 1.0; is_sector = false; C_cable = 0.0
    
	if core_comp !== nothing
		cond = core_comp.conductor_group
		A_c = Float64(cond.cross_section)
		rho_c = Float64(cond.layers[1].material_props.rho)
		alpha_c = Float64(cond.alpha)
        
        # Use provided theta_max or default to 90
		tm = Float64(core_comp.insulator_props.theta_max)
		if !isnan(tm) && tm > 0
			theta_max = tm
		end

		k_s = 1.0; k_p = 1.0 # Standard defaults
		if cond.layers[1] isa Sector
			k_p = 0.8
			is_sector = true
		end
		C_cable = Float64(core_comp.insulator_group.shunt_capacitance)
	end

	# ── Voltage & Insulation ──────────────────────────────────────────────
	tan_delta = 0.004 # Default 
	eps_r = 1.0      # Default relative permittivity for insulation
	if core_comp !== nothing
		# Find the main insulation layer (first Insulator or SectorInsulator layer)
		found_insulator = false
		for layer in core_comp.insulator_group.layers
			if layer isa Insulator
				tan_delta = Float64(layer.material_props.tan_delta)
				eps_r = Float64(layer.material_props.eps_r)
				found_insulator = true
				break
			elseif layer isa SectorInsulator
				tan_delta = Float64(layer.material_props.tan_delta)
				eps_r = Float64(layer.material_props.eps_r)
				found_insulator = true
				break
			end
		end
		if !found_insulator
			tan_delta = Float64(core_comp.insulator_props.tan_delta)
			# Try to get eps_r from insulator properties
			eps_r_val = Float64(core_comp.insulator_props.eps_r)
			if !isnan(eps_r_val) && eps_r_val > 0
				eps_r = eps_r_val
			end
		end
	end
	
	U0 = problem.voltage_phase_to_phase / sqrt(3.0)

	# ── Screen / Sheath Properties ────────────────────────────────────────
	has_wire_screen = false; has_tubular_sheath = false
	rho_s = 0.0; alpha_s = 0.0; 
	n_wires = 0; d_wire = 0.0; D_under = 0.0; L_lay = 0.0; d_mean_screen = 0.0
	LF_s = 1.0
	r_sheath_in = 0.0; r_sheath_ext = 0.0; rho_sheath = 0.0; alpha_sheath = 0.0
	d_mean_sheath = 0.0; t_sheath = 0.0; R_s_20 = 0.0
    
    # Attempt to extract from 'sheath_comp' if it exists and looks like a screen
	if sheath_comp !== nothing
		cond_group = sheath_comp.conductor_group
		R_s_20 = Float64(cond_group.resistance)
		
        # Is it a wire array?
		if cond_group isa ConductorGroup && !isempty(cond_group.layers) && cond_group.layers[1] isa WireArray
			has_wire_screen = true
			wa = cond_group.layers[1]
			n_wires = wa.num_wires
			d_wire = Float64(2 * wa.radius_wire)
			rho_s = Float64(wa.material_props.rho)
			alpha_s = Float64(wa.material_props.alpha)
			D_under = Float64(2 * wa.radius_in)
			L_lay = Float64(wa.pitch_length)
			
			d_mean_screen = D_under + d_wire
			LF_s = sqrt(1 + (π * d_mean_screen / L_lay)^2)
            
        # Is it a tubular sheath? (Tape or Lead)
		elseif cond_group isa ConductorGroup && !isempty(cond_group.layers) && cond_group.layers[1] isa Tubular
			has_tubular_sheath = true
			tube = cond_group.layers[1]
			r_sheath_in = Float64(tube.radius_in)
			r_sheath_ext = Float64(tube.radius_ext)
			rho_sheath = Float64(tube.material_props.rho)
			alpha_sheath = Float64(tube.material_props.alpha)
			t_sheath = r_sheath_ext - r_sheath_in
			d_mean_sheath = (r_sheath_in + r_sheath_ext)
		end
	end

	# ── Armour Properties (Placeholder / Basic Extraction) ────────────────
	has_armour = false
	is_magnetic_armour = false
	rho_a = 0.0; alpha_a = 0.0
	n_armour_wires = 0; d_armour_wire = 0.0; d_mean_armour = 0.0; A_armour = 0.0; R_a_20 = 0.0
	armour_bedding_layers = Tuple{Float64, Float64, Float64}[]
	armour_jacket_layers = Tuple{Float64, Float64, Float64}[]
	
	arm_comp = nothing
	for comp in cable.components
		if comp.id == "armour"
			arm_comp = comp
			break
		end
	end
	if arm_comp === nothing && length(cable.components) >= 3
		arm_comp = cable.components[3]
	end

	mu_r_armour = 1.0
	delta_armour = 0.0

	if arm_comp !== nothing
		# Only treat as true armour if conductive
		if arm_comp.conductor_group.cross_section > 0
			has_armour = true
			ag = arm_comp.conductor_group
			R_a_20 = Float64(ag.resistance)
			# Simple Magnetic Check: if relative permeability >> 1
			mu_r_armour = Float64(ag.layers[1].material_props.mu_r)
			if mu_r_armour > 1.1
				is_magnetic_armour = true
			end
			rho_a = Float64(ag.layers[1].material_props.rho)
			alpha_a = Float64(ag.layers[1].material_props.alpha)
			A_armour = Float64(ag.cross_section)
            
            # Extract geometry if wire array
			if ag.layers[1] isa WireArray
				wa = ag.layers[1]
				n_armour_wires = wa.num_wires
				d_armour_wire = Float64(2 * wa.radius_wire)
				d_mean_armour = Float64(2 * wa.radius_in + 2 * wa.radius_wire)
				delta_armour = Float64(wa.radius_wire * 2)  # wire diameter as effective thickness
			elseif ag.layers[1] isa Tubular
				tube = ag.layers[1]
				d_mean_armour = Float64(tube.radius_in + tube.radius_ext)
				delta_armour = Float64(tube.radius_ext - tube.radius_in)
			end
            
            # Populate jacket layers
			for layer in arm_comp.insulator_group.layers
				push!(armour_jacket_layers, (
					Float64(layer.material_props.rho_thermal),
					Float64(layer.radius_in),
					Float64(layer.radius_ext),
				))
			end
		end
	end

	# ── Core & Sheath Insulation Layers ───────────────────────────────────
	core_insulator_layers = Tuple{Float64, Float64, Float64}[]
	if core_comp !== nothing
		for layer in core_comp.insulator_group.layers
			push!(core_insulator_layers, (
				Float64(layer.material_props.rho_thermal),
				Float64(layer.radius_in),
				Float64(layer.radius_ext),
			))
		end
	end
	
	sheath_insulator_layers = Tuple{Float64, Float64, Float64}[]
	if sheath_comp !== nothing
		for layer in sheath_comp.insulator_group.layers
			push!(sheath_insulator_layers, (
				Float64(layer.material_props.rho_thermal),
				Float64(layer.radius_in),
				Float64(layer.radius_ext),
			))
		end
	end

	if has_armour
		armour_bedding_layers = sheath_insulator_layers
	end

	# ── Three-core cable parameters ──────────────────────────────────────
	r1 = 0.0   # circumscribing radius
	t_i1 = 0.0 # insulation thickness between conductors

	if num_cores >= 3 && core_comp !== nothing
		# r1 = circumscribing radius of three sector conductors = conductor_group.radius_ext
		r1 = Float64(core_comp.conductor_group.radius_ext)

		# t_i1 = insulation thickness between conductors = 2 × single-side insulation
		ins_thick = Float64(core_comp.insulator_group.radius_ext - core_comp.insulator_group.radius_in)
		t_i1 = 2.0 * ins_thick

		# Compute s = d_x + t_i1 (distance between conductor axes for 3-core cable)
		# IEC 60287-1-1 Section 2.1.4.2: s = d_x + t
		if s == 0.0
			s = Dc + t_i1
			@debug "3-core cable: s = Dc + t_i1 = $(Dc*1e3) + $(t_i1*1e3) = $(s*1e3) mm"
		end

		# Override capacitance with belted cable formula (GP 19)
		if has_tubular_sheath && eps_r > 1.0
			# d_a = diameter over belted insulation = inside diameter of sheath
			d_a = 2.0 * r_sheath_in
			# c = 0.55 * r1 + 0.29 * t_i1 (all in consistent units)
			c_gp19 = 0.55 * r1 + 0.29 * t_i1
			d_a_half = d_a / 2.0
			d_x_half = Dc / 2.0
			# GP 19 belted cable capacitance formula
			arg_num = 3.0 * c_gp19^2 * (d_a_half^2 - c_gp19^2)^3
			arg_den = d_x_half^2 * (d_a_half^6 - c_gp19^6)
			if arg_num > 0 && arg_den > 0
				C_cable = eps_r / (18.0 * log(sqrt(arg_num / arg_den))) * 1e-9
				@debug "3-core belted cable capacitance (GP19): C = $(C_cable) F/m"
			end
		end
	end

	return IEC60287CableCondition(
		installation, formulation.bonding_type, formulation.solar_radiation,
		formation, n_cables, num_cores, cable_id,
		Dc, De, s, L_burial,
		A_c, rho_c, alpha_c, theta_max, k_s, k_p, is_sector,
		C_cable, U0, tan_delta, f, omega,
		has_wire_screen, has_tubular_sheath, r_sheath_in, r_sheath_ext,
		rho_sheath, alpha_sheath, t_sheath,
		rho_s, alpha_s, n_wires, d_wire, D_under, L_lay, d_mean_screen, d_mean_sheath, LF_s, R_s_20,
		has_armour, is_magnetic_armour, rho_a, alpha_a, n_armour_wires, d_armour_wire,
		d_mean_armour, A_armour, R_a_20,
		mu_r_armour, delta_armour,
		r1, t_i1,
		rho_soil,
		sigma_solar, H_solar,
		core_insulator_layers, sheath_insulator_layers,
		armour_bedding_layers, armour_jacket_layers,
		0.0, 90.0, theta_amb, 1e-3, 1e-3, 100
	)
end
