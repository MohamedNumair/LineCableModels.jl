using LineCableToolbox
using Documenter

DocMeta.setdocmeta!(LineCableToolbox, :DocTestSetup, :(using LineCableToolbox); recursive=true)

makedocs(;
    modules=[LineCableToolbox],
    authors="Amauri Martins",
    sitename="LineCableToolbox.jl",
    format=Documenter.HTML(;
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)
