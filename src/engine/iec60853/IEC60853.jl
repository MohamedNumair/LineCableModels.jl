"""
    LineCableModels.Engine.IEC60853

Implements IEC 60853-2 cyclic rating factor (*M*) calculations for underground
power cables.  This module provides:

- Cyclic load profile analysis (loss-load factor μ, normalized ordinates Yᵢ)
- Cable internal transient via two-loop Cauer network (Van Wormer coefficient)
- Soil transient via exponential integral (single cable β and group γ)
- Cyclic rating factor M computation per IEC 60853-2
- Peak permissible current ``I_{peak} = M \\times I_{rated}``

# References
- IEC 60853-2:1989 + Amendment 1:2008
- CIGRE Technical Brochure 880, Section 5
"""
module IEC60853

using ..IEC60287: AmpacityProblem, IEC60287Formulation, IEC60287CableCondition,
                  iec60287_triage, compute_ampacity

export CyclicLoadProfile, load_cyclic_profile, compute_cyclic_rating

include("types.jl")
include("transient.jl")
include("solver.jl")

using .Transient
import .Solver: compute_cyclic_rating

end
