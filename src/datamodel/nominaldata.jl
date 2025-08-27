"""
$(TYPEDEF)

Stores the nominal electrical and geometric parameters for a cable design, with attributes:

$(TYPEDFIELDS)
"""
struct NominalData
    "Cable designation as per DIN VDE 0271/0276."
    designation_code::Union{Nothing,String}
    "Rated phase-to-earth voltage \\[kV\\]."
    U0::Union{Nothing,Number}
    "Rated phase-to-phase voltage \\[kV\\]."
    "Cross-sectional area of the conductor \\[mm²\\]."
    U::Union{Nothing,Number}
    conductor_cross_section::Union{Nothing,Number}
    "Cross-sectional area of the screen \\[mm²\\]."
    screen_cross_section::Union{Nothing,Number}
    "Cross-sectional area of the armor \\[mm²\\]."
    armor_cross_section::Union{Nothing,Number}
    "Base (DC) resistance of the cable core \\[Ω/km\\]."
    resistance::Union{Nothing,Number}
    "Capacitance of the main insulation \\[μF/km\\]."
    capacitance::Union{Nothing,Number}
    "Inductance of the cable (trifoil formation) \\[mH/km\\]."
    inductance::Union{Nothing,Number}

    @doc """
    $(TYPEDSIGNATURES)

    Initializes a [`NominalData`](@ref) object with optional default values.

    # Arguments
    - `designation_code`: Cable designation (default: `nothing`).
    - `U0`: Phase-to-earth voltage rating \\[kV\\] (default: `nothing`).
    - `U`: Phase-to-phase voltage rating \\[kV\\] (default: `nothing`).
    - `conductor_cross_section`: Conductor cross-section \\[mm²\\] (default: `nothing`).
    - `screen_cross_section`: Screen cross-section \\[mm²\\] (default: `nothing`).
    - `armor_cross_section`: Armor cross-section \\[mm²\\] (default: `nothing`).
    - `resistance`: Cable resistance \\[Ω/km\\] (default: `nothing`).
    - `capacitance`: Cable capacitance \\[μF/km\\] (default: `nothing`).
    - `inductance`: Cable inductance (trifoil) \\[mH/km\\] (default: `nothing`).

    # Returns
    An instance of [`NominalData`](@ref) with the specified nominal properties.

    # Examples
    ```julia
    nominal_data = $(FUNCTIONNAME)(
    	conductor_cross_section=1000,
    	resistance=0.0291,
    	capacitance=0.39,
    )
    println(nominal_data.conductor_cross_section)
    println(nominal_data.resistance)
    println(nominal_data.capacitance)
    ```
    """
    function NominalData(;
        designation_code::Union{Nothing,String}=nothing,
        U0::Union{Nothing,Number}=nothing,
        U::Union{Nothing,Number}=nothing,
        conductor_cross_section::Union{Nothing,Number}=nothing,
        screen_cross_section::Union{Nothing,Number}=nothing,
        armor_cross_section::Union{Nothing,Number}=nothing,
        resistance::Union{Nothing,Number}=nothing,
        capacitance::Union{Nothing,Number}=nothing,
        inductance::Union{Nothing,Number}=nothing,
    )
        return new(
            designation_code,
            U0,
            U,
            conductor_cross_section,
            screen_cross_section,
            armor_cross_section,
            resistance,
            capacitance,
            inductance,
        )
    end
end
