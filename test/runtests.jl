using LineCableModels
using Test
using TestItemRunner

@testsnippet defaults begin
    const TEST_TOL = 1e-8
    using Measurements
    using Measurements: measurement, uncertainty, value
    using DataFrames
end

@testsnippet defs_materials begin
    materials = MaterialsLibrary(add_defaults=true)
    copper_props = Material(1.7241e-8, 1.0, 1.0, 20.0, 0.00393)
    aluminum_props = Material(2.8264e-8, 1.0, 1.0, 20.0, 0.00429)
    insulator_props = Material(1e14, 2.3, 1.0, 20.0, 0.0)
    semicon_props = Material(1000.0, 1000.0, 1.0, 20.0, 0.0)
end

@run_package_tests verbose = true