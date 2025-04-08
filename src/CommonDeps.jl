using DocStringExtensions, Reexport, ForceImport, Pkg
using DocStringExtensions: Abbreviation

struct _CleanMethodList <: Abbreviation end

const _CLEANMETHODLIST = _CleanMethodList()

function format(::_CleanMethodList, buf, doc)
	local binding = doc.data[:binding]
	local typesig = doc.data[:typesig]
	local modname = doc.data[:module]
	local func = Docs.resolve(binding)
	local groups = methodgroups(func, typesig, modname; exact = false)
	if !isempty(groups)
		println(buf)
		local pkg_root = Pkg.pkgdir(modname) # Use Pkg.pkgdir here
		if pkg_root === nothing
			@warn "Could not determine package root for module $modname using METHODLIST. Paths will be shown as basenames."
		end
		for group in groups
			println(buf, "```julia")
			for method in group
				printmethod(buf, binding, func, method)
				println(buf)
			end
			println(buf, "```\n")
			if !isempty(group)
				local method = group[1]
				local file = string(method.file)
				local line = method.line
				# --- Path Modification Logic ---
				local path =
					if pkg_root !== nothing && !isempty(file) &&
					   startswith(file, pkg_root)
						relpath(file, pkg_root)
					elseif !isempty(file) && isfile(file)
						basename(file)
					else
						string(method.file) # Fallback
					end
				# --- End Path Modification ---

				# local path = cleanpath(file)
				local URL = url(method)
				isempty(URL) || println(buf, "defined at [`$path:$line`]($URL).")
			end
			println(buf)
		end
		println(buf)
	end
	return nothing
end
