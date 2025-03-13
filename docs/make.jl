using Documenter
using DocumenterCitations
using Pkg
using LineCableModels

PROJECT_TOML = Pkg.TOML.parsefile(joinpath(@__DIR__, "..", "Project.toml"))
PROJECT_VERSION = PROJECT_TOML["version"]
NAME = PROJECT_TOML["name"]
AUTHORS = join(PROJECT_TOML["authors"], ", ") * " and contributors"
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
		assets = ["assets/custom.js", "assets/citations.css"],
		prettyurls = get(ENV, "CI", "false") == "true",
		ansicolor = true,
		collapselevel = 1,
		footer = "[$NAME.jl]($GITHUB) v$PROJECT_VERSION supported by the Etch Competence Hub of EnergyVille, financed by the Flemish Government.",
	),
	pages = [
		"Home" => "index.md",
		"Toolbox reference" => "reference.md",
		"Examples" => "examples.md",
		"Bibliography" => "bib.md",
	],
	clean = true,
	plugins = [bib],
)
