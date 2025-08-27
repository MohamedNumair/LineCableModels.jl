
"""
$(TYPEDEF)

Represents a [`CableComponent`](@ref), i.e. a group of [`AbstractCablePart`](@ref) objects, with the equivalent geometric and material properties:

$(TYPEDFIELDS)

!!! info "Definition & application"
	Cable components operate as containers for multiple cable parts, allowing the calculation of effective electromagnetic (EM) properties (``\\sigma, \\varepsilon, \\mu``). This is performed by transforming the physical objects within the [`CableComponent`](@ref) into one equivalent coaxial homogeneous structure comprised of one conductor and one insulator, each one represented by effective [`Material`](@ref) types stored in `conductor_props` and `insulator_props` fields.

	The effective properties approach is widely adopted in EMT-type simulations, and involves locking the internal and external radii of the conductor and insulator parts, respectively, and calculating the equivalent EM properties in order to match the previously determined values of R, L, C and G [916943](@cite) [1458878](@cite).

	In applications, the [`CableComponent`](@ref) type is mapped to the main cable structures described in manufacturer datasheets, e.g., core, sheath, armor and jacket.
"""
mutable struct CableComponent
    "Cable component identification (e.g. core/sheath/armor)."
    id::String
    "The conductor group containing all conductive parts."
    conductor_group::ConductorGroup
    "Effective properties of the equivalent coaxial conductor."
    conductor_props::Material
    "The insulator group containing all insulating parts."
    insulator_group::InsulatorGroup
    "Effective properties of the equivalent coaxial insulator."
    insulator_props::Material

    @doc """
    $(TYPEDSIGNATURES)

    Initializes a [`CableComponent`](@ref) object based on its constituent conductor and insulator groups. The constructor performs the following sequence of steps:

    1.  Validate that the conductor and insulator groups have matching radii at their interface.
    2.  Obtain the lumped-parameter values (R, L, C, G) from the conductor and insulator groups, which are computed within their respective constructors.
    3.  Calculate the correction factors and equivalent electromagnetic properties of the conductor and insulator groups:


    | Quantity | Symbol | Function |
    |----------|--------|----------|
    | Resistivity (conductor) | ``\\rho_{con}`` | [`calc_equivalent_rho`](@ref) |
    | Permeability (conductor) | ``\\mu_{con}`` | [`calc_equivalent_mu`](@ref) |
    | Resistivity (insulator) | ``\\rho_{ins}`` | [`calc_sigma_lossfact`](@ref) |
    | Permittivity (insulation) | ``\\varepsilon_{ins}`` | [`calc_equivalent_eps`](@ref) |
    | Permeability (insulation) | ``\\mu_{ins}`` | [`calc_solenoid_correction`](@ref) |

    # Arguments

    - `id`: Cable component identification (e.g. core/sheath/armor).
    - `conductor_group`: The conductor group containing all conductive parts.
    - `insulator_group`: The insulator group containing all insulating parts.

    # Returns

    - A [`CableComponent`](@ref) instance with calculated equivalent properties.

    # Examples

    ```julia
    conductor_group = ConductorGroup(...)
    insulator_group = InsulatorGroup(...)
    cable = $(FUNCTIONNAME)("component_id", conductor_group, insulator_group)  # Create cable component with base parameters @ 50 Hz
    ```

    # See also

    - [`calc_equivalent_rho`](@ref)
    - [`calc_equivalent_mu`](@ref)
    - [`calc_equivalent_eps`](@ref)
    - [`calc_sigma_lossfact`](@ref)
    - [`calc_solenoid_correction`](@ref)
    """
    function CableComponent(
        id::String,
        conductor_group::ConductorGroup,
        insulator_group::InsulatorGroup)
        # Validate the geometry
        if conductor_group.radius_ext != insulator_group.radius_in
            error("Conductor outer radius must match insulator inner radius.")
        end

        # Use pre-calculated values from the groups
        radius_in_con = conductor_group.radius_in
        radius_ext_con = conductor_group.radius_ext
        radius_ext_ins = insulator_group.radius_ext

        # Equivalent conductor properties
        rho_con =
            calc_equivalent_rho(conductor_group.resistance, radius_ext_con, radius_in_con)
        mu_con = calc_equivalent_mu(conductor_group.gmr, radius_ext_con, radius_in_con)
        alpha_con = conductor_group.alpha
        conductor_props =
            Material(rho_con, 0.0, mu_con, conductor_group.layers[1].temperature, alpha_con)

        # Insulator properties
        C_eq = insulator_group.shunt_capacitance
        G_eq = insulator_group.shunt_conductance
        eps_ins = calc_equivalent_eps(C_eq, radius_ext_ins, radius_ext_con)
        rho_ins = 1 / calc_sigma_lossfact(G_eq, radius_ext_con, radius_ext_ins)
        correction_mu_ins = calc_solenoid_correction(
            conductor_group.num_turns,
            radius_ext_con,
            radius_ext_ins,
        )
        mu_ins = correction_mu_ins
        insulator_props =
            Material(rho_ins, eps_ins, mu_ins, insulator_group.layers[1].temperature, 0.0)

        # Initialize object
        return new(
            id,
            conductor_group,
            conductor_props,
            insulator_group,
            insulator_props,
        )
    end
end

include("cablecomponent/base.jl")

