using Documenter
using DocumenterCitations
using Literate
using Pkg
using Revise

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
				customize_literate_footer(content, "« Back to [Tutorials](@ref)\n"),
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
		],
		"Bibliography" => "bib.md",
	],
	clean = true,
	plugins = [bib],
	checkdocs = :exports,
	pagesonly = true,
	warnonly = false,
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

