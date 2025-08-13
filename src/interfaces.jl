# Export public API
export FormulationSet, OptSet, DataFrame, add!, load!, export_data, save, preview
export f₀, μ₀, ε₀, ρ₀, T₀, TOL, ΔTmax

# General constants
"Base power system frequency, f₀ = 50 [Hz]."
const f₀ = 50.0
"Magnetic constant (vacuum permeability), μ₀ = 4π * 1e-7 [H/m]."
const μ₀ = 4π * 1e-7
"Electric constant (vacuum permittivity), ε₀ = 8.8541878128e-12 [F/m]."
const ε₀ = 8.8541878128e-12
"Annealed copper reference resistivity, ρ₀ = 1.724e-08 [Ω·m]."
const ρ₀ = 1.724e-08
"Base temperature for conductor properties, T₀ = 20 [°C]."
const T₀ = 20.0
"Maximum tolerance for temperature variations, ΔTmax = 150 [°C]."
const ΔTmax = 150.0
"Default tolerance for floating-point comparisons, TOL = 1e-6."
const TOL = 1e-6

"""
    FormulationSet(...)

Constructs a specific formulation object based on the provided keyword arguments.
The system will infer the correct formulation type.
"""
FormulationSet(engine::Symbol; kwargs...) = FormulationSet(Val(engine); kwargs...)

function OptSet end

"""
$(TYPEDSIGNATURES)

Returns a standardized identifier string for formulation types.

# Arguments

- A concrete implementation of [`AbstractFormulationSet`](@ref).

# Returns

- A string identifier used consistently across plots, tables, and parametric analyses.

# Examples
```julia
cp = CPEarth()
tag = _get_description(cp)  # Returns "CP model"
```

# Methods

$(_CLEANMETHODLIST)

# See also

- [`AbstractFDEMFormulation`](@ref)
- [`AbstractEHEMFormulation`](@ref)
"""
function _get_description end

function add! end

function load! end

function export_data end

function save end

function preview end

"""
$(TYPEDSIGNATURES)

Determines if the current execution environment is headless (without display capability).

# Returns

- `true` if running in a continuous integration environment or without display access.
- `false` otherwise when a display is available.

# Examples

```julia
if $(FUNCTIONNAME)()
	# Use non-graphical backend
	gr()
else
	# Use interactive backend
	plotlyjs()
end
```
"""
function _is_headless()
    return haskey(ENV, "CI") || !haskey(ENV, "DISPLAY")
end
