using Documenter
using DocumenterCitations
using Literate
using Pkg
using Changelog
using DocStringExtensions
"""
Custom METHODLIST generator that uses relative paths.
"""
function custom_methodlist(f::Function, M::Module)
	# Find the root directory of the package associated with module M
	pkg_root = pkgdir(M)
	if pkg_root === nothing
		@warn "Could not determine package root for module $M. Using absolute paths."
		pkg_root = "" # Avoid error later, paths will remain absolute/weird
	end

	io = IOBuffer()
	# println(io, "\n# Methods\n") # Add the header manually if desired

	ms = methods(f)
	if isempty(ms)
		# Handle the case where the function has no methods defined yet
		# Or perhaps it's not a function, though METHODLIST implies it is.
		println(io, "No methods defined.")
		return String(take!(io))
	end

	for method in ms
		sig = Base.tuple_type_head(method.sig) # The signature type tuple
		file = String(method.file)
		line = method.line

		# Clean up the path
		display_path = if !isempty(pkg_root) && startswith(file, pkg_root)
			# Calculate relative path if possible
			relpath(file, pkg_root)
		else
			# Otherwise, use just the filename as a fallback
			basename(file)
		end

		# Generate the list item.
		# Note: Documenter usually handles linking automatically based on signature.
		# We just provide the text description. The @ref lookup happens later.
		# Formatting mimics the default style.
		println(io, "- `", method.sig, "` defined at `", display_path, ":", line, "`.")
		# Alternative simpler link (might not always resolve correctly if signatures are ambiguous)
		# println(io, "- [`", method.sig, "`](@ref) defined at `", display_path, ":", line, "`.")
	end

	return String(take!(io))
end

DocStringExtensions.set_template!(:METHODLIST, custom_methodlist)

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
