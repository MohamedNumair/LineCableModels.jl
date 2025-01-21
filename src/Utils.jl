_equals(x, y; atol = TOL) = isapprox(x, y, atol = atol)
_to_nominal(x) = x isa Measurement ? Measurements.value(x) : x

function error_with_bias(nominal::Float64, measurements::Vector{<:Measurement})
	# Compute the mean value and uncertainty from the measurements
	mean_measurement = mean(measurements)
	mean_value = Measurements.value(mean_measurement)  # Central value
	sigma_mean = Measurements.uncertainty(mean_measurement)  # Uncertainty of the mean
	# Compute the bias (deterministic nominal value minus mean measurement)
	bias = abs(nominal - mean_value)
	return mean_value ± (sigma_mean + bias)
end

function ubound_error(m::Measurement)
	return Measurements.value(m) + Measurements.uncertainty(m)
end

function lbound_error(m::Measurement)
	return Measurements.value(m) - Measurements.uncertainty(m)
end

function percent_error(m::Measurement)
	return (Measurements.uncertainty(m) / Measurements.value(m)) * 100
end
