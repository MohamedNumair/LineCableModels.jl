# Export public API
export FormulationSet, DataFrame, add!, load!, export_data, save, preview
export f₀, μ₀, ε₀, ρ₀, T₀, TOL, ΔTmax
export setup_logging!
export BASE_FLOAT, REALSCALAR, COMPLEXSCALAR

# General constants
"Base power system frequency, f₀ = 50.0 [Hz]."
const f₀ = 50.0
"Magnetic constant (vacuum permeability), μ₀ = 4π * 1e-7 [H/m]."
const μ₀ = 4π * 1e-7
"Electric constant (vacuum permittivity), ε₀ = 8.8541878128e-12 [F/m]."
const ε₀ = 8.8541878128e-12
"Annealed copper reference resistivity, ρ₀ = 1.724e-08 [Ω·m]."
const ρ₀ = 1.724e-08
"Base temperature for conductor properties, T₀ = 20.0 [°C]."
const T₀ = 20.0
"Maximum tolerance for temperature variations, ΔTmax = 150 [°C]."
const ΔTmax = 150.0
"Default tolerance for floating-point comparisons, TOL = 1e-6."
const TOL = 1e-6

using Reexport, ForceImport

# Define aliases for the type constraints
using Measurements: Measurement, value, uncertainty, measurement
const BASE_FLOAT = Float64
const REALSCALAR = Union{BASE_FLOAT,Measurement{BASE_FLOAT}}
const COMPLEXSCALAR = Union{Complex{BASE_FLOAT},Complex{Measurement{BASE_FLOAT}}}


using DocStringExtensions, Pkg
"""
Override `DocStringExtensions.format` for `_CLEANMETHODLIST`.
"""
struct _CleanMethodList <: DocStringExtensions.Abbreviation end
"Modified `_CLEANMETHODLIST` abbreviation with sanitized file paths."
const _CLEANMETHODLIST = _CleanMethodList()
function DocStringExtensions.format(::_CleanMethodList, buf, doc)
    local binding = doc.data[:binding]
    local typesig = doc.data[:typesig]
    local modname = doc.data[:module]
    local func = Docs.resolve(binding)
    local groups = DocStringExtensions.methodgroups(func, typesig, modname; exact=false)
    if !isempty(groups)
        println(buf)
        local pkg_root = Pkg.pkgdir(modname) # Use Pkg.pkgdir here
        if pkg_root === nothing
            @warn "Could not determine package root for module $modname using _CLEANMETHODLIST. Paths will be shown as basenames."
        end
        for group in groups
            println(buf, "```julia")
            for method in group
                DocStringExtensions.printmethod(buf, binding, func, method)
                println(buf)
            end
            println(buf, "```\n")
            if !isempty(group)
                local method = group[1]
                local file = string(method.file)
                local line = method.line
                local path =
                    if pkg_root !== nothing && !isempty(file) &&
                       startswith(file, pkg_root)
                        basename(file) # relpath(file, pkg_root)
                    # elseif !isempty(file) && isfile(file)
                    # 	basename(file)
                    else
                        string(method.file) # Fallback
                    end
                local URL = DocStringExtensions.url(method)
                isempty(URL) || println(buf, "defined at [`$path:$line`]($URL).")
            end
            println(buf)
        end
        println(buf)
    end
    return nothing
end

"""
    FormulationSet(...)

Constructs a specific formulation object based on the provided keyword arguments.
The system will infer the correct formulation type.
"""
FormulationSet(engine::Symbol; kwargs...) = FormulationSet(Val(engine); kwargs...)

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
# function _is_headless()::Bool
#     return haskey(ENV, "CI") || !haskey(ENV, "DISPLAY")
# end
function _is_headless()::Bool
    # 1. Check for common CI environment variables
    if get(ENV, "CI", "false") == "true"
        return true
    end

    # 2. Check if a display is available (primarily for Linux)
    if !haskey(ENV, "DISPLAY") && Sys.islinux()
        return true
    end

    # 3. Check for GR backend's specific headless setting
    if get(ENV, "GKSwstype", "") in ("100", "nul", "nil")
        return true
    end

    return false
end

function _display_path(file_name)
    return _is_headless() ? basename(file_name) : relpath(file_name) #abspath(file_name)
end

"""
$(TYPEDSIGNATURES)

Checks if the code is running inside a `@testset` by checking if `Test` is loaded
in the current session and then calling `get_testset_depth()`.
"""
function _is_in_testset()
    # Start with the current module
    current_module = @__MODULE__

    # Walk up the module tree (e.g., from the sandbox to Main)
    while true
        if isdefined(current_module, :Test) &&
           isdefined(current_module.Test, :get_testset_depth)
            # Found the Test module, check the test set depth
            return current_module.Test.get_testset_depth() > 0
        end

        # Move to the parent module
        parent = parentmodule(current_module)
        if parent === current_module # Reached the top (Main)
            break
        end
        current_module = parent
    end

    return false
end
# function _is_in_testset()
#     if isdefined(Main, :Test)
#         # If Test is loaded, we can safely access its functions
#         return Main.Test.get_testset_depth() > 0
#     end
#     return false
# end

# """
#     _get_args_T(args...)

# Recursively determines the common type for arguments (including structs, arrays, tuples):
# - If any field/element is a Measurement, returns `Measurement{BASE_FLOAT}`.
# - Otherwise, returns `BASE_FLOAT`.
# """
# function _get_arg_T(args...)
#     has_measurement(x) =
#         x isa Measurement ||
#         (x isa AbstractArray && eltype(x) <: Measurement) ||
#         (x isa NamedTuple && any(has_measurement, values(x))) ||
#         (x isa Tuple && any(has_measurement, x)) ||
#         (_isstructtype(typeof(x)) && any(has_measurement, getfield.(Ref(x), fieldnames(typeof(x)))))
#     any(has_measurement, args) ? Measurement{BASE_FLOAT} : BASE_FLOAT
# end

# # Helper to check if a type is a struct (not primitive, not array, not tuple)
# _isstructtype(T::Type) = isconcretetype(T) && !ismutable(T) && !T <: AbstractArray && !T <: Tuple && !T <: Number

_coerce_args_to_T(args...) =
    any(x -> x isa Measurement, args) ? Measurement{BASE_FLOAT} : BASE_FLOAT

# Promote scalar to T if T is Measurement; otherwise take nominal if x is Measurement.
function _coerce_scalar_to_T(x, ::Type{T}) where {T}
    if T <: Measurement
        return x isa Measurement ? x : (zero(T) + x)
    else
        return x isa Measurement ? T(value(x)) : convert(T, x)
    end
end

# Arrays: promote/demote elementwise, preserving shape. Arrays NEVER decide T.
function _coerce_array_to_T(A::AbstractArray, ::Type{T}) where {T}
    if T <: Measurement
        return (eltype(A) === T) ? A : (A .+ zero(T))             # Real → Measurement(σ=0)
    elseif eltype(A) <: Measurement
        B = value.(A)                                             # Measurement → Real (nominal)
        return (eltype(B) === T) ? B : convert.(T, B)
    else
        return (eltype(A) === T) ? A : convert.(T, A)
    end
end