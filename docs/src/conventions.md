# Naming conventions

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