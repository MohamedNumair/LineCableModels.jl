using GetDP
# using GetDP: Problem

# Revise.track(GetDP)
const PHASES = [("Pa", 0.0), ("Pb", -120 / 180 * pi), ("Pc", -240 / 180 * pi)]
const DEFAULT_CONSTS = [("I", 1.0), ("V0", 1.0), ("Flag_Degree_a", "1"), ("Flag_Degree_v", "1")] # Exclude Freq


function setup_group_function(main_problem, workspace, freq)
    # Use more descriptive collections with cleaner initialization
    material_regions = Dict{Symbol,Vector{Int}}(
        :conducting => Int[],
        :insulation => Int[],
        :infshell => Int[]
    )
    inds_reg = Dict{Int,Vector{Int}}()
    cables_reg = Dict{Int,Vector{Int}}()
    boundary_reg = Int[]

    # Create material properties function
    func = GetDP.Function()

    # Process physical groups in a single pass
    for (tag, mat) in workspace.physical_groups
        if tag > 10^8
            # Add material properties for this region
            add!(func, "nu", expression=1 / (mat.mu_r * μ₀), region=[tag])
            add!(func, "sigma", expression=isinf(mat.rho) ? 0.0 : 1 / mat.rho, region=[tag])
            add!(func, "epsilon", expression=mat.eps_r * ε₀, region=[tag])
            add_space!(func)

            # Decode tag information
            surface_type, entity_num, component_num, material_group, _ = decode_physical_group_tag(tag)

            # Categorize regions in a single operation
            if surface_type == 1
                push!(get!(cables_reg, entity_num, Int[]), tag)
            end

            if material_group == 1
                push!(material_regions[:conducting], tag)
                component_num == 1 && push!(get!(inds_reg, entity_num, Int[]), tag)
            elseif material_group == 2
                push!(material_regions[:insulation], tag)
            end

            surface_type == 3 && push!(material_regions[:infshell], tag)

        elseif 10^6 ≤ tag < 10^8
            decode_boundary_tag(tag)[1] == 2 && push!(boundary_reg, tag)
        end
    end

    # Add constants more concisely
    for (name, value) in [DEFAULT_CONSTS..., ("Freq", freq)]
        add_constant!(func, name, value)
    end
    add_space!(func)

    # Add other parameters
    add!(func, "Ns", expression="1")
    add!(func, "Sc", expression="SurfaceArea[]")
    add_raw_code!(func, "DefineFunction[js0];")
    add_space!(func)

    push!(main_problem.function_obj, func)

    # Create and configure groups
    group = GetDP.Group()

    # Add Dirichlet and boundary regions
    add!(group, "Sur_Dirichlet_Ele", Int[], "Region")
    add_space!(group)
    add!(group, "Sur_Dirichlet_Mag", boundary_reg, "Region"; comment="n.b=0 on this boundary")
    add_space!(group)

    # Add standard magnetodynamics domains
    domain_configs = [
        ("DomainS0_Mag", Int[], "UNUSED"),
        ("DomainS_Mag", Int[], "UNUSED"),
        ("DomainCWithI_Mag", Int[], "If source massive")
    ]

    for (name, regions, comment) in domain_configs
        add!(group, name, regions, "Region"; comment=comment)
    end
    add_space!(group)

    # Add conducting and insulation regions
    add_batched!(group, "DomainC_Mag", material_regions[:conducting])
    add_space!(group)
    add_batched!(group, "DomainCC_Mag", material_regions[:insulation])
    add_space!(group)

    # Process induction regions
    for (key, value) in inds_reg
        add!(group, "Ind_$key", value, "Region")
    end

    all_inds = reduce(vcat, values(inds_reg); init=Int[])
    add!(group, "Inds", all_inds, "Region")
    add!(group, "DomainCWithI_Mag", ["Inds"], "Region")
    add_space!(group)

    # Process cable regions
    for (key, value) in cables_reg
        add!(group, "Cable_$key", value, "Region")
    end
    add!(group, "Cable", ["Cable_$k" for k in keys(cables_reg)], "Region")
    add_space!(group)

    # Add domain groupings
    add!(group, "Domain_Mag", ["DomainCC_Mag", "DomainC_Mag"], "Region")
    add_space!(group)
    add!(group, "Domain_Ele", ["Cable"], "Region"; comment="Just the cable or the same domain as magnetodynamics")
    add_space!(group)
    add!(group, "DomainDummy", [12345], "Region")
    add!(group, "DomainInf", material_regions[:infshell], "Region")

    push!(main_problem.group, group)
end




"""
    make_getdp_problem(workspace)

Creates all the necessary problem definitions for GetDP opts.
Returns a tuple of (main_problem, jacobian_problem, electrodynamic_problem, darwin_problem)
"""
function make_getdp_problem(workspace::FEMWorkspace, freq::Float64)::Vector{<:AbstractFEMFormulation}
    # workspace.opts.analysis_type
    # Create Unique problem
    main_problem = Problem()

    # Create jacobian problem
    create_jacobian_problem(
        main_problem,
        workspace.formulation.domain_radius,
        workspace.formulation.domain_radius_inf)

    # Setup the Groups and Function (physical parameters)
    setup_group_function(main_problem, workspace, freq)

    # Create constraint
    create_constraint(main_problem, length(workspace.problem_def.system.cables))

    fem_objs = set_problem!(main_problem, workspace, Val(workspace.problem_def.analysis_type))

    return fem_objs
end


# """
#     create_main_problem(workspace, entities)

# Create the main Problem for GetDP with problem constants, functions, groups,
# constraints, and macro definitions.
# """
# function create_main_problem(main_problem::Problem, workspace::FEMWorkspace, freq::Float64)

#     # Setup the Groups and Function (physical parameters)
#     setup_group_function(main_problem, workspace, freq)

#     # Create constraint
#     create_constraint(main_problem, length(workspace.problem_def.system.cables))

# end

"""
    add_batched!(group, name, items; batch_size=4, kwargs...)

Add items to a group in batches to improve performance.
"""
function add_batched!(group, name, items; batch_size=4, kwargs...)
    isempty(items) && return

    # First batch uses direct assignment
    first_batch = items[1:min(batch_size, length(items))]
    add!(group, name, first_batch, "Region"; kwargs...)

    # Remaining batches use += operation
    for i in (batch_size+1):batch_size:length(items)
        batch_end = min(i + batch_size - 1, length(items))
        add!(group, name, items[i:batch_end], "Region"; operation="+=", kwargs...)
    end
end

"""
    create_constraint(inds_reg, phases)

Create constraint definitions for the problem.
"""
function create_constraint(main_problem::GetDP.Problem, number_of_core_cables::Int64)
    constraint = GetDP.Constraint()

    # Electrical constraints
    add_comment!(constraint, "Electrical constraints")

    # ElectricScalarPotential
    esp = assign!(constraint, "ElectricScalarPotential")
    for (inds_num, phase) in zip(1:number_of_core_cables, PHASES)
        case!(esp, "Ind_$inds_num", value="V0", time_function="F_Cos_wt_p[]{2*Pi*Freq, $(phase[2])}")
    end
    case!(esp, "Sur_Dirichlet_Ele", value="0")

    # ZeroElectricScalarPotential (for second order basis functions)
    zesp = assign!(constraint, "ZeroElectricScalarPotential", comment="Only if second order basis functions")
    case!(zesp, "Sur_Dirichlet_Ele", value="0")
    zesp_loop = for_loop!(zesp, "k", "1:$(number_of_core_cables)")
    case!(zesp_loop, "Ind~{k}", value="0")

    # Magnetic constraints
    add_comment!(constraint, "Magnetic constraints")

    # MagneticVectorPotential_2D
    mvp = assign!(constraint, "MagneticVectorPotential_2D")
    case!(mvp, "Sur_Dirichlet_Mag", value="0.")

    # Voltage_2D (placeholder)
    voltage = assign!(constraint, "Voltage_2D")
    case!(voltage, "", comment="UNUSED")

    # Current_2D
    current = assign!(constraint, "Current_2D", comment="constraint for three-phase cable")
    for (inds_num, phase) in zip(1:number_of_core_cables, PHASES)
        case!(current, "Ind_$inds_num", value="I", time_function="F_Cos_wt_p[]{2*Pi*Freq, $(phase[2])}")
    end
    push!(main_problem.constraint, constraint)

end

"""
    create_jacobian_problem(workspace)

Create the Jacobian problem for GetDP.
"""
function create_jacobian_problem(problem, Rint, Rext)

    # Initialize Jacobian
    jac = Jacobian()

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
        comment="Attention: there is no spherical shell for lines in a surface domain"
    )

    # Add Jacobian to problem
    push!(problem.jacobian, jac)

    # Initialize Integration
    integ = Integration()
    i1 = add!(integ, "I1")
    case = add!(i1)
    geo_case = add_nested_case!(case; type="Gauss")
    add!(geo_case; GeoElement="Point", NumberOfPoints=1)
    add!(geo_case; GeoElement="Line", NumberOfPoints=4)
    add!(geo_case; GeoElement="Triangle", NumberOfPoints=4)
    add!(geo_case; GeoElement="Quadrangle", NumberOfPoints=4)
    add!(geo_case; GeoElement="Triangle2", NumberOfPoints=7)
    push!(problem.integration, integ)

end

"""
    create_electrodynamic_problem(inds_reg, phases)

Create the electrodynamic problem for GetDP.
"""
function create_electrodynamic_problem(problem, num_sources, resolution_name)


    # FunctionSpace section
    functionspace = FunctionSpace()
    fs1 = add!(functionspace, "Hgrad_v_Ele", nothing, nothing, Type="Form0")
    add_basis_function!(functionspace, "sn", "vn", "BF_Node"; Support="Domain_Ele", Entity="NodesOf[ All ]")
    add_basis_function!(functionspace, "sn2", "vn2", "BF_Node_2E";
        Support="Domain_Ele",
        Entity="EdgesOf[ All ]",
        condition="If (Flag_Degree_v == 2)",
        endCondition="EndIf")

    add_constraint!(functionspace, "vn", "NodesOf", "ElectricScalarPotential")
    add_constraint!(functionspace, "vn2", "EdgesOf", "ZeroElectricScalarPotential";
        condition="If (Flag_Degree_v == 2)",
        endCondition="EndIf")

    # problem.functionspace = functionspace
    push!(problem.functionspace, functionspace)

    # Formulation section
    formulation = Formulation()
    form = add!(formulation, "Electrodynamics_v", "FemEquation")
    add_quantity!(form, "v", Type="Local", NameOfSpace="Hgrad_v_Ele")

    eq = add_equation!(form)
    add!(eq, "Galerkin", "[ sigma[] * Dof{d v} , {d v} ]", In="Domain_Ele", Jacobian="Vol", Integration="I1")
    add!(eq, "Galerkin", "DtDof[ epsilon[] * Dof{d v} , {d v} ]", In="Domain_Ele", Jacobian="Vol", Integration="I1")

    # problem.formulation = formulation
    push!(problem.formulation, formulation)

    # Resolution section
    resolution = Resolution()
    add!(resolution, resolution_name, "Sys_Ele",
        NameOfFormulation="Electrodynamics_v",
        Type="Complex",
        Frequency="Freq",
        Operation=[
            "CreateDir[\"$(joinpath("results", resolution_name))\"]",
            "Generate[Sys_Ele]",
            "Solve[Sys_Ele]",
            "SaveSolution[Sys_Ele]",
            "PostOperation[Ele_Maps]"
            # "PostOperation[Ele_Cuts]"
        ])

    # problem.resolution = resolution
    push!(problem.resolution, resolution)

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
    add!(q, "Term", "-sigma[] * {d v}"; In="Domain_Ele", Jacobian="Vol")
    add!(q, "Term", "-epsilon[] * Dt[{d v}]"; In="Domain_Ele", Jacobian="Vol")

    # Add ElectricEnergy
    q = add!(pp, "ElectricEnergy")
    add!(q, "Integral", "0.5 * epsilon[] * SquNorm[{d v}]"; In="Domain_Ele", Jacobian="Vol", Integration="I1")

    # V0
    q = add!(pp, "V0")
    for (inds_num, phase) in zip(1:num_sources, PHASES)
        add!(q, "Term", "V0 * F_Cos_wt_p[]{2*Pi*Freq, $(phase[2])}"; Type="Global", In="Ind_$inds_num")
    end

    # C_from_Energy
    q = add!(pp, "C_from_Energy")
    add!(q, "Term", "2*\$We/SquNorm[\$voltage]"; Type="Global", In="DomainDummy")

    # problem.postprocessing = postprocessing
    push!(problem.postprocessing, postprocessing)

    # PostOperation section
    postoperation = PostOperation()
    add_comment!(postoperation, "Electric")
    add_comment!(postoperation, "-------------------------------")
    add_raw_code!(postoperation, "po0 = \"{01Capacitance/\";")

    # Ele_Maps
    po1 = add!(postoperation, "Ele_Maps", "EleDyn_v")
    op1 = add_operation!(po1)
    add_operation!(op1, "Print[ v, OnElementsOf Domain_Ele, File \"$(joinpath("results", resolution_name))/v.pos\" ];")
    add_operation!(op1, "Print[ em, OnElementsOf Cable, Name \"|E| [V/m]\", File \"$(joinpath("results", resolution_name))/em.pos\" ];")
    add_operation!(op1, "Print[ dm, OnElementsOf Cable, Name \"|D| [A/m²]\", File \"$(joinpath("results", resolution_name))/dm.pos\" ];")
    add_operation!(op1, "Print[ e, OnElementsOf Cable, Name \"E [V/m]\", File \"$(joinpath("results", resolution_name))/e.pos\" ];")
    # add_operation!(op1, "Call Change_post_options;")
    add_operation!(op1, "Print[ ElectricEnergy[Domain_Ele], OnGlobal, Format Table, StoreInVariable \$We, SendToServer StrCat[po0,\"0Electric energy\"], File \"$(joinpath("results", resolution_name))/energy.dat\" ];")
    add_operation!(op1, "Print[ V0, OnRegion Ind_1, Format Table, StoreInVariable \$voltage, SendToServer StrCat[po0,\"0U1\"], Units \"V\", File \"$(joinpath("results", resolution_name))/U.dat\" ];")
    add_operation!(op1, "Print[ C_from_Energy, OnRegion DomainDummy, Format Table, StoreInVariable \$C1, SendToServer StrCat[po0,\"1Cpha\"], Units \"F/m\", File \"$(joinpath("results", resolution_name))/C.dat\" ];")

    # problem.postoperation = postoperation
    push!(problem.postoperation, postoperation)

end

"""
    create_darwin_problem()

Create the Darwin problem for GetDP.
"""
function create_darwin_problem(problem, resolution_name)

    # Create a new Problem instance
    functionspace = FunctionSpace()

    # FunctionSpace section
    fs1 = add!(functionspace, "Hcurl_a_Mag_2D", nothing, nothing, Type="Form1P")
    add_basis_function!(functionspace, "se", "ae", "BF_PerpendicularEdge"; Support="Domain_Mag", Entity="NodesOf[ All ]")
    add_basis_function!(functionspace, "se2", "ae2", "BF_PerpendicularEdge_2E";
        Support="Domain_Mag",
        Entity="EdgesOf[ All ]",
        condition="If (Flag_Degree_a == 2)",
        endCondition="EndIf")

    add_constraint!(functionspace, "ae", "NodesOf", "MagneticVectorPotential_2D")
    add_constraint!(functionspace, "ae2", "EdgesOf", "MagneticVectorPotential_2D";
        comment=" Only OK if homogeneous BC, otherwise specify zero-BC",
        condition="If (Flag_Degree_a == 2)",
        endCondition="EndIf")


    fs2 = add!(functionspace, "Hregion_i_2D", nothing, nothing, Type="Vector")
    add_basis_function!(functionspace, "sr", "ir", "BF_RegionZ"; Support="DomainS_Mag", Entity="DomainS_Mag")
    add_global_quantity!(functionspace, "Is", "AliasOf"; NameOfCoef="ir")
    add_global_quantity!(functionspace, "Us", "AssociatedWith"; NameOfCoef="ir")
    add_constraint!(functionspace, "Us", "Region", "Voltage_2D")
    add_constraint!(functionspace, "Is", "Region", "Current_2D")


    fs3 = add!(functionspace, "Hregion_u_Mag_2D", nothing, nothing, Type="Form1P", comment=" Gradient of Electric scalar potential (2D)")
    add_basis_function!(functionspace, "sr", "ur", "BF_RegionZ"; Support="DomainC_Mag", Entity="DomainC_Mag")
    add_global_quantity!(functionspace, "U", "AliasOf"; NameOfCoef="ur")
    add_global_quantity!(functionspace, "I", "AssociatedWith"; NameOfCoef="ur")
    add_constraint!(functionspace, "U", "Region", "Voltage_2D")
    add_constraint!(functionspace, "I", "Region", "Current_2D")

    # problem.functionspace = functionspace
    push!(problem.functionspace, functionspace)

    # Define Formulation
    formulation = GetDP.Formulation()

    form = add!(formulation, "Darwin_a_2D", "FemEquation"; comment=" Magnetodynamics + displacement current, no coupling")
    add_quantity!(form, "a", Type="Local", NameOfSpace="Hcurl_a_Mag_2D")
    add_quantity!(form, "ur", Type="Local", NameOfSpace="Hregion_u_Mag_2D", comment=" massive conductors (source or not)")
    add_quantity!(form, "I", Type="Global", NameOfSpace="Hregion_u_Mag_2D [I]")
    add_quantity!(form, "U", Type="Global", NameOfSpace="Hregion_u_Mag_2D [U]")
    add_quantity!(form, "ir", Type="Local", NameOfSpace="Hregion_i_2D", comment=" stranded conductors (source)")
    add_quantity!(form, "Us", Type="Global", NameOfSpace="Hregion_i_2D[Us]")
    add_quantity!(form, "Is", Type="Global", NameOfSpace="Hregion_i_2D[Is]")

    eq = add_equation!(form)

    add!(eq, "Galerkin", "[ nu[] * Dof{d a} , {d a} ]", In="Domain_Mag", Jacobian="Vol", Integration="I1")
    add!(eq, "Galerkin", "DtDof [ sigma[] * Dof{a} , {a} ]", In="DomainC_Mag", Jacobian="Vol", Integration="I1")
    add!(eq, "Galerkin", "[ sigma[] * Dof{ur}, {a} ]", In="DomainC_Mag", Jacobian="Vol", Integration="I1")
    add!(eq, "Galerkin", "DtDof [ sigma[] * Dof{a} , {ur} ]", In="DomainC_Mag", Jacobian="Vol", Integration="I1")
    add!(eq, "Galerkin", "[ sigma[] * Dof{ur}, {ur}]", In="DomainC_Mag", Jacobian="Vol", Integration="I1")
    add!(eq, "Galerkin", "DtDtDof [ epsilon[] * Dof{a} , {a}]", In="DomainC_Mag", Jacobian="Vol", Integration="I1", comment=" Added term => Darwin approximation")
    add!(eq, "Galerkin", "DtDof[ epsilon[] * Dof{ur}, {a} ]", In="DomainC_Mag", Jacobian="Vol", Integration="I1")
    add!(eq, "Galerkin", "DtDtDof [ epsilon[] * Dof{a} , {ur}]", In="DomainC_Mag", Jacobian="Vol", Integration="I1")
    add!(eq, "Galerkin", "DtDof[ epsilon[] * Dof{ur}, {ur} ]", In="DomainC_Mag", Jacobian="Vol", Integration="I1")
    add!(eq, "GlobalTerm", "[ Dof{I} , {U} ]", In="DomainCWithI_Mag")
    add!(eq, "Galerkin", "[ -js0[] , {a} ]", In="DomainS0_Mag", Jacobian="Vol", Integration="I1", comment=" Either you impose directly the function js0[]")
    add!(eq, "Galerkin", "[ -Ns[]/Sc[] * Dof{ir}, {a} ]", In="DomainS_Mag", Jacobian="Vol", Integration="I1", comment=" or you use the constraints => allows accounting for sigma[]")
    add!(eq, "Galerkin", "DtDof [ Ns[]/Sc[] * Dof{a}, {ir} ]", In="DomainS_Mag", Jacobian="Vol", Integration="I1")
    add!(eq, "Galerkin", "[ Ns[]/Sc[] / sigma[] * Ns[]/Sc[]* Dof{ir} , {ir}]", In="DomainS_Mag", Jacobian="Vol", Integration="I1", comment=" resistance term")
    add!(eq, "GlobalTerm", "[ Dof{Us}, {Is} ]", In="DomainS_Mag")

    # Add the formulation to the problem
    # problem.formulation = formulation
    push!(problem.formulation, formulation)

    # Define Resolution
    resolution = Resolution()

    # Add a resolution
    add!(resolution, resolution_name, "Sys_Mag",
        NameOfFormulation="Darwin_a_2D",
        Type="Complex", Frequency="Freq",
        Operation=[
            "CreateDir[\"$(joinpath("results", resolution_name))\"]",
            "InitSolution[Sys_Mag]",
            "Generate[Sys_Mag]",
            "Solve[Sys_Mag]",
            "SaveSolution[Sys_Mag]",
            "PostOperation[Mag_Maps]",
            "PostOperation[Mag_Global]"
        ])

    # Add the resolution to the problem
    # problem.resolution = resolution
    push!(problem.resolution, resolution)

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
    add!(q, "Term", "-sigma[]*(Dt[{a}]+{ur})"; In="DomainC_Mag", Jacobian="Vol")
    add!(q, "Term", "js0[]"; In="DomainS0_Mag", Jacobian="Vol")
    add!(q, "Term", "Ns[]/Sc[]*{ir}"; In="DomainS_Mag", Jacobian="Vol")

    q = add!(pp, "jz")
    add!(q, "Term", "CompZ[-sigma[]*(Dt[{a}]+{ur})]"; In="DomainC_Mag", Jacobian="Vol")
    add!(q, "Term", "CompZ[js0[]]"; In="DomainS0_Mag", Jacobian="Vol")
    add!(q, "Term", "CompZ[Ns[]/Sc[]*{ir}]"; In="DomainS_Mag", Jacobian="Vol")

    q = add!(pp, "jm")
    add!(q, "Term", "Norm[-sigma[]*(Dt[{a}]+{ur})]"; In="DomainC_Mag", Jacobian="Vol")
    add!(q, "Term", "Norm[js0[]]"; In="DomainS0_Mag", Jacobian="Vol")
    add!(q, "Term", "Norm[Ns[]/Sc[]*{ir}]"; In="DomainS_Mag", Jacobian="Vol")

    q = add!(pp, "d")
    add!(q, "Term", "epsilon[] * Dt[Dt[{a}]+{ur}]"; In="DomainC_Mag", Jacobian="Vol")
    q = add!(pp, "dz")
    add!(q, "Term", "CompZ[epsilon[] * Dt[Dt[{a}]+{ur}]]"; In="DomainC_Mag", Jacobian="Vol")
    q = add!(pp, "dm")
    add!(q, "Term", "Norm[epsilon[] * Dt[Dt[{a}]+{ur}]]"; In="DomainC_Mag", Jacobian="Vol")

    q = add!(pp, "rhoj2")
    add!(q, "Term", "0.5*sigma[]*SquNorm[Dt[{a}]+{ur}]"; In="DomainC_Mag", Jacobian="Vol")
    add!(q, "Term", "0.5/sigma[]*SquNorm[js0[]]"; In="DomainS0_Mag", Jacobian="Vol")
    add!(q, "Term", "0.5/sigma[]*SquNorm[Ns[]/Sc[]*{ir}]"; In="DomainS_Mag", Jacobian="Vol")

    q = add!(pp, "JouleLosses")
    add!(q, "Integral", "0.5*sigma[]*SquNorm[Dt[{a}]]"; In="DomainC_Mag", Jacobian="Vol", Integration="I1")
    add!(q, "Integral", "0.5/sigma[]*SquNorm[js0[]]"; In="DomainS0_Mag", Jacobian="Vol", Integration="I1")
    add!(q, "Integral", "0.5/sigma[]*SquNorm[Ns[]/Sc[]*{ir}]"; In="DomainS_Mag", Jacobian="Vol", Integration="I1")

    q = add!(pp, "U")
    add!(q, "Term", "{U}"; In="DomainC_Mag")
    add!(q, "Term", "{Us}"; In="DomainS_Mag")

    q = add!(pp, "I")
    add!(q, "Term", "{I}"; In="DomainC_Mag")
    add!(q, "Term", "{Is}"; In="DomainS_Mag")

    q = add!(pp, "S")
    add!(q, "Term", "{U}*Conj[{I}]"; In="DomainC_Mag")
    add!(q, "Term", "{Us}*Conj[{Is}]"; In="DomainS_Mag")

    q = add!(pp, "R")
    add!(q, "Term", "-Re[{U}/{I}]"; In="DomainC_Mag")
    add!(q, "Term", "-Re[{Us}/{Is}]"; In="DomainS_Mag")

    q = add!(pp, "L")
    add!(q, "Term", "-Im[{U}/{I}]/(2*Pi*Freq)"; In="DomainC_Mag")
    add!(q, "Term", "-Im[{Us}/{Is}]/(2*Pi*Freq)"; In="DomainS_Mag")

    q = add!(pp, "R_per_km"; comment=" For convenience... possible scaling")
    add!(q, "Term", "-Re[{U}/{I}]*1e3"; In="DomainC_Mag")
    add!(q, "Term", "-Re[{Us}/{Is}]*1e3"; In="DomainS_Mag")

    q = add!(pp, "mL_per_km")
    add!(q, "Term", "-1e6*Im[{U}/{I}]/(2*Pi*Freq)"; In="DomainC_Mag")
    add!(q, "Term", "-1e6*Im[{Us}/{Is}]/(2*Pi*Freq)"; In="DomainS_Mag")

    q = add!(pp, "Zs")
    add!(q, "Term", "-{U}/{I}"; In="DomainC_Mag")
    add!(q, "Term", "-{Us}/{Is}"; In="DomainS_Mag")

    # problem.postprocessing = postprocessing
    push!(problem.postprocessing, postprocessing)

    # PostOperation section
    postoperation = PostOperation()

    # Add post-operation items
    po1 = add!(postoperation, "Mag_Maps", "Darwin_a_2D")
    po2 = add!(postoperation, "Mag_Global", "Darwin_a_2D")

    # Add operations for maps
    op1 = add_operation!(po1)  # Creates a POBase_ for po1

    add_operation!(op1, "Print[ az, OnElementsOf Domain_Mag, //Smoothing 1\n        Name \"flux lines: Az [T m]\", File \"$(joinpath("results", resolution_name))/az.pos\" ];")
    add_operation!(op1, "Echo[Str[\"View[PostProcessing.NbViews-1].RangeType = 3;\", // per timestep\n    \"View[PostProcessing.NbViews-1].NbIso = 25;\",\n    \"View[PostProcessing.NbViews-1].IntervalsType = 1;\" // isolines\n    ], File \"$(joinpath("results", resolution_name))/maps.opt\"];")
    add_operation!(op1, "Print[ b, OnElementsOf Domain_Mag, //Smoothing 1,\n        Name \"B [T]\", File \"$(joinpath("results", resolution_name))/b.pos\" ];")
    add_operation!(op1, "Echo[Str[\"View[PostProcessing.NbViews-1].RangeType = 3;\", // per timestep\n    \"View[PostProcessing.NbViews-1].IntervalsType = 2;\"\n    ], File \"$(joinpath("results", resolution_name))/maps.opt\"];")
    add_operation!(op1, "Print[ bm, OnElementsOf Domain_Mag,\n        Name \"|B| [T]\", File \"$(joinpath("results", resolution_name))/bm.pos\" ];")
    add_operation!(op1, "Echo[Str[\"View[PostProcessing.NbViews-1].RangeType = 3;\", // per timestep\n    \"View[PostProcessing.NbViews-1].ShowTime = 0;\",\n    \"View[PostProcessing.NbViews-1].IntervalsType = 2;\"\n    ], File \"$(joinpath("results", resolution_name))/maps.opt\"];")
    add_operation!(op1, "Print[ jz, OnElementsOf Region[{DomainC_Mag, DomainS_Mag}],\n        Name \"jz [A/m^2] Conducting domain\", File \"$(joinpath("results", resolution_name))/jz_inds.pos\" ];")
    add_operation!(op1, "Echo[Str[\"View[PostProcessing.NbViews-1].RangeType = 3;\", // per timestep\n    \"View[PostProcessing.NbViews-1].IntervalsType = 2;\"\n    ], File \"$(joinpath("results", resolution_name))/maps.opt\"];")
    add_operation!(op1, "Print[ rhoj2, OnElementsOf Region[{DomainC_Mag, DomainS_Mag}],\n        Name \"Power density\", File \"$(joinpath("results", resolution_name))/rhoj2.pos\" ];")
    add_operation!(op1, "Echo[Str[\"View[PostProcessing.NbViews-1].RangeType = 3;\", // per timestep\n    \"View[PostProcessing.NbViews-1].ShowTime = 0;\",\n    \"View[PostProcessing.NbViews-1].IntervalsType = 2;\"\n    ], File \"$(joinpath("results", resolution_name))/maps.opt\"];")
    add_operation!(op1, "Print[ jm, OnElementsOf DomainC_Mag,\n        Name \"|j| [A/m^2] Conducting domain\", File \"$(joinpath("results", resolution_name))/jm.pos\" ];")
    add_operation!(op1, "Echo[Str[\"View[PostProcessing.NbViews-1].RangeType = 3;\", // per timestep\n    \"View[PostProcessing.NbViews-1].ShowTime = 0;\",\n    \"View[PostProcessing.NbViews-1].IntervalsType = 2;\"\n    ], File \"$(joinpath("results", resolution_name))/maps.opt\"];")
    add_operation!(op1, "Print[ dm, OnElementsOf DomainC_Mag,\n        Name \"|D| [A/m²]\", File \"$(joinpath("results", resolution_name))/dm.pos\" ];")
    add_operation!(op1, "Echo[Str[\"View[PostProcessing.NbViews-1].RangeType = 3;\", // per timestep\n    \"View[PostProcessing.NbViews-1].ShowTime = 0;\",\n    \"View[PostProcessing.NbViews-1].IntervalsType = 2;\"\n    ], File \"$(joinpath("results", resolution_name))/maps.opt\"];")

    add_raw_code!(po1, "po = \"{01Losses/\";")
    add_raw_code!(po1, "po2 = \"{02PU-parameters/\";")

    op2 = add_operation!(po2)  # Creates a POBase_ for po2
    add_operation!(op2, "Print[ JouleLosses[DomainC_Mag], OnGlobal, Format Table,\n    SendToServer StrCat[po,\"0Total conducting domain\"],\n    Units \"W/m\", File \"$(joinpath("results", resolution_name))/losses_total.dat\" ];", comment=" You may restrict DomainC_Mag to part of it")
    add_operation!(op2, "Print[ JouleLosses[Inds], OnGlobal, Format Table,\n    SendToServer StrCat[po,\"3Source (stranded OR massive)\"],\n    Units \"W/m\", File \"$(joinpath("results", resolution_name))/losses_inds.dat\" ];")
    add_operation!(op2, "Print[ R, OnRegion Inds, Format Table,\n    SendToServer StrCat[po2,\"0R\"],\n    Units \"Ω\", File \"$(joinpath("results", resolution_name))/Rinds.dat\" ];", comment=" Region to adapt according to your cable")
    add_operation!(op2, "Print[ L, OnRegion Inds, Format Table,\n    SendToServer StrCat[po2,\"1L\"],\n    Units \"H\", File \"$(joinpath("results", resolution_name))/Linds.dat\" ];")
    add_operation!(op2, "Print[ Zs[DomainC_Mag], OnRegion Inds, Format Table,\n    SendToServer StrCat[po2,\"2re(Zs)\"] {0},\n    Units \"Ω\", File \"$(joinpath("results", resolution_name))/Zsinds_C_Mag.dat\" ];")

    # Add the post-operation to the problem
    # problem.postoperation = postoperation
    push!(problem.postoperation, postoperation)


    # return problem
end

