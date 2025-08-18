"""
	LineCableModels.Engine.InsulationAdmittance

# Dependencies

$(IMPORTS)

# Exports

$(EXPORTS)
"""
module InsulationAdmittance

# Export public API
# export 

# Load common dependencies
include("../commondeps.jl")
using ...LineCableModels
using ...Utils
import ...LineCableModels: _get_description, REALTYPES, COMPLEXTYPES, NUMERICTYPES
import ..Engine: InsulationAdmittanceFormulation

# Module-specific dependencies
using Measurements

end # module InsulationAdmittance