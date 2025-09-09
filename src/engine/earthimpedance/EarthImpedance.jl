"""
	LineCableModels.Engine.EarthImpedance

# Dependencies

$(IMPORTS)

# Exports

$(EXPORTS)
"""
module EarthImpedance

# Export public API
export Papadopoulos

# Module-specific dependencies
using ...Commons
import ...Commons: get_description
import ..Engine: EarthImpedanceFormulation
using Measurements
using ...UncertainBessels: besselk
using QuadGK: quadgk

include("homogeneous.jl")
include("base.jl")

end # module EarthImpedance
