using LineCableModels
using Test
using TestItemRunner

@testsnippet commons begin
    const TEST_TOL = 1e-8
    using Measurements
    using Measurements: measurement, uncertainty, value
    using DataFrames

end

@run_package_tests

# @testset "LineCableModels.jl tests" begin
#     @info "Running BaseParams tests..."
#     @testitem "BaseParams module" begin
#         include("baseparams.jl")
#     end
#     @info "All tests completed."
# end

# @testset "LineCableModels.jl tests" begin
#     @info "Running BaseParams tests..."
#     @testitem "BaseParams module" begin
#         include("baseparams.jl")
#         for file in sort(filter(f -> endswith(f, ".jl"), readdir("test/unit_BaseParams", join=true)))
#             include(file)
#         end
#         @info "BaseParams tests completed."
#     end


#     @testitem "DataModel module 1/1" begin
#         include("datamodel.jl")
#         @info "DataModel tests completed."
#     end

#     @testitem "EarthProps module" begin
#         include("earthprops.jl")
#         @info "EarthProps tests completed."

#     end

#     @testitem "Integration tests based on example files" begin
#         exa_files = ["test_tutorial1.jl", "test_tutorial2.jl", "test_tutorial3.jl"]
#         for f in exa_files
#             include(f)
#         end
#         @info "Tutorials tests completed."
#     end

#     @info "All tests completed."
# end
