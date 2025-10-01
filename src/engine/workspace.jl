"""
$(TYPEDEF)

A container for the flattened, type-stable data arrays derived from a
[`LineParametersProblem`](@ref). This struct serves as the primary data source
for all subsequent computational steps.

# Fields
$(TYPEDFIELDS)
"""
@kwdef struct EMTWorkspace{T <: REALSCALAR}
	"Vector of frequency values [Hz]."
	freq::Vector{T}
	"Vector of complex frequency values cast as `σ + jω` [rad/s]."
		jω::Vector{Complex{T}}
	"Vector of horizontal positions [m]."
	horz::Vector{T}
	"Vector of horizontal separations [m]."
	horz_sep::Matrix{T}
	"Vector of vertical positions [m]."
	vert::Vector{T}
	"Vector of internal conductor radii [m]."
	r_in::Vector{T}
	"Vector of external conductor radii [m]."
	r_ext::Vector{T}
	"Vector of internal insulator radii [m]."
	r_ins_in::Vector{T}
	"Vector of external insulator radii [m]."
	r_ins_ext::Vector{T}
	"Vector of conductor resistivities [Ω·m]."
	rho_cond::Vector{T}
	"Vector of conductor temperature coefficients [1/°C]."
	alpha_cond::Vector{T}
	"Vector of conductor relative permeabilities."
	mu_cond::Vector{T}
	"Vector of conductor relative permittivities."
	eps_cond::Vector{T}
	"Vector of insulator resistivities [Ω·m]."
	rho_ins::Vector{T}
	"Vector of insulator relative permeabilities."
	mu_ins::Vector{T}
	"Vector of insulator relative permittivities."
	eps_ins::Vector{T}
	"Vector of insulator loss tangents."
	tan_ins::Vector{T}
	"Vector of phase mapping indices."
	phase_map::Vector{Int}
	"Vector of cable mapping indices."
	cable_map::Vector{Int}
	"Effective earth resistivity (layers × freq)."
	rho_g::Matrix{T}
	"Effective earth permittivity (layers × freq)."
	eps_g::Matrix{T}
	"Effective earth permeability (layers × freq)."
	mu_g::Matrix{T}
	"Operating temperature [°C]."
	temp::T
	"Number of frequency samples."
	n_frequencies::Int
	"Number of phases in the system."
	n_phases::Int
	"Number of cables in the system."
	n_cables::Int
	"Full component-based Z matrix (before bundling/reduction)."
	Z::Array{Complex{T}, 3}
	"Full component-based P matrix (before bundling/reduction)."
	P::Array{Complex{T}, 3}
	"Full internal impedance matrix (before bundling/reduction)."
	Zin::Array{Complex{T}, 3}
	"Full internal potential coefficient matrix (before bundling/reduction)."
	Pin::Array{Complex{T}, 3}
	"Earth impedance matrix (n_cables x n_cables)."
	Zg::Array{Complex{T}, 3}
	"Earth potential coefficient matrix (n_cables x n_cables)."
	Pg::Array{Complex{T}, 3}
end



"""
$(TYPEDSIGNATURES)

Initializes and populates the [`EMTWorkspace`](@ref) by normalizing a
[`LineParametersProblem`](@ref) into flat, type-stable arrays.
"""
function init_workspace(
	problem::LineParametersProblem{T},
	formulation::EMTFormulation,
) where {T}

	opts = formulation.options

	system = problem.system
	n_frequencies = length(problem.frequencies)
	n_phases = sum(length(cable.design_data.components) for cable in system.cables)
	n_cables = system.num_cables

	# Pre-allocate 1D arrays
	freq = Vector{T}(undef, n_frequencies)
	jω = Vector{Complex{T}}(undef, n_frequencies)
	horz = Vector{T}(undef, n_phases)
	horz_sep = Matrix{T}(undef, n_phases, n_phases)
	vert = Vector{T}(undef, n_phases)
	r_in = Vector{T}(undef, n_phases)
	r_ext = Vector{T}(undef, n_phases)
	r_ins_in = Vector{T}(undef, n_phases)
	r_ins_ext = Vector{T}(undef, n_phases)
	rho_cond = Vector{T}(undef, n_phases)
	alpha_cond = Vector{T}(undef, n_phases)
	mu_cond = Vector{T}(undef, n_phases)
	eps_cond = Vector{T}(undef, n_phases)
	rho_ins = Vector{T}(undef, n_phases)
	mu_ins = Vector{T}(undef, n_phases)
	eps_ins = Vector{T}(undef, n_phases)
	tan_ins = Vector{T}(undef, n_phases)   # Loss tangent for insulator
	phase_map = Vector{Int}(undef, n_phases)
	cable_map = Vector{Int}(undef, n_phases)
	Z =
		opts.store_primitive_matrices ?
		zeros(Complex{T}, n_phases, n_phases, n_frequencies) : nothing
	P =
		opts.store_primitive_matrices ?
		zeros(Complex{T}, n_phases, n_phases, n_frequencies) : nothing
	Zin =
		opts.store_primitive_matrices ?
		zeros(Complex{T}, n_phases, n_phases, n_frequencies) : nothing
	Pin =
		opts.store_primitive_matrices ?
		zeros(Complex{T}, n_phases, n_phases, n_frequencies) : nothing
	Zg =
		opts.store_primitive_matrices ?
		zeros(Complex{T}, n_cables, n_cables, n_frequencies) : nothing
	Pg =
		opts.store_primitive_matrices ?
		zeros(Complex{T}, n_cables, n_cables, n_frequencies) : nothing

	# Fill arrays, ensuring type promotion
	freq .= problem.frequencies
	jω .= 1im * 2π * freq

	idx = 0
	for (cable_idx, cable) in enumerate(system.cables)
		for (comp_idx, component) in enumerate(cable.design_data.components)
			idx += 1
			# Geometric properties
			horz[idx] = T(cable.horz)
			vert[idx] = T(cable.vert)
			r_in[idx] = T(component.conductor_group.radius_in)
			r_ext[idx] = T(component.conductor_group.radius_ext)
			r_ins_in[idx] = T(component.insulator_group.radius_in)
			r_ins_ext[idx] = T(component.insulator_group.radius_ext)

			# Material properties
			rho_cond[idx] = T(component.conductor_props.rho)
			alpha_cond[idx] = T(component.conductor_props.alpha)
			mu_cond[idx] = T(component.conductor_props.mu_r)
			eps_cond[idx] = T(component.conductor_props.eps_r)
			rho_ins[idx] = T(component.insulator_props.rho)
			mu_ins[idx] = T(component.insulator_props.mu_r)
			eps_ins[idx] = T(component.insulator_props.eps_r)

			# Calculate loss factor from resistivity
			ω = 2 * π * f₀  # Using default frequency
			C_eq = T(component.insulator_group.shunt_capacitance)
			G_eq = T(component.insulator_group.shunt_conductance)
			tan_ins[idx] = G_eq / (ω * C_eq)

			# Mapping
			phase_map[idx] = cable.conn[comp_idx]
			cable_map[idx] = cable_idx
		end
	end

	# Precompute Euclidean distances, use max radius for self-distances
	_calc_horz_sep!(horz_sep, horz, r_ext, r_ins_ext, cable_map)

	(rho_g, eps_g, mu_g) = _get_earth_data(
		formulation.equivalent_earth,
		problem.earth_props,
		freq,
		T,
	)

	temp = T(problem.temperature)

	# Construct and return the EMTWorkspace struct
	return EMTWorkspace{T}(
		freq = freq, jω = jω,
		horz = horz, horz_sep = horz_sep, vert = vert,
		r_in = r_in, r_ext = r_ext,
		r_ins_in = r_ins_in, r_ins_ext = r_ins_ext,
		rho_cond = rho_cond, alpha_cond = alpha_cond, mu_cond = mu_cond,
		eps_cond = eps_cond, rho_ins = rho_ins, mu_ins = mu_ins, eps_ins = eps_ins,
		tan_ins = tan_ins, phase_map = phase_map, cable_map = cable_map, rho_g = rho_g,
		eps_g = eps_g, mu_g = mu_g,
		temp = temp, n_frequencies = n_frequencies, n_phases = n_phases,
		n_cables = n_cables, Z = Z, P = P, Zin = Zin, Pin = Pin, Zg = Zg,
		Pg = Pg,
	)
end

"""
$(TYPEDEF)

A container for the simplified, type-stable data arrays derived from a
[`LineParametersProblem`](@ref) for use with the DSS formulation. This struct
contains only the fields necessary for the impedance and admittance calculations.

# Fields
$(TYPEDFIELDS)
"""
@kwdef struct DSSWorkspace{T<:REALSCALAR}
    "Vector of frequency values [Hz]."
    freq::Vector{T}
    "Vector of complex frequency values cast as `σ + jω` [rad/s]."
    jω::Vector{Complex{T}}
    "Vector of horizontal positions [m]."
    horz::Vector{T}
    "Vector of vertical positions [m]."
    vert::Vector{T}
    "Vector of external conductor radii [m]."
    r_ext::Vector{T}
    "Vector of DC resistance values [Ω/m]."
    rdc::Vector{T}
    "Vector of geometric mean radius values [m]."
    gmr::Vector{T}
    "Conductor group for each phase"
    conductor_groups::Vector{AbstractCablePart}
    "Effective earth resistivity (layers × freq)."
    rho_g::Matrix{T}
    "Operating temperature [°C]."
    temp::T
    "Number of frequency samples."
    n_frequencies::Int
    "Number of phases in the system."
    n_phases::Int
end

"""
$(TYPEDSIGNATURES)

Initializes and populates the [`DSSWorkspace`](@ref) by normalizing a
[`LineParametersProblem`](@ref) into flat, type-stable arrays.
"""
function init_workspace(
    problem::LineParametersProblem{T},
    formulation::DSSFormulation,
) where {T}

    opts = formulation.options

    system = problem.system
    n_frequencies = length(problem.frequencies)
    n_phases = sum(length(cable.design_data.components) for cable in system.cables)

    # Pre-allocate 1D arrays
    freq = Vector{T}(undef, n_frequencies)
    jω = Vector{Complex{T}}(undef, n_frequencies)
    horz = Vector{T}(undef, n_phases)
    vert = Vector{T}(undef, n_phases)
    r_ext = Vector{T}(undef, n_phases)
    rdc = Vector{T}(undef, n_phases)
    gmr = Vector{T}(undef, n_phases)
    conductor_groups = Vector{AbstractCablePart}(undef, n_phases)

    # Fill arrays, ensuring type promotion
    freq .= problem.frequencies
    jω .= 1im * 2π * freq

    idx = 0
    for (cable_idx, cable) in enumerate(system.cables)
        for (comp_idx, component) in enumerate(cable.design_data.components)
            idx += 1
            layers = component.conductor_group.layers
            @assert length(layers) == 1 "For a multi-layer conductor, DSS is not suitable analytical method."

            # Geometric properties
            if layers[1] isa Sector{T}
                horz[idx] = T(cable.horz + layers[1].centroid[1])
                vert[idx] = T(cable.vert + layers[1].centroid[2])
				@debug "(cable_idx :$cable_idx -> comp_idx: $comp_idx) Sector conductor position: horz=$(horz[idx]), vert=$(vert[idx])"
			elseif layers[1] isa WireArray{T}
				nW = layers[1].num_wires
				if nW == 1  # it is used as a solid conductor
					lay_r = 0.0
					horz[idx] = T(cable.horz)
					vert[idx] = T(cable.vert)
				else # it is a wire array (stranded conductor) #TODO: complete handling of this case
					lay_r = to_nominal(layers[1].radius_in)
					coords = calc_wirearray_coords(nW, layers[1].radius_wire, lay_r, C= (cable.horz, cable.vert))
					@debug "WireArray coordinates: $coords not used for now."
					horz[idx] = T(cable.horz)
					vert[idx] = T(cable.vert)
				end
				@debug "(cable_idx :$cable_idx -> comp_idx: $comp_idx) ConductorGroup position: horz=$(horz[idx]), vert=$(vert[idx])"
			else
                horz[idx] = T(cable.horz)
                vert[idx] = T(cable.vert)
            end

            r_ext[idx] = T(component.conductor_group.radius_ext)
            gmr[idx] = T(component.conductor_group.gmr)
            rdc[idx] = T(component.conductor_group.resistance)
            conductor_groups[idx] = component.conductor_group
        end
    end

    (rho_g, _, _) = _get_earth_data(
        nothing,
        problem.earth_props,
        freq,
        T,
    )

    temp = T(problem.temperature)

    # Construct and return the DSSWorkspace struct
    return DSSWorkspace{T}(
        freq = freq, jω = jω,
        horz = horz, vert = vert,
        r_ext = r_ext, rdc = rdc, gmr = gmr,
        conductor_groups = conductor_groups,
        rho_g = rho_g,
        temp = temp, n_frequencies = n_frequencies, n_phases = n_phases,
    )
end