"""
Visualization functions for the FEMTools.jl module.
These functions handle the visualization of the mesh and results.
"""

"""
$(TYPEDSIGNATURES)

Preview the mesh in the Gmsh GUI.

# Arguments

- `workspace`: The [`FEMWorkspace`](@ref) containing the model.

# Returns

- Nothing. Launches the Gmsh GUI.

# Examples

```julia
$(FUNCTIONNAME)(workspace)
```
"""
function preview_mesh(workspace::FEMWorkspace)
    # Check if Gmsh is already initialized
    gmsh_already_initialized = false

    try
        # Try to get version - this will throw if Gmsh is not initialized
        gmsh.option.getNumber("General.Terminal")
        @debug "Gmsh already initialized"
        gmsh_already_initialized = true
    catch
        gmsh_already_initialized = false
    end

    # Initialize Gmsh if needed
    if !gmsh_already_initialized
        gmsh.initialize()
        @debug "Initialized Gmsh for mesh preview"
    end

    try
        # Set visualization options
        gmsh.option.setNumber("Geometry.SurfaceLabels", 0)  # Show surface labels
        gmsh.option.setNumber("Geometry.PointNumbers", 0)
        gmsh.option.setNumber("Geometry.CurveNumbers", 0)
        gmsh.option.setNumber("Geometry.SurfaceNumbers", 0)
        gmsh.option.setNumber("Geometry.NumSubEdges", 160)
        gmsh.option.setNumber("Geometry.Points", 1)
        gmsh.option.setNumber("Geometry.Curves", 1)
        gmsh.option.setNumber("Geometry.Surfaces", 0)
        gmsh.option.setNumber("Mesh.ColorCarousel", 2)  # Colors by physical group
        gmsh.option.setNumber("Mesh.LineWidth", 1)
        gmsh.option.setNumber("Mesh.SurfaceFaces", 1)

        # Initialize FLTK GUI
        gmsh.fltk.initialize()

        @info "Launching Gmsh GUI for mesh preview"
        @info "Close the Gmsh window to continue..."

        # Define event check function
        function check_for_event()
            action = gmsh.onelab.getString("ONELAB/Action")
            if length(action) > 0 && action[1] == "check"
                gmsh.onelab.setString("ONELAB/Action", [""])
                @debug "UI interaction detected"
                gmsh.graphics.draw()
            end
            return true
        end

        # Wait for user to close the window
        while gmsh.fltk.isAvailable() == 1 && check_for_event()
            gmsh.fltk.wait()
        end

        @info "Mesh preview closed"

    catch e
        @warn "Error during mesh preview: $e"
    end
end

"""
$(TYPEDSIGNATURES)

Preview simulation results in the Gmsh GUI.

# Arguments

- `workspace`: The [`FEMWorkspace`](@ref) containing the model.
- `result_file`: Path to the result file (.pos or .msh). Default: mesh file from workspace.

# Returns

- Nothing. Launches the Gmsh GUI.

# Examples

```julia
$(FUNCTIONNAME)(workspace)
$(FUNCTIONNAME)(workspace, "results/field.pos")
```
"""
function preview_results(workspace::FEMWorkspace, result_file::String="")
    # Use mesh file if no result file provided
    if isempty(result_file)
        result_file = workspace.paths[:mesh_file]
    end

    # Check if the file exists
    if !isfile(result_file)
        @warn "Result file not found: $result_file"
        return
    end

    # Initialize Gmsh
    gmsh.initialize()

    try
        # Set visualization options
        gmsh.option.setNumber("View.VectorType", 4)  # Displacement is vector type
        gmsh.option.setNumber("View.Intervals", 20)  # Number of color intervals
        gmsh.option.setNumber("View.Light", 1)  # Enable lighting
        gmsh.option.setNumber("View.LineWidth", 1.5)

        # Open the result file
        gmsh.open(result_file)

        # Initialize FLTK GUI
        gmsh.fltk.initialize()

        @info "Launching Gmsh GUI for result preview"
        @info "Close the Gmsh window to continue..."

        # Wait for user to close the window
        while gmsh.fltk.isAvailable() == 1
            gmsh.fltk.wait()
        end

        @info "Result preview closed"

    catch e
        @warn "Error during result preview: $e"
    finally
        gmsh.finalize()
    end
end

"""
$(TYPEDSIGNATURES)

Save a screenshot of the current mesh to an image file.

# Arguments

- `workspace`: The [`FEMWorkspace`](@ref) containing the model.
- `output_file`: Path to the output image file.

# Returns

- `true` if successful, `false` otherwise.

# Examples

```julia
$(FUNCTIONNAME)(workspace, "mesh.png")
```
"""
function save_mesh_image(workspace::FEMWorkspace, output_file::String)
    # Check if Gmsh is already initialized
    gmsh_already_initialized = false

    try
        # Try to get version - this will throw if Gmsh is not initialized
        gmsh.option.getNumber("General.Terminal")
        gmsh_already_initialized = true
    catch
        gmsh_already_initialized = false
    end

    # Initialize Gmsh if needed
    if !gmsh_already_initialized
        gmsh.initialize()
        @debug "Initialized Gmsh for saving mesh image"
    end

    try
        # Set visualization options
        gmsh.option.setNumber("Mesh.SurfaceFaces", 1)
        gmsh.option.setNumber("Mesh.Points", 0)
        gmsh.option.setNumber("Mesh.Lines", 1)
        gmsh.option.setNumber("Mesh.ColorCarousel", 2)  # Colors by physical group
        gmsh.option.setNumber("Mesh.LineWidth", 2)

        # Initialize FLTK GUI without showing window
        gmsh.fltk.initialize()

        # Set up camera position (top view)
        gmsh.option.setNumber("General.Trackball", 0)
        gmsh.option.setNumber("General.RotationX", 0.0)
        gmsh.option.setNumber("General.RotationY", 0.0)
        gmsh.option.setNumber("General.RotationZ", 0.0)

        # Draw scene
        gmsh.graphics.draw()

        # Create the directory if it doesn't exist
        output_dir = dirname(output_file)
        if !isempty(output_dir) && !isdir(output_dir)
            mkpath(output_dir)
        end

        # Save screenshot
        gmsh.write(output_file)

        @info "Saved mesh image to: $output_file"

        return true
    catch e
        @warn "Error saving mesh image: $e"
        return false
    end
end
