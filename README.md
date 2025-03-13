# LineCableModels.jl

[![Build Status](https://github.com/Electa-Git/LineCableModels.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/Electa-Git/LineCableModels.jl/actions/workflows/CI.yml?query=branch%3Amain)

`LineCableModels.jl` is a specialized Julia module designed to compute the electrical parameters of coaxial arbitrarily-layered underground/overhead cables with uncertainty quantification. It focuses on calculating line and cable impedances and admittances in the frequency-domain, accounting for skin effect, insulation properties, and earth-return impedances with frequency-dependent soil models. The toolbox allows engineers and researchers to simulate and analyze the performance of power cables under various conditions, with the added ability to propagate uncertainties in cable geometries, material properties, and environmental parameters. Moreover,  both rigorous and simplified formulas are available, providing flexibility and compatibility with other frameworks developed within Etch.

## Highlight of the main features

| ![Cable-Light](assets/img/cable_dark_mode.svg#gh-dark-mode-only)![Cable-Dark](assets/img/cable_light_mode.svg#gh-light-mode-only) | 
|:--:| 
| **Fig. 1 - Cross-section representation of a cable composed of core, sheath and armor and its uncertain characteristics.** |

- Leverages the `Measurements.jl` package to accurately represent and properly propagate uncertainties associated to: cross-section information (horizontal/vertical coordinates), internal and external radii of each individual conductor and insulation layer (core/sheath/armor), electromagnetic properties of conductors, insulations and surrounding earth (conductivity, permittivity, permeability).
- Calculates all base DC parameters of a given cable design (R, L, C and G), for solid, tubular or stranded cores, semiconductors, screens, armors, sheaths, tapes,  and water-blocking materials.
- Correction factors to account for temperature, stranding and twisting effects on the DC resistance ([10.3390/app14198982](https://www.mdpi.com/2076-3417/14/19/8982)), GMR ([10.1109/TPWRD.2012.2213617](https://ieeexplore.ieee.org/document/6521501)) and base inductance of stranded cores and wire screens ([Proc. AsiaPES](https://www.actapress.com/Abstract.aspx?paperId=33058)).
- Explicit computation of dielectric losses and effective resistances for insulators and semiconductors ([10.1109/PESW.2001.916943](https://ieeexplore.ieee.org/document/916943)). Correction of the magnetic constant of insulation layers to account for the solenoid effect introduced by twisted strands ([10.1109/TPWRD.2010.2084600](https://ieeexplore.ieee.org/document/5743045)).
- Improved equivalent tubular representation for EMT simulations and direct export to PSCAD format.
- **(in progress)** Computes internal impedances of solid, tubular or coaxial multi-layered single-core (SC) cables, using rigorous ([10.1109/TPAS.1980.319718](https://ieeexplore.ieee.org/document/4113884)) or equivalent approximate formulas available in [industry-standard EMT software](https://www.pscad.com/webhelp/EMTDC/Transmission_Lines/Deriving_System_Y_and_Z_Matrices.htm).
- **(in progress)** Computes earth-return impedances and admittances of underground conductors in homogeneous soil, based on a rigorous solution of Helmholtz equation on the electric Hertzian vector, valid up to 10 MHz ([10.1109/TPWRD.2009.2034797](https://ieeexplore.ieee.org/abstract/document/5437464)). The expressions simplify to Pollaczek's solution if earth permittivity is set to zero.
- **(in progress)** Supports frequency-dependent soil properties.
- **(in progress)** Supports systems comprised by any number of phases with any number of conductors per phase, with or without Kron reduction.
- **(in progress)** Computes phase-domain Z/Y matrices for poliphase systems, and sequence-domain components for three-phase systems, with uncertainty propagation.
- **(in progress)** Includes a novel formulation for cables composed of N concentrical layers, allowing for accurate representations of semiconductor materials.
- General-purpose, reusable and customizable to different use cases via well-structured functions, object-oriented data model and user-defined parameters.

## Formulation

An overview of the methods implemented in `LineCableModels.jl` is given in the document titled [Cable modeling for assessment of uncertainties](https://www.overleaf.com/read/xhmvbjgdqjxn#5e6f69).

## Usage

Clone the package and add to the Julia environment:

```julia
] add https://github.com/Electa-Git/LineCableModels.jl.git
```

```julia
using LineCableModels
```

While the package documentation is a work in progress, a self-contained example is provided in the [Main.jl](Main.jl) file. This code demonstrates how to create a cable object, and compute its electrical parameters. The example also shows how to export the cable design to a PSCAD-compatible format.

## License

The source code is provided under the [BSD 3-Clause License](LICENSE).

## Acknowledgements

This work is supported by the Etch Competence Hub of EnergyVille, financed by the Flemish Government. The primary developer is Amauri Martins ([@amaurigmartins](https://github.com/amaurigmartins)).

<p align="center">
  <img src="assets/img/etch_logo.png" width="150">&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
  <img src="assets/img/energyville_logo.png" width="150">&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
  <img src="assets/img/kul_logo.png" width="150">
</p>

