# swgraph — Development Plan

> Iterative, phased plan. Each phase has a clear deliverable and acceptance
> check; we don't move forward until the previous phase passes.

> Project scope, inputs, outputs, invocation modes, and out-of-scope items
> live in [`SPEC.md`](SPEC.md). This document is about **how** we build it.

## Development phases

### Phase 1 — `SPEC.md` (lazy, brief)
Single high-level document covering the project, who it's for, accepted
inputs, produced outputs, invocation modes, out-of-scope items, and a repo
layout placeholder.

**Acceptance**: user reads it and OKs it.

### Phase 2 — `TECH_STACK.md` (skeleton)
Bare list of bundled tools, grouped by purpose. One line per tool: name,
what it renders, source (apk / jar / binary / script). Versions filled in
once Phase 3 confirms what installs cleanly.

**Acceptance**: user confirms the tool list matches expectations.

### Phase 3 — `Containerfile` + iterate until clean build
Build with `podman build`, iterate until:
- Build completes
- Every bundled tool answers `--version` or `--help` (or equivalent)
- `tests/verify-tools.sh` runs inside the container, prints one-line
  PASS/FAIL per tool, exits 0 if all PASS

**Deliverables**:
- `Containerfile`
- `tests/verify-tools.sh`
- `Makefile` with `build` and `verify` targets
- `scripts/wrappers/{plantuml,ditaa,structurizr}` shims (needed for verify)

**Acceptance**: `make verify` exits 0 with every tool reporting its version.

### Phase 4 — Demo input files
A small starter set covering each tool family. User will add more.

**Deliverables** (`examples/`):
- `deps.gv` — Graphviz dependency
- `sequence.puml` — PlantUML sequence
- `c4_container.puml` — PlantUML C4 (uses bundled stdlib)
- `architecture.d2` — d2
- `network.ditaa` — ditaa
- `flowchart.mmd` — Mermaid flowchart
- `workspace.dsl` — Structurizr DSL
- `examples/README.md` — what each example demonstrates

**Acceptance**: user reviews, adds their own examples.

### Phase 5 — Renderers, gallery, manifest, iteration
Build the actual rendering pipeline against Phase 4 inputs. Iterate
visually with the user.

Sub-deliverables:
- Per-tool renderer scripts (`scripts/lib/render-*.sh`)
- Batch entry point (`scripts/render-batch.sh`) — scans `/input`,
  dispatches by extension, writes to `/output/<tool>/`
- `scripts/generate-manifest.py` → `/output/manifest.json`
- `scripts/generate-index.py` → `/output/index.html` (one section per tool,
  source code shown next to rendered output)
- Mermaid + helpers loaded via CDN in the gallery (no server-side Mermaid)
- Single-file mode: `swgraph render path/to/file.ext`
- Stdin→stdout mode: `cat file | swgraph render --format X --to svg`
- Optional `--xkcd` flag: PlantUML `handwritten true`, d2 `--sketch`
- Optional `serve` subcommand: `python3 -m http.server` against `/output`
- `swgraph asciidag-from-git --repo <path>` — brownfield analysis helper

**Acceptance**: `make render` produces a gallery the user is happy with;
iterate per-tool until each rendering looks right.

## Tool inventory (Phase 2 will document this)

| Tool | Purpose | Source |
|---|---|---|
| Graphviz `dot`/`neato`/`fdp`/`circo`/`twopi`/`sfdp` | Dependency, module, generic graph | apk `graphviz` |
| PlantUML | UML structural + behavioral, C4 | jar download |
| C4-PlantUML stdlib | C4 macros (offline) | git clone, bundled |
| AWS / Azure / GCP icons for PlantUML | Cloud arch | git clone, bundled |
| PlantUML themes (puml-themes) | Consistent styling | git clone, bundled |
| Mermaid (CDN, client-side) | Flowchart, sequence, state, ER, C4, journey, timeline, mindmap | CDN only |
| d2 | Modern arch + journey diagrams | binary download |
| ditaa | ASCII-art → diagram | jar download |
| Structurizr CLI | C4 DSL → PlantUML/Mermaid/d2 | zip download |
| graph-easy | Graphviz `.gv` → ASCII | cpanm `Graph::Easy` |
| asciidag | Git-history DAG (brownfield) | uvx |
| rsvg-convert | SVG → PNG/PDF (Inkscape replacement) | apk `rsvg-convert` |
| cairosvg | Alt SVG → PNG/PDF | apk `py3-cairosvg` |
| ImageMagick (`magick`) | Raster utilities | apk `imagemagick` |
| chafa | PNG → terminal ASCII | apk `chafa` |
| jp2a | JPEG → terminal ASCII | built from source (not in apk) |
| xkcd-script.ttf / xkcd.otf | Hand-drawn typography (CC BY-NC) | github raw |

## Containerfile strategy (Phase 3)

Multi-stage Alpine 3.21 build.

**Stage 1 — `downloader`** (alpine:3.21 + curl, tar, unzip, git, build-base, libjpeg-turbo-dev)
- Fetch plantuml-1.2026.3.jar
- Fetch ditaa-0.11.0-standalone.jar
- Fetch + extract d2-v0.7.1-linux-amd64.tar.gz
- Fetch + extract Structurizr CLI zip
- `git clone --depth=1` C4-PlantUML, AWS-icons, Azure-icons, GCP-icons,
  puml-themes (strip `.git`, `*.md`, `images/` to shrink)
- Fetch xkcd-script.ttf and xkcd.otf
- `git clone` jp2a + `make` → static binary

**Stage 2 — final** (alpine:3.21)
- apk: `graphviz openjdk17-jre-headless rsvg-convert imagemagick python3
  py3-pip py3-cairosvg py3-jinja2 uv chafa perl perl-app-cpanminus bash
  fontconfig font-dejavu libjpeg-turbo git tini`
- `cpanm --notest --no-man-pages Graph::Easy`, then `apk del perl-app-cpanminus`
- COPY artifacts from stage 1
- `fc-cache -fv` to pick up xkcd font
- COPY `scripts/wrappers/` and symlink each into `/usr/local/bin/`
- `ENV PLANTUML_INCLUDE_PATH=/opt/plantuml-stdlib/c4:.../aws:.../azure:.../gcp:.../themes`
- `WORKDIR /input`, `ENTRYPOINT ["/sbin/tini", "--"]`

Estimated final image: **~430 MB**.

## Phase 3 verification matrix

`tests/verify-tools.sh` (runs inside the container):

| Tool | Verification command |
|---|---|
| graphviz | `dot -V` / `neato -V` / `fdp -V` / `circo -V` / `twopi -V` / `sfdp -V` |
| plantuml | `plantuml -version` |
| ditaa | `ditaa --help` |
| d2 | `d2 --version` |
| structurizr | `structurizr version` |
| graph-easy | `graph-easy --version` |
| asciidag | `uvx --from asciidag python3 -c "import asciidag"` |
| rsvg-convert | `rsvg-convert --version` |
| cairosvg | `python3 -c "import cairosvg; print(cairosvg.__version__)"` |
| imagemagick | `magick --version` |
| chafa | `chafa --version` |
| jp2a | `jp2a --version` |
| xkcd font | `fc-list \| grep -i xkcd` |
| python | `python3 --version` |
| uv | `uv --version` |
| C4-PlantUML | `test -f /opt/plantuml-stdlib/c4/C4_Container.puml` |

Output: one line per tool, `[ OK ] toolname  vX.Y.Z` or `[FAIL] toolname  reason`.
Script exits non-zero if any FAIL.

## Styling (best effort — NOT a project goal)

- xkcd font installed and on the fontconfig path
- Renderers that accept a default font get `xkcd Script` set as default
- Optional `--xkcd` flag turns on PlantUML `handwritten true` and d2 `--sketch`
- No palette system, no per-tool theme configs, no theme injection

If we want richer styling later, layer it on top — don't block v1 on it.

## Repo layout (target end state, built incrementally)

```
swgraph/
├── PLAN.md                     # this file
├── SPEC.md                     # Phase 1
├── TECH_STACK.md               # Phase 2
├── Containerfile               # Phase 3
├── Makefile                    # Phase 3 (build/verify) + Phase 5 (render/serve)
├── README.md                   # Phase 5
├── .containerignore
├── examples/                   # Phase 4
│   └── *.gv, *.puml, *.d2, *.ditaa, *.mmd, *.dsl
├── scripts/                    # Phase 5 (mostly)
│   ├── swgraph                 #   internal CLI
│   ├── render-batch.sh
│   ├── render-one.sh
│   ├── render-stdin.sh
│   ├── serve.sh
│   ├── asciidag-from-git.sh
│   ├── generate-index.py
│   ├── generate-manifest.py
│   ├── lib/
│   │   ├── common.sh
│   │   └── render-*.sh
│   ├── wrappers/               # Phase 3
│   │   ├── plantuml
│   │   ├── ditaa
│   │   └── structurizr
│   └── templates/              # Phase 5
│       ├── index.html.j2
│       ├── tool-section.html.j2
│       └── style.css
└── tests/
    ├── verify-tools.sh         # Phase 3
    └── smoke.sh                # Phase 5 (full E2E)
```

## Risks / call-outs (to land in README during Phase 5)

- **xkcd font is CC BY-NC 3.0** — non-commercial use only.
- **PlantUML jar is current upstream (1.2026.3)**, not the 5-year-old
  VSCode-bundled 1.2021.00 the source doc references.
- **Mermaid renders client-side via CDN** — `file://` works in modern
  browsers; corporate browsers blocking CDNs need `swgraph serve`.
- **`.py` execution**: render-batch will NOT execute arbitrary Python from
  `/input`. asciidag is invoked through the dedicated helper, not via user
  Python files.
- **AWS/Azure/GCP icons vendored at build time** — refresh by rebuilding.
- **linux/amd64 only** — d2 binary download is amd64-specific. Multi-arch
  is a later enhancement.
