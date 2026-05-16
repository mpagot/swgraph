#!/usr/bin/env bash
# render-batch.sh — runs INSIDE the swgraph container.
# Scans /input by extension, calls `swgraph render` for each variant,
# and produces /output/index.html (single-page gallery).
#
# Designed for the research / iteration phase: every diagram is rendered;
# Graphviz inputs are rendered with all six layout engines side by side;
# PlantUML, d2, and Structurizr get a parallel "xkcd-style" render.

set -u

INPUT="${INPUT_DIR:-/input}"
OUTPUT="${OUTPUT_DIR:-/output}"
LOG="$OUTPUT/render.log"

mkdir -p \
    "$OUTPUT/graphviz" \
    "$OUTPUT/plantuml" \
    "$OUTPUT/d2" \
    "$OUTPUT/ditaa" \
    "$OUTPUT/mermaid" \
    "$OUTPUT/structurizr" \
    "$OUTPUT/fonts"

# Copy bundled xkcd font into output so the gallery's @font-face works
cp -f /usr/share/fonts/xkcd/*.{ttf,otf} "$OUTPUT/fonts/" 2>/dev/null || true

: > "$LOG"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()    { printf '[%s] %s\n' "$1" "$2" | tee -a "$LOG"; }
basename_noext() { local f="$1"; f=$(basename "$f"); printf '%s' "${f%.*}"; }

# Wrapper: call swgraph render and log result.
# Usage: render_one LABEL OUTPUT_DIR [OPTIONS...] FILE
render_one() {
    local label="$1"; shift
    local outdir="$1"; shift
    # remaining args: [options...] file
    if swgraph render -o "$outdir" -q "$@" >>"$LOG" 2>&1; then
        log OK "$label"
        return 0
    else
        log FAIL "$label"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Graphviz: render each .gv/.dot with every layout engine + sketch + ASCII
# ---------------------------------------------------------------------------
shopt -s nullglob
for src in "$INPUT"/*.gv "$INPUT"/*.dot; do
    name=$(basename_noext "$src")
    for engine in dot neato fdp circo twopi sfdp; do
        render_one "graphviz/$engine -> ${name}" "$OUTPUT/graphviz" \
            --engine "$engine" "$src"
        # Rename output to include engine in filename
        [ -f "$OUTPUT/graphviz/${name}.svg" ] && \
            mv "$OUTPUT/graphviz/${name}.svg" "$OUTPUT/graphviz/${name}.${engine}.svg"
        [ -f "$OUTPUT/graphviz/${name}.png" ] && \
            mv "$OUTPUT/graphviz/${name}.png" "$OUTPUT/graphviz/${name}.${engine}.png"
    done

    # graph-easy ASCII (best effort; some advanced .gv constructs aren't supported)
    if graph-easy --as=ascii "$src" > "$OUTPUT/graphviz/${name}.txt" 2>>"$LOG"; then
        log OK "graph-easy -> ${name}.txt"
    else
        rm -f "$OUTPUT/graphviz/${name}.txt"
        log SKIP "graph-easy ${name} (could not parse this .gv)"
    fi

    # sketchviz — XKCD/hand-drawn variant
    render_one "sketchviz -> ${name}.xkcd" "$OUTPUT/graphviz" \
        --sketch "$src"
    [ -f "$OUTPUT/graphviz/${name}.svg" ] && \
        mv "$OUTPUT/graphviz/${name}.svg" "$OUTPUT/graphviz/${name}.xkcd.svg"
    [ -f "$OUTPUT/graphviz/${name}.png" ] && \
        mv "$OUTPUT/graphviz/${name}.png" "$OUTPUT/graphviz/${name}.xkcd.png"
done

# ---------------------------------------------------------------------------
# PlantUML: default + xkcd/handwritten variant
# ---------------------------------------------------------------------------
# PlantUML respects @startuml NAME for the output filename, so render into
# per-input subdirs to avoid naming collisions.
for src in "$INPUT"/*.puml "$INPUT"/*.plantuml; do
    name=$(basename_noext "$src")
    render_one "plantuml -> ${name}" "$OUTPUT/plantuml/$name" "$src"
    render_one "plantuml/xkcd -> ${name}" "$OUTPUT/plantuml/${name}.xkcd" \
        --sketch "$src"
done

# ---------------------------------------------------------------------------
# d2: three variants — default, --sketch, sketch + warm palette
# ---------------------------------------------------------------------------
for src in "$INPUT"/*.d2; do
    name=$(basename_noext "$src")
    render_one "d2 -> ${name}" "$OUTPUT/d2" "$src"
    [ -f "$OUTPUT/d2/${name}.svg" ] && \
        mv "$OUTPUT/d2/${name}.svg" "$OUTPUT/d2/${name}.default.svg"
    [ -f "$OUTPUT/d2/${name}.png" ] && \
        mv "$OUTPUT/d2/${name}.png" "$OUTPUT/d2/${name}.default.png"

    render_one "d2/sketch -> ${name}" "$OUTPUT/d2" --sketch "$src"
    [ -f "$OUTPUT/d2/${name}.svg" ] && \
        mv "$OUTPUT/d2/${name}.svg" "$OUTPUT/d2/${name}.sketch.svg"
    [ -f "$OUTPUT/d2/${name}.png" ] && \
        mv "$OUTPUT/d2/${name}.png" "$OUTPUT/d2/${name}.sketch.png"

    render_one "d2/xkcd -> ${name}" "$OUTPUT/d2" \
        --sketch --d2-theme 4 --d2-pad 60 "$src"
    [ -f "$OUTPUT/d2/${name}.svg" ] && \
        mv "$OUTPUT/d2/${name}.svg" "$OUTPUT/d2/${name}.xkcd.svg"
    [ -f "$OUTPUT/d2/${name}.png" ] && \
        mv "$OUTPUT/d2/${name}.png" "$OUTPUT/d2/${name}.xkcd.png"
done

# ---------------------------------------------------------------------------
# ditaa: PNG only; ditaa doesn't support SVG
# ---------------------------------------------------------------------------
for src in "$INPUT"/*.ditaa; do
    name=$(basename_noext "$src")
    render_one "ditaa -> ${name}" "$OUTPUT/ditaa" "$src"
done

# ---------------------------------------------------------------------------
# Mermaid: copy sources for client-side rendering in the gallery.
#   - <name>.mmd       — verbatim (default theme via gallery mermaid.initialize())
#   - <name>.xkcd.mmd  — prefixed with %%{init: …}%% for hand-drawn theme
# ---------------------------------------------------------------------------
MERMAID_XKCD_INIT='%%{init: {"look":"handDrawn","theme":"base","themeVariables":{"fontSize":"16px","background":"#fffff8","primaryColor":"#fffde7","primaryTextColor":"#1a1a1a","primaryBorderColor":"#1a1a1a","lineColor":"#1a1a1a","secondaryColor":"#cfe8cf","tertiaryColor":"#ffe0b2","noteBkgColor":"#fff9c4","noteBorderColor":"#1a1a1a","edgeLabelBackground":"#fffff8"}, "flowchart":{"curve":"basis"}}}%%'

for src in "$INPUT"/*.mmd "$INPUT"/*.mermaid; do
    name=$(basename_noext "$src")
    cp -f "$src" "$OUTPUT/mermaid/${name}.mmd"
    {
        printf '%s\n' "$MERMAID_XKCD_INIT"
        cat "$src"
    } > "$OUTPUT/mermaid/${name}.xkcd.mmd"
    log OK "mermaid -> ${name}.mmd + ${name}.xkcd.mmd"
done

# ---------------------------------------------------------------------------
# Structurizr: default + sketch
# ---------------------------------------------------------------------------
for src in "$INPUT"/*.dsl; do
    name=$(basename_noext "$src")
    render_one "structurizr -> ${name}" "$OUTPUT/structurizr" "$src"
    render_one "structurizr/xkcd -> ${name}" "$OUTPUT/structurizr" \
        --sketch "$src"
done

# ---------------------------------------------------------------------------
# index.html — single-page gallery
# ---------------------------------------------------------------------------
generate_index() {
    local out="$OUTPUT/index.html"

    {
        cat <<'HTML_HEAD'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>swgraph gallery</title>
<link rel="preload" href="fonts/xkcd-script.ttf" as="font" type="font/ttf" crossorigin>
<style>
@font-face {
    font-family: "xkcd Script";
    src: url("fonts/xkcd-script.ttf") format("truetype");
    font-display: block;
}
:root {
    --bg: #fffff8;
    --ink: #1a1a1a;
    --muted: #999;
    --rule: #ddd;
    --code-bg: #f6f6f3;
    --accent: #4a90d9;
}
* { box-sizing: border-box; }
body {
    background: var(--bg);
    color: var(--ink);
    font-family: -apple-system, "Segoe UI", Roboto, sans-serif;
    margin: 0;
    padding: 2rem;
    max-width: 1400px;
    margin-inline: auto;
}
h1 { font-size: 2rem; margin: 0 0 0.5rem; }
h1, h2 { font-family: "xkcd Script", sans-serif; }
h2 {
    margin-top: 3rem;
    padding-bottom: 0.4rem;
    border-bottom: 2px solid var(--ink);
    font-size: 1.6rem;
}
.intro { color: var(--muted); margin-bottom: 2rem; }
.tool-nav { margin: 1rem 0 2rem; }
.tool-nav a {
    display: inline-block;
    margin-right: 1rem;
    padding: 0.3rem 0.8rem;
    border: 1px solid var(--ink);
    border-radius: 4px;
    color: var(--ink);
    text-decoration: none;
    font-family: "xkcd Script", sans-serif;
}
.tool-nav a:hover { background: var(--ink); color: var(--bg); }

.diagram {
    margin: 2rem 0;
    padding: 1rem 1.2rem;
    border: 1px solid var(--rule);
    border-radius: 6px;
    background: white;
}
.diagram h3 {
    margin: 0 0 0.5rem;
    font-family: "xkcd Script", sans-serif;
    font-size: 1.2rem;
}
.filename {
    font-family: ui-monospace, "SF Mono", Menlo, monospace;
    font-size: 0.85rem;
    color: var(--muted);
}
details { margin: 0.5rem 0 1rem; }
summary { cursor: pointer; color: var(--accent); user-select: none; }
pre {
    background: var(--code-bg);
    padding: 0.8rem 1rem;
    border-radius: 4px;
    overflow-x: auto;
    font-size: 0.85rem;
    line-height: 1.4;
}
.renders {
    display: grid;
    gap: 1rem;
    margin-top: 1rem;
    grid-template-columns: 1fr;
}
.render-tile {
    border: 1px dashed var(--rule);
    padding: 0.5rem;
    text-align: center;
    background: var(--bg);
}
.render-tile .label {
    font-size: 0.8rem;
    color: var(--muted);
    margin-bottom: 0.2rem;
    font-family: ui-monospace, monospace;
}
.render-tile .tile-desc {
    font-size: 0.72rem;
    color: var(--muted);
    margin-bottom: 0.4rem;
    font-style: italic;
    line-height: 1.2;
}
.render-tile img,
.render-tile object,
.render-tile svg,
.render-tile pre.mermaid {
    max-width: 100%;
    height: auto;
}
.ascii {
    background: var(--code-bg);
    padding: 0.6rem;
    overflow-x: auto;
    font-size: 0.7rem;
    line-height: 1.1;
    margin: 0;
}
.empty-msg { color: var(--muted); font-style: italic; }
</style>
</head>
<body>
<h1>swgraph gallery</h1>
<p class="intro">Each input from <code>examples/</code> rendered with every applicable
tool. Compare layout engines, themes, and styles side by side.</p>

<nav class="tool-nav">
    <a href="#graphviz">Graphviz</a>
    <a href="#plantuml">PlantUML</a>
    <a href="#d2">d2</a>
    <a href="#ditaa">ditaa</a>
    <a href="#mermaid">Mermaid</a>
    <a href="#structurizr">Structurizr</a>
</nav>
HTML_HEAD

        # ---------- Graphviz ----------
        echo '<h2 id="graphviz">Graphviz</h2>'
        echo '<p class="intro">Each input rendered with all six layout engines (custom-built graphviz with GTS), plus a sketchy XKCD-style variant via <code>sketchviz</code>, plus an ASCII version via <code>graph-easy</code>.</p>'
        for src in "$INPUT"/*.gv "$INPUT"/*.dot; do
            [ -f "$src" ] || continue
            name=$(basename_noext "$src")
            echo "<div class=\"diagram\"><h3>$name <span class=\"filename\">$(basename "$src")</span></h3>"
            echo "<details><summary>source</summary><pre>"
            sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "$src"
            echo "</pre></details>"
            echo '<div class="renders">'
            for engine in dot neato fdp circo twopi sfdp; do
                f="graphviz/${name}.${engine}.svg"
                if [ -f "$OUTPUT/$f" ]; then
                    case "$engine" in
                        dot)   desc="hierarchical / layered DAG; the only engine that fully respects <code>subgraph cluster_*</code>";;
                        neato) desc="force-directed (springs); shows coupling. Cluster bounding-boxes ignored";;
                        fdp)   desc="force-directed (Fruchterman-Reingold); cluster boxes drawn but layout still flat";;
                        circo) desc="circular; best for graphs that have cycles";;
                        twopi) desc="radial; pick a centre with <code>graph[root=NODE]</code>; best for trees &amp; hub-and-spoke";;
                        sfdp)  desc="scalable force-directed; best for large graphs (&gt;100 nodes), uses GTS triangulation";;
                    esac
                    echo "<div class=\"render-tile\"><div class=\"label\">$engine</div><div class=\"tile-desc\">$desc</div><object data=\"$f\" type=\"image/svg+xml\"></object></div>"
                fi
            done
            # sketchviz (xkcd / hand-drawn)
            xkcd="graphviz/${name}.xkcd.svg"
            if [ -f "$OUTPUT/$xkcd" ]; then
                echo "<div class=\"render-tile\"><div class=\"label\">sketchviz / xkcd</div><div class=\"tile-desc\">hand-drawn variant via roughjs</div><object data=\"$xkcd\" type=\"image/svg+xml\"></object></div>"
            fi
            echo '</div>'
            ascii="$OUTPUT/graphviz/${name}.txt"
            if [ -f "$ascii" ]; then
                echo '<details><summary>ascii (graph-easy)</summary><pre class="ascii">'
                sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "$ascii"
                echo '</pre></details>'
            fi
            echo '</div>'
        done

        # ---------- PlantUML ----------
        echo '<h2 id="plantuml">PlantUML</h2>'
        echo '<p class="intro">Default render alongside the <code>handwritten</code> + <code>xkcd Script</code> variant.</p>'
        for src in "$INPUT"/*.puml "$INPUT"/*.plantuml; do
            [ -f "$src" ] || continue
            name=$(basename_noext "$src")
            echo "<div class=\"diagram\"><h3>$name <span class=\"filename\">$(basename "$src")</span></h3>"
            echo "<details><summary>source</summary><pre>"
            sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "$src"
            echo "</pre></details>"
            echo '<div class="renders">'
            for f in "$OUTPUT/plantuml/$name"/*.svg; do
                [ -f "$f" ] || continue
                rel=${f#$OUTPUT/}
                echo "<div class=\"render-tile\"><div class=\"label\">default</div><object data=\"$rel\" type=\"image/svg+xml\"></object></div>"
            done
            for f in "$OUTPUT/plantuml/${name}.xkcd"/*.svg; do
                [ -f "$f" ] || continue
                rel=${f#$OUTPUT/}
                echo "<div class=\"render-tile\"><div class=\"label\">handwritten / xkcd</div><object data=\"$rel\" type=\"image/svg+xml\"></object></div>"
            done
            echo '</div></div>'
        done

        # ---------- d2 ----------
        echo '<h2 id="d2">d2</h2>'
        echo '<p class="intro">Default &middot; <code>--sketch</code> &middot; sketch + warm palette (Cool Classics).</p>'
        for src in "$INPUT"/*.d2; do
            [ -f "$src" ] || continue
            name=$(basename_noext "$src")
            echo "<div class=\"diagram\"><h3>$name <span class=\"filename\">$(basename "$src")</span></h3>"
            echo "<details><summary>source</summary><pre>"
            sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "$src"
            echo "</pre></details>"
            echo '<div class="renders">'
            [ -f "$OUTPUT/d2/${name}.default.svg" ] && \
              echo "<div class=\"render-tile\"><div class=\"label\">default</div><object data=\"d2/${name}.default.svg\" type=\"image/svg+xml\"></object></div>"
            [ -f "$OUTPUT/d2/${name}.sketch.svg" ] && \
              echo "<div class=\"render-tile\"><div class=\"label\">--sketch</div><object data=\"d2/${name}.sketch.svg\" type=\"image/svg+xml\"></object></div>"
            [ -f "$OUTPUT/d2/${name}.xkcd.svg" ] && \
              echo "<div class=\"render-tile\"><div class=\"label\">sketch + warm palette</div><object data=\"d2/${name}.xkcd.svg\" type=\"image/svg+xml\"></object></div>"
            echo '</div></div>'
        done

        # ---------- ditaa ----------
        echo '<h2 id="ditaa">ditaa</h2>'
        for src in "$INPUT"/*.ditaa; do
            [ -f "$src" ] || continue
            name=$(basename_noext "$src")
            echo "<div class=\"diagram\"><h3>$name <span class=\"filename\">$(basename "$src")</span></h3>"
            echo "<details><summary>source (ASCII)</summary><pre>"
            sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "$src"
            echo "</pre></details>"
            if [ -f "$OUTPUT/ditaa/${name}.png" ]; then
                echo "<div class=\"renders\"><div class=\"render-tile\"><div class=\"label\">PNG</div><img src=\"ditaa/${name}.png\" alt=\"$name\"></div></div>"
            fi
            echo '</div>'
        done

        # ---------- Mermaid ----------
        echo '<h2 id="mermaid">Mermaid</h2>'
        echo '<p class="intro">Rendered client-side by your browser via the Mermaid CDN. Default theme on the left; xkcd-style theme on the right (per-block <code>%%{init:&hellip;}%%</code> override).</p>'
        for src in "$INPUT"/*.mmd "$INPUT"/*.mermaid; do
            [ -f "$src" ] || continue
            name=$(basename_noext "$src")
            echo "<div class=\"diagram\"><h3>$name <span class=\"filename\">$(basename "$src")</span></h3>"
            echo "<details><summary>source</summary><pre>"
            sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "$src"
            echo "</pre></details>"
            echo '<div class="renders">'
            echo "<div class=\"render-tile\"><div class=\"label\">default theme</div><pre class=\"mermaid\">"
            sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "$src"
            echo "</pre></div>"
            xkcd_src="$OUTPUT/mermaid/${name}.xkcd.mmd"
            if [ -f "$xkcd_src" ]; then
                echo "<div class=\"render-tile\"><div class=\"label\">xkcd theme</div><pre class=\"mermaid mermaid-xkcd\">"
                sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "$xkcd_src"
                echo "</pre></div>"
            fi
            echo "</div></div>"
        done

        # ---------- Structurizr ----------
        echo '<h2 id="structurizr">Structurizr</h2>'
        echo '<p class="intro">DSL exported to PlantUML (one .puml per view), then rendered.</p>'
        for src in "$INPUT"/*.dsl; do
            [ -f "$src" ] || continue
            name=$(basename_noext "$src")
            echo "<div class=\"diagram\"><h3>$name <span class=\"filename\">$(basename "$src")</span></h3>"
            echo "<details><summary>source (DSL)</summary><pre>"
            sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "$src"
            echo "</pre></details>"
            echo '<div class="renders">'
            for f in "$OUTPUT"/structurizr/*.svg; do
                [ -f "$f" ] || continue
                rel=${f#$OUTPUT/}
                view=$(basename_noext "$f")
                echo "<div class=\"render-tile\"><div class=\"label\">$view</div><object data=\"$rel\" type=\"image/svg+xml\"></object></div>"
            done
            echo '</div></div>'
        done

        # ---------- footer + Mermaid CDN init ----------
        cat <<'HTML_FOOT'
<hr>
<p class="intro">Generated by <code>swgraph</code> &middot; open <code>render.log</code> for raw tool output.</p>

<script type="module">
import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';

// Explicitly load the xkcd font — preload alone isn't sufficient because
// no visible element uses it before Mermaid renders.
await document.fonts.load('16px "xkcd Script"');

// Pass 1: render regular (non-xkcd) diagrams with default theme.
mermaid.initialize({ startOnLoad: false });
await mermaid.run({ querySelector: 'pre.mermaid:not(.mermaid-xkcd)' });

// Pass 2: render xkcd-themed diagrams.  fontFamily MUST be set here via
// initialize() because Mermaid v10 silently ignores fontFamily when set
// through per-diagram %%{init}%% directives (colors/curve still work there).
mermaid.initialize({
  startOnLoad: false,
  theme: 'base',
  look: 'handDrawn',
  themeVariables: {
    fontFamily: '"xkcd Script", "Comic Sans MS", sans-serif'
  }
});
await mermaid.run({ querySelector: 'pre.mermaid-xkcd' });
</script>
</body>
</html>
HTML_FOOT
    } > "$out"

    log OK "wrote index.html"
}

generate_index

echo
echo "== summary =="
grep -c '^\[OK\]' "$LOG"   | xargs -I{} echo "  OK   : {}"
grep -c '^\[FAIL\]' "$LOG" | xargs -I{} echo "  FAIL : {}"
grep -c '^\[SKIP\]' "$LOG" | xargs -I{} echo "  SKIP : {}"
echo "== outputs =="
echo "  index : $OUTPUT/index.html"
echo "  log   : $LOG"
