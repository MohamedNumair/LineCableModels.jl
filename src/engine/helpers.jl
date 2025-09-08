"""
$(TYPEDSIGNATURES)

Inspects all numerical data within a `LineParametersProblem` and determines the
common floating-point type. If any value (frequencies, geometric properties,
material properties, or earth properties) is a `Measurement`, the function
returns `Measurement{Float64}`. Otherwise, it returns `Float64`.
"""
function _find_common_type(problem::LineParametersProblem)
	# Check frequencies
	any(x -> x isa Measurement, problem.frequencies) && return Measurement{Float64}

	# Check cable system properties
	for cable in problem.system.cables
		(cable.horz isa Measurement || cable.vert isa Measurement) &&
			return Measurement{Float64}
		for component in cable.design_data.components
			if any(
				x -> x isa Measurement,
				(
					component.conductor_group.radius_in,
					component.conductor_group.radius_ext,
					component.insulator_group.radius_in,
					component.insulator_group.radius_ext,
					component.conductor_props.rho, component.conductor_props.mu_r,
					component.conductor_props.eps_r,
					component.insulator_props.rho, component.insulator_props.mu_r,
					component.insulator_props.eps_r,
					component.insulator_group.shunt_capacitance,
					component.insulator_group.shunt_conductance,
				),
			)
				return Measurement{Float64}
			end
		end
	end

	# Check earth model properties
	if !isnothing(problem.earth_props)
		for layer in problem.earth_props.layers
			if any(x -> x isa Measurement, (layer.rho_g, layer.mu_g, layer.eps_g))
				return Measurement{Float64}
			end
		end
	end

	if !isnothing(problem.temperature)
		if problem.temperature isa Measurement
			return Measurement{Float64}
		end

	end

	return Float64
end

function _get_earth_data(
	formulation::AbstractEHEMFormulation,
	earth_model::EarthModel,
	freq::Vector{<:REALSCALAR},
	T::DataType,
)
	return formulation(earth_model, freq, T)
end

"""
Default method for when no EHEM formulation is provided. 
"""
function _get_earth_data(::Nothing,
	earth_model::EarthModel,
	freq::AbstractVector{<:REALSCALAR},
	::Type{T}) where {T <: REALSCALAR}

	nL = length(earth_model.layers)
	nF = length(freq)

	ρ = Matrix{T}(undef, nL, nF)
	ε = Matrix{T}(undef, nL, nF)
	μ = Matrix{T}(undef, nL, nF)

	@inbounds for i in 1:nL
		L = earth_model.layers[i]
		@assert length(L.rho_g) == nF && length(L.eps_g) == nF && length(L.mu_g) == nF
		# Fill elementwise to avoid temp vectors
		for j in 1:nF
			ρ[i, j] = T(to_nominal(L.rho_g[j]))
			ε[i, j] = T(to_nominal(L.eps_g[j]))
			μ[i, j] = T(to_nominal(L.mu_g[j]))
		end
	end

	return (rho_g = ρ, eps_g = ε, mu_g = μ)
end
# function _get_earth_data(
# 	::Nothing,
# 	earth_model::EarthModel,
# 	freq::Vector{<:REALSCALAR},
# 	T::DataType,
# )
# 	return [
# 		(
# 			rho_g = T.(to_nominal.(layer.rho_g)),
# 			eps_g = T.(to_nominal.(layer.eps_g)),
# 			mu_g = T.(to_nominal.(layer.mu_g)),
# 		)
# 		for layer in earth_model.layers
# 	]
# end

