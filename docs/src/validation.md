# Validation module

This section documents the validation framework used by component constructors. The design is deterministic, non‑magical, and trait‑driven. The flow is:

```julia
sanitize(Type, args, kwargs)  →  parse(Type, nt)  →  apply rules  →  construct
```

The **typed cores** accept **numbers only**. All proxy handling happens in the **convenience constructors** via `validate!`.

---

## 1. Architecture

### 1.1 Pipeline

* **`sanitize(::Type{T}, args::Tuple, kwargs::NamedTuple)`**

  * Rejects wrong arities and enforces presence using `required_fields(T)`.
  * Maps optional keywords using `keyword_fields(T)`.
  * For `has_radii(T) == true`, checks admissibility of raw radius inputs with `is_radius_input(T, x)` (numbers by default; types may extend to allow proxies).
  * Returns a **raw** `NamedTuple`.

* **`parse(::Type{T}, nt)`**

  * Normalizes raw inputs to canonical representation (e.g., radius proxies → numeric radii) while preserving domain semantics (e.g., uncertainty reset rules).
  * Returns a **normalized** `NamedTuple`.

* **Rule application**

  * `_rules(T)` is generated from traits; evaluates over the normalized `NamedTuple`.
  * Standard bundles are injected when traits are `true` (e.g., for radii: `Normalized`, `Finite`, `Nonneg`, `Less`).
  * Per‑type extras come from `extra_rules(T)`.

* **`validate!(::Type{T}, args...; kwargs...)`**

  * Orchestrates the pipeline.
  * Converts `Base.Pairs` → `NamedTuple` once; do not pass `Pairs` to user extensions.

### 1.2 Traits (configuration surface)

* `has_radii(::Type{T})::Bool` — enables the radii rule bundle and raw acceptance checks.
* `has_temperature(::Type{T})::Bool` — enables finiteness check on `:temperature`.
* `required_fields(::Type{T})::NTuple` — positional keys.
* `keyword_fields(::Type{T})::NTuple` — keyword argument keys.
* `is_radius_input(::Type{T}, x)::Bool` — raw admissibility predicate for radii inputs; extend to allow proxies.
* `extra_rules(::Type{T})::NTuple{K,Rule}` — additional constraints appended to the generated bundle.

**Import before extending**:

```julia
import ..Validation: has_radii, has_temperature, required_fields, keyword_fields,
                     is_radius_input, parse, extra_rules
```

Failing to import will create shadow functions in your module; the engine will not see your methods.

---

## 2. Rules

Rules are small value types `struct <: Rule` with an `_apply(::Rule, nt, ::Type{T})` method. All rule methods must:

* Read data from the **normalized** `NamedTuple` `nt`.
* Throw `ArgumentError` for logical violations; `DomainError` for numerical domain violations (e.g., non‑finite).
* Avoid allocations; use `@inline` where appropriate.

### 2.1 Standard rules

* `Normalized(:field)` — field must be numeric post‑parse.
* `Finite(:field)` — `isfinite` must hold.
* `Nonneg(:field)` — value `≥ 0`.
* `Positive(:field)` — value `> 0`.
* `IntegerField(:field)` — value `isa Integer`.
* `Less(:a,:b)` — strict ordering `a < b`.
* `LessEq(:a,:b)` — non‑strict ordering `a ≤ b`.
* `IsA{M}(:field)` — type membership check.

### 2.2 Extending with custom rules (pattern)

```julia
struct InRange{T} <: Rule
    name::Symbol; lo::T; hi::T
end

@inline function Validation._apply(r::InRange, nt, ::Type{T}) where {T}
    x = getfield(nt, r.name)
    (x isa Number && !(x isa Complex)) || throw(ArgumentError("[$(String(nameof(T)))] $(r.name) must be real"))
    (r.lo ≤ x ≤ r.hi) || throw(ArgumentError("[$(String(nameof(T)))] $(r.name) out of range $(r.lo):$(r.hi), got $(x)"))
end
```

Attach via `extra_rules(::Type{X}) = (InRange(:alpha, 0.0, 1.0), ...)`.

---

## 3. Reverse tutorial — [`LineCableModels.DataModel.Tubular`](@ref)

**Typed core** (numbers only):

```julia
function Tubular(radius_in::T, radius_ext::T, material_props::Material{T}, temperature::T) where {T<:REALSCALAR}
```

Rationale: all proxy resolution must happen before reaching the typed core to avoid duplicate parsing and to keep type promotion deterministic.

**Trait configuration**:

```julia
const _REQ_TUBULAR = (:radius_in, :radius_ext, :material_props,)
const _OPT_TUBULAR = (:temperature,)
const _DEFS_TUBULAR = (T₀,)

Validation.has_radii(::Type{Tubular}) = true
Validation.has_temperature(::Type{Tubular}) = true
Validation.required_fields(::Type{Tubular}) = _REQ_TUBULAR
Validation.keyword_fields(::Type{Tubular}) = _OPT_TUBULAR
```

* `has_radii = true` enables the radii bundle: `Normalized(:radius_in)`, `Normalized(:radius_ext)`, `Finite`, `Nonneg`, `Less(:radius_in,:radius_ext)`.
* `has_temperature = true` adds `Finite(:temperature)`.
* `required_fields` defines the mandatory positional fields.
* `keyword_fields` defines the optional fields that will receive default values.

**Raw proxy acceptance**:

```julia
Validation.is_radius_input(::Type{Tubular}, ::Val{:radius_in}, x::AbstractCablePart) = true
Validation.is_radius_input(::Type{Tubular}, ::Val{:radius_ext}, x::Thickness) = true
```

Rationale: convenience constructors may accept layer objects or thickness/diameter wrappers; they are *raw* inputs and must be transformed.

**Extra rules**:

```julia
Validation.extra_rules(::Type{Tubular}) = (
    IsA{Material}(:material_props),)
```

* `IsA{Material}` enforces the material argument type.

**Parsing**:

```julia
Validation.parse(::Type{Tubular}, nt) = begin
    rin, rex = _normalize_radii(Tubular, nt.radius_in, nt.radius_ext)
    (; nt..., radius_in = rin, radius_ext = rex)
end
```

Rationale: centralizes radius proxy resolution and uncertainty semantics in one place. The output is numeric radii. After this step, the `Normalized` rules guarantee that rule checks run on numbers.

**Convenience constructor**:

```julia
function Tubular(radius_in, radius_ext, material_props; temperature = _DEFS_TUBULAR[1])
    ntv = validate!(Tubular, radius_in, radius_ext, material_props; temperature)
    T = resolve_T(ntv.radius_in, ntv.radius_ext, material_props, ntv.temperature)
    return Tubular(coerce_to_T(ntv.radius_in, T), coerce_to_T(ntv.radius_ext, T),
                   coerce_to_T(material_props, T), coerce_to_T(ntv.temperature, T))
end
```

Rationale: forces all user entry through `validate!`, then hands a coherent, type‑promoted set of values to the numeric core.

**Failure modes intentionally trapped**:

* Wrong arity, missing keys → `sanitize` via `required_fields`.
* String/complex radii → `sanitize` via default `is_radius_input` (unless explicitly allowed).
* Forgotten parsing after allowing proxies → caught by `Normalized` rules.
* Geometry violations (`radius_in ≥ radius_ext`) → `Less(:radius_in,:radius_ext)`.

---

## 4. Template for a New Component

Use the following checklist as a copy/paste starting point. Replace `NewPart` and fields accordingly.

```julia
# 1) Numeric core (numbers only)
function NewPart(a::T, b::T, material::Material{T}, temperature::T) where {T<:REALSCALAR}
    # compute derived quantities, then construct
end

# 2) Trait config
Validation.has_radii(::Type{NewPart}) = true            # if the type has radii
Validation.has_temperature(::Type{NewPart}) = true      # if temperature is used
Validation.field_order(::Type{NewPart}) = (:a, :b, :material)
Validation.required_fields(::Type{NewPart}) = (:a, :b, :material)

# 3) Raw acceptance (extend only what you intend to parse)
Validation.is_radius_input(::Type{NewPart}, x::AbstractCablePart) = true
Validation.is_radius_input(::Type{NewPart}, x::Thickness)        = true
Validation.is_radius_input(::Type{NewPart}, x::Diameter)         = true

# 4) Extra rules (append per‑type constraints)
Validation.extra_rules(::Type{NewPart}) = (
    IsA{Material}(:material),
    # InRange(:alpha, 0.0, 1.0), IntegerField(:num_wires), etc.
)

# 5) Parsing (proxy → numeric)
Validation.parse(::Type{NewPart}, nt) = begin
    a′, b′ = _normalize_radii(NewPart, nt.a, nt.b)
    (; nt..., a = a′, b = b′)
end

# 6) Convenience constructor — call validate!, then delegate to numeric core
function NewPart(a, b, material; temperature = T₀)
    ntv = validate!(NewPart, a, b, material; temperature)
    T = resolve_T(ntv.a, ntv.b, material, ntv.temperature)
    return NewPart(coerce_to_T(ntv.a, T), coerce_to_T(ntv.b, T),
                   coerce_to_T(material, T), coerce_to_T(ntv.temperature, T))
end
```

---

## 5. Extending Traits

Traits are just methods. Add traits only when behavior toggles; avoid proliferation.

### 5.1 New feature flags

Example: a shielding flag that enables a rule bundle for `:shield_thickness`.

```julia
# Trait
Validation.has_shield(::Type) = false
Validation.has_shield(::Type{SomeType}) = true

# Generated rule splice (in Validation, not per‑type)
#   Extend `_rules` to inject `(Nonneg(:shield_thickness), Finite(:shield_thickness))` when `has_shield(T)`.
```

### 5.2 New admissibility predicate

Example: accept `Symbol` values for a categorical option.

```julia
Validation.is_option(::Type{T}, x) where {T} = false           # default
Validation.is_option(::Type{X}, ::Symbol) where {X} = true      # for type X
```

Use in `sanitize` for key `:option` prior to parsing.

---

## 6. Testing guidelines

* Test arity: `()`, `(1)`, `(1,2)` → `ArgumentError`.
* Test raw type rejections: strings, complex numbers.
* Test proxy acceptance: prior layer objects, `Thickness`, `Diameter`.
* Test parse correctness: outputs are numeric and respect uncertainty rules.
* Test rule violations: negative radii, inverted radii, non‑finite values.
* Test constructor round‑trip: convenience path and numeric core produce equivalent instances after coercion.

---

## 7. Operational notes

* Keep all proxy handling in `parse`. Do not call normalizers in constructors.
* Keep error messages terse and contextualized with the component type name.
* Prefer tuple returns and `NamedTuple` updates for zero‑allocation pipelines.
* When adding rules, benchmark `_apply` methods; avoid dynamic dispatch inside rules.

---

This framework is designed to be extended in small, explicit increments. If behavior changes, change the trait and the minimal corresponding code; the rest of the pipeline remains stable.
