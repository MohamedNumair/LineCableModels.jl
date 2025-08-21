module LineCableModels

# Package-wide definitions
include("globals.jl")
include("typecoercion.jl")
include("logging.jl")
include("macros.jl")

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

# Submodule `Engine`
include("Engine.jl")
@force using .Engine
@reexport using .Engine

# Submodule `FEMTools`
include("FEMTools.jl")
@force using .FEMTools
@reexport using .FEMTools

# Submodule `ImportExport`
include("ImportExport.jl")
@force using .ImportExport
@reexport using .ImportExport

end