using Documenter
using DocumenterCitations
using Pkg
using Revise
using LineCableModels

ENV["DOCUMENTER_HIDE_PREFIX"] = "LineCableModels."

PROJECT_TOML = Pkg.TOML.parsefile(joinpath(@__DIR__, "..", "Project.toml"))
PROJECT_VERSION = PROJECT_TOML["version"]
NAME = PROJECT_TOML["name"]
AUTHORS = join(PROJECT_TOML["authors"], ", ") * " and contributors."
GITHUB = "https://github.com/Electa-Git/LineCableModels.jl"

bib = CitationBibliography(
	joinpath(@__DIR__, "src", "refs.bib"),
	style = :numeric,  # default
)

DocMeta.setdocmeta!(
	LineCableModels,
	:DocTestSetup,
	:(using LineCableModels);
	recursive = true,
)

makedocs(;
	modules = [LineCableModels],
	authors = "Amauri Martins",
	sitename = "LineCableModels.jl",
	format = Documenter.HTML(;
		edit_link = "main",
		# assets = ["assets/custom.js", "assets/citations.css", "assets/custom.css"],
		assets = ["assets/citations.css"],
		prettyurls = get(ENV, "CI", "false") == "true",
		ansicolor = true,
		collapselevel = 1,
		footer = "[$NAME.jl]($GITHUB) v$PROJECT_VERSION supported by the Etch Competence Hub of EnergyVille, financed by the Flemish Government.",
	),
	pages = [
		"Home" => "index.md",
		"Toolbox reference" => "reference.md",
		"Tutorials" => "tutorials.md",
		# "Development" => Any[
		# 	"Internal"=>"internals.md",
		# ],
		"Bibliography" => "bib.md",
	],
	clean = true,
	plugins = [bib],
	checkdocs = :exports,
	pagesonly = true,
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

