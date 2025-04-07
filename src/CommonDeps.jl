using DocStringExtensions, Reexport, ForceImport

function _CLEANMETHODLIST(f::Function)
	methods_list = methods(f)
	io = IOBuffer()
	project_root = pkgdir(@__MODULE__) # Get the root directory of your package

	for method in methods_list
		signature = sprint(show, method)
		file, line = string(method.file), method.line

		# Make the path relative
		relative_path = replace(file, "$(project_root)/" => "")

		println(
			io,
			"- [`",
			signature,
			"`](@ref ",
			"`",
			nameof(f),
			"-",
			method.sig,
			"`) defined at `",
			relative_path,
			":",
			line,
			"`",
		)
	end
	return String(take!(io))
end
