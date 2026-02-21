"""
    CyclicLoadProfile

Stores a 24-hour cyclic load profile and derived quantities for IEC 60853
cyclic rating calculations.

# Symbol Reference (IEC 60853-2)
- ``Y_i = (I_i / I_{max})^2``: Normalized loss-load ordinates
- ``\\mu = \\frac{1}{24}\\sum Y_i``: Loss-load factor
- ``N_h = 6``: Number of detailed hours before peak

# Fields
- `hourly_amperes`: 24 hourly current magnitudes [A]
- `I_max`: Peak current magnitude [A]
- `peak_hour`: 1-based index of the peak hour
- `Y`: 24 normalized loss-load ordinates
- `mu`: Loss-load factor μ
- `Y_Nh`: 6 loss-load ordinates for the hours preceding the peak;
  `Y_Nh[1]` = peak hour (always 1.0), `Y_Nh[6]` = 5 h before peak
"""
struct CyclicLoadProfile
    hourly_amperes::Vector{Float64}
    I_max::Float64
    peak_hour::Int
    Y::Vector{Float64}
    mu::Float64
    Y_Nh::Vector{Float64}

    function CyclicLoadProfile(currents::Vector{Float64})
        n = length(currents)
        @assert n == 24 "Load profile must have exactly 24 hourly values, got $n"

        I_max = maximum(currents)
        @assert I_max > 0 "Maximum current must be positive"

        peak_hour = argmax(currents)
        Y = (currents ./ I_max) .^ 2
        mu = sum(Y) / n

        # Extract N_h = 6 hourly ordinates ending at peak.
        # Y_Nh[1] = Y_0 = peak hour (most recent, always 1.0)
        # Y_Nh[k] = Y_{k-1} = (k-1) hours before peak
        N_h = 6
        Y_Nh = Vector{Float64}(undef, N_h)
        for k in 1:N_h
            idx = mod1(peak_hour - (k - 1), 24)
            Y_Nh[k] = Y[idx]
        end

        return new(currents, I_max, peak_hour, Y, mu, Y_Nh)
    end
end

"""
    load_cyclic_profile(filepath::String) -> CyclicLoadProfile

Read a CSV file containing a 24-hour load profile and return a
[`CyclicLoadProfile`](@ref).  The CSV must have 24 data rows; on each row the
current value is taken as the **last** comma-separated field.  Header lines
starting with `#` and blank lines are skipped.
"""
function load_cyclic_profile(filepath::String)
    lines = readlines(filepath)
    currents = Float64[]
    for line in lines
        line = strip(line)
        isempty(line) && continue
        startswith(line, '#') && continue
        parts = split(line, ',')
        push!(currents, parse(Float64, strip(parts[end])))
    end
    return CyclicLoadProfile(currents)
end
