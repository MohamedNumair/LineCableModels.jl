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

function get_physical_group_color(workspace::FEMWorkspace, physical_group_tag::Int)
    # Default alpha value
    alpha = 255

    # Check if it's a cable component by looking at the first digit (1)
    # Cable tags follow pattern 1CCOGYYYYY where first digit is 1
    if physical_group_tag >= 100000000 && physical_group_tag < 200000000
        # It's a cable - get material color from the material map
        if haskey(workspace.material_map, physical_group_tag)
            # Get color from material
            material = workspace.material_map[physical_group_tag]
            color = DataModel._get_material_color(material)

            # Convert from 0-1 range to 0-255 range
            r = round(Int, color.r * 255)
            g = round(Int, color.g * 255)
            b = round(Int, color.b * 255)
            a = round(Int, color.alpha * 255)
        else
            # Default color if material not found (bright magenta to highlight missing materials)
            r, g, b = 255, 0, 255
        end
    else
        # Not a cable - check if it's an environment entity
        # Environment tags: first digit 3, second digit indicates position (0=earth, 1=air)
        first_digit = div(physical_group_tag, 1000000)
        second_digit = div(physical_group_tag % 1000000, 100000)
        third_digit = div(physical_group_tag % 100000, 10000)  # surface_type in encode_medium_tag
        layer_idx = physical_group_tag % 10000

        if first_digit == 3
            if second_digit == 1
                # Air (3 1 x xxxx)
                r, g, b = 173, 216, 230  # Light blue for air
            elseif second_digit == 0
                # Earth (3 0 x xxxx)
                if third_digit == 2
                    # Infinite shell region (3 0 2 xxxx)
                    r, g, b = 25, 25, 112  # Midnight blue for infinity shells
                else
                    # Regular earth layers - create brownish gradient based on layer_idx
                    # Base brown color: RGB(139, 69, 19)
                    # Adjust lightness based on layer index (deeper layers are darker)
                    base_r, base_g, base_b = 139, 69, 19  # Base brown (sienna)

                    # Modulate the color based on layer index (max considered: 10 layers)
                    factor = max(0.5, 1.0 - (layer_idx - 1) * 0.05)  # Layer 1->1.0, layer 10->0.55

                    r = round(Int, base_r * factor)
                    g = round(Int, base_g * factor)
                    b = round(Int, base_b * factor)
                end
            else
                # Unknown environment type - use gray
                r, g, b = 128, 128, 128
            end
        else
            # Not a cable or known environment entity - use default gray
            r, g, b = 192, 192, 192
        end
    end

    # Set the color for the physical group
    return (r, g, b, alpha)
end