"""
	LineCableModels.ImportExport

The [`ImportExport`](@ref) module provides methods for serializing and deserializing data structures in [`LineCableModels.jl`](index.md), and data exchange with external programs.

# Overview

This module provides functionality for:

- Saving and loading cable designs and material libraries to/from JSON and other formats.
- Exporting cable system models to PSCAD format.
- Serializing custom types with special handling for measurements and complex numbers.

The module implements a generic serialization framework with automatic type reconstruction
and proper handling of Julia-specific types like `Measurement` objects and `Inf`/`NaN` values.

# Dependencies

$(IMPORTS)

# Exports

$(EXPORTS)
"""
module ImportExport

# Load common dependencies
using ..LineCableModels
include("utils/commondeps.jl")

# Module-specific dependencies
using Measurements
using EzXML, Dates # For PSCAD export
using JSON3
using Serialization # For .jls format
using ..Utils
using ..Materials
using ..EarthProps
using ..DataModel
import ..LineCableModels: load!, export_data, save

include("importexport/serialize.jl")
include("importexport/deserialize.jl")
include("importexport/cableslibrary.jl")
include("importexport/materialslibrary.jl")
include("importexport/pscad.jl")


end # module ImportExport
