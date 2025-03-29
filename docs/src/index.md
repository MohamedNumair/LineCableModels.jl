# LineCableModels.jl

[`LineCableModels.jl`](https://github.com/Electa-Git/LineCableModels.jl) is a specialized Julia package designed to compute the electrical parameters of coaxial arbitrarily-layered underground/overhead cables with uncertainty quantification. It focuses on calculating line and cable impedances and admittances in the frequency-domain, accounting for skin effect, insulation properties, and earth-return impedances with frequency-dependent soil models.

## Documentation outline

```@contents
Pages = [
    "index.md",
    "tutorials.md",
    "reference.md",
    "bib.md",
]
Depth = 1
```

## Features

- Leverages the `Measurements.jl` package to accurately represent and properly propagate uncertainties associated to: cross-section information (horizontal/vertical coordinates), internal and external radii of each individual conductor and insulation layer (core/sheath/armor), electromagnetic properties of conductors, insulations and surrounding earth (conductivity, permittivity, permeability).
- Calculates all base DC parameters of a given cable design (R, L, C and G), for solid, tubular or stranded cores, semiconductors, screens, armors, sheaths, tapes,  and water-blocking materials.
- Correction factors to account for temperature, stranding and twisting effects on the DC resistance [app14198982](@cite), GMR [6521501](@cite) and base inductance of stranded cores and wire screens [yang2008gmr](@cite).
- Explicit computation of dielectric losses and effective resistances for insulators and semiconductors [916943](@cite). Correction of the magnetic constant of insulation layers to account for the solenoid effect introduced by twisted strands [5743045](@cite).
- Improved equivalent tubular representation for EMT simulations and direct export to PSCAD format.
- **(in progress)** Computes internal impedances of solid, tubular or coaxial multi-layered single-core (SC) cables, using rigorous [4113884](@cite) or equivalent approximate formulas available in [industry-standard EMT software](https://www.pscad.com/webhelp/EMTDC/Transmission_Lines/Deriving_System_Y_and_Z_Matrices.htm).
- **(in progress)** Computes earth-return impedances and admittances of underground conductors in homogeneous soil, based on a rigorous solution of Helmholtz equation on the electric Hertzian vector, valid up to 10 MHz [5437464](@cite). The expressions simplify to Pollaczek's solution if earth permittivity is set to zero.
- **(in progress)** Supports frequency-dependent soil properties.
- **(in progress)** Supports systems comprised by any number of phases with any number of conductors per phase, with or without Kron reduction.
- **(in progress)** Computes phase-domain Z/Y matrices for poliphase systems, and sequence-domain components for three-phase systems, with uncertainty propagation.
- **(in progress)** Includes a novel formulation for cables composed of N concentrical layers, allowing for accurate representations of semiconductor materials.
- General-purpose, reusable and customizable to different use cases via well-structured functions, object-oriented data model and user-defined parameters.

## Installation

Clone the package and add to the Julia environment:

```julia
] add https://github.com/Electa-Git/LineCableModels.jl
```

```julia
using LineCableModels
```

## License

The source code is provided under the [BSD 3-Clause License](https://github.com/Electa-Git/LineCableModels.jl/LICENSE).

---
```@raw html
<p align="left">Documentation generated using <a target="_blank" href="https://github.com/JuliaDocs/Documenter.jl">Documenter.jl</a> and <a target="_blank" href="https://github.com/fredrikekre/Literate.jl">Literate.jl</a>.</p>
```

 
