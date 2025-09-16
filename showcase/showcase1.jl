### A Pluto.jl notebook ###
# v0.20.18

#> [frontmatter]

using Markdown
using InteractiveUtils

# This Pluto notebook uses @bind for interactivity. When running this notebook outside of Pluto, the following 'mock version' of @bind gives bound variables a default value (instead of an error).
macro bind(def, element)
    #! format: off
    return quote
        local iv = try Base.loaded_modules[Base.PkgId(Base.UUID("6e696c72-6542-2067-7265-42206c756150"), "AbstractPlutoDingetjes")].Bonds.initial_value catch; b -> missing; end
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : iv(el)
        el
    end
    #! format: on
end

# ╔═╡ a82fd7fe-465d-4744-870f-638a72a54317
# ╠═╡ show_logs = false
begin
	using Pkg: Pkg
	Pkg.activate()
	using WGLMakie: WGLMakie;
	WGLMakie.activate!()
	using Makie, PlutoUI, Colors
	using LineCableModels
	using DataFrames
	using HypertextLiteral
end

# ╔═╡ b081c88a-7959-44ea-85ff-33b980ec71b4
begin
    using Measurements: measurement, value

    # mm + percent → Measurement with absolute σ = (pct/100)*nom
    _with_unc(nom_mm::Real, pct::Real) = measurement(nom_mm/1000, abs(nom_mm/1000) * pct/100)

    # Pitch: start at 15, decrease 2.5 per layer, clamp at 10
    pitch_for_layer(ℓ::Integer) = max(10.0, 15.0 - 2.5*(ℓ - 1))

    function build_core(materials, d_wire_mm::Real, d_wire_pct::Real, n_layers::Int)
        d = _with_unc(d_wire_mm, d_wire_pct)  # Measurement
        core = ConductorGroup(WireArray(0, Diameter(d), 1, 0, get(materials, "aluminum")))
        for ℓ in 1:n_layers
            add!(core, WireArray, Diameter(d), 6*ℓ, pitch_for_layer(ℓ), get(materials, "aluminum"))
        end
        return core
    end

    function build_geometry(materials;
        d_wire_mm::Real, d_wire_pct::Real,
        t_sc_in_mm::Real,  t_sc_in_pct::Real,
        t_ins_mm::Real,    t_ins_pct::Real,
        t_sc_out_mm::Real, t_sc_out_pct::Real,
        n_layers::Int,
        t_sct # keep your existing t_sct (mm, can be Real or Measurement)
    )
        # Core
        core = build_core(materials, d_wire_mm, d_wire_pct, n_layers)

        # Layer thicknesses as Measurements (mm)
        t_sc_in  = _with_unc(t_sc_in_mm,  t_sc_in_pct)
        t_ins    = _with_unc(t_ins_mm,    t_ins_pct)
        t_sc_out = _with_unc(t_sc_out_mm, t_sc_out_pct)

        # Insulation group
        main_insu = InsulatorGroup(
            Semicon(core, Thickness(t_sct), get(materials, "polyacrylate")),
        )
        add!(main_insu, Semicon,   Thickness(t_sc_in),  get(materials, "semicon1"))
        add!(main_insu, Insulator, Thickness(t_ins),    get(materials, "pe"))
        add!(main_insu, Semicon,   Thickness(t_sc_out), get(materials, "semicon2"))
        add!(main_insu, Semicon,   Thickness(t_sct),    get(materials, "polyacrylate"))

        core_cc = CableComponent("core", core, main_insu)
        return core_cc
    end
end;

# ╔═╡ 46cfd6fa-b4d6-44c3-83cf-d2b9b1ff1cf1
# Override stupid CSS settings
@htl("""
<style id="lc-plutostyles">
/* ====== editor.css-like tweaks ====== */

/* occupy full width */
body main{
  max-width: calc(100% - 2em) !important;
  margin-left: 1em !important;
  margin-right: 1em !important;
  padding-left: max(160px, 10%);
  padding-right: max(383px, 10%);
}

/* larger images in arrays when expanded */
pluto-tree img{
  max-width: none !important;
  max-height: none !important;
}

/* somewhat larger images in arrays when collapsed */
pluto-tree.collapsed img{
  max-width: 15rem !important;
  max-height: 15rem !important;
}

/* move cell popup menu to the left of its button */
pluto-input > .open.input_context_menu > ul{
  margin-left: -200px;
  margin-right: 20px;
}
/* keep popup above other stuff */
pluto-input > .open.input_context_menu > ul,
pluto-input > .open.input_context_menu{
  z-index: 31 !important;
}

/* widen generic popup */
pluto-popup{
  --max-size: 451px;
  width: min(90vw, var(--max-size));
}

/* taller Pkg terminal */
pkg-terminal > .scroller{
  max-height: 70vh;
}

/* ====== index.css-like tweaks (harmless if not on index page) ====== */
li.recent > a:after,
li.running > a:after{
  display: block;
  content: attr(title);
  font-size: x-small;
}
li > a[title*="/pluto_notebooks/"]{ color: rgb(16 113 109); }
ul#recent{ max-height: none; }
</style>

<script>
  // Make overrides truly global: duplicate <style> into <head> so it survives rerenders
  (function(){
	const s = document.getElementById("lc-plutostyles");
	if(!s) return;
	const exists = document.getElementById("lc-plutostyles-head");
	if(!exists){
	  const clone = s.cloneNode(true);
	  clone.id = "lc-plutostyles-head";
	  document.head.appendChild(clone);
	}
  })();
</script>
""")

# ╔═╡ 4462e48f-0d08-4ad9-8dd9-12f4f5912f38
begin
	struct TwoColumn{A,B}
    left::A
    right::B
end

# New light wrapper that carries widths (percentages)
struct TwoColumnWithWidths{A,B}
    left::A
    right::B
    widths::NTuple{2,Float64}   # (left%, right%)
end

# Convenience “constructor” with keywords — old calls still work,
# new calls with kws return the width-aware wrapper
TwoColumn(left, right; left_pct::Real=50.0, right_pct::Real=50.0) =
    TwoColumnWithWidths{typeof(left), typeof(right)}(left, right, (float(left_pct), float(right_pct)))

# Original show (defaults to 50/50)
function Base.show(io, mime::MIME"text/html", tc::TwoColumn)
    write(io, """
    <div style="display:flex;">
      <div style="flex: 50%;">""")
    show(io, mime, tc.left)
    write(io, """
      </div>
      <div style="flex: 50%;">""")
    show(io, mime, tc.right)
    write(io, """
      </div>
    </div>""")
end

# New show for width-aware variant
function Base.show(io, mime::MIME"text/html", tc::TwoColumnWithWidths)
    l, r = tc.widths
    write(io, """
    <div style="display:flex;">
      <div style="flex: $(l)%;">""")
    show(io, mime, tc.left)
    write(io, """
      </div>
      <div style="flex: $(r)%;">""")
    show(io, mime, tc.right)
    write(io, """
      </div>
    </div>""")
end

	struct Foldable{C}
		title::String
		content::C
	end

	function Base.show(io, mime::MIME"text/html", fld::Foldable)
		write(io, "<details><summary>$(fld.title)</summary><p>")
		show(io, mime, fld.content)
		write(io, "</p></details>")
	end

	LocalImage(x::AbstractString; attrs...) =
		LocalResource(joinpath(@__DIR__, "assets", "img", x), pairs(attrs)...)
end;

# ╔═╡ e90baf94-c8b8-41aa-8728-e129f7f6881e
@htl(
	"""
<style>
  /* Hide inputs unless the root has .show-code */
  :root:not(.show-code) pluto-input { display: none !important; }
  .view_hidden_code { 
	cursor: pointer; padding: 0.35rem 0.6rem; border-radius: 6px; 
	border: 1px solid #bbb; background: #f8f8f8; font: inherit;
  }
</style>

<script>
  const root = document.documentElement
  const btn  = currentScript.parentElement.querySelector('#view_code_btn')
  const label = () => btn.querySelector('.text')
  function sync() { label().textContent = root.classList.contains('show-code') ? 'Hide code' : 'View code' }
  btn.addEventListener('click', () => { root.classList.toggle('show-code'); sync() })
  sync()
</script>
"""
)


# ╔═╡ 532cb61b-97b6-43e7-a8f9-3a5f12b8b3f7
@htl("""
<style id="lc-hide-pluto-slide-controls">
  /* Nuke the default slideshow arrows (both normal & presentation DOMs) */
  #slide_controls,
  #presentation #slide_controls {
	display: none !important;
  }
</style>

<script>
  // Defensive: if Pluto re-injects them, hide again
  const hide = (n) => { try { n.style.display = "none"; n.hidden = true } catch {} }
  const sc0 = document.getElementById("slide_controls"); if (sc0) hide(sc0)
  const mo = new MutationObserver(muts => {
	for (const m of muts) for (const el of m.addedNodes) {
	  if (el.nodeType !== 1) continue
	  if (el.id === "slide_controls") hide(el)
	  const sc = el.querySelector?.("#slide_controls"); if (sc) hide(sc)
	}
  })
  mo.observe(document.body, { childList: true, subtree: true })
</script>
""")

# ╔═╡ b16ff72c-872a-4505-9468-6cefd4a8852c

@htl(
	"""
<link rel="stylesheet"
  href="https://fonts.googleapis.com/css2?family=Material+Symbols+Rounded:opsz,wght,FILL,GRAD@24,400,0,0" />

<style id="lc-toolbar-vertical">
  :root{
	--lc-toolbar-w: 58px;
	--lc-toolbar-bg: color-mix(in oklab, var(--header-bg-color, #f1f1f1), transparent 20%);
	--lc-toolbar-bd: var(--rule-color, #0000001a);
	--lc-icon-bg: var(--overlay-button-bg, #2c2c2c);
	--lc-icon-fg: var(--overlay-button-color, white);
	--lc-icon-bd: var(--overlay-button-border, #9e9e9e70);
	--lc-icon-hover: color-mix(in oklab, var(--lc-icon-bg), white 10%);
	--lc-icon-active: color-mix(in oklab, var(--lc-icon-bg), black 12%);
	--lc-accent: var(--selected-cell-bg-color, #2a73cdc7);
  }

  /* keep content clear of the bar */
  html { scroll-padding-left: var(--lc-toolbar-w); }
  body { padding-left: var(--lc-toolbar-w); }

  /* Global 'show code' toggle */
  :root:not(.show-code) pluto-input { display: none !important; }

  /* Vertical toolbar */
  #lc-toolbar{
	position: fixed; left: 0; top: 0; bottom: 0;
	width: var(--lc-toolbar-w);
	display: flex; flex-direction: column; align-items: center; gap: 10px;
	padding: 10px 6px;
	background: var(--lc-toolbar-bg);
	border-right: 1px solid var(--lc-toolbar-bd);
	backdrop-filter: blur(6px);
	z-index: 2147483647;
  }

  .lc-icon{
	display:inline-flex; align-items:center; justify-content:center;
	width: 40px; height: 40px;
	border-radius: 10px;
	background: var(--lc-icon-bg);
	border: 1px solid var(--lc-icon-bd);
	color: var(--lc-icon-fg);
	cursor: pointer; user-select: none;
	transition: background .15s ease, transform .02s ease, border-color .15s ease;
  }
  .lc-icon:hover  { background: var(--lc-icon-hover); }
  .lc-icon:active { background: var(--lc-icon-active); transform: translateY(1px); }
  .lc-icon:focus-visible { outline: 2px solid color-mix(in oklab, var(--lc-accent), white 10%); outline-offset: 2px; }

  .lc-hidden{
	position:absolute !important; width:1px; height:1px; padding:0; margin:-1px;
	overflow:hidden; clip:rect(0 0 0 0); white-space:nowrap; border:0;
  }

  .material-symbols-rounded{
	font-variation-settings: 'OPSZ' 24, 'wght' 400, 'FILL' 0, 'GRAD' 0;
	font-size: 24px; line-height: 1;
  }
</style>

<nav id="lc-toolbar" role="toolbar" aria-label="Notebook toolbar (vertical)">
  <!-- ORDER: Next, Prev, Home, Present, Show/Hide code -->
  <button class="lc-icon" id="btn-next" title="Next slide">
	<span class="material-symbols-rounded">arrow_forward</span>
  </button>

  <button class="lc-icon" id="btn-prev" title="Previous slide">
	<span class="material-symbols-rounded">arrow_back</span>
  </button>

  <button class="lc-icon" id="btn-home" title="Scroll to title">
	<span class="material-symbols-rounded">home</span>
  </button>

  <button class="lc-icon" id="btn-present" title="Start presentation">
	<span class="material-symbols-rounded">slideshow</span>
  </button>

  <button class="lc-icon" id="btn-toggle-code" title="Show/Hide code">
	<span class="material-symbols-rounded" id="ico-toggle-code">code_blocks</span>
  </button>
</nav>

<script>
  const root = document.documentElement

  // Show/Hide code (icon stays code_blocks; tooltip flips)
  const bCode = document.getElementById("btn-toggle-code")
  function flipCode(){
	const showing = root.classList.toggle("show-code")
	bCode.title = showing ? "Hide code" : "Show code"
  }
  bCode.addEventListener("click", flipCode)

  // Presentation start (Pluto native)
  const bPresent = document.getElementById("btn-present")
  function startPresentation(){
	if (typeof window.present === "function"){ window.present(); return }
	const cand = document.querySelector('button.present, #present, [title="Start presentation"]')
	if (cand) { cand.click(); return }
	window.dispatchEvent(new KeyboardEvent('keydown', {key:'p'}))
  }
  bPresent.addEventListener("click", startPresentation)

  // Slide nav (prefer Pluto's buttons if present; fallback to arrow keys)
  function clickChange(dir){
	const sel = dir < 0 ? "button.changeslide.prev" : "button.changeslide.next"
	const b = document.querySelector(sel) || document.querySelector("#presentation " + sel)
	if (b){ b.click(); return true }
	const key = dir < 0 ? "ArrowLeft" : "ArrowRight"
	window.dispatchEvent(new KeyboardEvent('keydown', {key}))
	return false
  }
  document.getElementById("btn-prev").addEventListener("click", () => clickChange(-1))
  document.getElementById("btn-next").addEventListener("click", () => clickChange(1))

  // Home → smooth-scroll to #home and update the URL hash
document.getElementById("btn-home").addEventListener("click", () => {
  const target = document.getElementById("home");
  if (target) {
	// update the URL without a jump
	history.replaceState(null, "", "#home");
	// smooth scroll to the anchor
	target.scrollIntoView({ behavior: "smooth", block: "start", inline: "nearest" });
  } else {
	// fallback if #home isn't in the DOM
	window.scrollTo({ top: 0, behavior: "smooth" });
  }
});

</script>
"""
)


# ╔═╡ 9fefeafa-63f9-43d0-a2ee-4d4fca170126
begin
	@htl("""
	<style id="lc-anchor-style">
	  /* Invisible, takes no space; but scroll targets land nicely below fixed chrome */
	  .lc-anchor{
		display:block; height:0; margin:0; padding:0; border:0;
		scroll-margin-top: var(--lc-anchor-offset, 0px); /* tweak per anchor if needed */
	  }
	</style>
	""")

	anchor(id::AbstractString = "home"; offset_px::Real = 0) = @htl("""
		<span id="$(id)" class="lc-anchor" aria-hidden="true"
			  style="--lc-anchor-offset: $(offset_px)px;"></span>
		""")
end;

# ╔═╡ fde80e93-1964-4287-acfc-a2da2d4b7d48
TableOfContents()

# ╔═╡ 77d3c731-bdae-46c2-8b23-eb0b860e7444
md"""
---
"""

# ╔═╡ 9ef6f05f-c384-4fab-bc39-e47edb49f994
anchor("home"; offset_px = 256)

# ╔═╡ f08a32db-05d9-4ddb-9c46-34bc623ce5e7
md"""
$(LocalResource(joinpath(@__DIR__, "..", "assets", "img", "ETCH_LOGO_RGB_NEG.svg"), :width => 350, :style => "margin-right: 40px;"))
"""

# ╔═╡ 50384351-fc38-4b29-9bf6-db1556d49dee
html"""
<p style="font-size:40px; text-align: left; font-weight: bold; font-family: Vollkorn, Palatino, Georgia, serif;"> Uncertainty of Frequency Dependent Impedance Parameters for Transmission Assets</p>
<p style="font-size:28px; text-align: left; font-weight: bold; font-family: Vollkorn, Palatino, Georgia, serif;"> Second Annual Belgian Energy Transition Workshop</p>
"""

# ╔═╡ 23913cc6-a81b-4098-bacf-7a2e09998e53
md"""

####
#### Amauri Martins

#### [amauri.martinsbritto@kuleuven.be](mailto:amauri.martinsbritto@kuleuven.be)

#### KU Leuven – Etch / EnergyVille

##### 16 September 2025
"""

# ╔═╡ d482241c-4bd5-4896-bdc1-e82387f69051
md"""
$(LocalResource(joinpath(@__DIR__, "..", "assets", "img", "ENERGYVILLE-LOGO.svg"), :width => 150, :style => "margin-right: 40px;"))
$(LocalResource(joinpath(@__DIR__, "..", "assets", "img", "kul_logo.svg"), :width => 150, :style => "margin-right: 0px;"))
"""

# ╔═╡ 14f07acc-5353-4b1d-b94f-9ae43f87289b
md"""
# Introduction
"""

# ╔═╡ 6c6e4d21-cc38-46eb-8178-4cc4a99adcba
TwoColumn(
	html"<div style='text-align: left;'>
	 <p style='margin: 0; line-height: 1.2;'>
	   <span style='color: #34CA71; font-size: 60px; font-family: Vollkorn, Palatino, Georgia, serif;'>E</span><span style='color: white; font-size: 60px; font-family: Vollkorn, Palatino, Georgia, serif;'>nergy</span>
	 </p>
	 <p style='margin: 0; line-height: 1.2;'>
	   <span style='color: #34CA71; font-size: 60px; font-family: Vollkorn, Palatino, Georgia, serif;'>T</span><span style='color: white; font-size: 60px; font-family: Vollkorn, Palatino, Georgia, serif;'>ransmission</span>
	 </p>
	 <p style='margin: 0; line-height: 1.2;'>
	   <span style='color: #34CA71; font-size: 60px; font-family: Vollkorn, Palatino, Georgia, serif;'>C</span><span style='color: white; font-size: 60px; font-family: Vollkorn, Palatino, Georgia, serif;'>ompetence</span>
	 </p>
	 <p style='margin: 0; line-height: 1.2;'>
	   <span style='color: #34CA71; font-size: 60px; font-family: Vollkorn, Palatino, Georgia, serif;'>H</span><span style='color: white; font-size: 60px; font-family: Vollkorn, Palatino, Georgia, serif;'>ub</span>
	 </p>
	  </div>",
	md"""#### *Pioneering research for future-proofing electricity networks with large-scale integration of High Voltage Direct Current HVDC technology and underground cables.*

   ### Key challenges

   1. ###### More **underground cables**
   2. ###### **Protection** of cable-based systems
   3. ###### **Control** interactions
   4. ###### **Resilient HVDC** grids
   $(LocalImage("future_grids.svg", width = 600, style = "display: block; float: left; margin-left: auto; margin-right: auto;"))
   	""")

# ╔═╡ 3e6a9c64-827d-4491-bcac-252ee7b1dc81
md"""
## Undergrounding of future power systems
"""

# ╔═╡ 877a84cc-979f-48c9-ac41-59be60b4850b
TwoColumn(
	md"""
	### More underground cables
		
	- #### Large-scale integration of HVDC technology and underground cables.
	- #### Benefits in environmental impact, reliability, and public acceptance.
	- #### High costs and technical complexities still poses challenges to widespread adoption.
		
	### Research roadmaps

	- #### Accurate modelling of cables, joints and interaction with (complex) environment.
	- #### HVDC cables systems in multiterminal HVDC grids.
	- #### Enhanced computational tools in view of operation, diagnostics and condition monitoring.
	- #### Cable hosting capacity.

		""",
	md"""$(LocalImage("cables1.png", width=250, style="display: block; margin-left: auto; margin-right: auto; margin-bottom: 50px;"))
   $(LocalImage("cables2.png", width=250, style="display: block; margin-left: auto; margin-right: auto;"))
   	""")

# ╔═╡ db1944b6-c55f-4091-8128-8d297bdc9a74
md"""
## Sources of uncertainties in cable parameters
"""

# ╔═╡ 5397f442-8dc1-42a6-941d-0b1d58057a6b

	TwoColumn(
	html"""
	<div style="font-family: Vollkorn, Palatino, Georgia, serif;
            color: var(--pluto-output-h-color, inherit);
            line-height: 1.35;">
  <div style="font-size: 2rem; font-weight: 700; margin: 0 0 .35rem 0;">
    Internal and external origins:
  </div>
  <ul style="margin: .25rem 0 0 1.25rem; padding: 0; list-style: disc;">
    <li style="font-size: 2rem; margin: .25rem 0;">Geometrical and material properties</li>
    <li style="font-size: 2rem; margin: .25rem 0;">
      Real field data <span style="opacity:.85;">(resistivity, actual conductor layout etc.)</span>
    </li>
    <li style="font-size: 2rem; margin: .25rem 0;">Presence of interferences</li>
    <li style="font-size: 2rem; margin: .25rem 0;">
      Modeling procedure <span style="opacity:.85;">(parameters and EMT)</span>
    </li>
  </ul>
</div>
	""",
	md"""
$(LocalImage("skeffect.png", width=400, style="display: block; margin-left: auto; margin-right: auto; margin-bottom: 50px;"))
$(LocalImage("earthreturn.png", width=400, style="display: block; margin-left: auto; margin-right: auto;"))
	"""; left_pct=50, right_pct=50)

# ╔═╡ a3f5a8c5-4ab9-4a33-abab-7907ffab1347
md"""
## Uncertainty quantification
"""

# ╔═╡ 382252ca-ede1-4043-b921-7834e59810cb
md"""
#### - Physical quantities are treated as nominal values associated to the corresponding uncertainties, i.e. ``\hat{x} = x ± \delta x``, ``\hat{y} = y ± \delta y``. Uncertainties are propagated according to the linear error propagation theory by using the package `Measurements.jl`.
""" 

# ╔═╡ 96121e5b-6b5b-4ab1-81d0-6dcbe924cda2

	TwoColumn(
	md"""
	$(LocalResource(joinpath(@__DIR__, "..", "assets", "img", "cable_dark_mode.svg"), :width => 800, :style => "display: block; margin-top: 50px; margin-left: auto; margin-right: auto;"))
	""",
	md"""
	#### - Addition and subtraction:
	#### ``\hat{z} = \hat{x} \pm \hat{y} = (x \pm y) \pm \sqrt{(\delta x)^2 + (\delta y)^2}``
	#### - Multiplication and division:
	#### ``\hat{z} = (x \cdot y \text{ or } x/y) \pm \delta z``
	#### ``\frac{\delta z}{|z|} = \sqrt{\left(\frac{\delta x}{x}\right)^2 + \left(\frac{\delta y}{y}\right)^2}``
	#### - For an arbitrary function ``f(\hat{x}, \hat{y}, ...)``
	#### ``\delta f = \sqrt{\left( \frac{\partial f}{\partial x} \delta x \right)^2 + \left( \frac{\partial f}{\partial y} \delta y \right)^2 + \dots }``

	!!! warning "Warning"
		Even when subtracting the nominal values ($x-y$), the uncertainties are still combined, leading to a larger total uncertainty.
	"""; left_pct=65, right_pct=35)


# ╔═╡ a8ea0da0-36f1-44d4-9415-d3041f34c23f
md"""
# Application study
"""

# ╔═╡ f5fa7e28-97a7-456b-87a9-5ac4b76be9d4
begin
	num_co_wires = 61  # number of core wires
	num_sc_wires = 49  # number of screen wires
	d_core = 38.1e-3   # nominal core overall diameter
	d_w = 4.7e-3       # nominal strand diameter of the core
	t_sc_in = 0.6e-3   # nominal internal semicon thickness
	t_ins = 8e-3       # nominal main insulation thickness
	t_sc_out = 0.3e-3  # nominal external semicon thickness
	d_ws = .95e-3      # nominal wire screen diameter
	t_cut = 0.1e-3     # nominal thickness of the copper tape (around wire screens)
	w_cut = 10e-3      # nominal width of copper tape
	t_wbt = .3e-3      # nominal thickness of the water blocking tape
	t_sct = .3e-3      # nominal thickness of the semiconductive tape
	t_alt = .15e-3     # nominal thickness of the aluminum tape
	t_pet = .05e-3     # nominal thickness of the pe face in the aluminum tape
	t_jac = 2.4e-3     # nominal PE jacket thickness

	d_overall = d_core # hide
	layers = [] # hide
	push!(layers, ("Conductor", missing, d_overall * 1000)) # hide
	d_overall += 2 * t_sct # hide
	push!(layers, ("Inner semiconductive tape", t_sct * 1000, d_overall * 1000)) # hide
	d_overall += 2 * t_sc_in # hide
	push!(layers, ("Inner semiconductor", t_sc_in * 1000, d_overall * 1000)) # hide
	d_overall += 2 * t_ins # hide
	push!(layers, ("Main insulation", t_ins * 1000, d_overall * 1000)) # hide
	d_overall += 2 * t_sc_out # hide
	push!(layers, ("Outer semiconductor", t_sc_out * 1000, d_overall * 1000)) # hide
	d_overall += 2 * t_sct # hide
	push!(layers, ("Outer semiconductive tape", t_sct * 1000, d_overall * 1000)) # hide
	d_overall += 2 * d_ws # hide
	push!(layers, ("Wire screen", d_ws * 1000, d_overall * 1000)) # hide
	d_overall += 2 * t_cut # hide
	push!(layers, ("Copper tape", t_cut * 1000, d_overall * 1000)) # hide
	d_overall += 2 * t_wbt # hide
	push!(layers, ("Water-blocking tape", t_wbt * 1000, d_overall * 1000)) # hide
	d_overall += 2 * t_alt # hide
	push!(layers, ("Aluminum tape", t_alt * 1000, d_overall * 1000)) # hide
	d_overall += 2 * t_pet # hide
	push!(layers, ("PE with aluminum face", t_pet * 1000, d_overall * 1000)) # hide
	d_overall += 2 * t_jac # hide
	push!(layers, ("PE jacket", t_jac * 1000, d_overall * 1000)) # hide

	nothing
end

# ╔═╡ 8c2eaef0-4e01-41b9-b1a6-a20dfa9b2d57
md"""
## Cable specifications

* ##### Aluminum 1000 mm² cable, 18/30 kV, NA2XS(FL)2Y 18/30 kV
"""

# ╔═╡ cb8f01ae-26e0-44ce-8347-298ab692ac63
TwoColumn(
	md"""$(DataFrame( # hide
		layer = first.(layers), # hide
		thickness = [ # hide
			ismissing(t) ? "-" : round(t, sigdigits = 2) for t in getindex.(layers, 2) # hide
		], # hide
		diameter = [round(d, digits = 2) for d in getindex.(layers, 3)], # hide
	))
	""",
	md"""$(LocalImage("cable_photo.jpg", width = 350, style = "display: block; margin-top: 50px; margin-left: auto; margin-right: auto;"))
	""")

# ╔═╡ 29222f8e-fb07-4bdb-8939-f18e668d2037
# NominalData() will be used later to verify the calculations

datasheet_info = NominalData(
	designation_code = "NA2XS(FL)2Y",
	U0 = 18.0,                        # Phase-to-ground voltage [kV]
	U = 30.0,                         # Phase-to-phase voltage [kV]
	conductor_cross_section = 1000.0, # [mm²]
	screen_cross_section = 35.0,      # [mm²]
	resistance = 0.0291,              # DC resistance [Ω/km]
	capacitance = 0.39,               # Capacitance [μF/km]
	inductance = 0.3,                 # Inductance in trifoil [mH/km]
);

# ╔═╡ c1595a9d-7882-4b66-a1fc-fe6de19f1ef6
md"""
## Building the cable model

### Materials library
"""

# ╔═╡ c13e262c-2dd2-43da-a01b-a95adb7eaa7d
md"""
!!! note "Note"
	The `MaterialsLibrary` is a container for storing electromagnetic properties of 
	different materials used in power cables. By default, it initializes with several common 
	materials with their standard properties.
"""

# ╔═╡ c2539b01-ac04-48e4-a973-6a5d8a0e2b58
# ╠═╡ show_logs = false
# Initialize materials library with default values:
materials = MaterialsLibrary(add_defaults = true)


# ╔═╡ c7c7ce65-3a0c-4ac6-82f0-f9f58e46f47e
DataFrame(materials)

# ╔═╡ 062439db-1e3f-497e-96c1-e1f65f80399b
md"""
## Core and main insulation

- The core consists of a 4-layer AAAC stranded conductor with 61 wires arranged in (1/6/12/18/24) pattern, with respective lay ratios of (15/13.5/12.5/11). Stranded conductors are modeled using the `WireArray` object, which handles the helical pattern and twisting effects.
"""

# ╔═╡ 4e1dec4b-223f-45f8-9393-523fcc4019f0
 md"#### Controls"

# ╔═╡ 5b005f4b-605e-4a3d-ba7f-003908f332b2
md"""
Layers: $(@bind n_layers PlutoUI.Slider(0:10; default=4, show_value=true))

Wire diameter [mm]: $(@bind dd_w PlutoUI.Slider(0.45:0.01:11.7; default=3.0, show_value=true)), uncertainty [%]: $(@bind unc_d_w PlutoUI.Slider(0.0:0.01:10; default=0.0, show_value=true))

Inner semicon thickness [mm]: $(@bind tt_sc_in PlutoUI.Slider(0.45:0.01:11.7; default=3.0, show_value=true)), uncertainty [%]:  $(@bind unc_t_sc_in PlutoUI.Slider(0.0:0.01:10; default=0.0, show_value=true))

Main insulation thickness [mm]: $(@bind tt_ins PlutoUI.Slider(0.45:0.01:11.7; default=3.0, show_value=true)), uncertainty [%]:  $(@bind unc_t_ins PlutoUI.Slider(0.0:0.01:10; default=0.0, show_value=true))

Outer semicon thickness [mm]: $(@bind tt_sc_out PlutoUI.Slider(0.45:0.01:11.7; default=3.0, show_value=true)), uncertainty [%]:  $(@bind unc_t_sc_out PlutoUI.Slider(0.0:0.01:10; default=0.0, show_value=true))
"""

# ╔═╡ e0f87b28-14a3-4630-87db-6f4b51bdb30a
md"""
Cross-section: $(cable_design.components[1].conductor_group.cross_section*1e6) mm²
"""

# ╔═╡ da168b34-43be-4701-8de8-5e953ff8dcd8
cable_design.components[1].conductor_group.resistance

# ╔═╡ cda1f413-8d71-4473-af93-f6ae2dd06ccb
md"""
## Wire screens
"""

# ╔═╡ 926048a4-f1e9-46ca-a6a8-84e254d74719
# ╠═╡ show_logs = false
begin
	# Build the wire screens on top of the previous layer:
	lay_ratio = 10 # typical value for wire screens
	screen_con =
		ConductorGroup(
			WireArray(
				main_insu,
				Diameter(d_ws),
				num_sc_wires,
				lay_ratio,
				get_material(materials_db, "copper"),
			),
		)
	# Add the equalizing copper tape wrapping the wire screen:
	addto_conductorgroup!(
		screen_con,
		Strip,
		Thickness(t_cut),
		w_cut,
		lay_ratio,
		get_material(materials_db, "copper"),
	)

	# Water blocking tape over screen:
	screen_insu = InsulatorGroup(
		Semicon(screen_con, Thickness(t_wbt), get_material(materials_db, "polyacrylate")),
	)

	# Group sheath components and assign to design:
	sheath_cc = CableComponent("sheath", screen_con, screen_insu)
	addto_cabledesign!(cable_design, sheath_cc)
end

# ╔═╡ 6a74b6bf-d833-4d9b-af2c-0fcf729ff0f4
# ╠═╡ show_logs = false
# Examine the newly added components:
preview_cabledesign(cable_design, sz = (1200, 600))

# ╔═╡ c5bdbd1f-327e-4d33-8c14-f019b3057adb
md"""
## Outer jacket components
"""

# ╔═╡ 995cfe45-ba32-4c06-9843-603d2e6073bf
begin
	# Add the aluminum foil (moisture barrier):
	jacket_con = ConductorGroup(
		Tubular(screen_insu, Thickness(t_alt), get_material(materials_db, "aluminum")),
	)

	# PE layer after aluminum foil:
	jacket_insu = InsulatorGroup(
		Insulator(jacket_con, Thickness(t_pet), get_material(materials_db, "pe")),
	)

	# PE jacket (outer mechanical protection):
	addto_insulatorgroup!(
		jacket_insu,
		Insulator,
		Thickness(t_jac),
		get_material(materials_db, "pe"),
	)
end

# ╔═╡ 58626fd7-b088-4310-811c-a4f3f1338f03
# Assign the jacket parts directly to the design:
addto_cabledesign!(cable_design, "jacket", jacket_con, jacket_insu)

# ╔═╡ 783c759f-0889-4ce5-ba2e-6cc1c7555641
md"""
## Finished cable design
"""

# ╔═╡ a0138b90-e4d7-4711-95e1-b6e2f5f3fb30
# ╠═╡ show_logs = false
preview_cabledesign(cable_design, sz = (1200, 600))

# ╔═╡ f904b5e4-0167-4ecf-8a5e-078a2877d4f7
md"""
# Cable parameters (RLC)
"""

# ╔═╡ 1ae76282-4340-4df0-ba29-11712c184a79
md"""
## Core and corrected EM properties
"""

# ╔═╡ 9ddcccbe-86c8-4335-8d65-35af4ce755ab
# Compare with datasheet information (R, L, C values):
to_df(cable_design, :core)

# ╔═╡ 380b4c0a-780c-4be2-9c5a-666257dbe4da
# Obtain the equivalent electromagnetic properties of the cable:
to_df(cable_design, :components)

# ╔═╡ eb60126a-c646-417c-b9a6-9335b0cfe6c4
md"""
## Detailed report
"""

# ╔═╡ 58d30993-f4b3-4621-8d23-447b3d4f5935
to_df(cable_design, :detailed)

# ╔═╡ 02a77417-3896-4e29-abd6-6e2586da0571
md"""
# Data exchange features
"""

# ╔═╡ da6b39c6-7053-4412-8bd8-6c0f771ee456
md"""
## Cable designs library
"""

# ╔═╡ 282bd09f-ecea-44c7-b455-e83bb8e2fdd1
begin
	# Store the cable design and inspect the library contents:
	library = CablesLibrary()
	store_cableslibrary!(library, cable_design)
	list_cableslibrary(library)
end

# ╔═╡ 00fcdd99-c603-4df3-a15b-d3ba64b34b7a
md"""
!!! info "Note"
	Cable designs are exported to JSON format by default to facilitate data exchange acress projects. In case of sensitive design specs, it is also possible to use the standard binary format of Julia.
"""

# ╔═╡ 8f147f54-ec3d-47a7-a3e7-9ff533adfb2d
begin
	# Save to file for later use:
	output_file = joinpath(@__DIR__, "cables_library.json")
	save_cableslibrary(library, file_name = output_file)
	json_str = read(output_file, String)
	println(JSON3.pretty(JSON3.read(json_str)))
end

# ╔═╡ 878f722b-0ad8-4098-8ff7-c11797eddddc
md"""
## Materials library 
"""

# ╔═╡ a48ddf49-42f1-454e-8182-de1da6b51fe8
begin
	# Saving the materials library to JSON
	save_materialslibrary(
		materials_db,
		file_name = joinpath(@__DIR__, "materials_library.json"),
	)
	nothing
end

# ╔═╡ fd1e268a-6520-4dc8-a9ff-32a4854859df
md"""
# Cable system definition
"""

# ╔═╡ b4169697-e06d-4947-8105-9f42017f5042
md"""
## Earth model
"""

# ╔═╡ 0900d10f-8191-4507-af4e-50d7f4a1126f
begin
	# Define a frequency-dependent earth model (1 Hz to 1 MHz):
	f = 10.0 .^ range(0, stop = 6, length = 10)  # Frequency range
	earth_params = EarthModel(f, 100.0, 10.0, 1.0)  # 100 Ω·m resistivity, εr=10, μr=1
end

# ╔═╡ 9ef6ef41-3a95-4540-ae93-dcc279ec72b0
to_df(earth_params)

# ╔═╡ 4ce85966-0386-4525-8cf2-35e9814f8459
md"""
## Trifoil arrangement
"""

# ╔═╡ 44f5823e-4b07-4f2c-8773-e4c3187a6100
begin
	# Define system center point (underground at 1 m depth) and the trifoil positions
	x0 = 0
	y0 = -1
	xa, ya, xb, yb, xc, yc = trifoil_formation(x0, y0, 0.035)
	nothing
end

# ╔═╡ 987902c5-5983-4815-b62f-4eabc1be2362
begin
	# Initialize the `LineCableSystem` with the first cable (phase A):
	cabledef =
		CableDef(cable_design, xa, ya, Dict("core" => 1, "sheath" => 0, "jacket" => 0))
	cable_system = LineCableSystem("tutorial2", 20.0, earth_params, 1000.0, cabledef)

	# Add remaining cables (phases B and C):
	addto_linecablesystem!(cable_system, cable_design, xb, yb,
		Dict("core" => 2, "sheath" => 0, "jacket" => 0),
	)
	addto_linecablesystem!(
		cable_system, cable_design, xc, yc,
		Dict("core" => 3, "sheath" => 0, "jacket" => 0),
	)
end

# ╔═╡ 539cdfbe-f5c6-47eb-9b2d-64f9ca7feacd
md"""
!!! note "Phase mapping"
	The `addto_linecablesystem!` function allows the specification of phase mapping for each cable. The `Dict` argument maps the cable components to their respective phases, where `core` is the conductor, `sheath` is the screen, and `jacket` is the outer jacket. The values (1, 2, 3) represent the phase numbers (A, B, C) in this case. Components mapped to phase 0 will be Kron-eliminated (grounded). Components set to the same phase will be bundled into an equivalent phase.
"""

# ╔═╡ 960c9035-d86c-471a-9ed6-330beead03cb
md"""
## Cable system preview & PSCAD export
"""

# ╔═╡ 6ee6d16d-326c-4436-a750-077ecc2b3b9c
preview_linecablesystem(cable_system, zoom_factor = 0.15, sz = (1000, 600))

# ╔═╡ 2164f425-291b-4ca8-a66d-9ff3d402fdb8
begin
	# Export to PSCAD input file:
	export_file = export_pscad_lcp(
		cable_system,
		file_name = joinpath(@__DIR__, "tutorial2_export.pscx"),
	)
	nothing
end

# ╔═╡ 83d26ac6-24e5-4ca1-817c-921d3c2375c5
md"""$(LocalResource(joinpath(@__DIR__, "pscad_export.png"), :width => 800, :style => "display: block; margin-top: auto; margin-left: auto; margin-right: auto;"))
 """

# ╔═╡ 2f28cc7a-cb14-44e6-908a-f34b8991c1bd
md"""
# Concluding remarks & research directions
"""

# ╔═╡ a57fdd18-573b-4af9-984d-811132fe4fd1
md"""
- ##### Accurate modeling of the different conductor materials is crucial for the proper representation of line/cable parameters and propagation characteristics.
- ##### Expansion of currently implemented routines to include different earth impedance models, FD soil properties and modal decomposition techniques.
- ##### Construction of additional cable models, detailed investigations on uncertainty quantification.
- ##### Development of novel formulations for cables composed of N concentrical layers, allowing for accurate representations of semiconductor materials.
- ##### Implementation of an interface to run finite element simulations using the open-source software [ONELAB](https://onelab.info/) - Open Numerical Engineering LABoratory.
"""

# ╔═╡ 7d77f069-930b-4451-ab7d-0e77b8fd86a7
md"""
# Thank you!
"""

# ╔═╡ ec9ede5e-dd18-467e-88b7-e9964f05c97a
# ╠═╡ show_logs = false
# ╠═╡ disabled = true
#=╠═╡
begin
	cable_id = "showcase"
	cable_design = CableDesign(cable_id, core_cc, nominal_data = datasheet_info)

	# At this point, it becomes possible to preview the cable design:
	plt1, _ = preview(cable_design, size=(600, 400), backend=:wgl)
	plt1
end
  ╠═╡ =#

# ╔═╡ 0b5142ef-2eb0-4c72-8ba5-da776eadb5a3
begin
    core_cc = build_geometry(materials;
        d_wire_mm   = dd_w,      d_wire_pct   = unc_d_w,
        t_sc_in_mm  = tt_sc_in,  t_sc_in_pct  = unc_t_sc_in,
        t_ins_mm    = tt_ins,    t_ins_pct    = unc_t_ins,
        t_sc_out_mm = tt_sc_out, t_sc_out_pct = unc_t_sc_out,
        n_layers    = n_layers,
        t_sct       = t_sct # keep your existing var for semicon tape thickness (mm)
    )

    cable_id     = "showcase"
    cable_design = CableDesign(cable_id, core_cc; nominal_data = datasheet_info)
	backend_sym = :cairo 
    plt, _ = preview(cable_design; size = size=(600, 400), backend = backend_sym)
    plt
end

# ╔═╡ 1b2bc07f-a88c-4b2f-a920-406d8743a2a8
# ╠═╡ disabled = true
#=╠═╡
begin
	# Define the material and initialize the main conductor
	core = ConductorGroup(
		WireArray(0, Diameter(d_w), 1, 0, get(materials, "aluminum")),
	)
	# Add subsequent layers of stranded wires
	add!(
		core,
		WireArray,
		Diameter(d_w),
		6,
		15,
		get(materials, "aluminum"),
	)
	add!(
		core,
		WireArray,
		Diameter(d_w),
		12,
		13.5,
		get(materials, "aluminum"),
	)
	add!(
		core,
		WireArray,
		Diameter(d_w),
		18,
		12.5,
		get(materials, "aluminum"),
	)
	add!(
		core,
		WireArray,
		Diameter(d_w),
		24,
		11,
		get(materials, "aluminum"),
	)
	# Inner semiconductive tape:
	main_insu = InsulatorGroup(
		Semicon(core, Thickness(t_sct), get(materials, "polyacrylate")),
	)
	# Inner semiconductor (1000 Ω.m as per IEC 840):
	add!(
		main_insu,
		Semicon,
		Thickness(t_sc_in),
		get(materials, "semicon1"),
	)
	# Add the insulation layer XLPE (cross-linked polyethylene):
	add!(
		main_insu,
		Insulator,
		Thickness(t_ins),
		get(materials, "pe"),
	)
	# Outer semiconductor (500 Ω.m as per IEC 840):
	add!(
		main_insu,
		Semicon,
		Thickness(t_sc_out),
		get(materials, "semicon2"),
	)
	# Outer semiconductive tape:
	add!(
		main_insu,
		Semicon,
		Thickness(t_sct),
		get(materials, "polyacrylate"),
	)
	# Group core-related components:
	core_cc = CableComponent("core", core, main_insu)
end
  ╠═╡ =#

# ╔═╡ Cell order:
# ╠═a82fd7fe-465d-4744-870f-638a72a54317
# ╠═46cfd6fa-b4d6-44c3-83cf-d2b9b1ff1cf1
# ╠═4462e48f-0d08-4ad9-8dd9-12f4f5912f38
# ╠═e90baf94-c8b8-41aa-8728-e129f7f6881e
# ╠═532cb61b-97b6-43e7-a8f9-3a5f12b8b3f7
# ╠═b16ff72c-872a-4505-9468-6cefd4a8852c
# ╠═9fefeafa-63f9-43d0-a2ee-4d4fca170126
# ╠═fde80e93-1964-4287-acfc-a2da2d4b7d48
# ╟─77d3c731-bdae-46c2-8b23-eb0b860e7444
# ╟─9ef6f05f-c384-4fab-bc39-e47edb49f994
# ╟─f08a32db-05d9-4ddb-9c46-34bc623ce5e7
# ╟─50384351-fc38-4b29-9bf6-db1556d49dee
# ╟─23913cc6-a81b-4098-bacf-7a2e09998e53
# ╟─d482241c-4bd5-4896-bdc1-e82387f69051
# ╟─14f07acc-5353-4b1d-b94f-9ae43f87289b
# ╟─6c6e4d21-cc38-46eb-8178-4cc4a99adcba
# ╟─3e6a9c64-827d-4491-bcac-252ee7b1dc81
# ╠═877a84cc-979f-48c9-ac41-59be60b4850b
# ╟─db1944b6-c55f-4091-8128-8d297bdc9a74
# ╟─5397f442-8dc1-42a6-941d-0b1d58057a6b
# ╟─a3f5a8c5-4ab9-4a33-abab-7907ffab1347
# ╟─382252ca-ede1-4043-b921-7834e59810cb
# ╟─96121e5b-6b5b-4ab1-81d0-6dcbe924cda2
# ╟─a8ea0da0-36f1-44d4-9415-d3041f34c23f
# ╟─f5fa7e28-97a7-456b-87a9-5ac4b76be9d4
# ╟─8c2eaef0-4e01-41b9-b1a6-a20dfa9b2d57
# ╟─cb8f01ae-26e0-44ce-8347-298ab692ac63
# ╟─29222f8e-fb07-4bdb-8939-f18e668d2037
# ╟─c1595a9d-7882-4b66-a1fc-fe6de19f1ef6
# ╟─c13e262c-2dd2-43da-a01b-a95adb7eaa7d
# ╠═c2539b01-ac04-48e4-a973-6a5d8a0e2b58
# ╠═c7c7ce65-3a0c-4ac6-82f0-f9f58e46f47e
# ╟─062439db-1e3f-497e-96c1-e1f65f80399b
# ╠═1b2bc07f-a88c-4b2f-a920-406d8743a2a8
# ╠═ec9ede5e-dd18-467e-88b7-e9964f05c97a
# ╟─4e1dec4b-223f-45f8-9393-523fcc4019f0
# ╟─5b005f4b-605e-4a3d-ba7f-003908f332b2
# ╠═e0f87b28-14a3-4630-87db-6f4b51bdb30a
# ╟─b081c88a-7959-44ea-85ff-33b980ec71b4
# ╟─0b5142ef-2eb0-4c72-8ba5-da776eadb5a3
# ╠═da168b34-43be-4701-8de8-5e953ff8dcd8
# ╟─cda1f413-8d71-4473-af93-f6ae2dd06ccb
# ╠═926048a4-f1e9-46ca-a6a8-84e254d74719
# ╠═6a74b6bf-d833-4d9b-af2c-0fcf729ff0f4
# ╟─c5bdbd1f-327e-4d33-8c14-f019b3057adb
# ╠═995cfe45-ba32-4c06-9843-603d2e6073bf
# ╠═58626fd7-b088-4310-811c-a4f3f1338f03
# ╟─783c759f-0889-4ce5-ba2e-6cc1c7555641
# ╠═a0138b90-e4d7-4711-95e1-b6e2f5f3fb30
# ╟─f904b5e4-0167-4ecf-8a5e-078a2877d4f7
# ╟─1ae76282-4340-4df0-ba29-11712c184a79
# ╠═9ddcccbe-86c8-4335-8d65-35af4ce755ab
# ╠═380b4c0a-780c-4be2-9c5a-666257dbe4da
# ╟─eb60126a-c646-417c-b9a6-9335b0cfe6c4
# ╠═58d30993-f4b3-4621-8d23-447b3d4f5935
# ╟─02a77417-3896-4e29-abd6-6e2586da0571
# ╟─da6b39c6-7053-4412-8bd8-6c0f771ee456
# ╠═282bd09f-ecea-44c7-b455-e83bb8e2fdd1
# ╟─00fcdd99-c603-4df3-a15b-d3ba64b34b7a
# ╠═8f147f54-ec3d-47a7-a3e7-9ff533adfb2d
# ╟─878f722b-0ad8-4098-8ff7-c11797eddddc
# ╠═a48ddf49-42f1-454e-8182-de1da6b51fe8
# ╟─fd1e268a-6520-4dc8-a9ff-32a4854859df
# ╟─b4169697-e06d-4947-8105-9f42017f5042
# ╠═0900d10f-8191-4507-af4e-50d7f4a1126f
# ╠═9ef6ef41-3a95-4540-ae93-dcc279ec72b0
# ╟─4ce85966-0386-4525-8cf2-35e9814f8459
# ╠═44f5823e-4b07-4f2c-8773-e4c3187a6100
# ╠═987902c5-5983-4815-b62f-4eabc1be2362
# ╟─539cdfbe-f5c6-47eb-9b2d-64f9ca7feacd
# ╟─960c9035-d86c-471a-9ed6-330beead03cb
# ╠═6ee6d16d-326c-4436-a750-077ecc2b3b9c
# ╠═2164f425-291b-4ca8-a66d-9ff3d402fdb8
# ╟─83d26ac6-24e5-4ca1-817c-921d3c2375c5
# ╟─2f28cc7a-cb14-44e6-908a-f34b8991c1bd
# ╟─a57fdd18-573b-4af9-984d-811132fe4fd1
# ╟─7d77f069-930b-4451-ab7d-0e77b8fd86a7
