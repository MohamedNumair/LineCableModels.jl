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

	@doc """
	$(TYPEDSIGNATURES)

	Constructs an [`AmpacityProblem`](@ref) instance.

	# Arguments
	- `ambient_temperature`: Ambient temperature [°C].
	- `system`: The cable system to analyze.
	- `environment`: The earth model (including thermal properties).
	"""
	function AmpacityProblem(ambient_temperature::Real, system::LineCableSystem{T}, environment::EarthModel{T}) where {T <: REALSCALAR}
		return new{T}(Float64(ambient_temperature), system, environment)
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
	"Lay factor of screen wires."
	LF_s::Float64

	# ── Armour data ──────────────────────────────────────────────────────
	"Whether armour is present."
	has_armour::Bool

	# ── Thermal resistivities [K·m/W] ───────────────────────────────────
	"Soil thermal resistivity [K·m/W]."
	rho_soil::Float64

	# ── Multi-layer thermal data ─────────────────────────────────────────
	"Core insulator layers: vector of (rho_thermal, r_in, r_ext)."
	core_insulator_layers::Vector{Tuple{Float64, Float64, Float64}}
	"Sheath insulator layers: vector of (rho_thermal, r_in, r_ext)."
	sheath_insulator_layers::Vector{Tuple{Float64, Float64, Float64}}

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

All geometric quantities are converted to **meters** (SI) at this stage.
Temperature guesses are initialised as ``\\theta_{\\text{conductor}} = \\theta_{\\max}``,
``\\theta_{\\text{sheath}} = \\theta_{\\max}``.

# Formulation

No formula — this is a data extraction / unit conversion step.  Derived geometry:

``s = D_e`` (touching trefoil), ``\\omega = 2\\pi f``, conductor diameter
``D_c = 2 r_{\\text{ext}}``, cable diameter ``D_e = 2 r_{\\text{ext,last}}``.

# Source

IEC 60287-1-1:2006 / IEC 60287-2-1:2015 (multiple clauses)

# CIGRE TB880 Guidance

Dielectric losses (``W_d``) should always be calculated and included, regardless
of voltage level (Guidance Point 7).  Do not round intermediate values.  Enforce
strict convergence tolerances (``10^{-3}``  A / K) (Guidance Point 2).

# Arguments
- `problem`: The ampacity problem definition.
- `formulation`: The IEC 60287 formulation configuration.

# Returns
- An [`IEC60287CableCondition`](@ref) ready for the iterative solver.
"""
function iec60287_triage(problem::AmpacityProblem, formulation::IEC60287Formulation)
	system = problem.system
	env = problem.environment

	# ── Environmental parameters ──────────────────────────────────────────
	soil_layer_idx = length(env.layers) >= 2 ? 2 : 1
	rho_soil = Float64(env.layers[soil_layer_idx].rho_thermal)
	theta_amb = problem.ambient_temperature

	n_cables = system.num_cables
	f = 50.0
	omega = 2 * π * f

	# ── Formation detection ───────────────────────────────────────────────
	formation = if n_cables == 3
		:trefoil
	elseif n_cables == 1
		:single
	else
		:flat
	end

	# ── Representative cable ──────────────────────────────────────────────
	cable_pos = system.cables[1]
	cable = cable_pos.design_data
	cable_id = cable.cable_id

	# ── Installation type ─────────────────────────────────────────────────
	is_buried = cable_pos.vert < 0
	installation = is_buried ? :buried : :in_air

	L_burial = if is_buried
		if formation == :trefoil
			sum(Float64(-cp.vert) for cp in system.cables) / n_cables
		else
			Float64(-cable_pos.vert)
		end
	else
		0.0
	end

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
	A_c = 0.0
	rho_c = 0.0
	alpha_c = 0.0
	theta_max = 90.0
	k_s = 1.0
	k_p = 1.0
	C_cable = 0.0

	if core_comp !== nothing
		cond = core_comp.conductor_group
		Dc = Float64(2 * cond.radius_ext)
		A_c = Float64(cond.cross_section)
		rho_c = Float64(cond.layers[1].material_props.rho)
		alpha_c = Float64(cond.alpha)

		theta_max_raw = Float64(core_comp.insulator_props.theta_max)
		if !isnan(theta_max_raw) && theta_max_raw > 0
			theta_max = theta_max_raw
		end

		# IEC 60287-1-1 Table 2 — round stranded conductors
		k_s = 1.0
		k_p = 1.0

		C_cable = Float64(core_comp.insulator_group.shunt_capacitance)
	end

	last_comp = cable.components[end]
	De = Float64(2 * last_comp.insulator_group.radius_ext)

	# Conductor spacing — touching trefoil / flat default
	s = De

	# ── Insulation / dielectric ───────────────────────────────────────────
	tan_delta = 0.004  # XLPE default (IEC 60287-1-1 Table 3)

	# Voltage to earth [V] from nominal data
	U0 = 0.0
	nd = cable.nominal_data
	if nd !== nothing
		if nd.U !== nothing
			U0 = Float64(nd.U) * 1e3 / sqrt(3.0)
		elseif nd.U0 !== nothing
			U0 = Float64(nd.U0) * 1e3
		end
	end

	# ── Core insulator layers (for T1) ────────────────────────────────────
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

	# ── Sheath insulator layers (for T3) ──────────────────────────────────
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

	# ── Screen / sheath wire data ─────────────────────────────────────────
	has_wire_screen = false
	rho_s = 0.0
	alpha_s = 0.0
	n_wires = 0
	d_wire = 0.0
	D_under = 0.0
	L_lay = 0.0
	d_mean_screen = 0.0
	LF_s = 1.0

	if sheath_comp !== nothing && !isempty(sheath_comp.conductor_group.layers)
		wire_lyr = sheath_comp.conductor_group.layers[1]
		if hasproperty(wire_lyr, :radius_wire)          # it is a WireArray
			has_wire_screen = true
			d_wire = Float64(2 * wire_lyr.radius_wire)
			n_wires = wire_lyr.num_wires
			D_under = Float64(2 * wire_lyr.radius_in)
			d_mean_screen = D_under + d_wire
			L_lay = Float64(wire_lyr.lay_ratio) * d_mean_screen
			LF_s = sqrt(1.0 + (π * d_mean_screen)^2 / L_lay^2)
			rho_s = Float64(wire_lyr.material_props.rho)
			alpha_s = Float64(wire_lyr.material_props.alpha)
		end
	end

	# ── Armour (not present for this cable type) ──────────────────────────
	has_armour = false

	# ── Construct condition ───────────────────────────────────────────────
	return IEC60287CableCondition(
		# categorical
		installation, formulation.bonding_type, formulation.solar_radiation,
		formation, n_cables, cable_id,
		# geometry [m]
		Dc, De, s, L_burial,
		# conductor
		A_c, rho_c, alpha_c, theta_max, k_s, k_p,
		# dielectric
		C_cable, U0, tan_delta, f, omega,
		# screen
		has_wire_screen, rho_s, alpha_s, n_wires, d_wire, D_under,
		L_lay, d_mean_screen, LF_s,
		# armour
		has_armour,
		# thermal
		rho_soil,
		# multi-layer
		core_insulator_layers, sheath_insulator_layers,
		# iteration state
		0.0, theta_max, theta_amb,
		1e-3, 1e-3, 100,
	)
end
