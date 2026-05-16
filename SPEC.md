# swgraph — Specification

A containerized CLI tool that renders software-architecture and design
diagrams from text source files into SVG and PNG artifacts.

## Who it's for

- **Engineers** who want one tool to render `.gv`, `.puml`, `.d2`, `.ditaa`,
  `.mmd`, and `.dsl` source without installing a dozen tools locally.
- **Agentic workflows** (LLM-driven loops) that produce diagram source and
  need a deterministic way to turn it into image artifacts.
- **CI pipelines** that generate documentation with embedded diagrams.

## What it does

You give it one or more diagram source files. It gives you back SVG and PNG
files. That's it.

```bash
podman run --rm -v ./diagrams:/input -v ./out:/output swgraph render /input/*.puml
```

## Runtime

- **Container engine**: Podman (preferred) or Docker
- **Base image**: Alpine Linux (multi-stage build)
- **Platform**: linux/amd64 only (d2 binary is amd64-specific)
- **Entrypoint**: `swgraph` CLI script (Python 3), managed by `tini`

## CLI interface

```
swgraph render [OPTIONS] FILE [FILE...]

Options:
  -o, --output DIR        Output directory (default: /output)
  --sketch                Enable hand-drawn/xkcd style where supported
  --mermaid-backend CMD   'mmdc' (default) | 'isomorphic' (experimental)
  -q, --quiet             Suppress informational messages
  -v, --verbose           Show tool stdout/stderr
  --help                  Show usage

Other subcommands (convenience):
  swgraph verify          Run tool verification (all bundled tools healthy?)
  swgraph version         Print version of swgraph and all bundled tools
```

## Supported input formats

| Extension | Rendering tool | Output formats | Notes |
|-----------|---------------|----------------|-------|
| `.gv`, `.dot` | Graphviz | SVG + PNG | Layout engine auto-detected from `layout=X` in source; fallback: `dot` |
| `.puml`, `.plantuml` | PlantUML (+ C4, AWS, Azure, GCP stdlibs) | SVG + PNG | `--sketch` injects handwritten mode + xkcd font |
| `.d2` | d2 | SVG + PNG | `--sketch` uses d2's built-in sketch mode |
| `.ditaa` | ditaa | **PNG only** | ditaa has no SVG output; this is not an error |
| `.mmd`, `.mermaid` | Mermaid (mmdc) | SVG + PNG | Full server-side rendering via headless Chromium |
| `.dsl` | Structurizr CLI -> PlantUML | SVG + PNG | All views in the workspace are rendered |

## What it produces

For each input file, the tool produces artifacts in the output directory:

```
/output/
  deps.svg                       # from deps.gv
  deps.png
  sequence.svg                   # from sequence.puml
  sequence.png
  architecture.svg               # from architecture.d2
  architecture.png
  network.png                    # from network.ditaa (PNG only)
  flowchart.svg                  # from flowchart.mmd
  flowchart.png
  workspace-SystemContext.svg    # from workspace.dsl (one per view)
  workspace-SystemContext.png
  workspace-Container.svg
  workspace-Container.png
```

**Output naming**: `<input-basename-without-extension>.<format>`
Structurizr multi-view: `<input-basename>-<ViewName>.<format>`

## Behaviors

- **Best-effort output**: Always produce both SVG and PNG. If a tool can
  only produce one format (ditaa -> PNG), produce what it can without error.
- **Continue on error**: If one file fails to render, log the error and
  proceed to the next file. Exit non-zero at the end if any file failed.
- **Extension-based dispatch**: The tool is selected by file extension.
  Unrecognized extensions are rejected with a clear error message listing
  supported formats.
- **Graphviz engine auto-detection**: If the source contains a `layout=X`
  directive, that engine is used. Otherwise defaults to `dot`.
- **SVG to PNG conversion**: All SVG outputs are converted to PNG via
  `rsvg-convert`. This is a second step after the tool produces SVG.
- **Font embedding** (`--sketch`): When sketch mode is active, the xkcd
  font is embedded as a base64 data URI inside each SVG so the file is
  self-contained and renders correctly anywhere.

## Sketch / XKCD mode (`--sketch`)

An optional flag that enables each tool's native hand-drawn style:

| Tool | What `--sketch` does |
|------|---------------------|
| Graphviz | Renders via `sketchviz` (roughjs) instead of standard engine |
| PlantUML | Injects `!option handwritten true` + sets font to "xkcd Script" |
| d2 | Adds `--sketch` flag to d2 invocation |
| Mermaid | Adds `%%{init: {"look":"handDrawn"}}%%` directive |
| ditaa | No sketch mode available (ignored) |
| Structurizr | PlantUML output rendered with handwritten mode |

## Mermaid rendering

Two backends are bundled for evaluation:

1. **mmdc** (default) -- `@mermaid-js/mermaid-cli` with headless Chromium.
   Full diagram fidelity, supports all Mermaid diagram types. Uses
   Alpine's system `chromium` package with `--no-sandbox`.

2. **isomorphic-mermaid** (experimental) -- Pure Node.js rendering via
   jsdom/svgdom. No browser required. Lighter, but may produce imprecise
   layouts for complex diagrams. Select via `--mermaid-backend isomorphic`.

## Scope boundaries

### In scope

- Rendering diagram source files to SVG/PNG artifacts
- Bundling all tools in a single self-contained image
- Offline operation (PlantUML stdlibs vendored at build time)
- Deterministic output (same input -> same output paths)
- Best-effort hand-drawn styling via `--sketch`

### Out of scope

- **Data plotting** (scatter, bar, pie, line) -- use matplotlib/gnuplot
- **Interactive/animated diagrams** -- output is static images only
- **Theme system or palette enforcement** -- `--sketch` is the only styling knob
- **Diagram authoring / validation / linting** -- this tool renders, not edits
- **Multi-architecture images** -- linux/amd64 only for now
- **Web UI / editor** -- this is a CLI tool, not a web app
- **Stdin/stdout piping** -- files only (may be added later)

## Design constraints

- **Self-contained**: Everything needed to render is inside the image.
  No network access required at runtime.
- **Deterministic outputs**: Same input -> same output filenames, so
  scripts and agents can predict what will be produced.
- **No magic**: Extension determines the tool. No content sniffing.
- **Fail gracefully**: Never crash on bad input. Log, skip, continue.

## Image size budget

| Component | Approximate size |
|-----------|-----------------|
| Alpine base + system libs | ~50 MB |
| Java 17 JRE | ~170 MB |
| Graphviz (custom build with GTS) | ~50 MB |
| PlantUML + ditaa + Structurizr + stdlibs | ~80 MB |
| d2 binary | ~30 MB |
| Node.js + sketchviz + mmdc | ~100 MB |
| Chromium | ~150 MB |
| Fonts + misc tools | ~30 MB |
| **Total estimate** | **~850-900 MB** |
