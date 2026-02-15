"""
	LineCableModels.Engine.IEC60287

The [`IEC60287`](@ref) module implements the analytical ampacity ratings and loss calculations according to the IEC 60287 standard.

# Submodules
- [`Losses`](@ref): AC resistance and loss factor calculations.
- [`Thermal`](@ref): Thermal resistance calculations.
"""
module IEC60287

using ...Commons
using ...DataModel
using ...EarthProps
using ...Engine: ProblemDefinition, AbstractFormulationSet

# Export public API
export AmpacityProblem, IEC60287Formulation
export compute_ampacity

include("types.jl")
include("losses.jl")
include("thermal.jl")
include("solver.jl")

end
