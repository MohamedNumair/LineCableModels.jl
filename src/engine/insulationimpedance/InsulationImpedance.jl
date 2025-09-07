"""
	LineCableModels.Engine.InsulationImpedance

# Dependencies

$(IMPORTS)

# Exports

$(EXPORTS)
"""
module InsulationImpedance

# Export public API
export PureInductance


# Module-specific dependencies
using ...Commons
import ...Commons: get_description
import ..Engine: InsulationImpedanceFormulation
using Measurements

struct PureInductance <: InsulationImpedanceFormulation end
get_description(::PureInductance) = "Pure inductance (lossless dielectric)"

function calc_outer_insulation_impedance(
    radius_ex::Measurement{T},
    radius_in::Measurement{T},
    mur_ins::Measurement{T},
    f::T,
) where {T<:Real}

    # Constants
    m0 = 4 * pi * 1e-7
    mu_ins = m0 * mur_ins
    omega = 2 * pi * f

    # Avoid division by zero if radius_in is 0
    if radius_in == 0
        radius_in = eps()
    end

    # Impedance of the insulation layer
    zinsu = im * omega * mu_ins * log(radius_ex / radius_in) / (2 * pi)

    return zinsu
end

end # module InsulationImpedance