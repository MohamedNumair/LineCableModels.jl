@testitem "examples/tutorial2_sector.jl tests" setup = [defaults] begin
    # Replicate the setup from the tutorial

    # === Materials ===
    materials = MaterialsLibrary(add_defaults=true)
    pvc = Material(Inf, 8.0, 1.0, 20.0, 0.1)
    add!(materials, "pvc", pvc)
    copper = get(materials, "copper")
    aluminum = get(materials, "aluminum")

    @testset "Material setup" begin
        @test get(materials, "pvc") isa LineCableModels.Materials.Material
        @test get(materials, "aluminum") isa LineCableModels.Materials.Material
        @test get(materials, "copper") isa LineCableModels.Materials.Material
    end

    # === Sector (core) geometry ===
    @testset "Sector core construction" begin
        n_sectors = 3
        r_back_mm = 10.24
        d_sector_mm = 9.14
        r_corner_mm = 1.02
        theta_cond_deg = 119.0
        ins_thick = 1.1e-3

        sector_params = SectorParams(
            n_sectors,
            r_back_mm / 1000,
            d_sector_mm / 1000,
            r_corner_mm / 1000,
            theta_cond_deg,
            ins_thick
        )

        rot_angles = (0.0, 120.0, 240.0)
        sectors = [Sector(sector_params, ang, aluminum) for ang in rot_angles]
        insulators = [SectorInsulator(sectors[i], ins_thick, pvc) for i in 1:3]

        @test length(sectors) == 3
        @test all(s -> s isa Sector, sectors)
        @test length(insulators) == 3
        @test all(i -> i isa SectorInsulator, insulators)

        components = [
            CableComponent("core1", ConductorGroup(sectors[1]), InsulatorGroup(insulators[1])),
            CableComponent("core2", ConductorGroup(sectors[2]), InsulatorGroup(insulators[2])),
            CableComponent("core3", ConductorGroup(sectors[3]), InsulatorGroup(insulators[3]))
        ]
        @test length(components) == 3
        @test components[1].id == "core1"
    end

    # === Concentric neutral ===
    @testset "Concentric neutral construction" begin
        n_neutral = 30
        r_strand = 0.79e-3
        R_N = 14.36e-3
        R_O = 17.25e-3

        inner_radius_neutral = R_N - r_strand
        outer_jacket_thickness = R_O - (R_N + r_strand)

        neutral_wires = WireArray(
            inner_radius_neutral,
            Diameter(2*r_strand),
            n_neutral,
            0.0,
            copper
        )
        @test neutral_wires isa WireArray

        neutral_jacket = Insulator(neutral_wires, Thickness(outer_jacket_thickness), pvc)
        @test neutral_jacket isa Insulator

        neutral_component = CableComponent("neutral", ConductorGroup(neutral_wires), InsulatorGroup(neutral_jacket))
        @test neutral_component.id == "neutral"
    end

    # === Assemble cable design ===
    @testset "Full cable design assembly" begin
        # Re-create components for this testset to be self-contained
        n_sectors = 3
        r_back_mm = 10.24
        d_sector_mm = 9.14
        r_corner_mm = 1.02
        theta_cond_deg = 119.0
        ins_thick = 1.1e-3
        sector_params = SectorParams(n_sectors, r_back_mm/1000, d_sector_mm/1000, r_corner_mm/1000, theta_cond_deg, ins_thick)
        rot_angles = (0.0, 120.0, 240.0)
        sectors = [Sector(sector_params, ang, aluminum) for ang in rot_angles]
        insulators = [SectorInsulator(sectors[i], ins_thick, pvc) for i in 1:3]
        components = [
            CableComponent("core1", ConductorGroup(sectors[1]), InsulatorGroup(insulators[1])),
            CableComponent("core2", ConductorGroup(sectors[2]), InsulatorGroup(insulators[2])),
            CableComponent("core3", ConductorGroup(sectors[3]), InsulatorGroup(insulators[3]))
        ]

        n_neutral = 30
        r_strand = 0.79e-3
        R_N = 14.36e-3
        R_O = 17.25e-3
        inner_radius_neutral = R_N - r_strand
        outer_jacket_thickness = R_O - (R_N + r_strand)
        neutral_wires = WireArray(inner_radius_neutral, Diameter(2*r_strand), n_neutral, 0.0, copper)
        neutral_jacket = Insulator(neutral_wires, Thickness(outer_jacket_thickness), pvc)
        neutral_component = CableComponent("neutral", ConductorGroup(neutral_wires), InsulatorGroup(neutral_jacket))

        design = CableDesign("NAYCWY_O_3x95_30x2_5", components[1])
        add!(design, components[2])
        add!(design, components[3])
        add!(design, neutral_component)

        @test length(design.components) == 4
        @test design.cable_id == "NAYCWY_O_3x95_30x2_5"
        @test design.components[1].id == "core1"
        @test design.components[2].id == "core2"
        @test design.components[3].id == "core3"
        @test design.components[4].id == "neutral"
    end

    @testset "DataFrame and preview" begin
        # Re-create the full design
        n_sectors = 3
        r_back_mm = 10.24
        d_sector_mm = 9.14
        r_corner_mm = 1.02
        theta_cond_deg = 119.0
        ins_thick = 1.1e-3
        sector_params = SectorParams(n_sectors, r_back_mm/1000, d_sector_mm/1000, r_corner_mm/1000, theta_cond_deg, ins_thick)
        rot_angles = (0.0, 120.0, 240.0)
        sectors = [Sector(sector_params, ang, aluminum) for ang in rot_angles]
        insulators = [SectorInsulator(sectors[i], ins_thick, pvc) for i in 1:3]
        components = [
            CableComponent("core1", ConductorGroup(sectors[1]), InsulatorGroup(insulators[1])),
            CableComponent("core2", ConductorGroup(sectors[2]), InsulatorGroup(insulators[2])),
            CableComponent("core3", ConductorGroup(sectors[3]), InsulatorGroup(insulators[3]))
        ]
        n_neutral = 30
        r_strand = 0.79e-3
        R_N = 14.36e-3
        R_O = 17.25e-3
        inner_radius_neutral = R_N - r_strand
        outer_jacket_thickness = R_O - (R_N + r_strand)
        neutral_wires = WireArray(inner_radius_neutral, Diameter(2*r_strand), n_neutral, 0.0, copper)
        neutral_jacket = Insulator(neutral_wires, Thickness(outer_jacket_thickness), pvc)
        neutral_component = CableComponent("neutral", ConductorGroup(neutral_wires), InsulatorGroup(neutral_jacket))
        design = CableDesign("NAYCWY_O_3x95_30x2_5", components[1])
        add!(design, components[2])
        add!(design, components[3])
        add!(design, neutral_component)

        # Test that DataFrame constructors do not throw errors
        @test DataFrame(design, :detailed) isa DataFrame
        @test DataFrame(design, :components) isa DataFrame
        @test DataFrame(design, :baseparams) isa DataFrame

        # Test that preview functions execute without error
        @test preview(design, display_plot=false) isa Any
    end

    @testset "Sector FEM gap air assignment" begin
        mktempdir(joinpath(@__DIR__)) do tmpdir
            n_sectors = 3
            r_back_mm = 10.24
            d_sector_mm = 9.14
            r_corner_mm = 1.02
            theta_cond_deg = 119.0
            ins_thick = 1.1e-3

            sector_params = SectorParams(
                n_sectors,
                r_back_mm / 1000,
                d_sector_mm / 1000,
                r_corner_mm / 1000,
                theta_cond_deg,
                ins_thick,
            )

            rot_angles = (0.0, 120.0, 240.0)
            sectors = [Sector(sector_params, ang, aluminum) for ang in rot_angles]
            insulators = [SectorInsulator(sectors[i], ins_thick, pvc) for i in 1:3]

            components = [
                CableComponent("core1", ConductorGroup(sectors[1]), InsulatorGroup(insulators[1])),
                CableComponent("core2", ConductorGroup(sectors[2]), InsulatorGroup(insulators[2])),
                CableComponent("core3", ConductorGroup(sectors[3]), InsulatorGroup(insulators[3])),
            ]

            n_neutral = 30
            r_strand = 0.79e-3
            R_N = 14.36e-3
            R_O = 17.25e-3
            inner_radius_neutral = R_N - r_strand
            outer_jacket_thickness = R_O - (R_N + r_strand)
            neutral_wires = WireArray(inner_radius_neutral, Diameter(2 * r_strand), n_neutral, 0.0, copper)
            neutral_jacket = Insulator(neutral_wires, Thickness(outer_jacket_thickness), pvc)
            neutral_component = CableComponent("neutral", ConductorGroup(neutral_wires), InsulatorGroup(neutral_jacket))

            design = CableDesign("NAYCWY_O_3x95_30x2_5", components[1])
            add!(design, components[2])
            add!(design, components[3])
            add!(design, neutral_component)

            earth_params = EarthModel([50.0], 100.0, 10.0, 1.0)
            cable_position = CablePosition(
                design,
                0.0,
                -0.02,
                Dict("core1" => 1, "core2" => 2, "core3" => 3, "neutral" => 0),
            )
            cable_system = LineCableSystem("sector_gap_assignment", 1000.0, cable_position)

            problem = LineParametersProblem(
                cable_system,
                temperature = 20.0,
                earth_props = earth_params,
                frequencies = [50.0],
            )

            opts = (
                force_remesh = true,
                force_overwrite = true,
                plot_field_maps = false,
                mesh_only = false,
                save_path = joinpath(tmpdir, "fem_output"),
                keep_run_files = false,
                verbosity = 0,
            )

            formulation = FormulationSet(:FEM,
                impedance = Darwin(),
                admittance = Electrodynamics(),
                domain_radius = 1.0,
                domain_radius_inf = 1.25,
                elements_per_length_conductor = 2,
                elements_per_length_insulator = 2,
                elements_per_length_semicon = 1,
                elements_per_length_interfaces = 5,
                points_per_circumference = 24,
                mesh_size_min = 1e-6,
                mesh_size_max = 0.1,
                mesh_size_default = 0.05,
                mesh_algorithm = 5,
                mesh_max_retries = 20,
                materials = materials,
                options = opts,
            )

            fem = LineCableModels.Engine.FEM

            try
                workspace = fem.init_workspace(problem, formulation, nothing)
                fem.make_mesh!(workspace)

                air_layer_idx = 1
                air_material = fem.get_earth_model_material(workspace, air_layer_idx)
                air_material_id = fem.get_or_register_material_id(workspace, air_material)
                air_material_group = fem.get_material_group(workspace.problem_def.earth_props, air_layer_idx)
                air_region_tag = fem.encode_physical_group_tag(2, air_layer_idx, 0, air_material_group, air_material_id)

                air_regions = [
                    entity for entity in workspace.space_regions
                    if entity.data.core.physical_group_tag == air_region_tag
                ]

                @test length(air_regions) >= 2

                for entity in air_regions
                    surface_type, _, _, material_group, _ = fem.decode_physical_group_tag(entity.data.core.physical_group_tag)
                    @test surface_type == 2
                    @test material_group == 2
                end
            finally
                if fem.gmsh.is_initialized() == 1
                    fem.gmsh.clear()
                end
            end
        end
    end

    @testset "Error handling" begin
        # Test invalid geometric parameters for Sector
        @test_throws ArgumentError SectorParams(3, -10.24/1000, 9.14/1000, 1.02/1000, 119.0, 1.1e-3)
        @test_throws ArgumentError SectorParams(3, 10.24/1000, -9.14/1000, 1.02/1000, 119.0, 1.1e-3)
        @test_throws ArgumentError SectorParams(3, 10.24/1000, 9.14/1000, -1.02/1000, 119.0, 1.1e-3)
        @test_throws ArgumentError SectorParams(3, 10.24/1000, 9.14/1000, 1.02/1000, 119.0, -1.1e-3)
    end
end
