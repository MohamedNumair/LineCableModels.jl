"""
	LineCableModels.Engine.InsulationAdmittance

# Dependencies

$(IMPORTS)

# Exports

$(EXPORTS)
"""
module InsulationAdmittance

# Export public API
export PureCapacitance

# Module-specific dependencies
using ...Commons
import ...Commons: get_description
import ..Engine: InsulationAdmittanceFormulation
using Measurements

struct PureCapacitance <: InsulationAdmittanceFormulation end
get_description(::PureCapacitance) = "Pure capacitance (lossless dielectric)"

end # module InsulationAdmittance