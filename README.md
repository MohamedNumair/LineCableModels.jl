# LineCableModels.jl

<img src="docs/src/assets/logo.svg" align="left" width="150" alt="LineCableModels.jl logo" />

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://electa-git.github.io/LineCableModels.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://electa-git.github.io/LineCableModels.jl/dev/)
[![codecov](https://codecov.io/gh/Electa-Git/LineCableModels.jl/branch/main/graph/badge.svg?token=2Q0X1G3Z5A)](https://codecov.io/gh/Electa-Git/LineCableModels.jl)

[![Build Status](https://github.com/Electa-Git/LineCableModels.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/Electa-Git/LineCableModels.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![License](https://img.shields.io/badge/License-BSD%203--Clause-blue.svg)](https://opensource.org/licenses/BSD-3-Clause)

`LineCableModels.jl` is a Julia package for computing the electrical parameters of arbitrary arrangements of underground and overhead power cables, with built-in uncertainty quantification. It is designed as a general-purpose and scalable toolbox to calculate transmission line parameters and to construct models for steady-state analysis and electromagnetic transient (EMT) simulations.
  
## Main features

- **Comprehensive cable modeling:** Detailed representation of conductors (solid, tubular, stranded), insulation layers, screens, armoring, and semicons.
- **Line and cable constants:** Accurate DC and AC parameters (R, L, C, G) with correction factors for temperature, stranding, and helical effects.
- **Propagation characteristics:** Rigorous electromagnetic models for cable internal impedances and earth-return paths.
- **Multiple solvers:** Analytical formulations, finite element modeling, and interfaces to EMT programs, including PSCAD.
- **Materials and cables library:** Store and reuse standardized material properties and cable designs across projects.

## Documentation

See the [full documentation](https://electa-git.github.io/LineCableModels.jl/stable/) for detailed usage instructions, technical background, and examples.

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
  <p><br><img src="assets/img/etch_logo.png" width="150" alt="Etch logo"></p>
  <p><img src="assets/img/energyville_logo.png" width="150" alt="EV logo"></p>
  <p><img src="assets/img/kul_logo.png" width="150" alt="KUL logo"></p>
</p>
