using LineCableModels
using Measurements

# Constants (should be defined in your package)
const REALSCALAR = Union{Float64,Measurement{Float64}}
const ε₀ = 8.854e-12
const μ₀ = 4π * 1e-7

# Prepare test data
freqs = [1e3, 1e4, 1e5]
freqs_m = measurement.(freqs, 0.1)
rho = 100.0
epsr = 10.0
mur = 1.0

result1 = calc_equivalent_alpha(0.5, 100.0, 0.8, measurement(200, 0.1))
println("Result: $result1\n")

# Test with Float64
cp = CPEarth()
rho_v, eps_v, mu_v = cp(freqs_m, rho, epsr, mur)
@assert rho_v == fill(rho, 3)
@assert mu_v == fill(μ₀ * mur, 3)
println("Result: $rho_v\n")

# Test with Measurement{Float64}
# freqs_m = measurement.(freqs, 0.1)
# rho_m = measurement(rho, 0.1)
# epsr_m = measurement(epsr, 0.1)
# mur_m = measurement(mur, 0.1)
# rho_v_m, eps_v_m, mu_v_m = cp(freqs_m, rho_m, epsr_m, mur_m)
# @assert all(x -> x ≈ rho_m, rho_v_m)
# @assert all(x -> x ≈ μ₀ * mur_m, mu_v_m)

# println("CPEarth functor with @parameterize signature works for all REALSCALAR.")