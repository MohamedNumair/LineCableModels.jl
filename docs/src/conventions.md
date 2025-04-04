# Naming conventions

---

## Multi-dispatch resolution pattern

The codebase employs a consistent three-tier resolution pattern for handling user input processing through multi-dispatch. This standardized approach allows for predictable code organization and improved maintainability.

### Resolution pattern naming structure

```
_resolve_<entity>           # Primary resolution function
├─ _parse_inputs_<entity>   # Type conversion & normalization 
└─ _do_resolve_<entity>     # Core implementation logic
```

The naming pattern has been carefully selected to reflect the purpose of each dispatch layer:

1. **`_resolve_<entity>`**: The primary entry point that coordinates the resolution process. The term "resolve" indicates that the function must determine an appropriate course of action based on input types that are not known in advance. This function validates inputs and delegates to specialized implementations.

2. **`_parse_inputs_<entity>`**: The intermediate layer responsible for converting diverse input types into standardized forms that can be processed by the implementation layer. This function normalizes inputs through type-specific conversions.

3. **`_do_resolve_<entity>`**: The implementation layer that performs the actual computations or transformations once inputs have been standardized. This function contains the core logic specific to each component type.

### Function scope and visibility

All functions in this pattern are prefixed with an underscore (`_`) to indicate they are internal implementation details not intended for direct use by the package consumers.

---

## Calculation vs. computation pattern

The codebase distinguishes between calculation and computation methods through a clear naming convention:

### Calculation methods (`calc_`)

Functions prefixed with `calc_` handle intermediate steps within a broader computational framework. These methods:

- Perform specific mathematical operations on well-defined inputs.
- Typically represent a single conceptual step in a larger process.
- Return intermediate results that will be used by higher-level functions.
- Are often associated with specific physical or mathematical formulations.

### Computation methods (`comp_`)

Functions prefixed with `comp_` represent higher-level operations that perform multiple calculation steps to achieve a complete analysis. These methods:

- Coordinate multiple calculation steps toward a final result.
- Often work with complex objects rather than primitive types.
- Represent the primary technical capabilities of the toolbox.
- May store results in appropriate data structures for further processing.

This distinction reflects the hierarchical nature of the [`LineCableModels.jl`](@ref) package, where individual calculations support the broader computational objectives of modeling transmission lines and cables.

---

## Library management pattern

The codebase implements a consistent pattern for managing libraries of models and components through standardized naming conventions. This pattern facilitates the storage, retrieval, and management of reusable objects within the framework.

### Library operations naming structure

```
store_<library>!       # Add or update an object in a library
remove_<library>!      # Remove an object from a library
save_<library>         # Writes the entire library contents to a file
list_<library>         # Display contents of a library
```

Each library operation follows a predictable naming convention:

1. **`store_<library>!`**: Adds or updates objects in the specified library. The exclamation mark indicates that this operation modifies the library state.

2. **`remove_<library>!`**: Removes an object from the specified library. The exclamation mark indicates that this operation modifies the library state.

3. **`save_<library>`**: Persists the current state of the library to external storage, typically a file. This operation does not modify the library itself.

4. **`list_<library>`**: Displays the contents of the library for inspection without modifying its state.

---

## Object modification pattern

For operations that modify components within larger structures (e.g., [`AbstractConductorPart`](@ref) within a parent [`Conductor`](@ref)), the codebase employs the `addto_` prefix:

```
addto_<entity>!        # Add or modify a subcomponent within a larger component
```

The `addto_<entity>!` pattern:

- Indicates that a subcomponent is being added to or modified within a parent component.
- Always includes an exclamation mark to denote state modification.
- Typically invokes `calc_` methods to update derived properties.

This pattern allows for hierarchical composition of components while maintaining a clear distinction from library management operations.

## DataFrame view pattern

The codebase implements a consistent pattern for generating `DataFrame` views of complex objects through a standardized naming convention:

```
<entity>_todf        # Convert entity to a `DataFrame` representation
```

This pattern:

- Takes an entity object as input and creates a `DataFrame` visualization.
- Uses the suffix `_todf` to clearly indicate the conversion operation.
- Produces non-mutating transformations (no exclamation mark needed).
- Facilitates analysis, visualization, and reporting of complex data structures.

The `_todf` suffix provides a concise and immediately recognizable identifier for functions that expose object data in tabular format.
