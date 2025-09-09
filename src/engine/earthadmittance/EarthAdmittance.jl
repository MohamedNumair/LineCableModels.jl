"""
	LineCableModels.Engine.EarthAdmittance

# Dependencies

$(IMPORTS)

# Exports

$(EXPORTS)
"""
module EarthAdmittance

# Export public API
export Papadopoulos

# Module-specific dependencies
using ...Commons
import ...Commons: get_description
import ..Engine: EarthAdmittanceFormulation
using Measurements
using ...UncertainBessels: besselk
using QuadGK: quadgk

include("homogeneous.jl")
include("base.jl")

end # module EarthAdmittance
