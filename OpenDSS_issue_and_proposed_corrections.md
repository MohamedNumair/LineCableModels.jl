# OpenDSS Series Impedance Issues and Proposed Corrections

**Prepared by:** LineCableModels.jl Development Team  
**Date:** May 2026  
**Relates to:** OpenDSS line-impedance formation for underground cables and overhead conductors  
**Repository context:** [`Electa-Git/LineCableModels.jl`](https://github.com/Electa-Git/LineCableModels.jl), branch `integration/sector-fem-dss`

---

## Background

When implementing and validating the DSS-formulation impedance engine in `LineCableModels.jl` — which replicates and extends the Carson/Deri/Saad family of line-impedance models used by OpenDSS — two systematic errors were identified in how OpenDSS constructs the series impedance matrix. Both errors stem from the same root cause: the **Geometric Mean Radius (GMR) conflation** between (a) an encoding of internal magnetic-flux linkage and (b) a pure external-field self-distance. When the total impedance is decomposed into explicitly-computed internal and external components, using GMR for the external self-distance produces a **double-counted internal reactance**.

The issues are described below with full mathematical derivations, references to the affected code paths, quantitative impact, and proposed corrections.

---

## Issue 1 — GMR Double-Counting in the Self-Term of the External Inductance

### 1.1 The Physical Setup

The per-unit-length series impedance of conductor $i$ is conventionally decomposed as:

$$Z_{ii} = Z_{\text{int},i} + Z_{\text{ext},ii} + Z_{\text{earth},ii} \tag{1}$$

where

- $Z_{\text{int},i}$ is the internal impedance (skin-effect-corrected resistance plus internal reactance from flux inside the conductor body),
- $Z_{\text{ext},ii}$ is the reactance from the external magnetic field between the conductor surface and the earth-return reference (self-spacing term),
- $Z_{\text{earth},ii}$ is the earth-return correction (Carson, Deri, or Saad/Pollaczek integral).

### 1.2 The GMR Definition

For a solid or tubular conductor of physical outer radius $r$ with relative permeability $\mu_r$, the Geometric Mean Radius is defined as:

$$\text{GMR} = r \cdot e^{-\mu_r / 4} \tag{2}$$

Taking the natural logarithm:

$$\ln\!\left(\frac{1}{\text{GMR}}\right) = \ln\!\left(\frac{1}{r}\right) + \frac{\mu_r}{4} \tag{3}$$

### 1.3 The Double-Counting Mechanism

The external self-spacing term uses the self-distance $d_{\text{self}}$ in the denominator of the flux-linkage integral:

$$Z_{\text{ext},ii} = \frac{j\omega\mu_0}{2\pi} \ln\!\left(\frac{1}{d_{\text{self},i}}\right) \tag{4}$$

When **OpenDSS substitutes $d_{\text{self},i} = \text{GMR}$**, equation (3) gives:

$$Z_{\text{ext},ii}^{\text{OpenDSS}} = \frac{j\omega\mu_0}{2\pi} \ln\!\left(\frac{1}{r}\right) + \underbrace{\frac{j\omega\mu_0}{2\pi} \cdot \frac{\mu_r}{4}}_{\displaystyle = \frac{j\omega\mu_0\mu_r}{8\pi}} \tag{5}$$

The second term, $j\omega\mu_0\mu_r/(8\pi)$, is precisely the **low-frequency internal reactance** of a solid conductor. It is also the imaginary part returned by the explicitly-computed internal impedance $Z_{\text{int},i}$:

$$\text{Im}\!\left(Z_{\text{int},i}\right) = \frac{\omega\mu_0\mu_r}{8\pi} \quad (\text{low-frequency limit}) \tag{6}$$

When $Z_{\text{int},i}$ is computed separately (via Bessel functions in the Deri/Saad model, or via the closed-form approximation $R_{\text{ac}} + j\omega\mu_0/8\pi$ for SimpleCarson/FullCarson) **and** GMR is also used in equation (4), the internal reactance enters the total impedance twice:

$$Z_{ii}^{\text{OpenDSS, error}} = \underbrace{Z_{\text{int},i}}_{\ni\; j\omega\mu_0\mu_r/8\pi} + \underbrace{Z_{\text{ext},ii}^{\text{OpenDSS}}}_{\ni\; j\omega\mu_0\mu_r/8\pi} + Z_{\text{earth},ii}$$

$$\Rightarrow \quad Z_{ii}^{\text{error}} = Z_{ii}^{\text{correct}} + \frac{j\omega\mu_0\mu_r}{8\pi} \tag{7}$$

### 1.4 Quantitative Impact

For a conductor with $\mu_r = 1$ (copper or aluminium) at 50 Hz:

$$\Delta Z = \frac{j \cdot 2\pi \cdot 50 \cdot 4\pi \times 10^{-7}}{8\pi} \approx j\,3.14 \;\mu\Omega/\text{m}$$

While small at 50 Hz, this systematic bias is **frequency-proportional** ($\Delta Z \propto f$) and applies independently to every phase conductor. At 1 kHz the error reaches $\approx j\,62.8\;\mu\Omega/\text{m}$. For magnetic conductors ($\mu_r \gg 1$, e.g., steel-armoured cables) the error scales linearly with $\mu_r$.

Additionally, because the error enters only the **diagonal** self-terms, it inflates the diagonal of the impedance matrix and therefore corrupts the computed **sequence impedances** (positive-, negative-, and zero-sequence). The zero-sequence is most sensitive because it involves the phase-to-earth return path where $Z_{\text{earth},ii}$ dominates and any systematic error in $Z_{\text{ext},ii}$ has proportionally larger impact.

### 1.5 Affected Code Path in OpenDSS

The error occurs in the formation of the diagonal self-term when the Carson or Deri earth-return model is used together with a separately-computed internal impedance. The GMR is passed as the self-distance in the $\ln(1/d_{\text{self}})$ term.

### 1.6 Proposed Correction

Replace the GMR with the **physical outer conductor radius $r$** in the external self-spacing term:

$$\boxed{Z_{\text{ext},ii}^{\text{correct}} = \frac{j\omega\mu_0}{2\pi} \ln\!\left(\frac{1}{r}\right)} \tag{8}$$

The GMR encoding of internal inductance is appropriate **only** when $Z_{\text{int}}$ is *not* computed as an independent term (i.e., in the original combined Carson formulation). When the three components of equation (1) are computed separately, the external self-distance must be the physical conductor radius.

**Implementation in LineCableModels.jl** (`src/engine/dss_solver.jl`, function `get_Zspacing`):
```julia
# CORRECTED: use ws.r_self[i] (physical outer radius for solid/tubular/sector),
# NOT ws.gmr[i] which encodes internal flux and causes double-counting when
# Z_int is also computed explicitly.
return 1im * ω * μ₀ / (2.0 * π) * log(1.0 / ws.r_self[i])
```

---

## Issue 2 — Same Double-Counting in the Deri Combined External+Earth Self-Term

### 2.1 Context

The Deri model computes the external-field and earth-return contributions as a **single combined term** (eliminating the need for a separate $Z_{\text{ext},ii}$):

$$Z_{\text{ext+earth},ii}^{\text{Deri}} = \frac{j\omega\mu_0}{2\pi} \ln\!\left(\frac{S_{ii}}{d_{\text{self},i}}\right) \tag{9}$$

where $S_{ii} = 2(h_i + D_e)$, $h_i$ is the conductor depth below ground, and $D_e = 1/\gamma_e$ is the Deri complex earth-return depth with $\gamma_e = \sqrt{j\omega\mu_0/\rho_g}$ (Ametani, 2021, §2.5.3, eq. 2.27–2.28).

### 2.2 The Error

When OpenDSS evaluates equation (9) using $d_{\text{self},i} = \text{GMR}$:

$$\ln\!\left(\frac{S_{ii}}{\text{GMR}}\right) = \ln\!\left(\frac{S_{ii}}{r}\right) + \frac{\mu_r}{4} \tag{10}$$

The $\mu_r/4$ term again introduces $j\omega\mu_0\mu_r/(8\pi)$ in the combined Deri impedance. When $Z_{\text{int},i}^{\text{Deri}}$ is also computed explicitly (using the Bessel-function quotient $\frac{1}{2}\alpha_i R_{\text{dc}} I_0(\alpha_i)/I_1(\alpha_i)$, where $\alpha_i = \sqrt{j\omega\mu_0/(\pi R_{\text{dc}})}$, which correctly captures the full skin-effect internal impedance at any frequency), the internal reactance is double-counted by the same mechanism as Issue 1.

### 2.3 Proposed Correction

Use the physical conductor radius $r$ (not GMR) in the denominator of equation (9):

$$\boxed{Z_{\text{ext+earth},ii}^{\text{Deri, correct}} = \frac{j\omega\mu_0}{2\pi} \ln\!\left(\frac{2(h_i + D_e)}{r_i}\right)} \tag{11}$$

**Implementation in LineCableModels.jl** (`src/engine/dss_solver.jl`, function `get_Ze(::DeriModel)`):
```julia
# CORRECTED: ws.r_self[i] is the physical outer radius (or physical bundle GMR
# for multi-wire WireArrays). Using GMR would add mu_r/4 to the log argument,
# which equals j*ω*μ₀*μr/(8π) — already included in get_Zint(::DeriModel)
# via the Bessel-function quotient.
S = 2.0 * (abs(ws.vert[i]) + D_e)
ln_arg = S / ws.r_self[i]
```

---

## Issue 3 — Incorrect Self-Distance for Stranded (WireArray) Conductors

### 3.1 Background

For a stranded conductor consisting of $N$ wires of physical radius $r_w$, equally distributed on a lay circle of radius $R_{\text{lay}} = r_{\text{in}} + r_w$, the correct **physical self-distance** (geometric mean of all self- and mutual distances between wire filaments, without internal-flux correction) is given by (Rosa, 1908):

$$r_{\text{self}}^{\text{bundle}} = \exp\!\left(\frac{\ln r_w + \ln N + (N-1)\ln R_{\text{lay}}}{N}\right) = \left(r_w \cdot N \cdot R_{\text{lay}}^{N-1}\right)^{1/N} \tag{12}$$

### 3.2 The Error in OpenDSS

OpenDSS (and many implementations following Kersting, 2012) uses the **bundle GMR** instead:

$$\text{GMR}^{\text{bundle}} = \left(\text{GMR}_w \cdot N \cdot R_{\text{lay}}^{N-1}\right)^{1/N} = \left(r_w e^{-\mu_r/4} \cdot N \cdot R_{\text{lay}}^{N-1}\right)^{1/N} \tag{13}$$

where $\text{GMR}_w = r_w \cdot e^{-\mu_r/4}$ is the GMR of a single wire. Comparing equations (12) and (13):

$$\text{GMR}^{\text{bundle}} = r_{\text{self}}^{\text{bundle}} \cdot e^{-\mu_r/4} \tag{14}$$

So the bundle GMR encodes the same $e^{-\mu_r/4}$ internal-flux factor as a solid conductor. Substituting into equation (4):

$$Z_{\text{ext},ii}^{\text{OpenDSS, stranded}} = \frac{j\omega\mu_0}{2\pi} \ln\!\left(\frac{1}{\text{GMR}^{\text{bundle}}}\right) = \frac{j\omega\mu_0}{2\pi} \ln\!\left(\frac{1}{r_{\text{self}}^{\text{bundle}}}\right) + \frac{j\omega\mu_0\mu_r}{8\pi}$$

Again producing the same double-counting error as Issue 1.

### 3.3 Additional Impact: Conflict with the Capacitance Calculation

The outer conductor **envelope** radius $r_{\text{ext}} = r_{\text{in}} + 2 r_w$ (the physical outer boundary of the bundle) must be used for the potential-coefficient matrix (shunt capacitance):

$$P_{ii} = \frac{1}{2\pi\varepsilon_0} \ln\!\left(\frac{2 h_i}{r_{\text{ext},i}}\right) \tag{15}$$

If the bundle GMR is stored as the conductor radius and reused in equation (15), it **underestimates the conductor size** seen by the electric field, leading to a systematically high shunt capacitance. The self-distance for inductance (equation 12) and the outer radius for capacitance (equation 15) are distinct physical quantities and must be stored and used separately.

### 3.4 Proposed Correction

Use the **physical bundle GMR** (equation 12) — without the $e^{-\mu_r/4}$ internal-flux factor — as the self-distance in the impedance calculation, and preserve the outer conductor envelope radius for the capacitance calculation:

$$\boxed{d_{\text{self},i}^{\text{impedance}} = \left(r_w \cdot N \cdot R_{\text{lay}}^{N-1}\right)^{1/N}} \quad \text{(for impedance)} \tag{16}$$

$$\boxed{d_{\text{self},i}^{\text{capacitance}} = r_{\text{ext}} = r_{\text{in}} + 2 r_w} \quad \text{(for capacitance)} \tag{17}$$

**Implementation in LineCableModels.jl** (`src/engine/workspace.jl`, `init_workspace`):
```julia
if layers[1] isa WireArray{T} && layers[1].num_wires > 1
    wa = layers[1]
    R_lay = T(wa.radius_in + wa.radius_wire)   # lay radius
    N     = wa.num_wires
    r_w   = T(wa.radius_wire)
    # Physical bundle GMR — no exp(-μr/4), so internal reactance is NOT baked in.
    r_self[idx] = exp((log(r_w) + log(N) + (N - 1) * log(R_lay)) / N)
else
    # Tubular, Sector, single-wire WireArray: physical outer radius is correct.
    r_self[idx] = T(component.conductor_group.radius_ext)
end
# r_ext[idx] is kept as the physical outer envelope for the capacitance matrix (P).
```

A dedicated `r_self` field is introduced in the workspace to separate the two uses, ensuring `r_ext` remains the physical outer conductor boundary for capacitance calculations.

---

## Summary Table

| # | Location in OpenDSS | Mathematical Error | Effect on Impedance | Proposed Fix |
|---|---|---|---|---|
| 1 | `get_Zspacing` self-term (Carson/FullCarson) | Uses GMR where physical radius $r$ is required; adds $j\omega\mu_0\mu_r/(8\pi)$ to self-term | Diagonal overestimated by $j\omega\mu_0\mu_r/(8\pi)$; corrupts sequence impedances | Replace GMR with physical outer radius $r$ in $\ln(1/d_{\text{self}})$ |
| 2 | Deri self-term $\ln(S_{ii}/d_{\text{self}})$ | Same root cause as Issue 1, but within the combined external+earth term | Same diagonal error; magnified at high frequency by frequency-proportional scaling | Replace GMR with physical outer radius $r$ in Deri self-term denominator |
| 3 | Stranded bundle (WireArray) self-distance | Bundle GMR includes $e^{-\mu_r/4}$ per wire; same double-counting when $Z_{\text{int}}$ is explicit | Diagonal overestimated; additionally, if stored radius is also used for capacitance, shunt $Y$ is overestimated | Separate impedance self-distance (physical bundle GMR, eq. 12) from capacitance outer radius (eq. 17) |

---

## References

- E. B. Rosa, "The self and mutual inductances of linear conductors," *Bulletin of the Bureau of Standards*, 1908. (Physical bundle GMR formula for $N$-wire arrays.)
- A. Ametani, H. Xue, T. Ohno, and H. Khalilnezhad, *Electromagnetic Transients in Large HV Cable Networks: Modeling and Calculations*. Institution of Engineering and Technology, 2021. doi: [10.1049/PBPO204E](https://doi.org/10.1049/PBPO204E). §2.5.3, eqs. 2.27–2.28. (Deri combined formula and complex earth-return depth $D_e$.)
- W. H. Kersting, *Distribution System Modeling and Analysis*. CRC Press. §4.3–4.4. (Carson equations and GMR usage in distribution line modelling.)
- R. C. Dugan, "Reference guide: The open distribution system simulator (OpenDSS)," EPRI. (OpenDSS implementation reference.)
