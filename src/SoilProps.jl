abstract type FDPropsFormulation end

struct ConstantProperties <: FDPropsFormulation
	description::String
	ConstantProperties() = new("CP model")
end

# Multi-dispatch FD soil properties implementation for different formulations
function calculate_soil_properties(
	frequencies::Vector{<:Number},
	base_rho_g::Number,
	base_epsr_g::Number,
	base_mur_g::Number,
	::ConstantProperties,
)
	rho = fill(base_rho_g, length(frequencies))
	epsilon = fill(ε₀ * base_epsr_g, length(frequencies))
	mu = fill(μ₀ * base_mur_g, length(frequencies))
	return rho, epsilon, mu
end

abstract type EHEMFormulation end

struct EnforceLayer <: EHEMFormulation
	layer::Int
	description::String
	function EnforceLayer(layer::Int = -1)
		@assert (layer == -1 || layer >= 2) "Invalid earth layer choice."

		if layer == -1
			desc = "Bottom layer"
		elseif layer == 2
			desc = "Top layer"
		else
			desc = "Layer $layer"
		end
		return new(layer, desc)
	end
end

mutable struct EarthLayer
	base_rho_g::Number
	base_epsr_g::Number
	base_mur_g::Number
	t::Number
	rho_g::Vector{Number}
	eps_g::Vector{Number}
	mu_g::Vector{Number}

	function EarthLayer(
		frequencies,
		base_rho_g,
		base_epsr_g,
		base_mur_g,
		t,
		FDformulation::FDPropsFormulation,
	)
		rho_g, eps_g, mu_g = calculate_soil_properties(
			frequencies,
			base_rho_g,
			base_epsr_g,
			base_mur_g,
			FDformulation,
		)
		return new(
			base_rho_g,
			base_epsr_g,
			base_mur_g,
			t,
			rho_g,
			eps_g,
			mu_g,
		)
	end
end

mutable struct EarthModel
	num_layers::Int
	FDformulation::FDPropsFormulation
	EHEMformulation::Union{EHEMFormulation, Nothing}
	vertical_layers::Bool
	layers::Vector{EarthLayer}
	frequencies::Vector{Number}


	# Effective homogeneous parameters (start as `missing`)
	rho_eff::Union{Vector{Number}, Missing}
	eps_eff::Union{Vector{Number}, Missing}
	mu_eff::Union{Vector{Number}, Missing}

	function EarthModel(
		frequencies::Vector{<:Number},
		rho_g::Number,
		epsr_g::Number,
		mur_g::Number;
		t::Number = Inf,
		FDformulation::FDPropsFormulation = ConstantProperties(),
		EHEMformulation::Union{EHEMFormulation, Nothing} = nothing,
		vertical_layers::Bool = false,
	)
		air_layer = EarthLayer(frequencies, Inf, 1.0, 1.0, Inf, FDformulation)
		top_layer = EarthLayer(frequencies, rho_g, epsr_g, mur_g, t, FDformulation)
		model = new(
			2,
			FDformulation,
			EHEMformulation,
			vertical_layers,
			[air_layer, top_layer],
			frequencies,)

		# Set effective parameters as `missing` initially
		model.rho_eff = missing
		model.eps_eff = missing
		model.mu_eff = missing

		return model
	end
end

function add_earth_layer!(
	model::EarthModel,
	base_rho_g::Number,
	base_epsr_g::Number,
	base_mur_g::Number;
	t::Number = Inf,
)
	new_layer = EarthLayer(
		model.frequencies,
		base_rho_g,
		base_epsr_g,
		base_mur_g,
		t,
		model.FDformulation,
	)
	push!(model.layers, new_layer)
	model.num_layers += 1

	# Compute effective parameters **only if we have at least 2 earth layers**
	if model.num_layers > 2 && !isnothing(model.EHEMformulation)
		compute_ehem_properties!(model, model.EHEMformulation)
	end
end

# Multi-dispatch EHEM implementation for different formulations
function compute_ehem_properties!(model::EarthModel, formulation::EnforceLayer)
	layer_idx = formulation.layer

	if layer_idx == -1
		layer_idx = length(model.layers)  # Use last layer
	elseif layer_idx < 2 || layer_idx > length(model.layers)
		error(
			"Invalid layer index: $layer_idx. Must be between 2 and $(length(model.layers))",
		)
	end

	layer = model.layers[layer_idx]

	# Just reference the selected layer
	model.rho_eff = layer.rho_g
	model.eps_eff = layer.eps_g
	model.mu_eff = layer.mu_g
end
