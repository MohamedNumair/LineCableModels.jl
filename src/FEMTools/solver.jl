
function make_fem_problem!(fem_formulation::Union{AbstractImpedanceFormulation,AbstractAdmittanceFormulation}, frequency::Float64, workspace::FEMWorkspace)

    fem_formulation.problem = GetDP.Problem()
    define_jacobian!(fem_formulation.problem, workspace)
    define_integration!(fem_formulation.problem)
    define_material_props!(fem_formulation.problem, workspace)
    define_constants!(fem_formulation.problem, fem_formulation, frequency)
    define_domain_groups!(fem_formulation.problem, fem_formulation, workspace)
    define_constraint!(fem_formulation.problem, fem_formulation, workspace)
    define_resolution!(fem_formulation.problem, fem_formulation, workspace)

    make_problem!(fem_formulation.problem)
    fem_formulation.problem.filename = fem_formulation isa AbstractImpedanceFormulation ? workspace.paths[:impedance_file] : workspace.paths[:admittance_file]
    write_file(fem_formulation.problem)
end

function define_jacobian!(problem::GetDP.Problem, workspace::FEMWorkspace)
    # Initialize Jacobian
    jac = Jacobian()

    Rint = workspace.formulation.domain_radius
    Rext = workspace.formulation.domain_radius_inf

    # Add Vol Jacobian
    vol = add!(jac, "Vol")
    add!(vol;
        Region="DomainInf",
        Jacobian=VolSphShell(
            Rint=Rint,
            Rext=Rext,
            center_X=0.0,
            center_Y=0.0,
            center_Z=0.0
        )
    )
    add!(vol; Region="All", Jacobian="Vol")

    # Add Sur Jacobian
    sur = add!(jac, "Sur")
    add!(sur;
        Region="All",
        Jacobian="Sur",
    )

    # Add Jacobian to problem
    problem.jacobian = jac
end

function define_integration!(problem::GetDP.Problem)
    # Initialize Integration
    integ = Integration()
    i1 = add!(integ, "I1")
    case = add!(i1)
    geo_case = add_nested_case!(case; type="Gauss")
    add!(geo_case; GeoElement="Point", NumberOfPoints=1)
    add!(geo_case; GeoElement="Line", NumberOfPoints=4)
    add!(geo_case; GeoElement="Triangle", NumberOfPoints=4)
    add!(geo_case; GeoElement="Quadrangle", NumberOfPoints=4)
    # add!(geo_case; GeoElement="Triangle2", NumberOfPoints=7)
    problem.integration = integ

end

function define_material_props!(problem::GetDP.Problem, workspace::FEMWorkspace)
    # Create material properties function
    func = GetDP.Function()

    for (tag, mat) in workspace.physical_groups
        if tag > 10^8
            # Add material properties for this region
            add_comment!(func, "Material properties for region $(tag): $(create_physical_group_name(workspace, tag))", false)
            add_space!(func)
            add!(func, "nu", expression=1 / (mat.mu_r * μ₀), region=[tag])
            add!(func, "sigma", expression=isinf(mat.rho) ? 0.0 : 1 / mat.rho, region=[tag])
            add!(func, "epsilon", expression=mat.eps_r * ε₀, region=[tag])
        end
    end

    push!(problem.function_obj, func)
end

function define_constants!(problem::GetDP.Problem, fem_formulation::Union{AbstractImpedanceFormulation,AbstractAdmittanceFormulation}, frequency::Float64)
    func = GetDP.Function()

    # DEFAULT_CONSTS = [("I", 1.0), ("V0", 1.0), ("Flag_Degree_a", "1"), ("Flag_Degree_v", "1")]

    # Add constants more concisely (because of course it is so much better to jump one fuckton lines to find the damn parameter rather than making readable code)
    # for (name, value) in [DEFAULT_CONSTS..., ("Freq", frequency)]
    #     add_constant!(func, name, value)
    # end

    # # Add other parameters
    # add!(func, "Ns", expression="1")
    # add!(func, "Sc", expression="SurfaceArea[]")

    # if fem_formulation isa AbstractImpedanceFormulation
    #     add_raw_code!(func, "DefineFunction[js0];")
    # end
    add_constant!(func, "Freq", frequency)
    # if fem_formulation isa AbstractImpedanceFormulation
    #     add_constant!(func, "I", 1.0)
    # else
    #     add_constant!(func, "V0", 1.0)
    # end
    add_constant!(func, "UnitAmplitude", 1.0)
    push!(problem.function_obj, func)
end

function define_domain_groups!(problem::GetDP.Problem, fem_formulation::Union{AbstractImpedanceFormulation,AbstractAdmittanceFormulation}, workspace::FEMWorkspace)

    material_reg = Dict{Symbol,Vector{Int}}(
        :DomainC => Int[],
        :DomainCC => Int[],
        :DomainInf => Int[]
    )
    inds_reg = Int[]
    cables_reg = Dict{Int,Vector{Int}}()
    # DomainZ = Int[]
    boundary_reg = Int[]
    add_raw_code!(problem,
        """
        DefineConstant[
        active_con = {1, Choices{1,9999}, Name "Input/Active conductor", Visible 1}];
        """)
    for tag in keys(workspace.physical_groups)
        if tag > 10^8
            # Decode tag information
            surface_type, entity_num, component_num, material_group, _ = decode_physical_group_tag(tag)

            # Categorize regions 
            if surface_type == 1
                push!(get!(cables_reg, entity_num, Int[]), tag)
                if material_group == 1
                    push!(inds_reg, tag)
                end
            end
            if material_group == 1
                push!(material_reg[:DomainC], tag)
                #     component_num == 1 && push!(get!(inds_reg, entity_num, Int[]), tag)
            elseif material_group == 2
                push!(material_reg[:DomainCC], tag)
            end

            surface_type == 3 && push!(material_reg[:DomainInf], tag)

        else
            decode_boundary_tag(tag)[1] == 2 && push!(boundary_reg, tag)
        end
    end
    inds_reg = sort(inds_reg)
    material_reg[:DomainC] = sort(material_reg[:DomainC])
    material_reg[:DomainCC] = sort(material_reg[:DomainCC])
    # Create and configure groups
    group = GetDP.Group()

    # Add common domains
    add!(group, "DomainInf", material_reg[:DomainInf], "Region", comment="Domain transformation to infinity")

    # Process regions with energized conductors, i.e. inducing elements
    # for (key, tag) in inds_reg
    #     add!(group, "Ind_$key", tag, "Region")
    # end
    for (key, tag) in enumerate(inds_reg)
        add!(group, "Con_$key", [tag], "Region";
            comment="$(create_physical_group_name(workspace, tag))")
    end
    # all_inds = reduce(vcat, values(inds_reg); init=Int[])
    add!(group, "Conductors", inds_reg, "Region")

    # Add standard FEM domains
    domain_configs = [
        ("DomainC", Int[], "All conductor materials"),
        ("DomainCC", Int[], "All non-conductor materials"),
        ("DomainActive", ["Con~{active_con}"], "Sources"),
        ("DomainInactive", ["Conductors - Con~{active_con}"], "Conductors set to zero energization")
    ]

    for (name, regions, comment) in domain_configs
        add!(group, name, regions, "Region"; comment=comment)
    end

    # add!(group, "DomainActive", ["Con~{active_con}"], "Region")
    # add!(group, "DomainInactive", ["Con~{active_con}"], "Region";
    #     operation="-=")

    for tag in material_reg[:DomainC]
        add!(group, "DomainC", [tag], "Region";
            operation="+=",
            comment="$(create_physical_group_name(workspace, tag))")
    end

    for tag in material_reg[:DomainCC]
        add!(group, "DomainCC", [tag], "Region";
            operation="+=",
            comment="$(create_physical_group_name(workspace, tag))")
    end

    if fem_formulation isa AbstractAdmittanceFormulation
        # add!(group, "DomainDummy", [12345], "Region")
        # # Process cable regions
        # for (key, tag) in cables_reg
        #     add!(group, "Cable_$key", tag, "Region")
        # end
        # add!(group, "Cables", ["Cable_$k" for k in keys(cables_reg)], "Region")
        add!(group, "Domain_Ele", ["DomainCC", "DomainC"], "Region")
        add!(group, "Sur_Dirichlet_Ele", boundary_reg, "Region")
    else
        # Add domain groups
        add!(group, "Domain_Mag", ["DomainCC", "DomainC"], "Region")
        add!(group, "Sur_Dirichlet_Mag", boundary_reg, "Region")
    end

    problem.group = group
end

function define_constraint!(problem::GetDP.Problem, fem_formulation::Union{AbstractImpedanceFormulation,AbstractAdmittanceFormulation}, workspace::FEMWorkspace)
    constraint = GetDP.Constraint()

    num_cores = workspace.problem_def.system.num_cables

    if fem_formulation isa AbstractAdmittanceFormulation
        # ElectricScalarPotential
        esp = assign!(constraint, "ScalarPotential_2D")
        # for inds_num in 1:num_cores
        #     # Calculate phase angle: 0° for phase 1, -120° for phase 2, -240° for phase 3
        #     phase_angle = -120.0 * (inds_num - 1) / 180.0 * π

        #     case!(esp, "Con_$inds_num",
        #         value="V0",
        #         time_function="F_Cos_wt_p[]{2*Pi*Freq, $phase_angle}")
        # end
        case!(esp, "DomainInactive", value="0.0")
        case!(esp, "Con~{active_con}", value="UnitAmplitude")
        case!(esp, "Sur_Dirichlet_Ele", value="0.0")

        charge = assign!(constraint, "Charge_2D")

        # # ZeroElectricScalarPotential (for second order basis functions)
        # zesp = assign!(constraint, "ZeroElectricScalarPotential")
        # case!(zesp, "Sur_Dirichlet_Ele", value="0.0")
        # zesp_loop = for_loop!(zesp, "k", "1:$(num_cores)")
        # case!(zesp_loop, "Core~{k}", value="0.0")
    else
        # MagneticVectorPotential_2D
        mvp = assign!(constraint, "MagneticVectorPotential_2D")
        case!(mvp, "Sur_Dirichlet_Mag", value="0.0")

        # Voltage_2D (placeholder)
        voltage = assign!(constraint, "Voltage_2D")
        case!(voltage, "")

        # Current_2D
        current = assign!(constraint, "Current_2D")

        # for inds_num in 1:num_cores
        #     # Calculate phase angle: 0° for phase 1, -120° for phase 2, -240° for phase 3
        #     phase_angle = -120.0 * (inds_num - 1) / 180.0 * π

        #     case!(current, "Core_$inds_num",
        #         value="I",
        #         time_function="F_Cos_wt_p[]{2*Pi*Freq, $phase_angle}")
        # end
        case!(current, "DomainInactive", value="0.0")
        case!(current, "Con~{active_con}", value="UnitAmplitude")
    end

    problem.constraint = constraint

end

function define_resolution!(problem::GetDP.Problem, formulation::FEMElectrodynamics, workspace::FEMWorkspace)
    resolution_name = formulation.resolution_name
    num_sources = workspace.problem_def.system.num_cables

    # FunctionSpace section
    functionspace = FunctionSpace()
    fs1 = add!(functionspace, "Hgrad_v_Ele", nothing, nothing, Type="Form0")
    add_basis_function!(functionspace, "sn", "vn", "BF_Node"; Support="Domain_Ele", Entity="NodesOf[ All, Not DomainC ]")
    add_basis_function!(functionspace, "sf", "vf", "BF_GroupOfNodes"; Support="Domain_Ele", Entity="GroupsOfNodesOf[ DomainC ]")
    add_global_quantity!(functionspace, "U", "AliasOf"; NameOfCoef="vf")
    add_global_quantity!(functionspace, "Q", "AssociatedWith"; NameOfCoef="vf")
    add_constraint!(functionspace, "U", "Region", "ScalarPotential_2D")
    add_constraint!(functionspace, "Q", "Region", "Charge_2D")
    # add_basis_function!(functionspace, "sn2", "vn2", "BF_Node_2E";
    #     Support="Domain_Ele",
    #     Entity="EdgesOf[ All ]",
    #     condition="If (Flag_Degree_v == 2)",
    #     endCondition="EndIf")

    add_constraint!(functionspace, "vn", "NodesOf", "ScalarPotential_2D")
    # add_constraint!(functionspace, "vn2", "EdgesOf", "ZeroElectricScalarPotential";
    #     condition="If (Flag_Degree_v == 2)",
    #     endCondition="EndIf")

    problem.functionspace = functionspace

    # Formulation section
    formulation = Formulation()
    form = add!(formulation, "Electrodynamics_v", "FemEquation")
    add_quantity!(form, "v", Type="Local", NameOfSpace="Hgrad_v_Ele")
    add_quantity!(form, "U", Type="Global", NameOfSpace="Hgrad_v_Ele [U]")
    add_quantity!(form, "Q", Type="Global", NameOfSpace="Hgrad_v_Ele [Q]")

    eq = add_equation!(form)
    add!(eq, "Galerkin", "[ sigma[] * Dof{d v} , {d v} ]", In="Domain_Ele", Jacobian="Vol", Integration="I1")
    add!(eq, "Galerkin", "DtDof[ epsilon[] * Dof{d v} , {d v} ]", In="Domain_Ele", Jacobian="Vol", Integration="I1")
    add!(eq, "GlobalTerm", "[ Dof{Q} , {U} ]", In="DomainActive")

    problem.formulation = formulation

    # Resolution section
    output_dir = joinpath("results", lowercase(resolution_name))
    resolution = Resolution()
    add!(resolution, resolution_name, "Sys_Ele",
        NameOfFormulation="Electrodynamics_v",
        Type="Complex",
        Frequency="Freq",
        Operation=[
            "CreateDir[\"$(output_dir)\"]",
            "Generate[Sys_Ele]",
            "Solve[Sys_Ele]",
            "SaveSolution[Sys_Ele]",
            "PostOperation[LineParams]"
            # "PostOperation[Ele_Cuts]"
        ])

    problem.resolution = resolution

    # PostProcessing section
    postprocessing = PostProcessing()
    pp = add!(postprocessing, "EleDyn_v", "Electrodynamics_v")

    # Add standard quantities
    for (name, expr, options) in [
        ("v", "{v}", Dict()),
        ("e", "-{d v}", Dict()),
        ("em", "Norm[-{d v}]", Dict()),
        ("d", "-epsilon[] * {d v}", Dict()),
        ("dm", "Norm[-epsilon[] * {d v}]", Dict()),
        ("j", "-sigma[] * {d v}", Dict()),
        ("jm", "Norm[-sigma[] * {d v}]", Dict())
    ]
        q = add!(pp, name)
        add!(q, "Term", expr; In="Domain_Ele", Jacobian="Vol", options...)
    end

    # Add jtot (combination of j and d)
    q = add!(pp, "jtot")
    add!(q, "Term", "-sigma[] * {d v}"; Type="Global", In="Domain_Ele", Jacobian="Vol")
    add!(q, "Term", "-epsilon[] * Dt[{d v}]"; Type="Global", In="Domain_Ele", Jacobian="Vol")

    # # # Add ElectricEnergy
    # q = add!(pp, "ElectricEnergy")
    # add!(q, "Integral", "0.5 * epsilon[] * SquNorm[{d v}]"; In="Domain_Ele", Jacobian="Vol", Integration="I1")

    q = add!(pp, "U")
    add!(q, "Term", "{U}"; In="Domain_Ele")
    # add!(q, "Term", "{Us}"; In="DomainS_Mag")

    q = add!(pp, "Q")
    add!(q, "Term", "{Q}"; In="Domain_Ele")

    q = add!(pp, "Y")
    add!(q, "Term", "-{Q}"; In="Domain_Ele")

    # # V0
    # q = add!(pp, "V0")
    # for inds_num in 1:num_sources
    #     # Calculate phase angle: 0° for phase 1, -120° for phase 2, -240° for phase 3
    #     phase_angle = -120.0 * (inds_num - 1) / 180.0 * π

    #     add!(q, "Term", "V0 * F_Cos_wt_p[]{2*Pi*Freq, $phase_angle}"; Type="Global", In="Core_$inds_num")

    # end

    # # C_from_Energy
    # q = add!(pp, "C_from_Energy")
    # add!(q, "Term", "2*\$We/SquNorm[\$voltage]"; Type="Global", In="DomainDummy")

    problem.postprocessing = postprocessing

    # PostOperation section
    postoperation = PostOperation()
    # add_comment!(postoperation, "Electric")
    # add_raw_code!(postoperation, "po0 = \"{01Pul-capacitance/\";")

    # Field_Maps
    po1 = add!(postoperation, "Field_Maps", "EleDyn_v")
    op1 = add_operation!(po1)
    add_operation!(op1, "Print[ v, OnElementsOf Domain_Ele, File StrCat[ \"$(joinpath(output_dir,"v_"))\", Sprintf(\"%g\",active_con), \".pos\" ] ];")
    add_operation!(op1, "Print[ em, OnElementsOf Domain_Ele, Name \"|E| [V/m]\", File StrCat[ \"$(joinpath(output_dir,"em_"))\", Sprintf(\"%g\",active_con), \".pos\" ] ];")
    add_operation!(op1, "Print[ dm, OnElementsOf Domain_Ele, Name \"|D| [A/m²]\", File StrCat[ \"$(joinpath(output_dir,"dm_"))\", Sprintf(\"%g\",active_con), \".pos\" ] ];")
    add_operation!(op1, "Print[ e, OnElementsOf Domain_Ele, Name \"E [V/m]\", File StrCat[ \"$(joinpath(output_dir,"e_"))\", Sprintf(\"%g\",active_con), \".pos\" ] ];")

    # LineParams
    po2 = add!(postoperation, "LineParams", "EleDyn_v")
    op2 = add_operation!(po2)
    # add_operation!(op2, "Print[ ElectricEnergy[Conductors], OnGlobal, Format Table, StoreInVariable \$We, File \"$(joinpath(output_dir,"E.dat"))\" ];")
    # add_operation!(op2, "Print[ V0[Core_1], OnRegion Core_1, Format Table, StoreInVariable \$voltage, File \"$(joinpath(output_dir,"U.dat"))\" ];")
    # add_operation!(op2, "Print[ C_from_Energy, OnRegion DomainDummy, Format Table, StoreInVariable \$C1, File \"$(joinpath(output_dir,"C.dat"))\" ];")
    # add_operation!(op2, "Print[ V0[Cores], OnRegion Cores, Format Table, File \"$(joinpath(output_dir,"Y.dat"))\" ];")
    add_operation!(op2, "Print[ Y, OnRegion Conductors, Format Table, File \"$(joinpath(output_dir,"Y.dat"))\", AppendToExistingFile (active_con > 1 ? 1 : 0) ];")

    problem.postoperation = postoperation

end

function define_resolution!(problem::GetDP.Problem, formulation::FEMDarwin, workspace::FEMWorkspace)

    resolution_name = formulation.resolution_name

    # Create a new Problem instance
    functionspace = FunctionSpace()

    # FunctionSpace section
    fs1 = add!(functionspace, "Hcurl_a_Mag_2D", nothing, nothing, Type="Form1P")
    add_basis_function!(functionspace, "se", "ae", "BF_PerpendicularEdge"; Support="Domain_Mag", Entity="NodesOf[ All ]")
    # add_basis_function!(functionspace, "se2", "ae2", "BF_PerpendicularEdge_2E";
    #     Support="Domain_Mag",
    #     Entity="EdgesOf[ All ]",
    #     condition="If (Flag_Degree_a == 2)",
    #     endCondition="EndIf")

    add_constraint!(functionspace, "ae", "NodesOf", "MagneticVectorPotential_2D")
    # add_constraint!(functionspace, "ae2", "EdgesOf", "MagneticVectorPotential_2D";
    #     condition="If (Flag_Degree_a == 2)",
    #     endCondition="EndIf")


    # fs2 = add!(functionspace, "Hregion_i_2D", nothing, nothing, Type="Vector")
    # add_basis_function!(functionspace, "sr", "ir", "BF_RegionZ"; Support="DomainS_Mag", Entity="DomainS_Mag")
    # add_global_quantity!(functionspace, "Is", "AliasOf"; NameOfCoef="ir")
    # add_global_quantity!(functionspace, "Us", "AssociatedWith"; NameOfCoef="ir")
    # add_constraint!(functionspace, "Us", "Region", "Voltage_2D")
    # add_constraint!(functionspace, "Is", "Region", "Current_2D")


    fs3 = add!(functionspace, "Hregion_u_Mag_2D", nothing, nothing, Type="Form1P")
    add_basis_function!(functionspace, "sr", "ur", "BF_RegionZ"; Support="DomainC", Entity="DomainC")
    add_global_quantity!(functionspace, "U", "AliasOf"; NameOfCoef="ur")
    add_global_quantity!(functionspace, "I", "AssociatedWith"; NameOfCoef="ur")
    add_constraint!(functionspace, "U", "Region", "Voltage_2D")
    add_constraint!(functionspace, "I", "Region", "Current_2D")

    problem.functionspace = functionspace

    # Define Formulation
    formulation = GetDP.Formulation()

    form = add!(formulation, "Darwin_a_2D", "FemEquation")
    add_quantity!(form, "a", Type="Local", NameOfSpace="Hcurl_a_Mag_2D")
    add_quantity!(form, "ur", Type="Local", NameOfSpace="Hregion_u_Mag_2D")
    add_quantity!(form, "I", Type="Global", NameOfSpace="Hregion_u_Mag_2D [I]")
    add_quantity!(form, "U", Type="Global", NameOfSpace="Hregion_u_Mag_2D [U]")
    # add_quantity!(form, "ir", Type="Local", NameOfSpace="Hregion_i_2D")
    # add_quantity!(form, "Us", Type="Global", NameOfSpace="Hregion_i_2D[Us]")
    # add_quantity!(form, "Is", Type="Global", NameOfSpace="Hregion_i_2D[Is]")

    eq = add_equation!(form)

    add!(eq, "Galerkin", "[ nu[] * Dof{d a} , {d a} ]", In="Domain_Mag", Jacobian="Vol", Integration="I1")
    add!(eq, "Galerkin", "DtDof [ sigma[] * Dof{a} , {a} ]", In="DomainC", Jacobian="Vol", Integration="I1")
    add!(eq, "Galerkin", "[ sigma[] * Dof{ur}, {a} ]", In="DomainC", Jacobian="Vol", Integration="I1")
    add!(eq, "Galerkin", "DtDof [ sigma[] * Dof{a} , {ur} ]", In="DomainC", Jacobian="Vol", Integration="I1")
    add!(eq, "Galerkin", "[ sigma[] * Dof{ur}, {ur}]", In="DomainC", Jacobian="Vol", Integration="I1")
    add!(eq, "Galerkin", "DtDtDof [ epsilon[] * Dof{a} , {a}]", In="DomainC", Jacobian="Vol", Integration="I1", comment=" Darwin approximation term")
    add!(eq, "Galerkin", "DtDof[ epsilon[] * Dof{ur}, {a} ]", In="DomainC", Jacobian="Vol", Integration="I1")
    add!(eq, "Galerkin", "DtDtDof [ epsilon[] * Dof{a} , {ur}]", In="DomainC", Jacobian="Vol", Integration="I1")
    add!(eq, "Galerkin", "DtDof[ epsilon[] * Dof{ur}, {ur} ]", In="DomainC", Jacobian="Vol", Integration="I1")
    add!(eq, "GlobalTerm", "[ Dof{I} , {U} ]", In="DomainActive")
    # add!(eq, "Galerkin", "[ -js0[] , {a} ]", In="DomainS0_Mag", Jacobian="Vol", Integration="I1", comment=" Either you impose directly the function js0[]...")
    # add!(eq, "Galerkin", "[ -Ns[]/Sc[] * Dof{ir}, {a} ]", In="DomainS_Mag", Jacobian="Vol", Integration="I1", comment=" ...or you use the constraints")
    # add!(eq, "Galerkin", "DtDof [ Ns[]/Sc[] * Dof{a}, {ir} ]", In="DomainS_Mag", Jacobian="Vol", Integration="I1")
    # add!(eq, "Galerkin", "[ Ns[]/Sc[] / sigma[] * Ns[]/Sc[]* Dof{ir} , {ir}]", In="DomainS_Mag", Jacobian="Vol", Integration="I1")
    # add!(eq, "GlobalTerm", "[ Dof{Us}, {Is} ]", In="DomainS_Mag")

    # Add the formulation to the problem
    problem.formulation = formulation

    # Define Resolution
    resolution = Resolution()

    # Add a resolution
    output_dir = joinpath("results", lowercase(resolution_name))
    add!(resolution, resolution_name, "Sys_Mag",
        NameOfFormulation="Darwin_a_2D",
        Type="Complex", Frequency="Freq",
        Operation=[
            "CreateDir[\"$(output_dir)\"]",
            "InitSolution[Sys_Mag]",
            "Generate[Sys_Mag]",
            "Solve[Sys_Mag]",
            "SaveSolution[Sys_Mag]",
            "PostOperation[LineParams]"
        ])

    # Add the resolution to the problem
    problem.resolution = resolution

    # PostProcessing section
    postprocessing = PostProcessing()

    pp = add!(postprocessing, "Darwin_a_2D", "Darwin_a_2D")
    q = add!(pp, "a")
    add!(q, "Term", "{a}"; In="Domain_Mag", Jacobian="Vol")
    q = add!(pp, "az")
    add!(q, "Term", "CompZ[{a}]"; In="Domain_Mag", Jacobian="Vol")
    q = add!(pp, "b")
    add!(q, "Term", "{d a}"; In="Domain_Mag", Jacobian="Vol")
    q = add!(pp, "bm")
    add!(q, "Term", "Norm[{d a}]"; In="Domain_Mag", Jacobian="Vol")

    # Multi-term entries
    q = add!(pp, "j")
    add!(q, "Term", "-sigma[]*(Dt[{a}]+{ur})"; In="DomainC", Jacobian="Vol")
    # add!(q, "Term", "js0[]"; In="DomainS0_Mag", Jacobian="Vol")
    # add!(q, "Term", "Ns[]/Sc[]*{ir}"; In="DomainS_Mag", Jacobian="Vol")

    q = add!(pp, "jz")
    add!(q, "Term", "CompZ[-sigma[]*(Dt[{a}]+{ur})]"; In="DomainC", Jacobian="Vol")
    # add!(q, "Term", "CompZ[js0[]]"; In="DomainS0_Mag", Jacobian="Vol")
    # add!(q, "Term", "CompZ[Ns[]/Sc[]*{ir}]"; In="DomainS_Mag", Jacobian="Vol")

    q = add!(pp, "jm")
    add!(q, "Term", "Norm[-sigma[]*(Dt[{a}]+{ur})]"; In="DomainC", Jacobian="Vol")
    # add!(q, "Term", "Norm[js0[]]"; In="DomainS0_Mag", Jacobian="Vol")
    # add!(q, "Term", "Norm[Ns[]/Sc[]*{ir}]"; In="DomainS_Mag", Jacobian="Vol")

    q = add!(pp, "d")
    add!(q, "Term", "epsilon[] * Dt[Dt[{a}]+{ur}]"; In="DomainC", Jacobian="Vol")
    q = add!(pp, "dz")
    add!(q, "Term", "CompZ[epsilon[] * Dt[Dt[{a}]+{ur}]]"; In="DomainC", Jacobian="Vol")
    q = add!(pp, "dm")
    add!(q, "Term", "Norm[epsilon[] * Dt[Dt[{a}]+{ur}]]"; In="DomainC", Jacobian="Vol")

    q = add!(pp, "rhoj2")
    add!(q, "Term", "0.5*sigma[]*SquNorm[Dt[{a}]+{ur}]"; In="DomainC", Jacobian="Vol")
    # add!(q, "Term", "0.5/sigma[]*SquNorm[js0[]]"; In="DomainS0_Mag", Jacobian="Vol")
    # add!(q, "Term", "0.5/sigma[]*SquNorm[Ns[]/Sc[]*{ir}]"; In="DomainS_Mag", Jacobian="Vol")

    q = add!(pp, "JouleLosses")
    add!(q, "Integral", "0.5*sigma[]*SquNorm[Dt[{a}]]"; In="DomainC", Jacobian="Vol", Integration="I1")
    # add!(q, "Integral", "0.5/sigma[]*SquNorm[js0[]]"; In="DomainS0_Mag", Jacobian="Vol", Integration="I1")
    # add!(q, "Integral", "0.5/sigma[]*SquNorm[Ns[]/Sc[]*{ir}]"; In="DomainS_Mag", Jacobian="Vol", Integration="I1")

    q = add!(pp, "U")
    add!(q, "Term", "{U}"; In="DomainC")
    # add!(q, "Term", "{Us}"; In="DomainS_Mag")

    q = add!(pp, "I")
    add!(q, "Term", "{I}"; In="DomainC")
    # add!(q, "Term", "{Is}"; In="DomainS_Mag")

    # q = add!(pp, "S")
    # add!(q, "Term", "{U}*Conj[{I}]"; In="DomainC")
    # # add!(q, "Term", "{Us}*Conj[{Is}]"; In="DomainS_Mag")

    # q = add!(pp, "R")
    # add!(q, "Term", "-Re[{U}/{I}]"; In="DomainC")
    # # add!(q, "Term", "-Re[{Us}/{Is}]"; In="DomainS_Mag")

    # q = add!(pp, "L")
    # add!(q, "Term", "-Im[{U}/{I}]/(2*Pi*Freq)"; In="DomainC")
    # add!(q, "Term", "-Im[{Us}/{Is}]/(2*Pi*Freq)"; In="DomainS_Mag")

    # q = add!(pp, "R_per_km")
    # add!(q, "Term", "-Re[{U}/{I}]*1e3"; In="DomainC")
    # add!(q, "Term", "-Re[{Us}/{Is}]*1e3"; In="DomainS_Mag")

    # q = add!(pp, "mL_per_km")
    # add!(q, "Term", "-1e6*Im[{U}/{I}]/(2*Pi*Freq)"; In="DomainC")
    # add!(q, "Term", "-1e6*Im[{Us}/{Is}]/(2*Pi*Freq)"; In="DomainS_Mag")

    q = add!(pp, "Z")
    add!(q, "Term", "-{U}"; In="DomainC")
    # add!(q, "Term", "-{Us}/{Is}"; In="DomainS_Mag")

    problem.postprocessing = postprocessing

    # PostOperation section
    postoperation = PostOperation()

    # Add post-operation items
    po1 = add!(postoperation, "Field_Maps", "Darwin_a_2D")
    op1 = add_operation!(po1)  # Creates a POBase_ for po1

    add_operation!(op1, "Print[ az, OnElementsOf Domain_Mag, Smoothing 1, Name \"flux lines: Az [T m]\", File StrCat[ \"$(joinpath(output_dir,"az_"))\", Sprintf(\"%g\",active_con), \".pos\" ] ];")
    add_operation!(op1, "Print[ b, OnElementsOf Domain_Mag, Smoothing 1, Name \"B [T]\", File StrCat[ \"$(joinpath(output_dir,"b_"))\", Sprintf(\"%g\",active_con), \".pos\" ] ];")
    add_operation!(op1, "Print[ bm, OnElementsOf Domain_Mag, Smoothing 1, Name \"|B| [T]\", File StrCat[ \"$(joinpath(output_dir,"bm_"))\", Sprintf(\"%g\",active_con), \".pos\" ] ];")
    add_operation!(op1, "Print[ jz, OnElementsOf Region[{DomainC}], Smoothing 1, Name \"jz [A/m²] Conducting domain\", File StrCat[ \"$(joinpath(output_dir,"jz_"))\", Sprintf(\"%g\",active_con), \".pos\" ] ];")
    add_operation!(op1, "Print[ rhoj2, OnElementsOf Region[{DomainC}], Smoothing 1, Name \"Power density\", File StrCat[ \"$(joinpath(output_dir,"rhoj2_"))\", Sprintf(\"%g\",active_con), \".pos\" ] ];")
    add_operation!(op1, "Print[ jm, OnElementsOf DomainC, Smoothing 1, Name \"|j| [A/m²] Conducting domain\", File StrCat[ \"$(joinpath(output_dir,"jm_"))\", Sprintf(\"%g\",active_con), \".pos\" ] ];")
    add_operation!(op1, "Print[ dm, OnElementsOf DomainC, Smoothing 1, Name \"|D| [A/m²]\", File StrCat[ \"$(joinpath(output_dir,"dm_"))\", Sprintf(\"%g\",active_con), \".pos\" ] ];")

    # add_raw_code!(po1, "po = \"{01Losses/\";")
    # add_raw_code!(po1, "po2 = \"{02Pul-parameters/\";")

    po2 = add!(postoperation, "LineParams", "Darwin_a_2D")
    op2 = add_operation!(po2)  # Creates a POBase_ for po2
    # add_operation!(op2, "Print[ Z[DomainC], OnRegion Cores, Format Table, File \"$(joinpath(output_dir,"Z.dat"))\" ];")
    add_operation!(op2, "Print[ Z, OnRegion Conductors, Format Table, File \"$(joinpath(output_dir,"Z.dat"))\", AppendToExistingFile (active_con > 1 ? 1 : 0) ];")


    # Add the post-operation to the problem
    problem.postoperation = postoperation

end

# Verbosity Levels in GetDP
# Level	Output Description
# 0	     Silent (no output)
# 1	     Errors only
# 2	     Errors + warnings
# 3	     Errors + warnings + basic info
# 4	     Detailed debugging
# 5	     Full internal tracing
function run_fem_solver(workspace::FEMWorkspace, fem_formulation::AbstractFormulation)
    # Initialize Gmsh if not already initialized
    if gmsh.is_initialized() == 0
        gmsh.initialize()
    end

    # Number of iterations (from the original function)
    n_phases = sum([length(c.design_data.components) for c in workspace.problem_def.system.cables])

    # Flag to track if all solves are successful
    all_success = true

    # Loop over each active_ind from 1 to n_phases
    for i in 1:n_phases
        # Construct solver command with -setnumber active_ind i
        solve_cmd = "$(workspace.opts.getdp_executable) $(fem_formulation.problem.filename) -msh $(workspace.paths[:mesh_file]) -solve $(fem_formulation.resolution_name) -setnumber active_con $i -v$(workspace.opts.verbosity == 0 ? 2 : 3)"

        # Log the current solve attempt
        @info "Solving for source conductor $i... (Resolution = $(fem_formulation.resolution_name))"

        # Attempt to run the solver
        try
            gmsh.onelab.run("GetDP", solve_cmd)

            if workspace.opts.plot_field_maps
                @info "Building field maps for source conductor $i... (Resolution = $(fem_formulation.resolution_name))"

                post_cmd = "$(workspace.opts.getdp_executable) $(fem_formulation.problem.filename) -msh $(workspace.paths[:mesh_file]) -pos Field_Maps -setnumber active_con $i -v$(workspace.opts.verbosity == 0 ? 2 : 3)"

                gmsh.onelab.run("GetDP", post_cmd)
            end

            @info "Solve successful for source conductor $(i)!"
        catch e
            # Log the error and update the success flag
            @error "Solver failed for source conductor $i: $e"
            all_success = false
            # Continue to the next iteration even if this one fails
        end
    end

    # Return true only if all solves were successful
    return all_success
end