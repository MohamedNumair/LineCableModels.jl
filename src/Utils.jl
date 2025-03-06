function _equals(x, y; atol = TOL)
	return isapprox(x, y, atol = atol)
end

function _to_nominal(x)
	return x isa Measurement ? Measurements.value(x) : x
end

function percent_to_uncertain(val, perc) #perc from 0 to 100
	measurement(val, (perc * val) / 100)
end

function bias_to_uncertain(nominal::Float64, measurements::Vector{<:Measurement})
	# Compute the mean value and uncertainty from the measurements
	mean_measurement = mean(measurements)
	mean_value = Measurements.value(mean_measurement)  # Central value
	sigma_mean = Measurements.uncertainty(mean_measurement)  # Uncertainty of the mean
	# Compute the bias (deterministic nominal value minus mean measurement)
	bias = abs(nominal - mean_value)
	return mean_value ± (sigma_mean + bias)
end

function _to_upper(m::Number)
	if m isa Measurement
		return Measurements.value(m) + Measurements.uncertainty(m)
	else
		return NaN
	end
end

function _to_lower(m::Number)
	if m isa Measurement
		return Measurements.value(m) - Measurements.uncertainty(m)
	else
		return NaN
	end
end

function _percent_error(m::Number)
	if m isa Measurement
		return 100 * Measurements.uncertainty(m) / Measurements.value(m)
	else
		return NaN
	end
end
