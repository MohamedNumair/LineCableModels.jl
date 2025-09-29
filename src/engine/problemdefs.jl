"""
$(TYPEDEF)

Represents a line parameters computation problem for a given physical cable system.

$(TYPEDFIELDS)
"""
struct LineParametersProblem{T <: REALSCALAR} <: ProblemDefinition
	"The physical cable system to analyze."
	system::LineCableSystem{T}
	"Operating temperature \\[°C\\]."
	temperature::T
	"Earth properties model."
	earth_props::EarthModel{T}
	"Frequencies at which to perform the analysis \\[Hz\\]."
	frequencies::Vector{T}

	@doc """
	$(TYPEDSIGNATURES)

	Constructs a [`LineParametersProblem`](@ref) instance.

	# Arguments

	- `system`: The cable system to analyze ([`LineCableSystem`](@ref)).
	- `temperature`: Operating temperature \\[°C\\]. Default: `T₀`.
	- `earth_props`: Earth properties model ([`EarthModel`](@ref)).
	- `frequencies`: Frequencies for analysis \\[Hz\\]. Default: [`f₀`](@ref).

	# Returns

	- A [`LineParametersProblem`](@ref) object with validated cable system, temperature, earth model, and frequency vector.

	# Examples

	```julia
	prob = $(FUNCTIONNAME)(system; temperature=25.0, earth_props=earth, frequencies=[50.0, 60.0, 100.0])
	```
	"""
	function LineParametersProblem(
		system::LineCableSystem;
		temperature::REALSCALAR = (T₀),
		earth_props::EarthModel,
		frequencies::Vector{<:Number} = [f₀],
	)

		# 1. System structure validation
		@assert !isempty(system.cables) "LineCableSystem must contain at least one cable"

		# 2. Phase assignment validation
		phase_numbers = unique(vcat([cable.conn for cable in system.cables]...))
		@assert !isempty(filter(x -> x > 0, phase_numbers)) "At least one conductor must be assigned to a phase (>0)"
		@assert maximum(phase_numbers) <= system.num_phases "Invalid phase number detected"

		# 3. Cable components validation
		for (i, cable) in enumerate(system.cables)
			@assert !isempty(cable.design_data.components) "Cable $i has no components defined"

			# Validate conductor-insulator pairs
			for (j, comp) in enumerate(cable.design_data.components)
				@assert !isempty(comp.conductor_group.layers) "Component $j in cable $i has no conductor layers"
				@assert !isempty(comp.insulator_group.layers) "Component $j in cable $i has no insulator layers"

				# Validate monotonic increase of radii
				@assert comp.conductor_group.radius_ext > comp.conductor_group.radius_in "Component $j in cable $i: conductor outer radius must be larger than inner radius"
				@assert comp.insulator_group.radius_ext > comp.insulator_group.radius_in "Component $j in cable $i: insulator outer radius must be larger than inner radius"

				# Validate geometric continuity between conductor and insulator
				r_ext_cond = comp.conductor_group.radius_ext
				r_in_ins = comp.insulator_group.radius_in
				@assert abs(r_ext_cond - r_in_ins) < 1e-10 "Geometric mismatch in cable $i component $j: conductor outer radius ≠ insulator inner radius"

				# Validate electromagnetic properties
				# Conductor properties
				@assert comp.conductor_props.rho > 0 "Component $j in cable $i: conductor resistivity must be positive"
				@assert comp.conductor_props.mu_r > 0 "Component $j in cable $i: conductor relative permeability must be positive"
				@assert comp.conductor_props.eps_r >= 0 "Component $j in cable $i: conductor relative permittivity grater than or equal to zero"

				# Insulator properties
				@assert comp.insulator_props.rho > 0 "Component $j in cable $i: insulator resistivity must be positive"
				@assert comp.insulator_props.mu_r > 0 "Component $j in cable $i: insulator relative permeability must be positive"
				@assert comp.insulator_props.eps_r > 0 "Component $j in cable $i: insulator relative permittivity must be positive"
			end
		end

		# 4. Temperature range validation
		@assert abs(temperature - T₀) < ΔTmax """
Temperature is outside the valid range for linear resistivity model:
T = $temperature
T₀ = $T₀
ΔTmax = $ΔTmax
|T - T₀| = $(abs(temperature - T₀))"""

		# 5. Frequency range validation
		@assert !isempty(frequencies) "Frequency vector cannot be empty"
		@assert all(f -> f > 0, frequencies) "All frequencies must be positive"
		@assert issorted(frequencies) "Frequency vector must be monotonically increasing"
		if maximum(frequencies) > 1e8
			@warn "Frequencies above 100 MHz exceed quasi-TEM validity limit. High-frequency results should be interpreted with caution." maxfreq =
				maximum(frequencies)
		end

		# 6. Earth model validation
		@assert length(earth_props.layers[end].rho_g) == length(frequencies) """Earth model frequencies must match analysis frequencies
		Earth model frequencies = $(length(earth_props.layers[end].rho_g))
		Analysis frequencies = $(length(frequencies))
		"""

		# 7. Geometric validation
		positions = [
			(
				cable.horz,
				cable.vert,
				maximum(
					comp.insulator_group.radius_ext
					for comp in cable.design_data.components
				),
			)
			for cable in system.cables
		]

		for i in eachindex(positions)
			for j in (i+1):lastindex(positions)
				# Calculate center-to-center distance
				dist = sqrt(
					(positions[i][1] - positions[j][1])^2 +
					(positions[i][2] - positions[j][2])^2,
				)

				# Get outermost radii for both cables
				r_outer_i = positions[i][3]
				r_outer_j = positions[j][3]

				# Check if cables overlap
				min_allowed_dist = r_outer_i + r_outer_j

				@assert dist > min_allowed_dist """
					Cables $i and $j overlap!
					Center-to-center distance: $(dist) m
					Minimum required distance: $(min_allowed_dist) m
					Cable $i outer radius: $(r_outer_i) m
					Cable $j outer radius: $(r_outer_j) m"""
			end
		end

		T = resolve_T(system, temperature, earth_props, frequencies)
		return new{T}(
			coerce_to_T(system, T),
			coerce_to_T(temperature, T),
			coerce_to_T(earth_props, T),
			coerce_to_T(frequencies, T),
		)
	end
end

# @kwdef struct EMTOptions <: AbstractFormulationOptions
# 	"Skip user confirmation for overwriting results"
# 	force_overwrite::Bool = false
# 	"Reduce bundle conductors to equivalent single conductor"
# 	reduce_bundle::Bool = true
# 	"Eliminate grounded conductors from the system (Kron reduction)"
# 	kron_reduction::Bool = true
# 	"Enforce ideal transposition/snaking"
# 	ideal_transposition::Bool = true
# 	"Temperature correction"
# 	temperature_correction::Bool = true
# 	"Save path for output files"
# 	save_path::String = joinpath(".", "lineparams_output")
# 	"Verbosity level"
# 	verbosity::Int = 0
# 	"Log file path"
# 	logfile::Union{String, Nothing} = nothing
# end

# The one-line constructor to "promote" a NamedTuple
# EMTOptions(opts::NamedTuple) = EMTOptions(; opts...)

"""
$(TYPEDEF)

Represents the electromagnetic transient (EMT) formulation set for cable or line systems, containing all required impedance and admittance models for internal and earth effects.

$(TYPEDFIELDS)
"""
struct EMTFormulation <: AbstractFormulationSet
	"Internal impedance formulation."
	internal_impedance::InternalImpedanceFormulation
	"Insulation impedance formulation."
	insulation_impedance::InsulationImpedanceFormulation
	"Earth impedance formulation."
	earth_impedance::EarthImpedanceFormulation
	"Insulation admittance formulation."
	insulation_admittance::InsulationAdmittanceFormulation
	"Earth admittance formulation."
	earth_admittance::EarthAdmittanceFormulation
	"Modal transformation method."
	modal_transform::AbstractTransformFormulation
	"Equivalent homogeneous earth model (EHEM) formulation."
	equivalent_earth::Union{AbstractEHEMFormulation, Nothing}
	"Solver options for EMT-type computations."
	options::EMTOptions

	@doc """
	$(TYPEDSIGNATURES)

	Constructs an [`EMTFormulation`](@ref) instance.

	# Arguments

	- `internal_impedance`: Internal impedance formulation.
	- `insulation_impedance`: Insulation impedance formulation.
	- `earth_impedance`: Earth impedance formulation.
	- `insulation_admittance`: Insulation admittance formulation.
	- `earth_admittance`: Earth admittance formulation.
	- `modal_transform`: Modal transformation method.
	- `equivalent_earth`: Equivalent homogeneous earth model (EHEM) formulation.
	- `options`: Solver options for EMT-type computations.

	# Returns

	- An [`EMTFormulation`](@ref) object containing the specified methods.

	# Examples

	```julia
	emt = $(FUNCTIONNAME)(...)
	```
	"""
	function EMTFormulation(;
		internal_impedance::InternalImpedanceFormulation,
		insulation_impedance::InsulationImpedanceFormulation,
		earth_impedance::EarthImpedanceFormulation,
		insulation_admittance::InsulationAdmittanceFormulation,
		earth_admittance::EarthAdmittanceFormulation,
		modal_transform::AbstractTransformFormulation,
		equivalent_earth::Union{AbstractEHEMFormulation, Nothing},
		options::EMTOptions,
	)
		return new(
			internal_impedance, insulation_impedance, earth_impedance,
			insulation_admittance, earth_admittance, modal_transform, equivalent_earth,
			options,
		)
	end
end

function FormulationSet(::Val{:EMT};
	internal_impedance::InternalImpedanceFormulation = InternalImpedance.ScaledBessel(),
	insulation_impedance::InsulationImpedanceFormulation = InsulationImpedance.Lossless(),
	earth_impedance::EarthImpedanceFormulation = EarthImpedance.Papadopoulos(),
	insulation_admittance::InsulationAdmittanceFormulation = InsulationAdmittance.Lossless(),
	earth_admittance::EarthAdmittanceFormulation = EarthAdmittance.Papadopoulos(),
	modal_transform::AbstractTransformFormulation = Transforms.Fortescue(),
	equivalent_earth::Union{AbstractEHEMFormulation, Nothing} = nothing,
	options = (;),
)
	emt_opts = build_options(EMTOptions, options; strict = true)
	return EMTFormulation(; internal_impedance, insulation_impedance, earth_impedance,
		insulation_admittance, earth_admittance, modal_transform, equivalent_earth,
		options = emt_opts,
	)
end

function FormulationSet(::Val{:DSS};
	internal_impedance::DSSEarthModel = DeriModel(),
	earth_impedance::DSSEarthModel = FullCarson(),
	options = (;),
)
	dss_opts = build_options(DSSOptions, options; strict = true)
	return DSSFormulation(; internal_impedance, earth_impedance, options = dss_opts)
end

