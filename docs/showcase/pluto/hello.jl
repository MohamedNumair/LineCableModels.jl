# Minimal Pluto demo: tweak N with a slider and recompute.
# This file can be opened by Pluto via Binder proxy.

begin
    import Pkg
    # Ensure PlutoUI is available when running on Binder
    try
        using PlutoUI
    catch
        Pkg.add("PlutoUI"); using PlutoUI
    end
end

md"""
# Pluto Demo (Hello)
Adjust N and recompute a couple of expressions.
"""

@bind N Slider(1:50, default=10)

md"N = $(N)"

sum_squares = sum(i^2 for i in 1:N)
prod_small  = prod(i for i in 1:5)

md"sum(i^2 for i in 1:N) = $(sum_squares)\n\nprod(i for i in 1:5) = $(prod_small)"

