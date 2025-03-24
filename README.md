# LineCableModels.jl

<img src="docs/src/assets/logo.svg" align="left" width="150">

[![Build Status](https://github.com/Electa-Git/LineCableModels.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/Electa-Git/LineCableModels.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![License](https://img.shields.io/badge/License-BSD%203--Clause-blue.svg)](https://opensource.org/licenses/BSD-3-Clause)

`LineCableModels.jl` is a Julia package for computing the electrical parameters of arbitrary arrangements of underground and overhead power cables, with built-in uncertainty quantification. It is designed as a general-purpose and scalable toolbox to calculate transmission line parameters and to construct models for steady-state analysis and electromagnetic transient (EMT) simulations. 
  

## Main features

- Models power cable geometries with uncertainty quantification using `Measurements.jl`.
- Calculates DC and AC electrical parameters (R, L, C, G) for various conductor types.
- Provides detailed representation of all cable components: including semiconductors, screens, armoring, insulators, tapes, and water-blocking materials.
- Supports temperature, twisting, and stranding corrections for accurate simulations.
- Offers both internal impedance/admittance calculation and PSCAD export capabilities.
- Implements rigorous electromagnetic formulations for cable and earth-return impedances.
- Features extensible, object-oriented design with customizable parameters.

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

While the package documentation is a work in progress, a self-contained example is provided in the [`Main.jl`](Main.jl) file. This code demonstrates how to create a cable object, and compute its electrical parameters. The example also shows how to export the cable design to a PSCAD-compatible format.

## License

The source code is provided under the [BSD 3-Clause License](LICENSE).

## Acknowledgements

This work is supported by the Etch Competence Hub of EnergyVille, financed by the Flemish Government. The primary developer is Amauri Martins ([@amaurigmartins](https://github.com/amaurigmartins)).

<p align = "left">
  <p><br><img src="assets/img/etch_logo.png" width="150"></p>
  <p><img src="assets/img/energyville_logo.png" width="150"></p>
  <p><img src="assets/img/kul_logo.png" width="150"></p>
</p>
