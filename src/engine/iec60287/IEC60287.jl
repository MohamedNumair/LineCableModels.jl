"""
	LineCableModels.Engine.IEC60287

The [`IEC60287`](@ref) module implements the analytical ampacity ratings and loss calculations according to the IEC 60287 standard.

# Submodules
- [`Losses`](@ref): AC resistance and loss factor calculations.
- [`Thermal`](@ref): Thermal resistance calculations.
- [`Solver`](@ref): Iterative ampacity solver (IEC 60287-1-1 Eq. 3).
"""
module IEC60287

using ...Commons
using ...DataModel
using ...EarthProps
using ...Engine: ProblemDefinition, AbstractFormulationSet, compute!

# Export public API
export AmpacityProblem, IEC60287Formulation, IEC60287CableCondition
export iec60287_triage, compute_ampacity, compute!, calculate_ac_permissible_current

include("types.jl")
include("losses.jl")
include("thermal.jl")
include("solver.jl")

using .Losses
using .Thermal
import .Solver: compute_ampacity, calculate_ac_permissible_current

end
