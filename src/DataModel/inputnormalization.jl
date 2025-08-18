using MacroTools
# TODO: Develop and integrate input type normalization

# """
#     @sanitize_inputs(func_def)

# A macro that wraps a function definition (typically a constructor) to sanitize its numeric inputs.

# It enforces type consistency by promoting inputs to `Measurement{Float64}` if any input is a `Measurement`,
# or to `Float64` otherwise. Integers are automatically converted.

# # Usage
# Apply this macro to a constructor definition:

# ```julia
# @sanitize_inputs function MyType(a::Number, b::Number)
#     # constructor logic
# end
# ```
# """
# macro sanitize_inputs(func_def)
#     # Deconstruct the function definition into its parts (name, args, body, etc.)
#     dict = splitdef(func_def)

#     # Extract argument names
#     arg_names = [isa(arg, Symbol) ? arg : arg.args[1] for arg in dict[:args]]

#     # Generate the code for the new function body
#     new_body = quote
#         # 1. Collect all arguments into a tuple
#         all_args = ($(arg_names...),)

#         # 2. Determine the target numeric type
#         # If any argument is a Measurement, the target is Measurement{Float64}.
#         # Otherwise, it's Float64.
#         target_type = any(x -> isa(x, Measurement), all_args) ? Measurement{Float64} : Float64

#         # 3. Sanitize and promote arguments
#         # Create a new tuple `sanitized_args` with corrected types.
#         sanitized_args = map(all_args) do arg
#             if isa(arg, Number) && !isa(arg, Bool) # Exclude Bools
#                 return convert(target_type, arg)
#             else
#                 return arg # Keep non-numeric types as they are
#             end
#         end

#         # 4. Re-call the original constructor logic with sanitized arguments.
#         # We use `invokelatest` to call the inner constructor method with the newly typed arguments.
#         # This avoids recursion and correctly dispatches to the intended implementation.
#         return Base.invokelatest(__module__.$(dict[:name]), sanitized_args...)
#     end

#     # Update the function body with our new sanitation logic
#     dict[:body] = new_body

#     # Reconstruct the function definition and escape it to be inserted into the calling module's AST
#     return esc(combinedef(dict))
# end
#=
...existing code...
import Base: get, delete!, length, setindex!, iterate, keys, values, haskey, getindex

# Include and use the input sanitizer
include("DataModel/sanitizer.jl")
using .Main.LineCableModels.DataModel: @sanitize_inputs

# To handle radius-related operations
abstract type AbstractRadius end
# ...existing code...
```

### 4. Apply the Macro to Constructors

Finally, apply the `@sanitize_inputs` macro to the constructors in `conductors.jl` and `insulators.jl`. You only need to add one line above each function definition. The macro will handle the rest.

**Example for `conductors.jl`:**

````julia
// filepath: /home/amartins/Documents/KUL/LineCableModels/src/DataModel/conductors.jl
// ...existing code...
- [`calc_helical_params`](@ref)
"""
@sanitize_inputs
function WireArray(
    radius_in::Union{Number,<:AbstractCablePart},
// ...existing code...
// ...existing code...
- [`calc_helical_params`](@ref)
"""
@sanitize_inputs
function Strip(
    radius_in::Union{Number,<:AbstractCablePart},
// ...existing code...
// ...existing code...
- [`calc_tubular_gmr`](@ref)
"""
@sanitize_inputs
function Tubular(
    radius_in::Union{Number,<:AbstractCablePart},
// ...existing code...
```

**Example for `insulators.jl`:**

````julia
// filepath: /home/amartins/Documents/KUL/LineCableModels/src/DataModel/insulators.jl
// ...existing code...
println(semicon_layer.shunt_conductance)  # Expected output: Conductance in [S·m]
```
"""
@sanitize_inputs
function Semicon(
    radius_in::Union{Number,<:AbstractCablePart},
// ...existing code...
// ...existing code...
insulator_layer = $(FUNCTIONNAME)(0.01, 0.015, material_props, temperature=25)
```
"""
@sanitize_inputs
function Insulator(
    radius_in::Union{Number,<:AbstractCablePart},
// ...existing code...
```

### Advantages of this Approach

*   **Non-Invasive:** You only add a single macro annotation (`@sanitize_inputs`) to each constructor. The original logic inside the constructors remains untouched.
*   **Centralized Logic:** The type promotion rules are defined in one place (`sanitizer.jl`), making them easy to maintain and update.
*   **No Breaking Changes:** The function signatures do not change, so all existing user code will work as before, but with the added benefit of automatic type sanitation.
*   **Flexibility:** The macro is generic and can be applied to any function that requires this type of input sanitation, not just your constructors.// filepath: /home/amartins/Documents/KUL/LineCableModels/src/DataModel.jl
// ...existing code...
import Base: get, delete!, length, setindex!, iterate, keys, values, haskey, getindex

# Include and use the input sanitizer
include("DataModel/sanitizer.jl")
using .Main.LineCableModels.DataModel: @sanitize_inputs

# To handle radius-related operations
abstract type AbstractRadius end
// ...existing code...
```

### 4. Apply the Macro to Constructors

Finally, apply the `@sanitize_inputs` macro to the constructors in `conductors.jl` and `insulators.jl`. You only need to add one line above each function definition. The macro will handle the rest.

**Example for `conductors.jl`:**

````julia
// filepath: /home/amartins/Documents/KUL/LineCableModels/src/DataModel/conductors.jl
// ...existing code...
- [`calc_helical_params`](@ref)
"""
@sanitize_inputs
function WireArray(
    radius_in::Union{Number,<:AbstractCablePart},
// ...existing code...
// ...existing code...
- [`calc_helical_params`](@ref)
"""
@sanitize_inputs
function Strip(
    radius_in::Union{Number,<:AbstractCablePart},
// ...existing code...
// ...existing code...
- [`calc_tubular_gmr`](@ref)
"""
@sanitize_inputs
function Tubular(
    radius_in::Union{Number,<:AbstractCablePart},
// ...existing code...
```

**Example for `insulators.jl`:**

````julia
// filepath: /home/amartins/Documents/KUL/LineCableModels/src/DataModel/insulators.jl
// ...existing code...
println(semicon_layer.shunt_conductance)  # Expected output: Conductance in [S·m]
```
"""
@sanitize_inputs
function Semicon(
    radius_in::Union{Number,<:AbstractCablePart},
// ...existing code...
// ...existing code...
insulator_layer = $(FUNCTIONNAME)(0.01, 0.015, material_props, temperature=25)
```
"""
@sanitize_inputs
function Insulator(
    radius_in::Union{Number,<:AbstractCablePart},
// ...existing code...
```
"""
# ### Advantages of this Approach

# *   **Non-Invasive:** You only add a single macro annotation (`@sanitize_inputs`) to each constructor. The original logic inside the constructors remains untouched.
# *   **Centralized Logic:** The type promotion rules are defined in one place (`sanitizer.jl`), making them easy to maintain and update.
# *   **No Breaking Changes:** The function signatures do not change, so all existing user code will work as before, but with the added benefit of automatic type sanitation.
# *   **Flexibility:** The macro is generic and can be applied to any function that requires this type of input sanitation, not just
=#