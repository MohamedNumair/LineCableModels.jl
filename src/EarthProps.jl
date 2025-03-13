"""
Abstract type for frequency-dependent (FD) earth properties formulations.
"""
abstract type FDPropsFormulation end

"""
Represents an earth model with frequency-invariant electromagnetic properties.

# Arguments
- None.

# Returns
A `ConstantProperties` object with the following attribute:
- `description`: A tag/label to identify the formu;ation in parametric analyses.

# Dependencies
- None.

# Examples
```julia
cp_model = ConstantProperties()
println(cp_model.description) # Output: "CP model"
```

# References
- None.
"""
struct ConstantProperties <: FDPropsFormulation
	description::String
	ConstantProperties() = new("CP model")
end

"""
Computes frequency-dependent earth properties using the formulation specified via object `FDPropsFormulation`.

# Arguments
- `frequencies`: A vector of frequency values \\[Hz\\].
- `base_rho_g`: The base electrical resistivity of the soil \\[Ω·m\\].
- `base_epsr_g`: The base relative permittivity of the soil (unitless).
- `base_mur_g`: The base relative permeability of the soil (unitless).
- `formulation`: An instance of a subtype of `FDPropsFormulation` defining the computation method.

# Multi-dispatch formulation
The calculation method depends on the `formulation` argument, which can be:
- `ConstantProperties()`: Assumes static values for resistivity, permittivity, and permeability.
- Additional formulations can be implemented via multi-dispatch.

# Returns
A tuple containing:
- `rho`: A vector of resistivity values \\[Ω·m\\] at the given frequencies.
- `epsilon`: A vector of permittivity values \\[F/m\\] at the given frequencies.
- `mu`: A vector of permeability values \\[H/m\\] at the given frequencies.

# Dependencies
- None.

# Examples
```julia
frequencies = [1e3, 1e4, 1e5]

# Using the CP model
rho, epsilon, mu = _calculate_earth_properties(frequencies, 100, 10, 1, ConstantProperties())
println(rho)     # Output: [100, 100, 100]
println(epsilon) # Output: [8.854e-11, 8.854e-11, 8.854e-11]
println(mu)      # Output: [1.2566e-6, 1.2566e-6, 1.2566e-6]

# Using a different model
rho, epsilon, mu = _calculate_earth_properties(frequencies, 200, 5, 1, CIGRE())
println(rho)     # Output: [computed values based on CIGRE model]
```

# References
- None.
"""
function _calculate_earth_properties(
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

"""
Abstract type for equivalent homogeneous earth model (EHEM) formulations.
"""
abstract type EHEMFormulation end

"""
EnforceLayer: Represents an homogeneous earth model defined with the properties of a specific earth layer.

# Arguments
- `layer`: An integer specifying the layer to be enforced as the equivalent homogeneous layer.
  - `-1` selects the bottommost layer.
  - `2` selects the topmost earth layer (excluding air).
  - Any integer `≥ 2` selects a specific layer.

# Returns
An instance of `EnforceLayer` with the following attributes:
- `layer`: The enforced layer index.
- `description`: A string describing the chosen layer.

# Dependencies
- None.

# Examples
```julia
# Enforce the bottommost layer
bottom_layer = EnforceLayer(-1)
println(bottom_layer.description) # Output: "Bottom layer"

# Enforce the topmost earth layer
first_layer = EnforceLayer(2)
println(first_layer.description) # Output: "Top layer"

# Enforce a specific layer
specific_layer = EnforceLayer(3)
println(specific_layer.description) # Output: "Layer 3"
```

# References
- None.
"""
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

"""
Represents a single earth layer with base and frequency-dependent properties.
"""
mutable struct EarthLayer
	base_rho_g::Number
	base_epsr_g::Number
	base_mur_g::Number
	t::Number
	rho_g::Vector{Number}
	eps_g::Vector{Number}
	mu_g::Vector{Number}

	"""
	Constructor: Initializes an `EarthLayer` object with specified base properties and computes its frequency-dependent values.

	# Arguments
	- `frequencies`: A vector of frequency values \\[Hz\\].
	- `base_rho_g`: The base electrical resistivity of the layer \\[Ω·m\\].
	- `base_epsr_g`: The base relative permittivity of the layer (unitless).
	- `base_mur_g`: The base relative permeability of the layer (unitless).
	- `t`: The thickness of the layer \\[m\\].
	- `FDformulation`: An instance of a subtype of `FDPropsFormulation` defining the computation method for frequency-dependent properties.

	# Returns
	An instance of `EarthLayer` with the following attributes:
	- `base_rho_g`: The base electrical resistivity \\[Ω·m\\].
	- `base_epsr_g`: The base relative permittivity (unitless).
	- `base_mur_g`: The base relative permeability (unitless).
	- `t`: The thickness of the layer \\[m\\].
	- `rho_g`: A vector of computed resistivity values \\[Ω·m\\] at given frequencies.
	- `eps_g`: A vector of computed permittivity values \\[F/m\\] at given frequencies.
	- `mu_g`: A vector of computed permeability values \\[H/m\\] at given frequencies.

	# Dependencies
	- `_calculate_earth_properties`: Computes frequency-dependent soil properties based on the selected formulation.

	# Examples
	```julia
	frequencies = [1e3, 1e4, 1e5]
	layer = EarthLayer(frequencies, 100, 10, 1, 5, ConstantProperties())
	println(layer.rho_g) # Output: [100, 100, 100]
	println(layer.eps_g) # Output: [8.854e-11, 8.854e-11, 8.854e-11]
	println(layer.mu_g)  # Output: [1.2566e-6, 1.2566e-6, 1.2566e-6]
	```

	# References
	- None.
	"""
	function EarthLayer(
		frequencies,
		base_rho_g,
		base_epsr_g,
		base_mur_g,
		t,
		FDformulation::FDPropsFormulation,
	)
		rho_g, eps_g, mu_g = _calculate_earth_properties(
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

"""
Represents a multi-layered earth model with frequency-dependent properties.
"""
mutable struct EarthModel
	num_layers::Int
	FDformulation::FDPropsFormulation
	EHEMformulation::Union{EHEMFormulation, Nothing}
	vertical_layers::Bool
	layers::Vector{EarthLayer}

	# Effective homogeneous parameters (start as `missing`)
	rho_eff::Union{Vector{Number}, Missing}
	eps_eff::Union{Vector{Number}, Missing}
	mu_eff::Union{Vector{Number}, Missing}

	"""
	Constructor: Initializes an `EarthModel` object with a specified first earth layer. Horizontal layering is assumed by default. A semi-infinite air layer is always added prior to the first earth layer.

	# Arguments
	- `frequencies`: A vector of frequency values \\[Hz\\].
	- `rho_g`: The base electrical resistivity of the first earth layer \\[Ω·m\\].
	- `epsr_g`: The base relative permittivity of the first earth layer (unitless).
	- `mur_g`: The base relative permeability of the first earth layer (unitless).
	- `t`: The thickness of the first earth layer \\[m\\]. For homogeneous earth models (or the bottommost layer), set `t = Inf`.
	- `FDformulation`: An instance of a subtype of `FDPropsFormulation` defining the computation method for frequency-dependent properties (default: `ConstantProperties()`).
	- `EHEMformulation`: An optional instance of a subtype of `EHEMFormulation` defining the equivalent homogeneous medium formulation (default: `nothing`).
	- `vertical_layers`: A boolean flag indicating whether the model should be treated as vertically-layered (default: `false`). In this case, the first layer is assumed to be horizontal and semi-infinite, and the subsequent layers are vertical. The thickness of the leftmost and rightmost layers should be set as `t = Inf`. The interface between the first and second vertical layers is assumed to be at `y = 0`.

	# Returns
	An instance of `EarthModel` with the following attributes:
	- `num_layers`: The total number of layers in the model, including the air layer.
	- `FDformulation`: The selected frequency-dependent formulation for earth properties.
	- `EHEMformulation`: The selected equivalent homogeneous earth formulation (or `nothing`).
	- `vertical_layers`: Boolean flag for vertically-layered earth.
	- `layers`: A vector of `EarthLayer` objects, starting with an air layer and the specified first earth layer.
	- `rho_eff`: The effective resistivity values \\[Ω·m\\] at the given frequencies (`missing` initially, computed later if needed).
	- `eps_eff`: The effective permittivity values \\[F/m\\] at the given frequencies (`missing` initially, computed later if needed).
	- `mu_eff`: The effective permeability values \\[H/m\\] at the given frequencies (`missing` initially, computed later if needed).

	# Dependencies
	- `EarthLayer`: Represents individual layers within the earth model.

	# Examples
	```julia
	frequencies = [1e3, 1e4, 1e5]
	earth_model = EarthModel(frequencies, 100, 10, 1, t=Inf)
	println(length(earth_model.layers)) # Output: 2 (air + top layer)
	println(earth_model.rho_eff) # Output: missing
	```

	# References
	- None.
	"""
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
			[air_layer, top_layer])

		# Set effective parameters as `missing` initially
		model.rho_eff = missing
		model.eps_eff = missing
		model.mu_eff = missing

		return model
	end
end

"""
Adds a new earth layer to an existing `EarthModel`.

# Arguments
- `model`: An instance of `EarthModel` to which the new layer will be added.
- `frequencies`: A vector of frequency values \\[Hz\\].
- `base_rho_g`: The base electrical resistivity of the new earth layer \\[Ω·m\\].
- `base_epsr_g`: The base relative permittivity of the new earth layer (unitless).
- `base_mur_g`: The base relative permeability of the new earth layer (unitless).
- `t`: The thickness of the new earth layer \\[m\\] (default: `Inf`).

# Returns
- Modifies `model` in place by appending a new `EarthLayer` and updating `num_layers`.
- If the model contains at least two earth layers and an `EHEMformulation` is defined, effective homogeneous parameters are computed.

# Notes
For **horizontal layering** (`vertical_layers = false`):
- Layer 1 (air) is always infinite (`t = Inf`).
- Layer 2 (first earth layer) can be infinite if modeling a homogeneous half-space.
- If adding a third layer (`num_layers = 3`), it can be infinite **only if the previous layer is finite**.
- No two successive earth layers (`num_layers > 2`) can have infinite thickness.

For **vertical layering** (`vertical_layers = true`):
- Layer 1 (air) is always **horizontal** and infinite at `z > 0`.
- Layer 2 (first vertical layer) is always **infinite** in `z < 0` **and** `y < 0`. The first vertical layer is assumed to always end at `y = 0`.
- Layer 3 (second vertical layer) **can be infinite** (establishing a vertical interface at `y = 0`).
- Subsequent layers **can be infinite only if the previous is finite**.
- No two successive vertical layers (`num_layers > 3`) can both be infinite.

# Dependencies
- `EarthLayer`: Represents individual layers within the `EarthModel`.
- `_compute_ehem_properties!`: Computes the equivalent homogeneous parameters if applicable.

# Examples
```julia
frequencies = [1e3, 1e4, 1e5]

# To define a horizontal model, initialize the top earth layer with finite thickness
horz_earth_model = EarthModel(frequencies, 100, 10, 1, t=5)

# Add a second horizontal earth layer
add_earth_layer!(horz_earth_model, frequencies, 200, 15, 1, t=10)
println(horz_earth_model.num_layers) # Output: 3

# The bottom layer should be set to infinite thickness
add_earth_layer!(horz_earth_model, frequencies, 300, 15, 1, t=Inf)
println(horz_earth_model.num_layers) # Output: 4

# Initialize a vertical-layered model with first interface at y = 0.
vert_earth_model = EarthModel(frequencies, 100, 10, 1, t=Inf, vertical_layers=true)

# Add a second vertical layer at y = 0 (this can also be infinite)
add_earth_layer!(vert_earth_model, frequencies, 150, 12, 1, t=Inf)
println(vert_earth_model.num_layers) # Output: 3

# Attempt to add a third infinite layer (invalid case)
try
	add_earth_layer!(vert_earth_model, frequencies, 120, 12, 1, t=Inf)
catch e
	println(e) # Error: Cannot add consecutive vertical layers with infinite thickness.
end

# Fix: Set a finite thickness to the currently rightmost layer
vert_earth_model.layers[end].t = 3

# Add the third layer with infinite thickness now
add_earth_layer!(vert_earth_model, frequencies, 120, 12, 1, t=Inf)
println(vert_earth_model.num_layers) # Output: 4
```

# References
- None.
"""
function add_earth_layer!(
	model::EarthModel,
	frequencies::Vector{<:Number},
	base_rho_g::Number,
	base_epsr_g::Number,
	base_mur_g::Number;
	t::Number = Inf,
)
	# Enforce thickness rules for vertically-layered models
	if model.vertical_layers
		if model.num_layers <= 3
			# Any thicknesses are valid for the first two earth layers
		elseif model.num_layers > 3
			prev_layer = model.layers[end]
			if prev_layer.t == Inf && t == Inf
				error("Cannot add consecutive vertical layers with infinite thickness.")
			end
		end
	else
		# Standard horizontal layering checks
		if model.num_layers == 2
			# If adding the first earth layer, any thickness is valid
		elseif model.num_layers > 2
			prev_layer = model.layers[end]
			if prev_layer.t == Inf && t == Inf
				error("Cannot add consecutive earth layers with infinite thickness.")
			end
		end
	end

	# Create the new earth layer
	new_layer = EarthLayer(
		frequencies,
		base_rho_g,
		base_epsr_g,
		base_mur_g,
		t,
		model.FDformulation,
	)
	push!(model.layers, new_layer)
	model.num_layers += 1

	# Compute effective parameters **only if we have at least 2 earth layers**
	if model.num_layers > 2 && !isnothing(model.EHEMformulation) && !(model.vertical_layers)
		_compute_ehem_properties!(model, frequencies, model.EHEMformulation)
	end
end

"""
Computes the effective homogeneous earth model (EHEM) properties for an `EarthModel`, using the formulation specified via object `EHEMFormulation`.

# Arguments
- `model`: An instance of `EarthModel` for which effective properties are computed.
- `frequencies`: A vector of frequency values \\[Hz\\].
- `formulation`: An `EHEMFormulation` specifying how the effective properties should be determined.

# Multi-dispatch formulation
This function is part of a **multi-dispatch framework** for computing EHEM properties. Different `EHEMFormulation` types define how the effective properties are calculated:
	- `EnforceLayer(layer)` extends the parameters of the specified layer to the entire semi-infinite (homogeneous) earth.
	- Additional formulations can be implemented by extending `_compute_ehem_properties!` with new methods.

# Behavior
- If `formulation` is an `EnforceLayer`, the effective properties (`rho_eff`, `eps_eff`, `mu_eff`) are **directly assigned** from the specified layer.
- If `layer_idx = -1`, the **last** layer in `model.layers` is used.
- If `layer_idx < 2` or `layer_idx > length(model.layers)`, an error is raised.

# Returns
- Modifies `model` in place by updating `rho_eff`, `eps_eff`, and `mu_eff` with the corresponding values.

# Dependencies
- `EarthModel`: The main struct containing all earth layers.
- `EnforceLayer`: A specific formulation that forces effective parameters to match an existing layer.

# Examples
```julia
frequencies = [1e3, 1e4, 1e5]
earth_model = EarthModel(frequencies, 100, 10, 1, t=5)
earth_model.EHEMformulation = EnforceLayer(-1)  # Enforce the last layer as the effective
add_earth_layer!(earth_model, frequencies, 200, 15, 1, t=Inf) # Inclusion of an extra layer will invoke the _compute_ehem_properties! method

println(earth_model.rho_eff) # Should match the last layer rho_g = 200
println(earth_model.eps_eff) # Should match the last layer eps_g = 15*ε₀
println(earth_model.mu_eff)  # Should match the last layer mu_g = 1*μ₀
```

# References
- None.
"""
function _compute_ehem_properties!(
	model::EarthModel,
	frequencies::Vector{<:Number},
	formulation::EnforceLayer,
)
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

"""
Generate a `DataFrame` summarizing basic properties of earth layers from an EarthModel.

# Arguments
- `earth_model`: An `EarthModel` object containing earth layers.

# Returns
- A `DataFrame` with columns:
	- `rho_g`: Base resistivity of each layer \\[Ω·m\\].
	- `epsr_g`: Relative permittivity of each layer [dimensionless].
	- `mur_g`: Relative permeability of each layer [dimensionless].
	- `thickness`: Thickness of each layer \\[m\\].

# Dependencies
- None.

# Examples
```julia
df = earth_data(earth_model)
println(df)
```

# References
- None.
"""
function earth_data(earth_model::EarthModel)
	layers = earth_model.layers

	base_rho_g = [layer.base_rho_g for layer in layers]
	base_epsr_g = [layer.base_epsr_g for layer in layers]
	base_mur_g = [layer.base_mur_g for layer in layers]
	thickness = [layer.t for layer in layers]

	return DataFrame(
		rho_g = base_rho_g,
		epsr_g = base_epsr_g,
		mur_g = base_mur_g,
		thickness = thickness,
	)
end
