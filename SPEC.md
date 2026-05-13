# swgraph — Specification

A small container image that renders software-architecture and software-design
diagrams from text source files. Designed to be invoked from the command line
or wired into an agentic LLM workflow.

## Who it's for

- Engineers who want one place to render `.gv`, `.puml`, `.d2`, `.ditaa`,
  `.mmd`, and `.dsl` source without installing a dozen tools locally.
- Agentic skills (LLM-driven loops) that produce diagram source and need a
  fast, deterministic way to turn it into SVG/PNG and inspect the result.

## Runtime

- Container engine: **Podman** (Containerfile preferred). The same file
  also works with `docker build`.
- Platform: **linux/amd64** only for now (the d2 binary download is
  amd64-specific; multi-arch is a later enhancement).

## Scope

In-scope diagram families:
- Dependency graphs (modules, packages, services)
- User interaction / UX flow / customer story / journey
- Feature description
- UML structural (class, component, deployment, package, object)
- UML behavioral (sequence, state, activity, use-case, timing)
- C4 model (Context / Container / Component / Code)
- Brownfield analysis: git-history DAG visualisation

Out of scope:
- Data plotting (scatter, bar, pie, line) → no matplotlib

## What it accepts

| Input extension | Tool used | What it represents |
|---|---|---|
| `.gv`, `.dot` | Graphviz (six layout engines) | Dependency / module / structural graphs |
| `.puml`, `.plantuml` | PlantUML (+ bundled C4 / AWS / Azure / GCP / themes) | UML structural & behavioral, C4 |
| `.mmd`, `.mermaid` | Mermaid (client-side via CDN) | Flowchart, sequence, state, class, ER, C4, journey, mindmap, timeline |
| `.d2` | d2 | Modern arch diagrams, customer journey |
| `.ditaa` | ditaa | ASCII-art → diagram (good for sketches) |
| `.dsl` | Structurizr CLI | C4 model DSL (transpiled to PlantUML/Mermaid/d2) |

Plus a dedicated helper for git-history DAGs:
- `swgraph asciidag-from-git --repo <path>` — brownfield analysis, no input file required.

Out of scope: data plotting (scatter, bar, pie, line). Use a different tool.

## What it produces

Default output directory layout (mounted at `/output` in the container):

```
output/
├── index.html               # gallery: every input rendered, source side-by-side
├── manifest.json            # machine-readable list of inputs → outputs
├── graphviz/<name>.{dot,neato,fdp,circo,twopi,sfdp}.svg
├── graphviz/<name>.txt      # ASCII version via graph-easy
├── plantuml/<name>.svg
├── d2/<name>.svg
├── ditaa/<name>.png
├── ditaa/<name>.ascii.txt   # chafa terminal preview
├── mermaid/<name>.mmd       # copied; index.html renders client-side via CDN
├── structurizr/<name>/      # one render per view defined in the DSL
└── asciidag/<repo>.txt
```

## How it's invoked

Three modes, same image:

### Batch (default)
Mount an input directory and an output directory, render everything found:

```bash
podman run --rm \
  -v ./diagrams:/input \
  -v ./out:/output \
  swgraph
```

### Single file
Render exactly one file. Output directory still mounted:

```bash
podman run --rm \
  -v ./diagrams:/input \
  -v ./out:/output \
  swgraph render diagrams/sequence.puml
```

### Stdin → stdout
Tightest agent loop, no volume mounts needed:

```bash
echo '@startuml
A -> B
@enduml' | podman run --rm -i swgraph render --format plantuml --to svg
```

### Other subcommands
- `swgraph serve` — start `python3 -m http.server 8080 --directory /output`
- `swgraph asciidag-from-git --repo /repo [--limit N]` — git log → asciidag
- `swgraph list-tools` — print the version of every bundled tool
- `swgraph verify` — run the install-time tool verification script

### Optional flags
- `--xkcd` — turn on each tool's native handwritten/sketch mode where
  available (PlantUML `handwritten true`, d2 `--sketch`). Best-effort
  styling, not a strict theme.

## Tools intentionally omitted

- **Inkscape** — replaced by `rsvg-convert` + `cairosvg` (saves ~500MB).
- **Mermaid CLI / Chromium** — Mermaid renders client-side in the gallery
  page via a CDN script (saves ~250MB). Use `swgraph serve` if your browser
  blocks CDNs over `file://`.

## Repo layout

```
swgraph/
├── PLAN.md                  # development plan (phased)
├── SPEC.md                  # this file
├── TECH_STACK.md            # tool inventory (filled in Phase 2)
├── Containerfile            # multi-stage Alpine build (Phase 3)
├── Makefile                 # build / verify / render / serve / test
├── README.md                # user-facing docs (Phase 5)
├── examples/                # demo inputs (Phase 4)
├── scripts/                 # renderers + helpers (Phase 5, plus wrappers in Phase 3)
└── tests/                   # verify-tools.sh + smoke.sh
```

## Design constraints

- **Smallest practical image.** Target ~430 MB. No GUI tools, no Chromium,
  no JDK (JRE only).
- **Offline by default.** PlantUML stdlibs (C4, AWS, Azure, GCP, themes)
  are vendored at build time. Mermaid is the only runtime CDN dependency,
  and only inside the gallery page.
- **Deterministic outputs.** Same input → same output paths every time, so
  an agent can reason about what was produced.
- **Best-effort styling, not a project goal.** xkcd font is the default
  where renderers accept one; `--xkcd` flag opts into native sketch modes;
  no palette enforcement or theme system.
