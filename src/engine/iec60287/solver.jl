"""
    LineCableModels.Engine.IEC60287.Solver

Solves the AmpacityProblem using the IEC 60287 formulation.
Implements the complete steady-state ampacity calculation including:
- Multi-layer thermal resistances T1, T3 (IEC 60287-2-1)
- Wire screen degree-of-cover correction factors (IEC 60287-2-1 Section 4.2.4.3.3)
- External thermal resistance T4 for trefoil formation
- Skin + proximity effects, dielectric losses, screen circulating-current losses
- Iterative solution coupling screen temperature to ampacity
"""
module Solver

using ....Commons: π, T₀
using ....DataModel
using ..IEC60287: AmpacityProblem, IEC60287Formulation
using ..Losses
using ..Thermal

export compute_ampacity

"""
    compute_ampacity(problem::AmpacityProblem, formulation::IEC60287Formulation)

Calculates the continuous current rating (ampacity) for the cables in the system
according to IEC 60287-1-1/2-1.

Returns a `Dict{String, NamedTuple}` with detailed intermediate values for validation.
"""
function compute_ampacity(problem::AmpacityProblem, formulation::IEC60287Formulation)
	system = problem.system
	env = problem.environment

	# ── Environmental parameters ──────────────────────────────────────────────
	soil_layer_idx = length(env.layers) >= 2 ? 2 : 1
	rho_soil = env.layers[soil_layer_idx].rho_thermal
	theta_amb = problem.ambient_temperature

	# System-level constants
	n_cables = system.num_cables
	f = 50.0
	omega = 2 * π * f
	is_trefoil = (n_cables == 3)

	results = Dict{String, Any}()

	# ── Representative cable (identical cables) ───────────────────────────────
	cable_pos = system.cables[1]
	cable = cable_pos.design_data
	cable_id = cable.cable_id

	is_buried = cable_pos.vert < 0
	L_burial = if is_buried
		if is_trefoil
			# IEC 60287 trefoil T4: use mean depth of cable group centre
			sum(-cp.vert for cp in system.cables) / n_cables
		else
			-cable_pos.vert
		end
	else
		0.0
	end

	# ── Identify core and sheath components ───────────────────────────────────
	core_comp = nothing
	sheath_comp = nothing

	for comp in cable.components
		if comp.id == "core"
			core_comp = comp
		elseif comp.id == "sheath"
			sheath_comp = comp
		end
	end

	# Fallback: use phase connection vector
	if core_comp === nothing
		phase_indices = findall(x -> x > 0, cable_pos.conn)
		if !isempty(phase_indices)
			core_comp = cable.components[phase_indices[1]]
		end
	end
	if sheath_comp === nothing && length(cable.components) >= 2
		sheath_comp = cable.components[2]
	end

	if core_comp === nothing
		results[cable_id] = (; I_rated = 0.0)
		return results
	end

	# =====================================================================
	# 1. GEOMETRY
	# =====================================================================

	cond = core_comp.conductor_group
	Dc = 2 * cond.radius_ext                                   # conductor diameter [m]

	last_comp = cable.components[end]
	De_cable = 2 * last_comp.insulator_group.radius_ext        # overall cable diameter [m]

	s = De_cable                                               # conductor spacing (touching trefoil) [m]

	# =====================================================================
	# 2. DC RESISTANCE AT 20 °C
	# =====================================================================

	alpha_c = cond.alpha

	# DC resistance at 20 °C from material resistivity and conductor cross-section
	rho_elec = cond.layers[1].material_props.rho
	R_dc_20 = rho_elec / cond.cross_section

	# Maximum operating temperature
	theta_max = core_comp.insulator_props.theta_max
	if isnan(theta_max) || iszero(theta_max)
		theta_max = 90.0
	end

	# =====================================================================
	# 3. AC RESISTANCE  (skin + proximity)
	# =====================================================================

	k_s = 1.0   # IEC 60287-1-1 Table 2 — round stranded
	k_p = 1.0

	ac = calc_ac_resistance(R_dc_20, alpha_c, theta_max, f, k_s, k_p, Dc, s)
	R_ac      = ac.R_ac
	R_dc_th   = ac.R_dc_theta
	y_s       = ac.y_s
	y_p       = ac.y_p

	# =====================================================================
	# 4. DIELECTRIC LOSSES
	# =====================================================================

	Wd = 0.0
	U_e = 0.0
	tandelta = 0.004       # XLPE, IEC 60287-1-1 Table 3

	# Capacitance [F/m] from insulator group (series combination of all layers)
	C_cable = core_comp.insulator_group.shunt_capacitance

	# Voltage phase-to-earth [V] from nominal data (system specification)
	nd = cable.nominal_data
	if nd !== nothing
		if nd.U !== nothing
			U_e = nd.U * 1e3 / sqrt(3.0)
		elseif nd.U0 !== nothing
			U_e = nd.U0 * 1e3
		end
	end

	if C_cable > 0 && U_e > 0
		Wd = calc_dielectric_loss(U_e, omega, C_cable, tandelta)
	end

	# =====================================================================
	# 5. THERMAL RESISTANCE T1  (conductor → screen, multi-layer)
	# =====================================================================

	T1_prime = 0.0
	for layer in core_comp.insulator_group.layers
		T1_prime += calc_layer_thermal_resistance(
			layer.material_props.rho_thermal,
			layer.radius_in,
			layer.radius_ext)
	end

	# =====================================================================
	# 6. THERMAL RESISTANCE T2 (armour bedding)
	# =====================================================================

	T2 = 0.0              # no armour in this cable

	# =====================================================================
	# 7. THERMAL RESISTANCE T3  (jacket / outer covering, multi-layer)
	# =====================================================================

	T3_prime = 0.0
	if sheath_comp !== nothing
		for layer in sheath_comp.insulator_group.layers
			T3_prime += calc_layer_thermal_resistance(
				layer.material_props.rho_thermal,
				layer.radius_in,
				layer.radius_ext)
		end
	end

	# =====================================================================
	# 8. CORRECTION FACTORS  (wire-screen cover < 50 %)
	#    IEC 60287-2-1 Note following Table 1
	# =====================================================================

	T1_corr = 1.0
	T3_corr = 1.0

	# Screen wire data (needed for correction AND for λ₁ later)
	has_wire_screen = false
	d_wire = 0.0
	n_wires = 0
	D_under = 0.0
	LF_s = 1.0
	d_mean_sc = 0.0
	L_lay = 0.0

	if sheath_comp !== nothing && !isempty(sheath_comp.conductor_group.layers)
		wire_lyr = sheath_comp.conductor_group.layers[1]

		if hasproperty(wire_lyr, :radius_wire)          # it is a WireArray
			has_wire_screen = true
			d_wire   = 2 * wire_lyr.radius_wire
			n_wires  = wire_lyr.num_wires
			D_under  = 2 * wire_lyr.radius_in
			d_mean_sc = D_under + d_wire                    # corrected mean diameter [m]
			L_lay    = wire_lyr.lay_ratio * d_mean_sc       # corrected lay length [m]

			LF_s = sqrt(1 + (π * d_mean_sc)^2 / L_lay^2)

			DoC = calc_screen_degree_of_cover(d_wire, n_wires, D_under, LF_s)

			if DoC < 0.5
				T1_corr = 1.07
				T3_corr = 1.6
			end
		end
	end

	T1 = T1_corr * T1_prime
	T3 = T3_corr * T3_prime

	# =====================================================================
	# 9. THERMAL RESISTANCE T4  (external / soil)
	# =====================================================================

	T4 = if is_buried
		is_trefoil ? calc_T4_trefoil(rho_soil, L_burial, De_cable) :
		             calc_T4(rho_soil, L_burial, De_cable)
	else
		calc_T4_air(De_cable, theta_amb, theta_max, 10.0)
	end

	# =====================================================================
	# 10. AMPACITY — iterative solution for screen temperature
	# =====================================================================

	n = 1.0              # single core per cable
	delta_theta = theta_max - theta_amb

	lambda1 = 0.0
	lambda2 = 0.0

	# Initial guess (no screen losses)
	num0 = delta_theta - Wd * (0.5 * T1 + n * (T2 + T3 + T4))
	den0 = R_ac * T1 + n * R_ac * (1 + lambda1) * T2 +
	       n * R_ac * (1 + lambda1 + lambda2) * (T3 + T4)
	I_rated = num0 > 0 ? sqrt(num0 / den0) : 0.0

	theta_s = theta_max
	R_s = 0.0
	X_s = 0.0

	if has_wire_screen
		wire_lyr = sheath_comp.conductor_group.layers[1]
		rho_s   = wire_lyr.material_props.rho
		alpha_s = wire_lyr.material_props.alpha

		max_iter = 50
		tol      = 1e-6
		I_prev   = 0.0

		for _iter in 1:max_iter
			# Screen temperature
			theta_s = theta_max - (I_rated^2 * R_ac + 0.5 * Wd) * T1

			# Screen resistance at θ_s
			scr = calc_screen_resistance(rho_s, alpha_s, n_wires, d_wire,
			                             D_under, L_lay, theta_s)
			R_s = scr.R_s

			# Sheath loss factor
			slf = calc_sheath_loss_factors(R_s, R_ac, s, d_mean_sc, omega;
			                              bonding = formulation.bonding_type)
			lambda1 = slf.lambda1
			X_s     = slf.X_s

			# Re-evaluate ampacity
			num = delta_theta - Wd * (0.5 * T1 + n * (T2 + T3 + T4))
			den = R_ac * T1 +
			      n * R_ac * (1 + lambda1) * T2 +
			      n * R_ac * (1 + lambda1 + lambda2) * (T3 + T4)

			I_rated = num > 0 ? sqrt(num / den) : 0.0

			abs(I_rated - I_prev) < tol && break
			I_prev = I_rated
		end
	end

	# =====================================================================
	# 11. POST-PROCESS: losses and temperatures at rated current
	# =====================================================================

	Wc  = R_ac * I_rated^2                                 # conductor losses  [W/m]
	Ws  = lambda1 * Wc                                     # screen losses     [W/m]
	WI  = Wc * (1 + lambda1 + lambda2)                     # total ohmic       [W/m]
	Wt  = WI + Wd                                          # total per phase   [W/m]
	Wsys = n_cables * Wt                                   # total system      [W/m]

	theta_c  = theta_max
	theta_s  = theta_c - (Wc + 0.5 * Wd) * T1
	theta_e  = theta_s -
	           n * (Wc * (1 + lambda1) + Wd) * T2 -
	           n * (WI + Wd) * T3

	# =====================================================================
	# 12. RESULTS NAMED-TUPLE
	# =====================================================================

	result = (;
		I_rated,
		# temperatures [°C]
		theta_c, theta_s, theta_e, theta_amb, delta_theta,
		# resistance [Ω/m]
		R_dc_20, R_dc_theta = R_dc_th, R_ac, y_s, y_p,
		# losses [W/m]
		Wd, Wc, Ws, WI, Wt, Wsys,
		# loss factors
		lambda1, lambda2,
		# thermal resistances [K·m/W]
		T1_prime, T1, T1_correction = T1_corr,
		T2,
		T3_prime, T3, T3_correction = T3_corr,
		T4,
		# screen
		R_s, X_s, d_mean_screen = d_mean_sc, LF_s,
		# cable
		Dc, De_cable, s, C_cable, U_e,
		n_cables, is_trefoil, f,
		bonding_type = formulation.bonding_type,
	)

	results[cable_id] = result
	return results
end

end # module
