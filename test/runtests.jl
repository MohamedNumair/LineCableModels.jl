using LineCableModels
using Test

@testset "LineCableModels.jl tests" begin
	@info "Running BaseParams tests..."
	@testset "BaseParams module" begin
		# This line executes all the tests defined in baseparams.jl
		include("baseparams.jl")
	end
	@info "BaseParams tests completed."

	@info "All tests completed."
end
