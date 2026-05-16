# swgraph examples

A starter set of demo input files covering the diagram families in scope.
Used by `make render` to produce `out/index.html` for visual inspection.

## Coverage

| Diagram family | Files |
|---|---|
| Dependency / module / structural | `graphviz_module_deps.gv`, `graphviz_minimal.gv`, `plantuml_components.puml` |
| Behavioural (state, sequence, flow) | `graphviz_state_machine.gv`, `plantuml_sequence.puml`, `plantuml_ux_state_machine.puml`, `plantuml_xkcd_handwritten.puml`, `mermaid_flowchart.mmd`, `mermaid_sequence.mmd` |
| C4 model | `plantuml_c4_container.puml`, `mermaid_c4.mmd`, `structurizr_workspace.dsl` |
| Cloud architecture | `plantuml_aws.puml`, `d2_architecture.d2` |
| User journey / customer story | `d2_journey.d2`, `mermaid_journey.mmd`, `plantuml_ux_state_machine.puml` |
| ASCII / sketch | `ditaa_network.ditaa` |
| XKCD / handwritten variants | `plantuml_xkcd_handwritten.puml`, `d2_journey.d2` (rendered with `--sketch`) |

## How to add more

Drop a new file into this directory. The renderer dispatches by extension:

| Extension | Tool |
|---|---|
| `.gv`, `.dot` | Graphviz (rendered with all 6 layout engines) |
| `.puml`, `.plantuml` | PlantUML |
| `.d2` | d2 (also rendered in `--sketch` mode) |
| `.ditaa` | ditaa |
| `.mmd`, `.mermaid` | Mermaid (client-side via CDN in `index.html`) |
| `.dsl` | Structurizr CLI (exports to PlantUML, then renders) |
