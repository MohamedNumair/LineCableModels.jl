"""
	LineCableModels.Engine.InternalImpedance

# Dependencies

$(IMPORTS)

# Exports

$(EXPORTS)
"""
module InternalImpedance

# Export public API
export ScaledBessel, SimpleSkin, DeriSkin

# Module-specific dependencies
using ...Commons
import ...Commons: get_description
import ..Engine: InternalImpedanceFormulation
using Measurements
using LinearAlgebra
using ...UncertainBessels: besselix, besselkx
using ...Utils: _to_σ

include("scaledbessel.jl")
include("simpleskin.jl")
include("deriskin.jl")

end # module InternalImpedance

