# Export public API
export FormulationSet, OptSet, to_df, add!

"""
    FormulationSet(...)

Constructs a specific formulation object based on the provided keyword arguments.
The system will infer the correct formulation type.
"""
function FormulationSet end

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

function to_df end

function add! end
