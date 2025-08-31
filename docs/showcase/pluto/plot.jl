# Pluto plot demo using Plots.jl and PlutoUI

begin
    import Pkg
    try
        using PlutoUI, Plots
    catch
        Pkg.add(["PlutoUI","Plots"]) ; using PlutoUI, Plots
    end
end

md"""
# Pluto Plot Demo
Interactively change N and see the curve update.
"""

@bind N Slider(10:10:200, default=50)

x = 0:0.01:2π
y = @. sin(N * x) * exp(-0.2x)

plt = plot(x, y, lw=2, color=:cyan, bg=:transparent, legend=false,
           xlabel="x", ylabel="y", title="y = sin(Nx) * exp(-0.2x)")

plt

