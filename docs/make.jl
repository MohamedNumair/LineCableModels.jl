using Documenter
using DocumenterCitations
using Literate
using Pkg
using Changelog
using DocStringExtensions
using Documenter.Utilities: @docerror
using Base.Docs: DocStr

function get_project_toml()
	# Get the current active environment (docs)
	docs_env = Pkg.project().path

	# Path to the main project (one level up from docs)
	main_project_path = joinpath(dirname(docs_env), "..")

	# Parse the main project's TOML
	project_toml = Pkg.TOML.parsefile(joinpath(main_project_path, "Project.toml"))

	return project_toml
end

# Get project data
PROJECT_TOML = get_project_toml()
PROJECT_VERSION = PROJECT_TOML["version"]
NAME = PROJECT_TOML["name"]
AUTHORS = join(PROJECT_TOML["authors"], ", ") * " and contributors."
GITHUB = PROJECT_TOML["git_url"]

@eval using $(Symbol(NAME))
main_module = @eval $(Symbol(NAME))

function customize_literate_footer(content, custom_footer = "")
	if isempty(custom_footer)
		return replace(
			content,
			r"---\s*\n\*This page was generated using \[Literate\.jl\]\(.*?\)\.\*\s*$" => "",
		)
	else
		return replace(content,
			r"\*This page was generated using \[Literate\.jl\]\(.*?\)\.\*\s*$" =>
				custom_footer)
	end
end

tutorial_source = joinpath(@__DIR__, "..", "examples")
tutorial_output = joinpath(@__DIR__, "src", "tutorials")
# Remove the directory if it exists and then create it fresh
if isdir(tutorial_output)
	rm(tutorial_output, recursive = true)
end
mkpath(tutorial_output)

for file in readdir(tutorial_source)
	if endswith(file, ".jl")
		Literate.markdown(
			joinpath(tutorial_source, file),
			tutorial_output,
			documenter = true,
			postprocess = content ->
				customize_literate_footer(content, "🏠 Back to [Tutorials](@ref)\n"),
		)
	end
end

# Get all .md files in tutorial_output
tutorial_files = filter(
	file -> endswith(file, ".md") && file != "index.md",
	readdir(tutorial_output),
)

# Build menu from existing files only
tutorial_menu = ["Contents" => "tutorials.md"]
for file in tutorial_files
	relative_path = String(joinpath("tutorials", file))  # Convert to full String
	# Get title from file content
	content = read(joinpath(tutorial_output, file), String)
	m = match(r"#\s+(.*)", content)
	# Make sure title is a full String too, not SubString
	if m !== nothing
		title = String(m.captures[1])
	else
		title = String(titlecase(replace(basename(file)[1:end-3], "_" => " ")))
	end
	push!(tutorial_menu, title => relative_path)
end

tutorial_pages = [String(joinpath("tutorials", file)) for file in tutorial_files]

bib = CitationBibliography(
	joinpath(@__DIR__, "src", "refs.bib"),
	style = :numeric,  # default
)

DocMeta.setdocmeta!(
	main_module,
	:DocTestSetup,
	:(using $(Symbol(NAME)));
	recursive = true,
)

mathengine = MathJax3(
	Dict(
		:loader => Dict("load" => ["[tex]/physics"]),
		:tex => Dict(
			"inlineMath" => [["\$", "\$"], ["\\(", "\\)"]],
			"tags" => "ams",
			"packages" => ["base", "ams", "autoload", "physics"],
		),
		:chtml => Dict(
			:scale => 1.1,
		),
	),
)

Changelog.generate(
	Changelog.Documenter(),                 # output type
	joinpath(@__DIR__, "..", "CHANGELOG.md"),  # input file
	joinpath(@__DIR__, "src", "CHANGELOG.md"); # output file
	repo = "Electa-Git/LineCableModels.jl",        # default repository for links
)

todo_src = joinpath(@__DIR__, "..", "TODO.md")
todo_dest = joinpath(@__DIR__, "src", "TODO.md")
cp(todo_src, todo_dest, force = true)

# --- Monkey-Patch DocStringExtensions.format for MethodList ---
@info "Applying monkey-patch to DocStringExtensions.format(::MethodList, ...) for relative paths."

# Define the NEW format method, OVERWRITING the default one for MethodList
function DocStringExtensions.format(
	::DocStringExtensions.MethodList,
	buf::IOBuffer,
	doc::Documenter.Utilities.DocStr,
)
	# --- Logic copied/adapted from DocStringExtensions internal format(::MethodList, ...) ---
	# (Using the robust logic from the previous attempt)
	local binding = doc.data[:binding]
	local typesig = doc.data[:typesig]
	local modname = doc.data[:module] # Module where the docstring is defined

	local func = nothing
	try
		func = Docs.resolve(binding)
	catch err
		@docerror(
			Documenter,
			doc,
			"'$binding' could not be resolved in module '$modname': $err"
		)
		return
	end

	if !(func isa Function || func isa DataType)
		@docerror(
			Documenter,
			doc,
			"METHODLIST can only be applied to Functions or DataTypes, got $(typeof(func)) for binding '$binding'."
		)
		return
	end

	local groups = DocStringExtensions.methodgroups(func, typesig, modname; exact = false)

	if isempty(groups)
		println(buf)
		return
	end

	println(buf) # Add leading newline

	local pkg_root = Pkg.pkgdir(modname) # Use Pkg.pkgdir here
	if pkg_root === nothing
		@warn "Could not determine package root for module $modname using METHODLIST. Paths will be shown as basenames."
	end

	for group in groups
		isempty(group) && continue

		println(buf, "```julia")
		for method in group
			# Ensure printmethod is qualified if not automatically found
			DocStringExtensions.printmethod(buf, binding, func, method)
			println(buf)
		end
		println(buf, "```\n")

		local method = first(group)
		local file_str = string(method.file)
		local line = method.line

		# --- Path Modification Logic ---
		local display_path =
			if pkg_root !== nothing && !isempty(file_str) && startswith(file_str, pkg_root)
				relpath(file_str, pkg_root)
			elseif !isempty(file_str) && isfile(file_str)
				basename(file_str)
			else
				string(method.file) # Fallback
			end
		# --- End Path Modification ---

		# Get URL using qualified helper
		local URL = DocStringExtensions.url(method)

		if !isempty(URL)
			println(buf, "defined at [`$display_path:$line`]($URL).")
		elseif !isempty(display_path) && line > 0
			println(buf, "defined at `$display_path:$line`.")
		end
		println(buf) # Add newline after the 'defined at' line
	end

	return nothing # Format functions modify the buffer directly
end
# --- End Monkey-Patch ---

makedocs(;
	modules = [main_module],
	authors = "Amauri Martins",
	sitename = "$NAME.jl",
	format = Documenter.HTML(;
		mathengine = mathengine,
		edit_link = "main",
		assets = [
			"assets/citations.css",
			"assets/favicon.ico",
			"assets/custom.css",
			"assets/custom.js",
		],
		prettyurls = get(ENV, "CI", "false") == "true",
		ansicolor = true,
		collapselevel = 1,
		footer = "[$NAME.jl]($GITHUB) v$PROJECT_VERSION supported by the Etch Competence Hub of EnergyVille, financed by the Flemish Government.",
		size_threshold = nothing,
	),
	pages = [
		"Home" => "index.md",
		"Tutorials" => tutorial_menu,
		"Toolbox reference" => "reference.md",
		"Development" => Any[
			"Naming conventions"=>"conventions.md",
			"TODO"=>"TODO.md",
			"Changelog"=>"CHANGELOG.md",
		],
		"Bibliography" => "bib.md",
	],
	clean = true,
	plugins = [bib],
	checkdocs = :exports,
	pagesonly = true,
	warnonly = false,
)

if haskey(ENV, "CI")
	deploydocs(
		repo = "github.com/Electa-Git/LineCableModels.jl.git",
		devbranch = "main",
		versions = ["stable" => "v^", "dev" => "main"],
		branch = "gh-pages",
	)
end
@info "Finished docs build." # Good to know the script completed

