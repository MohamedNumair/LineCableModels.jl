module Commons

include("commons/docstringextension.jl")
include("commons/consts.jl")


export get_description, add!, FormulationSet
export AbstractEHEMFormulation

"""
    FormulationSet(...)

Constructs a specific formulation object based on the provided keyword arguments.
The system will infer the correct formulation type.
"""
FormulationSet(engine::Symbol; kwargs...) = FormulationSet(Val(engine); kwargs...)

function get_description end

function add! end

end