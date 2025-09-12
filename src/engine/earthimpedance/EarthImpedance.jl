"""
	LineCableModels.Engine.EarthImpedance

# Dependencies

$(IMPORTS)

# Exports

$(EXPORTS)
"""
module EarthImpedance

# Export public API
export Papadopoulos, SimpleCarson, FullCarson, DeriEarth

# Module-specific dependencies
using ...Commons
import ...Commons: get_description
import ..Engine: EarthImpedanceFormulation
using Measurements: Measurement, value
using QuadGK: quadgk
using ...Utils: _to_σ, _bessel_diff, to_nominal

include("homogeneous.jl")
include("base.jl")
include("simplecarson.jl")
include("fullcarson.jl")
include("deriearth.jl")

end # module EarthImpedance
