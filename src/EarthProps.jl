"""
	LineCableModels.EarthProps

The [`EarthProps`](@ref) module provides functionality for modeling and computing earth properties within the [`LineCableModels.jl`](index.md) package. This module includes definitions for homogeneous and layered earth models, and formulations for frequency-dependent and equivalent homogeneous earth properties, to be used in impedance/admittance calculations.

# Overview

- Defines the [`EarthModel`](@ref) object for representing horizontally or vertically multi-layered earth models with frequency-dependent properties (ρ, ε, μ).
- Provides the [`EarthLayer`](@ref) type for representing individual soil layers with electromagnetic properties.
- Implements a multi-dispatch framework to allow different formulations of frequency-dependent earth models with [`AbstractFDEMFormulation`](@ref) and equivalent homogeneous earth models via [`AbstractEHEMFormulation`](@ref).
- Contains utility functions for building complex multi-layered earth models and generating data summaries.

# Dependencies

$(IMPORTS)

# Exports

$(EXPORTS)
"""
module EarthProps

# Load common dependencies
include("CommonDeps.jl")
using ..Utils

# Module-specific dependencies
using Measurements
using DataFrames

"""
$(TYPEDEF)

Abstract type representing different frequency-dependent earth models (FDEM). Used in the multi-dispatch implementation of [`_calc_earth_properties`](@ref).

# Currently available formulations

- [`CPEarth`](@ref): Constant properties (CP) model.
"""
abstract type AbstractFDEMFormulation end

"""
$(TYPEDEF)

Represents an earth model with constant properties (CP), i.e. frequency-invariant electromagnetic properties.
"""
struct CPEarth <: AbstractFDEMFormulation end

# "Identifier displayed in parametric analyses."
# 	description::String

# 	@doc """
# 	$(TYPEDSIGNATURES)

# 	Constructs a [`CPEarth`](@ref) instance.

# 	# Returns

# 	- A [`CPEarth`](@ref) object with a predefined description label.

# 	# Examples

# 	```julia
# 	cp_model = $(FUNCTIONNAME)()
# 	println(cp_model.description) # Output: "CP model"
# 	```
# 	"""
# 	CPEarth() = new("CP model")
# end

"""
$(TYPEDSIGNATURES)

Returns a standardized identifier string for earth model formulations.

# Arguments

- A concrete implementation of [`AbstractFDEMFormulation`](@ref) or [`AbstractEHEMFormulation`](@ref) representing the earth model formulation.

# Returns

- A string identifier used consistently across plots, tables, and parametric analyses.

# Examples
```julia
cp = CPEarth()
tag = _get_earth_formulation_tag(cp)  # Returns "CP model"
```

# Methods

$(METHODLIST)

# See also

- [`AbstractFDEMFormulation`](@ref)
- [`AbstractEHEMFormulation`](@ref)
- [`_calc_earth_properties`](@ref)
"""
function _get_earth_formulation_tag end

"""
$(TYPEDSIGNATURES)

Computes frequency-dependent earth properties using the [`CPEarth`](@ref) formulation, which assumes frequency-invariant values for resistivity, permittivity, and permeability.

# Arguments

- `frequencies`: Vector of frequency values \\[Hz\\].
- `base_rho_g`: Base (DC) electrical resistivity of the soil \\[Ω·m\\].
- `base_epsr_g`: Base (DC) relative permittivity of the soil \\[dimensionless\\].
- `base_mur_g`: Base (DC) relative permeability of the soil \\[dimensionless\\].
- `formulation`: Instance of a subtype of [`AbstractFDEMFormulation`](@ref) defining the computation method.

# Returns

- `rho`: Vector of resistivity values \\[Ω·m\\] at the given frequencies.
- `epsilon`: Vector of permittivity values \\[F/m\\] at the given frequencies.
- `mu`: Vector of permeability values \\[H/m\\] at the given frequencies.

# Examples

```julia
frequencies = [1e3, 1e4, 1e5]

# Using the CP model
rho, epsilon, mu = $(FUNCTIONNAME)(frequencies, 100, 10, 1, CPEarth())
println(rho)     # Output: [100, 100, 100]
println(epsilon) # Output: [8.854e-11, 8.854e-11, 8.854e-11]
println(mu)      # Output: [1.2566e-6, 1.2566e-6, 1.2566e-6]
```

# See also

- [`EarthLayer`](@ref)
- [`AbstractFDEMFormulation`](@ref)
"""
function _calc_earth_properties(
	frequencies::Vector{<:Number},
	base_rho_g::Number,
	base_epsr_g::Number,
	base_mur_g::Number,
	::CPEarth,
)
	rho = fill(base_rho_g, length(frequencies))
	epsilon = fill(ε₀ * base_epsr_g, length(frequencies))
	mu = fill(μ₀ * base_mur_g, length(frequencies))
	return rho, epsilon, mu
end

_get_earth_formulation_tag(::CPEarth) = "CP model"

"""
$(TYPEDEF)

Abstract type representing different equivalent homogeneous earth models (EHEM). Used in the multi-dispatch implementation of [`_calc_ehem_properties!`](@ref).

# Currently available formulations

- [`EnforceLayer`](@ref): Effective parameters defined according to a specific earth layer.
"""
abstract type AbstractEHEMFormulation end

"""
$(TYPEDEF)

Represents a homogeneous earth model defined using the properties of a specific earth layer, with atttribute:

$(TYPEDFIELDS)
"""
struct EnforceLayer <: AbstractEHEMFormulation
	"Index of the enforced earth layer."
	layer::Int

	@doc """
	$(TYPEDSIGNATURES)

	Constructs an [`EnforceLayer`](@ref) instance, meaning that the properties of the specified layer are extended to the entire semi-infinite earth.

	# Arguments

	- `layer`: Integer specifying the layer to be enforced as the equivalent homogeneous layer.
	- `-1` selects the bottommost layer.
	- `2` selects the topmost earth layer (excluding air).
	- Any integer `≥ 2` selects a specific layer.

	# Returns

	- An [`EnforceLayer`](@ref) instance with the specified layer index.

	# Examples

	```julia
	# Enforce the bottommost layer
	bottom_layer = $(FUNCTIONNAME)(-1)
	println(_get_earth_formulation_tag(bottom_layer)) # Output: "Bottom layer"

	# Enforce the topmost earth layer
	first_layer = $(FUNCTIONNAME)(2)
	println(_get_earth_formulation_tag(first_layer)) # Output: "Top layer"

	# Enforce a specific layer
	specific_layer = $(FUNCTIONNAME)(3)
	println(_get_earth_formulation_tag(specific_layer)) # Output: "Layer 3"
	```
	"""
	function EnforceLayer(layer::Int)
		@assert (layer == -1 || layer >= 2) "Invalid earth layer choice."
		return new(layer)
	end
end

function _get_earth_formulation_tag(formulation::EnforceLayer)
	if formulation.layer == -1
		return "Bottom layer"
	elseif formulation.layer == 2
		return "Top layer"
	else
		return "Layer $(formulation.layer)"
	end
end

"""
$(TYPEDEF)

Represents one single earth layer in an [`EarthModel`](@ref) object, with base and frequency-dependent properties, and attributes:

$(TYPEDFIELDS)
"""
mutable struct EarthLayer
	"Base (DC) electrical resistivity \\[Ω·m\\]."
	base_rho_g::Number
	"Base (DC) relative permittivity \\[dimensionless\\]."
	base_epsr_g::Number
	"Base (DC)  relative permeability \\[dimensionless\\]."
	base_mur_g::Number
	"Thickness of the layer \\[m\\]."
	t::Number
	"Computed resistivity values \\[Ω·m\\] at given frequencies."
	rho_g::Vector{Number}
	"Computed permittivity values \\[F/m\\] at given frequencies."
	eps_g::Vector{Number}
	"Computed permeability values \\[H/m\\] at given frequencies."
	mu_g::Vector{Number}

	@doc """
	$(TYPEDSIGNATURES)

	Constructs an [`EarthLayer`](@ref) instance with specified base properties and computes its frequency-dependent values.

	# Arguments

	- `frequencies`: Vector of frequency values \\[Hz\\].
	- `base_rho_g`: Base (DC) electrical resistivity of the layer \\[Ω·m\\].
	- `base_epsr_g`: Base (DC) relative permittivity of the layer \\[dimensionless\\].
	- `base_mur_g`: Base (DC) relative permeability of the layer \\[dimensionless\\].
	- `t`: Thickness of the layer \\[m\\].
	- `FDformulation`: Instance of a subtype of [`AbstractFDEMFormulation`](@ref) defining the computation method for frequency-dependent properties.

	# Returns

	- An [`EarthLayer`](@ref) instance with computed frequency-dependent properties.

	# Examples

	```julia
	frequencies = [1e3, 1e4, 1e5]
	layer = $(FUNCTIONNAME)(frequencies, 100, 10, 1, 5, CPEarth())
	println(layer.rho_g) # Output: [100, 100, 100]
	println(layer.eps_g) # Output: [8.854e-11, 8.854e-11, 8.854e-11]
	println(layer.mu_g)  # Output: [1.2566e-6, 1.2566e-6, 1.2566e-6]
	```

	# See also

	- [`_calc_earth_properties`](@ref)
	"""
	function EarthLayer(
		frequencies,
		base_rho_g,
		base_epsr_g,
		base_mur_g,
		t,
		FDformulation::AbstractFDEMFormulation,
	)
		rho_g, eps_g, mu_g = _calc_earth_properties(
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
$(TYPEDEF)

Represents a multi-layered earth model with frequency-dependent properties, and attributes:

$(TYPEDFIELDS)
"""
mutable struct EarthModel
	"Total number of layers in the model, including the air layer."
	num_layers::Int
	"Selected frequency-dependent formulation for earth properties."
	FDformulation::AbstractFDEMFormulation
	"Selected equivalent homogeneous earth formulation (or `nothing`)."
	EHEMformulation::Union{AbstractEHEMFormulation, Nothing}
	"Boolean flag indicating whether the model is treated as vertically layered."
	vertical_layers::Bool
	"Vector of [`EarthLayer`](@ref) objects, starting with an air layer and the specified first earth layer."
	layers::Vector{EarthLayer}

	"Effective resistivity values \\[Ω·m\\] at the given frequencies (`missing` initially, computed later if needed)."
	rho_eff::Union{Vector{Number}, Missing}
	"Effective permittivity values \\[F/m\\] at the given frequencies (`missing` initially, computed later if needed)."
	eps_eff::Union{Vector{Number}, Missing}
	"Effective permeability values \\[H/m\\] at the given frequencies (`missing` initially, computed later if needed)."
	mu_eff::Union{Vector{Number}, Missing}

	@doc """
	$(TYPEDSIGNATURES)

	Constructs an [`EarthModel`](@ref) instance with a specified first earth layer. A semi-infinite air layer is always added before the first earth layer.

	# Arguments

	- `frequencies`: Vector of frequency values \\[Hz\\].
	- `rho_g`: Base (DC) electrical resistivity of the first earth layer \\[Ω·m\\].
	- `epsr_g`: Base (DC) relative permittivity of the first earth layer \\[dimensionless\\].
	- `mur_g`: Base (DC) relative permeability of the first earth layer \\[dimensionless\\].
	- `t`: Thickness of the first earth layer \\[m\\]. For homogeneous earth models (or the bottommost layer), set `t = Inf`.
	- `FDformulation`: Instance of a subtype of [`AbstractFDEMFormulation`](@ref) defining the computation method for frequency-dependent properties (default: [`CPEarth`](@ref)).
	- `EHEMformulation`: Optional instance of a subtype of [`AbstractEHEMFormulation`](@ref) defining the equivalent homogeneous medium formulation (default: `nothing`).
	- `vertical_layers`: Boolean flag indicating whether the model should be treated as vertically-layered (default: `false`).
	- `air_layer`: optional [`EarthLayer`](@ref) object representing the semi-infinite air layer (default: `EarthLayer(frequencies, Inf, 1.0, 1.0, Inf, FDformulation)`).

	# Returns

	- An [`EarthModel`](@ref) instance with the specified attributes and computed frequency-dependent properties.

	# Examples

	```julia
	frequencies = [1e3, 1e4, 1e5]
	earth_model = $(FUNCTIONNAME)(frequencies, 100, 10, 1, t=Inf)
	println(length(earth_model.layers)) # Output: 2 (air + top layer)
	println(earth_model.rho_eff) # Output: missing
	```

	# See also

	- [`EarthLayer`](@ref)
	- [`addto_earth_model!`](@ref)
	"""
	function EarthModel(
		frequencies::Vector{<:Number},
		rho_g::Number,
		epsr_g::Number,
		mur_g::Number;
		t::Number = Inf,
		FDformulation::AbstractFDEMFormulation = CPEarth(),
		EHEMformulation::Union{AbstractEHEMFormulation, Nothing} = nothing,
		vertical_layers::Bool = false,
		air_layer = EarthLayer(frequencies, Inf, 1.0, 1.0, Inf, FDformulation),
	)

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
$(TYPEDSIGNATURES)

Adds a new earth layer to an existing [`EarthModel`](@ref).

# Arguments

- `model`: Instance of [`EarthModel`](@ref) to which the new layer will be added.
- `frequencies`: Vector of frequency values \\[Hz\\].
- `base_rho_g`: Base electrical resistivity of the new earth layer \\[Ω·m\\].
- `base_epsr_g`: Base relative permittivity of the new earth layer \\[dimensionless\\].
- `base_mur_g`: Base relative permeability of the new earth layer \\[dimensionless\\].
- `t`: Thickness of the new earth layer \\[m\\] (default: `Inf`).

# Returns

- Modifies `model` in place by appending a new [`EarthLayer`](@ref) and updating `num_layers`.
- If the model contains at least two earth layers and an [`AbstractEHEMFormulation`](@ref) is defined, effective homogeneous parameters are computed.

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

# Examples

```julia
frequencies = [1e3, 1e4, 1e5]

# Define a horizontal model with finite thickness for the first earth layer
horz_earth_model = EarthModel(frequencies, 100, 10, 1, t=5)

# Add a second horizontal earth layer
$(FUNCTIONNAME)(horz_earth_model, frequencies, 200, 15, 1, t=10)
println(horz_earth_model.num_layers) # Output: 3

# The bottom layer should be set to infinite thickness
$(FUNCTIONNAME)(horz_earth_model, frequencies, 300, 15, 1, t=Inf)
println(horz_earth_model.num_layers) # Output: 4

# Initialize a vertical-layered model with first interface at y = 0.
vert_earth_model = EarthModel(frequencies, 100, 10, 1, t=Inf, vertical_layers=true)

# Add a second vertical layer at y = 0 (this can also be infinite)
$(FUNCTIONNAME)(vert_earth_model, frequencies, 150, 12, 1, t=Inf)
println(vert_earth_model.num_layers) # Output: 3

# Attempt to add a third infinite layer (invalid case)
try
	$(FUNCTIONNAME)(vert_earth_model, frequencies, 120, 12, 1, t=Inf)
catch e
	println(e) # Error: Cannot add consecutive vertical layers with infinite thickness.
end

# Fix: Set a finite thickness to the currently rightmost layer
vert_earth_model.layers[end].t = 3

# Add the third layer with infinite thickness now
$(FUNCTIONNAME)(vert_earth_model, frequencies, 120, 12, 1, t=Inf)
println(vert_earth_model.num_layers) # Output: 4
```

# See also

- [`EarthLayer`](@ref)
- [`_calc_ehem_properties!`](@ref)
"""
function addto_earth_model!(
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
	if model.num_layers > 2 && !isnothing(model.AbstractEHEMFormulation) &&
	   !(model.vertical_layers)
		_calc_ehem_properties!(model, frequencies, model.AbstractEHEMFormulation)
	end
end

"""
$(TYPEDSIGNATURES)

Computes the effective homogeneous earth model (EHEM) properties for an [`EarthModel`](@ref), overriding the layered model with the properties of the layer defined in [`EnforceLayer`](@ref).

# Arguments

- `model`: Instance of [`EarthModel`](@ref) for which effective properties are computed.
- `frequencies`: Vector of frequency values \\[Hz\\].
- `formulation`: Instance of [`AbstractEHEMFormulation`](@ref) specifying how the effective properties should be determined.

# Returns

- Modifies `model` in place by updating `rho_eff`, `eps_eff`, and `mu_eff` with the corresponding values.

# Notes

- If `formulation` is an [`EnforceLayer`](@ref), the effective properties (`rho_eff`, `eps_eff`, `mu_eff`) are **directly assigned** from the specified layer.
- If `layer_idx = -1`, the **last** layer in `model.layers` is used.
- If `layer_idx < 2` or `layer_idx > length(model.layers)`, an error is raised.

# Examples

```julia
frequencies = [1e3, 1e4, 1e5]
earth_model = EarthModel(frequencies, 100, 10, 1, t=5)
earth_model.AbstractEHEMFormulation = EnforceLayer(-1)  # Enforce the last layer as the effective
$(FUNCTIONNAME)(earth_model, frequencies, EnforceLayer(-1))

println(earth_model.rho_eff) # Should match the last layer rho_g = 100
println(earth_model.eps_eff) # Should match the last layer eps_g = 10*ε₀
println(earth_model.mu_eff)  # Should match the last layer mu_g = 1*μ₀
```

# See also

- [`EarthModel`](@ref)
- [`AbstractEHEMFormulation`](@ref)
"""
function _calc_ehem_properties!(
	model::EarthModel,
	frequencies::Vector{<:Number},
	formulation::AbstractEHEMFormulation = EnforceLayer(-1),
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
$(TYPEDSIGNATURES)

Generates a `DataFrame` summarizing basic properties of earth layers from an [`EarthModel`](@ref).

# Arguments

- `earth_model`: Instance of [`EarthModel`](@ref) containing earth layers.

# Returns

- A `DataFrame` with columns:
  - `rho_g`: Base (DC) resistivity of each layer \\[Ω·m\\].
  - `epsr_g`: Base (DC) relative permittivity of each layer \\[dimensionless\\].
  - `mur_g`: Base (DC) relative permeability of each layer \\[dimensionless\\].
  - `thickness`: Thickness of each layer \\[m\\].

# Examples

```julia
df = $(FUNCTIONNAME)(earth_model)
println(df)
```
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

import Base: show
"""
$(TYPEDSIGNATURES)

Defines the display representation of a [`EarthModel`](@ref) object for REPL or text output.

# Arguments

- `io`: The output stream to write the representation to \\[IO\\].
- `mime`: The MIME type for plain text output \\[MIME"text/plain"\\].
- `model`: The [`EarthModel`](@ref) instance to be displayed.


# Returns

- Nothing. Modifies `io` to format the output.
"""
function show(io::IO, ::MIME"text/plain", model::EarthModel)
	# Determine model type based on num_layers and vertical_layers flag
	model_type = model.num_layers == 2 ? "homogeneous" : "multilayer"
	orientation = model.vertical_layers ? "vertical" : "horizontal"
	layer_word = (model.num_layers - 1) == 1 ? "layer" : "layers"

	# Count frequency samples from the first layer's property arrays
	num_freq_samples = length(model.layers[1].rho_g)
	freq_word = (num_freq_samples) == 1 ? "sample" : "samples"

	# Print header with key information
	println(
		io,
		"EarthModel with $(model.num_layers-1) $(orientation) earth $(layer_word) ($(model_type)) and $(num_freq_samples) frequency $(freq_word)",
	)

	# Print layers in treeview style
	for i in 1:model.num_layers
		layer = model.layers[i]
		# Determine prefix based on whether it's the last layer
		prefix = i == model.num_layers ? "└─" : "├─"

		# Format thickness value
		thickness_str = isinf(layer.t) ? "∞" : "$(round(layer.t, sigdigits=4))"

		# Format layer name
		layer_name = i == 1 ? "Air" : "Earth $i"

		# Print layer properties with proper formatting
		println(
			io,
			"$prefix $layer_name: [rho_g=$(round(layer.base_rho_g, sigdigits=4)), " *
			"epsr_g=$(round(layer.base_epsr_g, sigdigits=4)), " *
			"mur_g=$(round(layer.base_mur_g, sigdigits=4)), " *
			"t=$thickness_str]",
		)
	end

	# Add formulation information as child nodes
	if !isnothing(model.FDformulation)
		formulation_tag = _get_earth_formulation_tag(model.FDformulation)
		println(io, "├─ Frequency-dependent model: $(formulation_tag)")
	end

	# If there's an equivalent homogeneous earth model formulation, show it
	if !isnothing(model.EHEMformulation)
		formulation_tag = _get_earth_formulation_tag(model.EHEMformulation)
		println(io, "└─ Equivalent homogeneous model: $(formulation_tag)")
	elseif !isnothing(model.FDformulation)
		# Adjust the last connector if this is the last item
		println(io, "└─ No equivalent homogeneous model")
	end
end

Utils.@_autoexport

end