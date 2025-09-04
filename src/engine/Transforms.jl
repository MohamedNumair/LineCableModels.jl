"""
	LineCableModels.Engine.Transforms

# Dependencies

$(IMPORTS)

# Exports

$(EXPORTS)
"""
module Transforms

# Export public API
export Fortescue

# Module-specific dependencies
using ...Commons
import ...Commons: get_description
import ..Engine: AbstractTransformFormulation, LineParameters
using Measurements
using LinearAlgebra

struct Fortescue <: AbstractTransformFormulation
	tol::BASE_FLOAT
end
# Convenient constructor with default tolerance
Fortescue(; tol::BASE_FLOAT = BASE_FLOAT(1e-4)) = Fortescue(tol)
get_description(::Fortescue) = "Fortescue (symmetrical components)"
include("transforms/fortescue.jl")

include("transforms/mode_decomp.jl")




end # module Transforms
