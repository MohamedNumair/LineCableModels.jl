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

# Load common dependencies
using ...LineCableModels
include("../commondeps.jl")

# Module-specific dependencies
using Measurements
using ...Utils
import ...LineCableModels: _get_description
import ..Engine: InsulationAdmittanceFormulation

struct Lossless <: InsulationAdmittanceFormulation end
_get_description(::Lossless) = "Lossless dielectric"

end # module InsulationAdmittance