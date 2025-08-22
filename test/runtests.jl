using LineCableModels
using Test
using TestItemRunner

@testsnippet defaults begin
    const TEST_TOL = 1e-8
    using Measurements
    using Measurements: measurement, uncertainty, value
    using DataFrames
end

@run_package_tests