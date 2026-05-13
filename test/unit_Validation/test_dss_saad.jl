@testitem "DSS Saad implementation" setup = [defaults] begin
    using SpecialFunctions: besselk

    function build_single_core_design()
        materials = MaterialsLibrary(add_defaults = true)
        conductor_material = get(materials, "aluminum")
        insulation_material = get(materials, "pe")

        core = ConductorGroup(WireArray(0.0, Diameter(0.02), 1, 0.0, conductor_material))
        insulation = InsulatorGroup(Insulator(core, Thickness(0.01), insulation_material))
        component = CableComponent("core", core, insulation)

        return CableDesign("saad_test_cable", component)
    end

    function build_parallel_problem()
        cable_design = build_single_core_design()

        cablepos = CablePosition(cable_design, 0.0, -1.0, Dict("core" => 1))
        cable_system = LineCableSystem("saad_test_system", 1000.0, cablepos)
        add!(cable_system, cable_design, 0.3, -2.0, Dict("core" => 2))

        earth = EarthModel([50.0], 100.0, 1.0, 1.0)

        problem = LineParametersProblem(cable_system;
            temperature = 20.0,
            earth_props = earth,
            frequencies = [50.0],
        )

        formulation = LineCableModels.Engine.FormulationSet(:DSS,
            internal_impedance = LineCableModels.Engine.SimpleCarson(),
            earth_impedance = LineCableModels.Engine.Saad(),
        )

        return problem, formulation
    end

    @testset "workspace captures insulation radius" begin
        problem, formulation = build_parallel_problem()
        ws = LineCableModels.Engine.init_workspace(problem, formulation)

        @test ws.r_ext ≈ [0.01, 0.01]
        @test ws.r_ins_ext ≈ [0.02, 0.02]
        @test ws.vert ≈ [-1.0, -2.0]
    end

    @testset "Saad formula matches Ametani geometry" begin
        problem, formulation = build_parallel_problem()
        ws = LineCableModels.Engine.init_workspace(problem, formulation)

        ω = 2π * ws.freq[1]
        μ₀ = 4π * 1e-7
        γ₁ = sqrt(1im * ω * μ₀ / ws.rho_g[2, 1])

        z_self = LineCableModels.Engine.get_Ze(ws, 1, 1, 1, LineCableModels.Engine.Saad())
        expected_self = (1im * ω * μ₀) / (2 * π) * (
            besselk(0, γ₁ * ws.r_ins_ext[1]) +
            2 * exp(-2 * abs(ws.vert[1]) * γ₁) / (4 + γ₁^2 * ws.r_ins_ext[1]^2)
        )
        @test z_self ≈ expected_self atol = 1e-12 rtol = 1e-12

        z_mutual = LineCableModels.Engine.get_Ze(ws, 1, 2, 1, LineCableModels.Engine.Saad())
        h_sep = abs(ws.horz[1] - ws.horz[2])
        expected_mutual = (1im * ω * μ₀) / (2 * π) * (
            besselk(0, γ₁ * h_sep) +
            2 * exp(-(abs(ws.vert[1]) + abs(ws.vert[2])) * γ₁) / (4 + γ₁^2 * h_sep^2)
        )
        @test z_mutual ≈ expected_mutual atol = 1e-12 rtol = 1e-12
    end

    @testset "Saad path does not add OpenDSS spacing" begin
        problem, formulation = build_parallel_problem()
        ws = LineCableModels.Engine.init_workspace(problem, formulation)

        Ztmp = Matrix{ComplexF64}(undef, ws.n_phases, ws.n_phases)
        LineCableModels.Engine.compute_impedance_matrix!(Ztmp, ws, 1, formulation)

        z11 = LineCableModels.Engine.get_Zint(ws, 1, 1, LineCableModels.Engine.SimpleCarson()) +
              LineCableModels.Engine.get_Ze(ws, 1, 1, 1, LineCableModels.Engine.Saad())
        z22 = LineCableModels.Engine.get_Zint(ws, 2, 1, LineCableModels.Engine.SimpleCarson()) +
              LineCableModels.Engine.get_Ze(ws, 2, 2, 1, LineCableModels.Engine.Saad())
        z12 = LineCableModels.Engine.get_Ze(ws, 1, 2, 1, LineCableModels.Engine.Saad())

        @test Ztmp[1, 1] ≈ z11 atol = 1e-12 rtol = 1e-12
        @test Ztmp[2, 2] ≈ z22 atol = 1e-12 rtol = 1e-12
        @test Ztmp[1, 2] ≈ z12 atol = 1e-12 rtol = 1e-12
        @test Ztmp[2, 1] ≈ z12 atol = 1e-12 rtol = 1e-12

        _, line_params = compute!(problem, formulation)
        @test line_params.Z[:, :, 1] ≈ Ztmp atol = 1e-12 rtol = 1e-12
    end
end