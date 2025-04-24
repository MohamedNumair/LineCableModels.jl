module LineCableModels

# Load common dependencies and definitions
include("CommonDeps.jl")

# Submodule `Utils`
include("Utils.jl")
@force using .Utils
@reexport using .Utils

# Submodule `Materials`
include("Materials.jl")
@force using .Materials
@reexport using .Materials

# Submodule `EarthProps`
include("EarthProps.jl")
@force using .EarthProps
@reexport using .EarthProps

# Submodule `DataModel`
include("DataModel.jl")
@force using .DataModel
@reexport using .DataModel

# Submodule `FEMTools`
include("FEMTools.jl")
@force using .FEMTools
@reexport using .FEMTools

# Submodule `ImportExport`
include("ImportExport.jl")
@force using .ImportExport
@reexport using .ImportExport

end