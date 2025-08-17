using LineCableModels
using Test

@testset "LineCableModels.jl tests" begin
    @info "Running BaseParams tests..."
    @testset "BaseParams module" begin
        include("baseparams.jl")
    end
    @info "BaseParams tests completed."

    @testset "DataModel module 1/1" begin
        include("datamodel.jl")
    end
    @info "DataModel tests completed."

    @testset "EarthProps module" begin
        include("earthprops.jl")
    end
    @info "EarthProps tests completed."

    @testset "Integration tests based on example files" begin
        exa_files = ["test_tutorial1.jl", "test_tutorial2.jl", "test_tutorial3.jl"]
        for f in exa_files
            include(f)
        end
    end

    @info "Tutorials tests completed."

    @info "All tests completed."
end
