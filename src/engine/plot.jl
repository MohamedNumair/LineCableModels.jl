
using Makie
import Makie: plot

import ..BackendHandler: BackendHandler, next_fignum
using Base: basename, mod1
using Dates: format, now

using ..PlotUIComponents:
	PlotAssembly,
	PlotBuildArtifacts,
	ControlButtonSpec,
	ControlToggleSpec,
	ControlReaction,
	_make_window,
	_run_plot_pipeline,
	with_plot_theme,
	ensure_export_background!,
	with_icon,
	MI_REFRESH,
	MI_SAVE,
	ICON_TTF,
	AXIS_LABEL_FONT_SIZE,
	clear_status!

const _ICON_FN =
	(icon; text = nothing, kwargs...) ->
		with_icon(icon; text = text === nothing ? "" : text, kwargs...)

const LP_FIG_SIZE = (800, 400)

const METRIC_PREFIX_EXPONENT = Dict(
	:yocto => -24,
	:zepto => -21,
	:atto => -18,
	:femto => -15,
	:pico => -12,
	:nano => -9,
	:micro => -6,
	:milli => -3,
	:centi => -2,
	:deci => -1,
	:base => 0,
	:deca => 1,
	:hecto => 2,
	:kilo => 3,
	:mega => 6,
	:giga => 9,
	:tera => 12,
	:peta => 15,
	:exa => 18,
	:zetta => 21,
	:yotta => 24,
)

const METRIC_PREFIX_SYMBOL = Dict(
	:yocto => "y",
	:zepto => "z",
	:atto => "a",
	:femto => "f",
	:pico => "p",
	:nano => "n",
	:micro => "μ",
	:milli => "m",
	:centi => "c",
	:deci => "d",
	:base => "",
	:deca => "da",
	:hecto => "h",
	:kilo => "k",
	:mega => "M",
	:giga => "G",
	:tera => "T",
	:peta => "P",
	:exa => "E",
	:zetta => "Z",
	:yotta => "Y",
)

const DEFAULT_QUANTITY_UNITS = Dict(
	:impedance => :base,
	:admittance => :base,
	:resistance => :base,
	:inductance => :milli,
	:conductance => :base,
	:capacitance => :micro,
	:angle => :base,
)

struct UnitSpec
	symbol::String
	per_length::Bool
end

struct ComponentMetadata
	component::Symbol
	quantity::Symbol
	symbol::String
	title::String
	axis_label::String
	unit::UnitSpec
end

struct LineParametersPlotSpec
	parent_kind::Symbol
	component::Symbol
	symbol::String
	title::String
	xlabel::String
	ylabel::String
	freqs::Vector{Float64}
	raw_freqs::Vector{Float64}
	curves::Vector{Vector{Float64}}
	raw_curves::Vector{Vector{Float64}}
	labels::Vector{String}
	x_exp::Int
	y_exp::Int
	fig_size::Union{Nothing, Tuple{Int, Int}}
	xscale::Base.RefValue{Function}
	yscale::Base.RefValue{Function}
end

const EXPORT_TIMESTAMP_FORMAT = "yyyymmdd_HHMMSS"
const EXPORT_EXTENSION = "svg"

function _sanitize_filename_component(str::AbstractString)
	sanitized = lowercase(strip(str))
	sanitized = replace(sanitized, r"[^0-9a-z]+" => "_")
	sanitized = strip(sanitized, '_')
	return isempty(sanitized) ? "lineparameters_plot" : sanitized
end

function _default_export_path(
	spec::LineParametersPlotSpec;
	extension::AbstractString = EXPORT_EXTENSION,
)
	base_title = strip(spec.title)
	base = isempty(base_title) ? string(spec.parent_kind, "_", spec.component) : base_title
	name = _sanitize_filename_component(base)
	timestamp = format(now(), EXPORT_TIMESTAMP_FORMAT)
	filename = string(name, "_", timestamp, ".", extension)
	return joinpath(pwd(), filename)
end

function _save_plot_export(spec::LineParametersPlotSpec, axis)
	# Capture current axis scales before building the export figure
	spec.xscale[] = axis.xscale[]
	spec.yscale[] = axis.yscale[]
	fig = build_export_figure(spec)
	trim!(fig.layout)
	path = _default_export_path(spec)
	Makie.save(path, fig)
	return path
end

get_description(::SeriesImpedance) = (
	impedance = "Series impedance",
	resistance = "Series resistance",
	inductance = "Series inductance",
)

get_symbol(::SeriesImpedance) = (
	impedance = "Z",
	resistance = "R",
	inductance = "L",
)

get_unit_symbol(::SeriesImpedance) = (
	impedance = "Ω",
	resistance = "Ω",
	inductance = "H",
)

get_description(::ShuntAdmittance) = (
	admittance = "Shunt admittance",
	conductance = "Shunt conductance",
	capacitance = "Shunt capacitance",
)

get_symbol(::ShuntAdmittance) = (
	admittance = "Y",
	conductance = "G",
	capacitance = "C",
)

get_unit_symbol(::ShuntAdmittance) = (
	admittance = "S",
	conductance = "S",
	capacitance = "F",
)

parent_kind(::SeriesImpedance) = :series_impedance
parent_kind(::ShuntAdmittance) = :shunt_admittance

metric_exponent(prefix::Symbol) =
	get(METRIC_PREFIX_EXPONENT, prefix) do
		Base.error("Unsupported metric prefix :$(prefix)")
	end

prefix_symbol(prefix::Symbol) =
	get(METRIC_PREFIX_SYMBOL, prefix) do
		Base.error("Unsupported metric prefix :$(prefix)")
	end

quantity_scale(prefix::Symbol) = 10.0 ^ (-metric_exponent(prefix))
length_scale(prefix::Symbol) = 10.0 ^ (metric_exponent(prefix))
frequency_scale(prefix::Symbol) = quantity_scale(prefix)

function unit_text(quantity_prefix::Symbol, base_unit::String)
	ps = prefix_symbol(quantity_prefix)
	return isempty(ps) ? base_unit : string(ps, base_unit)
end

function length_unit_text(prefix::Symbol)
	ps = prefix_symbol(prefix)
	return isempty(ps) ? "m" : string(ps, "m")
end

function composite_unit(
	quantity_prefix::Symbol,
	base_unit::String,
	per_length::Bool,
	length_prefix::Symbol,
)
	numerator = unit_text(quantity_prefix, base_unit)
	if per_length
		denominator = length_unit_text(length_prefix)
		return string(numerator, "/", denominator)
	else
		return numerator
	end
end

function frequency_axis_label(prefix::Symbol)
	unit = unit_text(prefix, "Hz")
	return string("frequency [", unit, "]")
end

function normalize_quantity_units(units)
	table = Dict(DEFAULT_QUANTITY_UNITS)
	if units isa Symbol
		for key in keys(table)
			table[key] = units
		end
	elseif units isa NamedTuple
		for (key, val) in pairs(units)
			table[key] = val
		end
	elseif units isa AbstractDict
		for (key, val) in units
			table[key] = val
		end
	elseif units === nothing
		return table
	else
		Base.error("Unsupported quantity unit specification $(typeof(units))")
	end
	return table
end

function resolve_quantity_prefix(quantity::Symbol, units::AbstractDict{Symbol, Symbol})
	return get(units, quantity, get(DEFAULT_QUANTITY_UNITS, quantity, :base))
end

function resolve_conductors(data_dims::NTuple{3, Int}, con)
	nrows, ncols, _ = data_dims
	if con === nothing
		return collect(1:nrows), collect(1:ncols)
	elseif con isa Tuple && length(con) == 2
		isel = collect_indices(con[1], nrows)
		jsel = collect_indices(con[2], ncols)
		return isel, jsel
	else
		Base.error("Conductor selector must be a tuple (i_sel, j_sel)")
	end
end

function collect_indices(sel, n)
	if sel === nothing
		return collect(1:n)
	elseif sel isa Integer
		(1 <= sel <= n) ||
			Base.error("Index $(sel) out of bounds for dimension of size $(n)")
		return [sel]
	elseif sel isa AbstractVector
		indices = collect(Int, sel)
		for idx in indices
			(1 <= idx <= n) ||
				Base.error("Index $(idx) out of bounds for dimension of size $(n)")
		end
		return indices
	elseif sel isa AbstractRange
		indices = collect(sel)
		for idx in indices
			(1 <= idx <= n) ||
				Base.error("Index $(idx) out of bounds for dimension of size $(n)")
		end
		return indices
	elseif sel isa Colon
		return collect(1:n)
	else
		Base.error("Unsupported selector $(sel)")
	end
end

function components_for(obj::SeriesImpedance, mode::Symbol, coord::Symbol)
	desc = get_description(obj)
	sym = get_symbol(obj)
	units = get_unit_symbol(obj)
	if mode == :ZY
		coord in (:cart, :polar) || Base.error("Unsupported coordinate system $(coord)")
		if coord == :cart
			return ComponentMetadata[
				ComponentMetadata(:real, :impedance, sym.impedance,
					string(desc.impedance, " – real part"),
					string("real(", sym.impedance, ")"),
					UnitSpec(units.impedance, true)),
				ComponentMetadata(:imag, :impedance, sym.impedance,
					string(desc.impedance, " – imaginary part"),
					string("imag(", sym.impedance, ")"),
					UnitSpec(units.impedance, true)),
			]
		else
			return ComponentMetadata[
				ComponentMetadata(:magnitude, :impedance, sym.impedance,
					string(desc.impedance, " – magnitude"),
					string("|", sym.impedance, "|"),
					UnitSpec(units.impedance, true)),
				ComponentMetadata(:angle, :angle, sym.impedance,
					string(desc.impedance, " – angle"),
					string("angle(", sym.impedance, ")"),
					UnitSpec("deg", false)),
			]
		end
	elseif mode == :RLCG
		return ComponentMetadata[
			ComponentMetadata(:resistance, :resistance, sym.resistance,
				desc.resistance,
				sym.resistance,
				UnitSpec(units.resistance, true)),
			ComponentMetadata(:inductance, :inductance, sym.inductance,
				desc.inductance,
				sym.inductance,
				UnitSpec(units.inductance, true)),
		]
	else
		Base.error("Unsupported mode $(mode)")
	end
end

function components_for(obj::ShuntAdmittance, mode::Symbol, coord::Symbol)
	desc = get_description(obj)
	sym = get_symbol(obj)
	units = get_unit_symbol(obj)
	if mode == :ZY
		coord in (:cart, :polar) || Base.error("Unsupported coordinate system $(coord)")
		if coord == :cart
			return ComponentMetadata[
				ComponentMetadata(:real, :admittance, sym.admittance,
					string(desc.admittance, " – real part"),
					string("real(", sym.admittance, ")"),
					UnitSpec(units.admittance, true)),
				ComponentMetadata(:imag, :admittance, sym.admittance,
					string(desc.admittance, " – imaginary part"),
					string("imag(", sym.admittance, ")"),
					UnitSpec(units.admittance, true)),
			]
		else
			return ComponentMetadata[
				ComponentMetadata(:magnitude, :admittance, sym.admittance,
					string(desc.admittance, " – magnitude"),
					string("|", sym.admittance, "|"),
					UnitSpec(units.admittance, true)),
				ComponentMetadata(:angle, :angle, sym.admittance,
					string(desc.admittance, " – angle"),
					string("angle(", sym.admittance, ")"),
					UnitSpec("deg", false)),
			]
		end
	elseif mode == :RLCG
		return ComponentMetadata[
			ComponentMetadata(:conductance, :conductance, sym.conductance,
				desc.conductance,
				sym.conductance,
				UnitSpec(units.conductance, true)),
			ComponentMetadata(:capacitance, :capacitance, sym.capacitance,
				desc.capacitance,
				sym.capacitance,
				UnitSpec(units.capacitance, true)),
		]
	else
		Base.error("Unsupported mode $(mode)")
	end
end

function component_values(component::Symbol, slice, freqs::Vector{Float64})
	data = collect(slice)
	if component === :real
		return (real.(data))
	elseif component === :imag
		return (imag.(data))
	elseif component === :magnitude
		return (abs.(data))
	elseif component === :angle
		return rad2deg.((angle.(data)))
	elseif component === :resistance || component === :conductance
		return (real.(data))
	elseif component === :inductance
		imag_part = (imag.(data))
		return reactance_to_l(imag_part, freqs)
	elseif component === :capacitance
		imag_part = (imag.(data))
		return reactance_to_c(imag_part, freqs)
	else
		Base.error("Unsupported component $(component)")
	end
end

function reactance_to_l(imag_part::Vector{Float64}, freqs::Vector{Float64})
	result = similar(freqs)
	two_pi = 2π
	for idx in eachindex(freqs)
		f = freqs[idx]
		if iszero(f)
			result[idx] = NaN
		else
			result[idx] = imag_part[idx] / (two_pi * f)
		end
	end
	return result
end

function reactance_to_c(imag_part::Vector{Float64}, freqs::Vector{Float64})
	result = similar(freqs)
	two_pi = 2π
	for idx in eachindex(freqs)
		f = freqs[idx]
		if iszero(f)
			result[idx] = NaN
		else
			result[idx] = imag_part[idx] / (two_pi * f)
		end
	end
	return result
end

function legend_label(symbol::String, i::Int, j::Int)
	return string(symbol, "(", i, ",", j, ")")
end

function _axis_label(base::AbstractString, exp::Int)
	exp == 0 && return base
	return Makie.rich(
		base,
		Makie.rich("  × 10"; font = :regular, fontsize = AXIS_LABEL_FONT_SIZE),
		Makie.rich(
			superscript(string(exp));
			font = :regular,
			fontsize = AXIS_LABEL_FONT_SIZE - 2,
			# baseline_shift = 0.6,
		),
	)
end

# Return scaled data and the exponent factored out for the axis badge.
function autoscale_axis(values::AbstractVector{<:Real}; _threshold = 1e4)
	isempty(values) && return values, 0
	maxval = 0.0
	has_value = false
	for val in values
		if isnan(val)
			continue
		end
		absval = abs(val)
		if !has_value || absval > maxval
			maxval = absval
			has_value = true
		end
	end
	!has_value && return values, 0
	exp = floor(Int, log10(maxval))
	abs(exp) < 3 && return values, 0
	scale = 10.0 ^ exp
	# return values ./ scale, exp
	return values ./ scale, exp
end

function autoscale_axis_stacked(
	curves::AbstractVector{<:AbstractVector{<:Real}};
	_threshold = 1e4,
)
	isempty(curves) && return curves, 0
	maxval = 0.0
	has_value = false
	for curve in curves
		for val in curve
			if isnan(val)
				continue
			end
			absval = abs(val)
			if !has_value || absval > maxval
				maxval = absval
				has_value = true
			end
		end
	end
	!has_value && return curves, 0
	exp = floor(Int, log10(maxval))
	abs(exp) < 3 && return curves, 0
	scale = 10.0 ^ exp
	scaled_curves = [curve ./ scale for curve in curves]
	return scaled_curves, exp
end

function lineparameter_plot_specs(
	obj::SeriesImpedance,
	freqs::AbstractVector;
	mode::Symbol = :ZY,
	coord::Symbol = :cart,
	freq_unit::Symbol = :base,
	length_unit::Symbol = :base,
	quantity_units = nothing,
	con = nothing,
	fig_size::Union{Nothing, Tuple{Int, Int}} = LP_FIG_SIZE,
)
	freq_vec = collect(float.(freqs))
	nfreq = length(freq_vec)
	if nfreq <= 1
		@warn "Frequency vector has $(nfreq) sample(s); nothing to plot."
		return LineParametersPlotSpec[]
	end
	size(obj.values, 3) == nfreq ||
		Base.error("Frequency vector length does not match impedance samples")
	comps = components_for(obj, mode, coord)
	units = normalize_quantity_units(quantity_units)
	freq_scale = frequency_scale(freq_unit)
	raw_freq_axis = freq_vec .* freq_scale
	freq_axis, freq_exp = autoscale_axis(raw_freq_axis)
	xlabel_base = frequency_axis_label(freq_unit)
	(isel, jsel) = resolve_conductors(size(obj.values), con)
	specs = LineParametersPlotSpec[]
	for meta in comps
		q_prefix = resolve_quantity_prefix(meta.quantity, units)
		y_scale = quantity_scale(q_prefix)
		l_scale = meta.unit.per_length ? length_scale(length_unit) : 1.0
		ylabel_unit =
			composite_unit(q_prefix, meta.unit.symbol, meta.unit.per_length, length_unit)
		ylabel_base = string(meta.axis_label, " [", ylabel_unit, "]")

		# collect raw curves and labels
		raw_curves = Vector{Vector{Float64}}()
		labels = String[]
		for i in isel, j in jsel
			slice = @view obj.values[i, j, :]
			raw_vals = component_values(meta.component, slice, freq_vec)
			push!(raw_curves, (raw_vals .* y_scale .* l_scale))
			push!(labels, legend_label(meta.symbol, i, j))
		end
		curves, y_exp = autoscale_axis_stacked(raw_curves)
		push!(
			specs,
			LineParametersPlotSpec(
				parent_kind(obj),
				meta.component,
				meta.symbol,
				meta.title,
				xlabel_base,
				ylabel_base,
				freq_axis,
				raw_freq_axis,
				curves,
				raw_curves,
				labels,
				freq_exp,
				y_exp,
				fig_size,
				Ref{Function}(Makie.identity),
				Ref{Function}(Makie.identity),
			),
		)
	end
	return specs
end

function lineparameter_plot_specs(
	obj::ShuntAdmittance,
	freqs::AbstractVector;
	mode::Symbol = :ZY,
	coord::Symbol = :cart,
	freq_unit::Symbol = :base,
	length_unit::Symbol = :base,
	quantity_units = nothing,
	con = nothing,
	fig_size::Union{Nothing, Tuple{Int, Int}} = LP_FIG_SIZE,
)
	freq_vec = collect(float.(freqs))
	nfreq = length(freq_vec)
	if nfreq <= 1
		@warn "Frequency vector has $(nfreq) sample(s); nothing to plot."
		return LineParametersPlotSpec[]
	end
	size(obj.values, 3) == nfreq ||
		Base.error("Frequency vector length does not match admittance samples")
	comps = components_for(obj, mode, coord)
	units = normalize_quantity_units(quantity_units)
	freq_scale = frequency_scale(freq_unit)
	raw_freq_axis = freq_vec .* freq_scale
	freq_axis, freq_exp = autoscale_axis(raw_freq_axis)
	xlabel_base = frequency_axis_label(freq_unit)
	(isel, jsel) = resolve_conductors(size(obj.values), con)
	specs = LineParametersPlotSpec[]
	for meta in comps
		q_prefix = resolve_quantity_prefix(meta.quantity, units)
		y_scale = quantity_scale(q_prefix)
		l_scale = meta.unit.per_length ? length_scale(length_unit) : 1.0
		ylabel_unit =
			composite_unit(q_prefix, meta.unit.symbol, meta.unit.per_length, length_unit)
		ylabel_base = string(meta.axis_label, " [", ylabel_unit, "]")

		raw_curves = Vector{Vector{Float64}}()
		labels = String[]
		for i in isel, j in jsel
			slice = @view obj.values[i, j, :]
			raw_vals = component_values(meta.component, slice, freq_vec)
			push!(raw_curves, (raw_vals .* y_scale .* l_scale))
			push!(labels, legend_label(meta.symbol, i, j))
		end

		curves, y_exp = autoscale_axis_stacked(raw_curves)
		push!(
			specs,
			LineParametersPlotSpec(
				parent_kind(obj),
				meta.component,
				meta.symbol,
				meta.title,
				xlabel_base,
				ylabel_base,
				freq_axis,
				raw_freq_axis,
				curves,
				raw_curves,
				labels,
				freq_exp,
				y_exp,
				fig_size,
				Ref{Function}(Makie.identity),
				Ref{Function}(Makie.identity),
			),
		)
	end
	return specs
end

function lineparameter_plot_specs(
	lp::LineParameters;
	mode::Symbol = :ZY,
	coord::Symbol = :cart,
	freq_unit::Symbol = :base,
	length_unit::Symbol = :base,
	quantity_units = nothing,
	con = nothing,
	fig_size::Union{Nothing, Tuple{Int, Int}} = LP_FIG_SIZE,
)
	specs = LineParametersPlotSpec[]
	append!(
		specs,
		lineparameter_plot_specs(lp.Z, lp.f;
			mode = mode,
			coord = coord,
			freq_unit = freq_unit,
			length_unit = length_unit,
			quantity_units = quantity_units,
			con = con,
			fig_size = fig_size,
		),
	)
	append!(
		specs,
		lineparameter_plot_specs(lp.Y, lp.f;
			mode = mode,
			coord = coord,
			freq_unit = freq_unit,
			length_unit = length_unit,
			quantity_units = quantity_units,
			con = con,
			fig_size = fig_size,
		),
	)
	return specs
end

function render_plot_specs(
	specs::Vector{LineParametersPlotSpec};
	backend = nothing,
	display_plot::Bool = true,
)
	assemblies = Dict{Tuple{Symbol, Symbol}, PlotAssembly}()
	for spec in specs
		assembly = _render_spec(spec; backend = backend, display_plot = display_plot)
		assemblies[(spec.parent_kind, spec.component)] = assembly
	end
	return assemblies
end

function plot(
	obj::SeriesImpedance,
	freqs::AbstractVector;
	backend = nothing,
	display_plot::Bool = true,
	kwargs...,
)
	specs = lineparameter_plot_specs(obj, freqs; kwargs...)
	return render_plot_specs(specs; backend = backend, display_plot = display_plot)
end

function plot(
	obj::ShuntAdmittance,
	freqs::AbstractVector;
	backend = nothing,
	display_plot::Bool = true,
	kwargs...,
)
	specs = lineparameter_plot_specs(obj, freqs; kwargs...)
	return render_plot_specs(specs; backend = backend, display_plot = display_plot)
end

function plot(
	lp::LineParameters;
	backend = nothing,
	display_plot::Bool = true,
	kwargs...,
)
	specs = lineparameter_plot_specs(lp; kwargs...)
	return render_plot_specs(specs; backend = backend, display_plot = display_plot)
end

function build_export_figure(spec::LineParametersPlotSpec)
	backend_ctx = _make_window(
		BackendHandler,
		:cairo;
		icons = _ICON_FN,
		icons_font = ICON_TTF,
		interactive_override = false,
		use_latex_fonts = true,
	)
	pipeline_kwargs =
		spec.fig_size === nothing ?
		(; initial_status = "") :
		(; fig_size = spec.fig_size, initial_status = "")
	assembly = with_plot_theme(backend_ctx; mode = :export) do
		_run_plot_pipeline(
			backend_ctx,
			(fig_ctx, ctx, axis) -> _build_plot!(fig_ctx, ctx, axis, spec);
			pipeline_kwargs...,
		)
	end
	ensure_export_background!(assembly.figure)
	return assembly.figure
end

function build_export_figure(
	obj,
	key::Tuple{Symbol, Symbol};
	kwargs...,
)
	specs =
		obj isa LineParametersPlotSpec ? [obj] : lineparameter_plot_specs(obj; kwargs...)
	idx = findfirst(s -> (s.parent_kind, s.component) == key, specs)
	idx === nothing && Base.error("No plot specification found for key $(key)")
	return build_export_figure(specs[idx])
end

function _render_spec(
	spec::LineParametersPlotSpec;
	backend = nothing,
	display_plot::Bool = true,
)
	n = next_fignum()
	backend_ctx = _make_window(
		BackendHandler,
		backend;
		title = "Fig. $(n) – $(spec.title)",
		icons = _ICON_FN,
		icons_font = ICON_TTF,
	)
	pipeline_kwargs =
		spec.fig_size === nothing ?
		(; initial_status = " ") :
		(; fig_size = spec.fig_size, initial_status = " ")
	assembly = with_plot_theme(backend_ctx) do
		_run_plot_pipeline(
			backend_ctx,
			(fig_ctx, ctx, axis) -> _build_plot!(fig_ctx, ctx, axis, spec);
			pipeline_kwargs...,
		)
	end
	if display_plot
		_display!(backend_ctx, assembly.figure; title = spec.title)
	end
	return assembly
end

function _build_plot!(fig_ctx, ctx, axis, spec::LineParametersPlotSpec)
	# axis.title = spec.title
	# axis.xlabel = spec.x_exp == 0 ? spec.xlabel : _axis_label(spec.xlabel, spec.x_exp)
	# axis.ylabel = spec.y_exp == 0 ? spec.ylabel : _axis_label(spec.ylabel, spec.y_exp)

	axis.title = spec.title

	if spec.xscale[] == Makie.log10
		axis.xlabel = spec.xlabel
		x_data = spec.raw_freqs
	else
		axis.xlabel = spec.x_exp == 0 ? spec.xlabel : _axis_label(spec.xlabel, spec.x_exp)
		x_data = spec.freqs
	end

	if spec.yscale[] == Makie.log10
		axis.ylabel = spec.ylabel
		y_data = spec.raw_curves
	else
		axis.ylabel = spec.y_exp == 0 ? spec.ylabel : _axis_label(spec.ylabel, spec.y_exp)
		y_data = spec.curves
	end

	palette = Makie.wong_colors()
	ncolors = length(palette)
	# Store the created lines objects to update them dynamically
	lines_plots = []
	for (idx, curve) in enumerate(y_data)
		color = palette[mod1(idx, ncolors)]
		label = spec.labels[idx]
		l = lines!(axis, x_data, curve; color = color, label = label, linewidth = 2)
		push!(lines_plots, l)
	end

	# Apply scales from spec, which are relevant for export mode
	axis.xscale[] = spec.xscale[]
	axis.yscale[] = spec.yscale[]

	Makie.autolimits!(axis)

	buttons = [
		ControlButtonSpec(
			(_ctx, _btn) -> begin
				Makie.reset_limits!(axis)
				return nothing
			end;
			icon = MI_REFRESH,
			on_success = ControlReaction(
				status_string = "Axis limits reset",
			),
		),
		ControlButtonSpec(
			(_ctx, _btn) -> _save_plot_export(spec, axis);
			icon = MI_SAVE,
			on_success = ControlReaction(
				status_string = path -> string("Saved SVG to ", basename(path)),
			),
		),
	]

	# --- Define control toggles ---
	toggles = [
		ControlToggleSpec(
			# Action when toggled ON
			(_ctx, _toggle) -> begin
				try
					# Set scale and update data to raw values
					axis.xscale = Makie.log10
					for l in lines_plots
						l[1] = spec.raw_freqs
					end
					# Remove the exponent badge from the label
					axis.xlabel = spec.xlabel
					Makie.autolimits!(axis)
				catch
					# If Makie fails to set the log scale, throw a user-friendly error.
					# This will be caught by the wiring and trigger the on_failure reaction.
					Base.error(
						"Cannot apply log scale: axis contains non-positive values.",
					)
				end
			end,
			# Action when toggled OFF
			(_ctx, _toggle) -> begin
				# Set scale and update data to scaled values
				axis.xscale = Makie.identity
				for l in lines_plots
					l[1] = spec.freqs
				end
				# Restore the exponent badge on the label
				axis.xlabel =
					spec.x_exp == 0 ? spec.xlabel : _axis_label(spec.xlabel, spec.x_exp)
				Makie.autolimits!(axis)
			end;
			label = "log x-axis",
			start_active = false,
			on_success_on = ControlReaction(status_string = "x-axis scale set to log"),
			on_success_off = ControlReaction(status_string = "x-axis scale set to linear"),
			on_failure = ControlReaction(
				# The status_string function will receive the error message we threw.
				status_string = err_msg -> err_msg,
				undo_on_fail = true,
			),
		),
		ControlToggleSpec(
			# Action when toggled ON
			(_ctx, _toggle) -> begin
				try
					# Set scale and update data to raw values
					axis.yscale = Makie.log10
					for (idx, l) in enumerate(lines_plots)
						l[2] = spec.raw_curves[idx]
					end
					# Remove the exponent badge from the label
					axis.ylabel = spec.ylabel
					Makie.autolimits!(axis)
				catch
					# If Makie fails to set the log scale, throw a user-friendly error.
					# This will be caught by the wiring and trigger the on_failure reaction.
					Base.error(
						"Cannot apply log scale: axis contains non-positive values.",
					)
				end
			end,
			# Action when toggled OFF
			(_ctx, _toggle) -> begin
				# Set scale and update data to scaled values
				axis.yscale = Makie.identity
				for (idx, l) in enumerate(lines_plots)
					l[2] = spec.curves[idx]
				end
				# Restore the exponent badge on the label
				axis.ylabel =
					spec.y_exp == 0 ? spec.ylabel : _axis_label(spec.ylabel, spec.y_exp)
				Makie.autolimits!(axis)
			end;
			label = "log y-axis",
			start_active = false,
			on_success_on = ControlReaction(status_string = "y-axis scale set to log"),
			on_success_off = ControlReaction(status_string = "y-axis scale set to linear"),
			on_failure = ControlReaction(
				# The status_string function will receive the error message we threw.
				status_string = err_msg -> err_msg,
				undo_on_fail = true,
			),
		),
	]

	legend_builder = parent -> Makie.Legend(parent, axis; orientation = :vertical)

	return PlotBuildArtifacts(
		axis = axis,
		legends = legend_builder,
		colorbars = Any[],
		control_buttons = buttons,
		control_toggles = toggles,
		status_message = nothing,
	)
end

function _display!(backend_ctx, fig::Makie.Figure; title::AbstractString = "")
	if backend_ctx.interactive && backend_ctx.window !== nothing
		display(backend_ctx.window, fig)
		if !isempty(title) && hasproperty(backend_ctx.window, :title)
			backend_ctx.window.title[] = title
		end
	else
		BackendHandler.renderfig(fig)
	end
	return nothing
end
