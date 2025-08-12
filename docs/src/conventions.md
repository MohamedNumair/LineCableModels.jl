# Package conventions

---

## Function and method names

### Multi-dispatch resolution pattern

The codebase employs a consistent three-tier resolution pattern for handling user input processing through multi-dispatch. This standardized approach allows for predictable code organization and improved maintainability.

#### Resolution pattern naming structure

```julia
_resolve_<entity>           # Primary resolution function
├─ _parse_inputs_<entity>   # Type conversion & normalization 
└─ _do_resolve_<entity>     # Core implementation logic
```

The naming pattern has been carefully selected to reflect the purpose of each dispatch layer:

1. **`_resolve_<entity>`**: The primary entry point that coordinates the resolution process. The term "resolve" indicates that the function must determine an appropriate course of action based on input types that are not known in advance. This function validates inputs and delegates to specialized implementations.

2. **`_parse_inputs_<entity>`**: The intermediate layer responsible for converting diverse input types into standardized forms that can be processed by the implementation layer. This function normalizes inputs through type-specific conversions.

3. **`_do_resolve_<entity>`**: The implementation layer that performs the actual computations or transformations once inputs have been standardized. This function contains the core logic specific to each component type.

#### Function scope and visibility

All functions in this pattern are prefixed with an underscore (`_`) to indicate they are internal implementation details not intended for direct use by the package consumers.

### Calculation vs. computation pattern

The codebase distinguishes between calculation and computation methods through a clear naming convention:

#### Calculation methods (`calc_`)

Functions prefixed with `calc_` handle intermediate steps within a broader computational framework. These methods:

- Perform specific mathematical operations on well-defined inputs.
- Typically represent a single conceptual step in a larger process.
- Return intermediate results that will be used by higher-level functions.
- Are often associated with specific physical or mathematical formulations.

#### Computation methods (`comp_`)

Functions prefixed with `comp_` represent higher-level operations that perform multiple calculation steps to achieve a complete analysis. These methods:

- Coordinate multiple calculation steps toward a final result.
- Often work with complex objects rather than primitive types.
- Represent the primary technical capabilities of the toolbox.
- May store results in appropriate data structures for further processing.

This distinction reflects the hierarchical nature of the [`LineCableModels.jl`](@ref) package, where individual calculations support the broader computational objectives of modeling transmission lines and cables.

### Library management pattern

The codebase implements a consistent pattern for managing libraries of models and components through standardized naming conventions. This pattern facilitates the storage, retrieval, and management of reusable objects within the framework.

#### Library operations naming structure

```julia
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

### Object modification pattern

For operations that modify components within larger structures (e.g., [`AbstractConductorPart`](@ref) within a parent [`ConductorGroup`](@ref)), the codebase employs the `addto_` prefix:

```julia
addto_<entity>!        # Add or modify a subcomponent within a larger component
```

The `addto_<entity>!` pattern:

- Indicates that a subcomponent is being added to or modified within a parent component.
- Always includes an exclamation mark to denote state modification.
- Typically invokes `calc_` methods to update derived properties.

This pattern allows for hierarchical composition of components while maintaining a clear distinction from library management operations.

### DataFrame view pattern

The codebase implements a consistent pattern for generating `DataFrame` views of complex objects through a standardized naming convention:

```julia
<entity>_todf        # Convert entity to a `DataFrame` representation
```

This pattern:

- Takes an entity object as input and creates a `DataFrame` visualization.
- Uses the suffix `_todf` to clearly indicate the conversion operation.
- Produces non-mutating transformations (no exclamation mark needed).
- Facilitates analysis, visualization, and reporting of complex data structures.

The `_todf` suffix provides a concise and immediately recognizable identifier for functions that expose object data in tabular format.

---

## Docstrings

The following docstring standards are generally adopted across the codebase.

### General Docstring principles

1. **Placement:** Docstrings must immediately precede the code entity (struct, function, module, constant) they describe.
2. **Delimiter:** Use triple double quotes (`"""Docstring content"""`) for all docstrings, *except* for individual struct field documentation.
3. **Conciseness:** Avoid redundancy. Information should be presented clearly and concisely in the appropriate section.
4. **Tone:** Use formal, precise scientific language suitable for technical documentation. Avoid contractions, colloquialisms, and ambiguous phrasing.

### Physical unit formatting

All variables corresponding to physical quantities must be annotated with their SI units and according to the following rules:

1. **Mandatory units:** ALL arguments, return values, struct fields, and constants representing **physical quantities** MUST have their SI units specified.
2. **Dimensionless quantities:** Physical quantities that are dimensionless MUST be explicitly marked as `\\[dimensionless\\]`.
3. **Non-physical quantities:** Do *not* add unit annotations to arguments, variables, or fields that do not represent physical quantities (e.g., counters, flags, indices).
4. **Standard format:** Units MUST be enclosed in double-backslash escaped square brackets: `\\[unit\\]`.
    - **Correct:** `\\[m\\]`, `\\[Hz\\]`, `\\[Ω\\]`, `\\[H/m\\]`, `\\[dimensionless\\]`
    - **Incorrect:** `[m]`, `\[m]`, `m` (as a standalone unit identifier)
5. **Exception for example comments:** Inside ` ```julia` code blocks within the `# Examples` section, use *regular* (non-escaped) square brackets for units within comments.
    - **Correct:** ````julia result = calculation(10.0) # Output in [m]````
    - **Incorrect:** ````julia result = calculation(10.0) # Output in \\[m\\]````
6. **Common units:** Use standard SI abbreviations (e.g., `m`, `s`, `kg`, `A`, `K`, `mol`, `cd`, `Hz`, `N`, `Pa`, `J`, `W`, `C`, `V`, `F`, `Ω`, `S`, `T`, `H`, `lm`, `lx`, `Bq`, `Gy`, `Sv`, `°C`). Use the Unicode middle dot `·` for multiplication where appropriate (e.g., `\\[Ω·m\\]`).

### Mathematical formulation formatting

1. **Requirement:** Mathematical formulas rendered using LaTeX are MANDATORY *only* for functions/methods whose names start with the prefix `calc_`.
2. **Location:** For `calc_` functions, the LaTeX formula MUST be placed within a ````math ...```` block inside the `# Notes` section.
3. **Forbidden:** Do NOT include ````math``` blocks or LaTeX formulations for any functions or methods *not* prefixed with `calc_`.
4. **LaTeX escaping:** Within documentation text AND inside ````math``` blocks, all LaTeX commands (like `\frac`, `\mu`) MUST have their backslashes escaped (`\\`).
    - **Correct:** `\\mu_r`, ```math \\frac{a}{b}```
    - **Incorrect:** `\mu_r`, ```math \frac{a}{b}```

### Documentation templates

The subsections below contain templates for different types of code elements.

#### 1. Structs

- **Main docstring:** Use `$(TYPEDEF)` for the signature and `$(TYPEDFIELDS)` to list the fields automatically. Provide a concise description of the struct purpose.

    ```julia
    """
    $(TYPEDEF)

    Represents a physical entity with specific properties...

    $(TYPEDFIELDS)
    """
    struct StructName
        # Field definitions follow
    end
    ```

- **Field documentation:**
  - Place *directly above* each field definition.
  - Use single-line double quotes: `"Description with units \\[unit\\] or \\[dimensionless\\] if applicable."`
  - Do NOT use `""" """` block quotes or inline comments (`#`) for documenting struct fields.

#### 2. Constructors (inside or outside structs)

- ALL constructors MUST be documented using the `@doc` macro placed immediately before the `function` keyword or the compact assignment form (`TypeName(...) = ...`). This applies even to default constructors if explicitly defined.
- **Format:** Use `$(TYPEDSIGNATURES)`. Include standard sections (`Arguments`, `Returns`, `Examples`).

    ````julia
    @doc """
    $(TYPEDSIGNATURES)

    Constructs a [`StructName`](@ref) instance.

    # Arguments

    - `arg_name`: Description including units `\\[unit\\]` if physical.

    # Returns

    - A [`StructName`](@ref) object. [Optionally add details about initialization].

    # Examples

    ```julia
    instance = $(FUNCTIONNAME)(...) # Provide meaningful example values
    ```

    """
    function StructName(...)
        # Implementation
    end
    ````

#### 3. Functions / methods

- **Format:** Start with `$(TYPEDSIGNATURES)`. Follow the section order described.
  
    ````julia
    """
    $(TYPEDSIGNATURES)

    Concise description of the function's purpose.

    # Arguments

    - `arg1`: Description, units `\\[unit\\]` if physical. Specify `Default: value` if applicable.
    - `arg2`: Description, `\\[dimensionless\\]` if physical and dimensionless.

    # Returns

    - Description of the return value, including units `\\[unit\\]` if physical. Document multiple return values individually if using tuples.

    # Notes  (OPTIONAL - MANDATORY ONLY for `calc_` functions for the formula)

    [For `calc_` functions: Explanation and formula]
    ```math
    \\LaTeX... \\escaped... \\formula...
    ```

    # Errors (OPTIONAL)

    - Describes potential errors or exceptions thrown.

    # Examples

    ```julia
    result = $(FUNCTIONNAME)(...) # Use representative values. Add expected output comment.
    # Example: result = $(FUNCTIONNAME)(0.02, 0.01, 1.0) # Expected output: ~0.0135 [m]
    ```

    # See also (OPTIONAL)

    - [`related_package_function`](@ref)
    """
    function function_name(...)
        # Implementation
    end
    ````
  
- **Section order:**
    1. Description (no heading)
    2. `# Arguments`
    3. `# Returns`
    4. `# Notes` (Only if needed; mandatory for `calc_` functions)
    5. `# Errors` (Only if needed)
    6. `# Examples`
    7. `# See also` (Only if needed)
- **Spacing:** Ensure exactly one blank line separates the description from `# Arguments` and precedes every subsequent section heading.
- **Examples:** Use the `$(FUNCTIONNAME)` macro instead of hardcoding the function name. Use meaningful, realistic input values. Include expected output or behavior in a comment, using *non-escaped* brackets for units (`[unit]`).
- **See also:** Only link to other functions *within this package* using `[`function_name`](@ref)`. Do not link to Base Julia functions or functions from external packages unless absolutely necessary for context. Only include if the linked function provides relevant context or alternatives.

#### 4. Modules

- **Format:** The first line must be the module name indented by four spaces. Use `$(IMPORTS)` and `$(EXPORTS)` literals.

    ````julia
    """
        ModuleName

    Brief description of the module purpose within the broader package (e.g., for [`Package.jl`](index.md)).

    # Overview

    - Bullet points describing key capabilities or features provided by the module.

    # Dependencies

    $(IMPORTS)

    # Exports

    $(EXPORTS)
    """
    module ModuleName
        # Contents
    end
    ````

#### 5. Constants

- **Format:** Use a single-line docstring with double quotes (`"..."`). Include a brief description, the symbol of the constant if standard (e.g., `μ₀`), its value, and its units using the `\\[unit\\]` format.

    ```julia
    "Magnetic constant (vacuum permeability), μ₀ = 4π * 1e-7 \\[H/m\\]]."
    const μ₀ = 4π * 1e-7
    ```

#### Common mistakes to avoid

Double-check the docstrings to avoid these common errors:

- **Missing `@doc` for constructors:** ALL constructors require the `@doc` macro before their definition.
- **Incorrect struct field docstrings:** Use single-line `"..."` *above* the field, not block `"""..."""` quotes or inline `#` comments.
- **Incorrect section order:** Follow the specified order for function docstring sections precisely.
- **Hard-coding function names in examples:** Always use `$(FUNCTIONNAME)`.
- **Incorrect unit formatting:** Ensure `\\[unit\\]` syntax is used everywhere except comments within `Examples` blocks (`[unit]`). Double-check escaping (`\\`) for LaTeX.
- **Adding math formulas to non-`calc_` functions:** Math blocks are *only* for functions prefixed with `calc_`.

---

## Module organization

### Exports and visibility

- Public API functions have no underscore prefix and are explicitly exported.
- Internal functions use leading underscore prefix (`_function_name`) and are not exported.
- Modules use `@reexport` to propagate exports from submodules to parent modules.
- Exports are placed at the top of each module for visibility.

### Module structure

- Main module (`LineCableModels`) reexports from submodules.
- Submodules (`DataModel`, `Materials`, etc.) handle their own exports.
- Maximum nesting depth is 3 levels (parent → child → grandchild).
- Documentation is maintained at all levels using `DocStringExtensions`.

### Code navigation

- Module docstrings should list key exported functions and types.
- All exported items require docstrings.
- Internal implementation details use minimal documentation.

---

## Framework design pattern

### Core architecture

The `LineCableModels.jl` package implements a consistent framework pattern across all modules, designed to provide flexibility while maintaining type stability and performance. The architecture is built around three key components:

1. **Problem definition**: Defines the physics/mathematical approach
2. **Solver**: Controls execution parameters
3. **Workspace**: Centralizes all state during computation

This pattern separates *what* is being calculated (problem definition, formulation) from *how* calculations are executed (engine used, solver) and *where* data is stored (workspace).

### The workspace pattern

At the core of the framework is the Workspace pattern, exemplified by `FEMWorkspace` in the `FEMTools` module. This pattern can be replicated across other modules (e.g., `EMTWorkspace`).

A workspace:

- Acts as a centralized state container.
- Stores all intermediate computation data.
- Manages entity tracking and lookup tables.
- Provides consistent interfaces for data access.
- Maintains configuration and results.

### Type hierarchy

Each module follows a consistent type hierarchy:

```julia
AbstractProblemFormulation
  ├── FEMFormulation :> {FEMDarwin, FEMElectrodynamics, ...}
  ├── AbstractFDEMFormulation :> {CPEarth, CIGRE, ...}
  ├── AbstractEHEMFormulation :> {EnforceLayer, EquivalentSigma, ...}
  ├── ...
  └── [Other specialized formulations, concrete or abstract]

AbstractWorkspace
  ├── FEMWorkspace
  ├── EMTWorkspace
  ├── ...
  └── [Other specialized workspaces]

AbstractEntityData
  └── [Domain-specific entity types]
```

This hierarchy enables both specialization and shared interfaces.

### Data flow

Data flows through the system in a consistent pattern:

1. System definition (LineCableSystem instance).
2. Problem definition (physics parameters, formulations to employ).
3. Solver configuration (execution parameters).
4. Workspace initialization (state container).
5. Execution (multi-phase processing).
6. Result extraction (from workspace).

This pattern applies regardless of the specific module or calculation type.

### Multi-phase processing

All modules implement a multi-phase execution pattern with clear separation between phases. For example, the `FEMTools` module follows this pattern:

1. **Initialization phase**: Setup workspace, load configurations.
2. **Construction phase**: Create entities based on system definition (may include specific preliminary tasks, e.g. fragments/synchronization steps FEM simulations).
3. **Processing phase**: Execute main computation loops, store raw results in workspace container.
4. **Post processing phase**: Assign properties to processed entities.
5. **Result phase**: Extract and format results.

This pattern ensures clean separation of concerns, making the code more maintainable.

### State management

State is managed exclusively through the Workspace, which contains:

1. **Configuration state**: Original system, formulation, and opts.
2. **Entity state**: Collections of typed entities.
3. **Lookup maps**: Efficient mappings between entities and properties.
4. **Processing state**: Temporary calculation state.
5. **Result state**: Final calculation outputs.

This centralized approach eliminates global state and ensures thread safety.

### Implementation example: FEMTools.jl

The FEMTools module exemplifies this pattern:

- `FEMFormulation`: Physics parameters for FEM simulation.
- `FEMSolver`: Execution parameters for meshing and solving.
- `FEMWorkspace`: Central state container for all FEM operations.
- Entity types: Typed data containers for different geometric elements.
- Multi-phase workflow: Creation → Fragmentation → Identification → Assignment → Meshing → Solving → Post-processing.

### Extension to new modules

When creating new modules, the following patterns should be followed:

1. Define problem & formulation type (physics parameters).
2. Define solver type (execution parameters).
3. Define workspace type (state container).
4. Implement entity types specific to the domain.
5. Implement multi-phase workflow with clear separation.
6. Use the workspace pattern for state management.
7. Follow the standard data flow.

This framework ensures consistency, maintainability, and performance across all modules within the package.
