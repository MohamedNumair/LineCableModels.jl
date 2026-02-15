"""
    LineCableModels.Engine.IEC60287.Solver

Solves the AmpacityProblem using the IEC 60287 formulation.
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

Calculates the continuous current rating (ampacity) for the cables in the system.
Returns a Dict mapping each cable to its rated current.

Assumes all cables are loaded equally if they are part of the same circuit.
"""
function compute_ampacity(problem::AmpacityProblem, formulation::IEC60287Formulation)
	system = problem.system
	env = problem.environment

	results = Dict{String, Float64}()

	# Extract environmental parameters
	# Assume homogeneous earth or first layer dominates for simple T4 calculations
	# In EarthModel, layers[1] is typically Air, layers[2] is the first soil layer.
	# If the model only has 1 layer (Air), then use that (unlikely for buried).
	soil_layer_idx = length(env.layers) >= 2 ? 2 : 1
	rho_soil = env.layers[soil_layer_idx].rho_thermal 
	theta_amb = env.layers[soil_layer_idx].theta_ambient

	for (i, cable_pos) in enumerate(system.cables)
		cable = cable_pos.design_data
		cable_id = cable.cable_id 
        
		# Unique result key
		res_key = "$(cable_id)_$i"
		
		# Depth of burial (L) is negative of vertical position if buried
		is_buried = cable_pos.vert < 0
		L_burial = is_buried ? -cable_pos.vert : 0.0

		# 1. Gather component parameters
		# Identify Conductor component (carrying current)
		# Look at 'conn' to find phase connection
		phase_indices = findall(x -> x > 0, cable_pos.conn)
		
		if isempty(phase_indices)
			# @warn "Cable position $i ($cable_id) has no phase conductor connected"
			results[res_key] = 0.0
			continue
		end
		
		# Assume first phase connected component is the main conductor
		cond_idx = phase_indices[1]
		conductor_comp = cable.components[cond_idx]
		
		cond = conductor_comp.conductor_group
		# Effective properties for conductor
		cond_props = conductor_comp.conductor_props
        
		# Insulation is usually the NEXT component's insulator or this component's insulator?
		# Actually for "core" component, insulator_group is the insulation around the conductor.
		insu = conductor_comp.insulator_group
		insu_props = conductor_comp.insulator_props
		
		# Geometry
		Dc = 2 * cond.r_out
		t1 = insu.r_out - insu.r_in
		De_insu = 2 * insu.r_out 
		
		# Losses placeholders
		Wd = 0.0 
		lambda1 = 0.0 
		lambda2 = 0.0 
        
		# Thermal Resistances
		rho_ins = insu_props.rho_thermal
		T1 = calc_T1(rho_ins, t1, Dc)
		T2 = 0.0
		T3 = 0.0
        
		# Materials for calculations
		theta_max = insu_props.theta_max
		if isnan(theta_max) || iszero(theta_max)
			 theta_max = 90.0 # Default fallback
		end

		# 2. Electrical Parameters
		alpha = cond_props.alpha
		rho_elec = cond_props.rho
        
		# R_dc calculation. 
		area = π * (cond.r_out^2 - cond.r_in^2)
		R_dc_20 = rho_elec / area
		
		R_theta = R_dc_20 * (1 + alpha * (theta_max - 20))
		
		ys = calc_skin_effect_factor(R_theta, 50.0, 1.0) # k_s=1 placeholder
		yp = 0.0 # Proximity placeholder
		
		R_ac = R_theta * (1 + ys + yp)
		
		# Calculate T4
		# Need Diameter External of the WHOLE cable
		last_comp = cable.components[end]
		De_cable = 2 * last_comp.insulator_group.r_out
		
		if is_buried
			T4 = calc_T4(rho_soil, L_burial, De_cable)
		else
			# Air
			T4 = calc_T4_air(De_cable, theta_amb, theta_max, 10.0) # h=10 placeholder
		end
		
		# 5. Ampacity Equation
		n = 1.0 # 1 core per cable (if single core)
		
		delta_theta = theta_max - theta_amb
		
		# Numerator
		num = delta_theta - Wd * (0.5 * T1 + n * (T2 + T3 + T4))
		
		# Denominator
		den = R_ac * T1 + n * R_ac * (1 + lambda1) * T2 + n * R_ac * (1 + lambda1 + lambda2) * (T3 + T4)
		
		if num < 0
			 I_rated = 0.0
		else
			 I_rated = sqrt(num / den)
		end
		
		results[res_key] = I_rated
	end

	return results
end

end # module
