using Documenter
using DocumenterCitations
using Pkg

function get_project_toml()
	# Get the current active environment
	docs_env = Pkg.project().path

	# Path to the main project (one level up from docs)
	main_project_path = joinpath(dirname(docs_env), "..")

	# Parse the main project's TOML
	project_toml = Pkg.TOML.parsefile(joinpath(main_project_path, "Project.toml"))
	project_name = project_toml["name"]

	# Activate main project temporarily to check dependencies
	Pkg.activate(main_project_path)
	Pkg.activate(docs_env)

	# Check if main project is added to docs
	try
		# Try to import the main package
		@eval import $(Symbol(project_name))
	catch e
		# If it fails, develop the main package into docs environment
		@info "Adding main project to docs environment..."
		Pkg.develop(path = main_project_path)
	end

	# Now try to load it
	@eval using $(Symbol(project_name))

	return project_toml
end

# Ensure dependencies and get project data
PROJECT_TOML = get_project_toml()
PROJECT_VERSION = PROJECT_TOML["version"]
NAME = PROJECT_TOML["name"]
AUTHORS = join(PROJECT_TOML["authors"], ", ") * " and contributors."
GITHUB = PROJECT_TOML["git_url"]

using Revise
@eval using $(Symbol(NAME))
main_module = @eval $(Symbol(NAME))

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
	),
)

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
		"Tutorials" => "tutorials.md",
		"Toolbox reference" => "reference.md",
		"Bibliography" => "bib.md",
		"Development" => Any[
			"Naming conventions"=>"conventions.md",
		],
	],
	clean = true,
	plugins = [bib],
	checkdocs = :exports,
	pagesonly = true,
	warnonly = true,
)

html_path = joinpath(@__DIR__, "build", "index.html")
browser_cmd = `google-chrome-stable --new-window file://$(html_path)`

# browser_cmd = `firefox --new-window file://$(html_path)`
# try
# 	run(`killall firefox`)
# catch e
# 	println("No existing Firefox process found. Continuing...")
# end

run(browser_cmd, wait = false)

