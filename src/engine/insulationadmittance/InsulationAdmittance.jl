"""
	LineCableModels.Engine.InsulationAdmittance

# Dependencies

$(IMPORTS)

# Exports

$(EXPORTS)
"""
module InsulationAdmittance

# Export public API
export Lossless

# Module-specific dependencies
using ...Commons
import ...Commons: get_description
import ..Engine: InsulationAdmittanceFormulation
using Measurements

struct Lossless <: InsulationAdmittanceFormulation end
get_description(::Lossless) = "Lossless insulation (ideal dielectric)"

end # module InsulationAdmittance