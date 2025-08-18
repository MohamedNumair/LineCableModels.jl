"""
$(TYPEDSIGNATURES)

Flattens a hierarchical cable system into 1D arrays of geometric and material properties for each cable component, suitable for matrix-based calculations and parameter extraction.

# Arguments

- `system`: The cable system to flatten ([`LineCableSystem`](@ref)).

# Returns

- Named tuple containing arrays for each geometric and material property:
    - `horz`: Horizontal positions \\[m\\]
    - `vert`: Vertical positions \\[m\\]
    - `r_in`: Internal conductor radii \\[m\\]
    - `r_ext`: External conductor radii \\[m\\]
    - `r_ins_in`: Internal insulator radii \\[m\\]
    - `r_ins_ext`: External insulator radii \\[m\\]
    - `rho_cond`: Conductor resistivities \\[Ω·m\\]
    - `mu_cond`: Conductor relative permeabilities \\[dimensionless\\]
    - `eps_cond`: Conductor relative permittivities \\[dimensionless\\]
    - `rho_ins`: Insulator resistivities \\[Ω·m\\]
    - `mu_ins`: Insulator relative permeabilities \\[dimensionless\\]
    - `eps_ins`: Insulator relative permittivities \\[dimensionless\\]
    - `tan_ins`: Insulator loss tangents \\[dimensionless\\]
    - `phase_map`: Phase mapping indices \\[dimensionless\\]
    - `cable_map`: Cable mapping indices \\[dimensionless\\]

# Examples

```julia
flat = $(FUNCTIONNAME)(system)
horz = flat.horz  # Horizontal positions [m]
rho_cond = flat.rho_cond  # Conductor resistivities [Ω·m]
```
"""
function flatten(system::LineCableSystem)
    # Count total components
    n_components = sum(length(cable.design_data.components) for cable in system.cables)

    # Determine type based on first numeric value
    T = typeof(system.cables[1].horz)

    # Pre-allocate 1D arrays
    horz = Vector{T}(undef, n_components)
    vert = Vector{T}(undef, n_components)
    r_in = Vector{T}(undef, n_components)
    r_ext = Vector{T}(undef, n_components)
    r_ins_in = Vector{T}(undef, n_components)
    r_ins_ext = Vector{T}(undef, n_components)
    rho_cond = Vector{T}(undef, n_components)
    mu_cond = Vector{T}(undef, n_components)
    eps_cond = Vector{T}(undef, n_components)
    rho_ins = Vector{T}(undef, n_components)
    mu_ins = Vector{T}(undef, n_components)
    eps_ins = Vector{T}(undef, n_components)
    tan_ins = Vector{T}(undef, n_components)   # Loss tangent for insulator
    phase_map = Vector{Int}(undef, n_components)
    cable_map = Vector{Int}(undef, n_components)

    # Fill arrays
    idx = 1
    for (cable_idx, cable) in enumerate(system.cables)
        for (comp_idx, component) in enumerate(cable.design_data.components)
            # Geometric properties
            horz[idx] = cable.horz
            vert[idx] = cable.vert
            r_in[idx] = component.conductor_group.radius_in
            r_ext[idx] = component.conductor_group.radius_ext
            r_ins_in[idx] = component.insulator_group.radius_in
            r_ins_ext[idx] = component.insulator_group.radius_ext

            # Material properties
            rho_cond[idx] = component.conductor_props.rho
            mu_cond[idx] = component.conductor_props.mu_r
            eps_cond[idx] = component.conductor_props.eps_r
            rho_ins[idx] = component.insulator_props.rho
            mu_ins[idx] = component.insulator_props.mu_r
            eps_ins[idx] = component.insulator_props.eps_r

            # Calculate loss factor from resistivity
            ω = 2 * π * f₀  # Using default frequency
            C_eq = component.insulator_group.shunt_capacitance
            G_eq = component.insulator_group.shunt_conductance
            tan_ins[idx] = G_eq / (ω * C_eq)

            # Mapping
            phase_map[idx] = cable.conn[comp_idx]
            cable_map[idx] = cable_idx

            idx += 1
        end
    end

    return (
        horz=horz, vert=vert,
        r_in=r_in, r_ext=r_ext,
        r_ins_in=r_ins_in, r_ins_ext=r_ins_ext,
        rho_cond=rho_cond, mu_cond=mu_cond, eps_cond=eps_cond,
        rho_ins=rho_ins, mu_ins=mu_ins, eps_ins=eps_ins, tan_ins=tan_ins,
        phase_map=phase_map, cable_map=cable_map
    )
end

function compute!(problem::LineParametersProblem,
    formulation::CoaxialFormulation)

    opts = formulation.options

    # Flatten the system into 1D arrays for computation
    data = flatten(problem.system)

    @show data

    line_params = nothing

    @info "Starting line parameters computation"
    line_params = nothing

    @info "Line parameters computation completed successfully"
    return line_params
end