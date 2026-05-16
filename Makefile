# swgraph — make targets
#
# Usage:
#   make build     build the container image
#   make verify    run the in-container tool-verification script
#   make size      print the final image size
#   make shell     drop into bash inside the image
#   make render    run the demo gallery (render-batch.sh)
#   make clean     remove local build artifacts (out/)
#
# To render specific files via the CLI entrypoint:
#   make run ARGS="render examples/deps.gv"

IMAGE         ?= swgraph
TAG           ?= latest
ENGINE        ?= podman
BUILD_FLAGS   ?=
ARGS          ?= --help

.PHONY: help build rebuild verify verify-render size shell render run serve clean

help:
	@awk '/^[a-zA-Z_-]+:/ { sub(":.*", "", $$1); print "  " $$1 }' Makefile | sort -u

build:
	$(ENGINE) build $(BUILD_FLAGS) -f Containerfile -t $(IMAGE):$(TAG) .

rebuild:
	$(ENGINE) build --no-cache -f Containerfile -t $(IMAGE):$(TAG) .

verify:
	$(ENGINE) run --rm $(IMAGE):$(TAG) swgraph verify

# Render all examples in default + sketch modes. Fails if any file errors.
# Discovers input files automatically by supported extensions.
RENDER_EXTS := gv dot puml plantuml d2 ditaa mmd mermaid dsl
EXAMPLES    := $(foreach ext,$(RENDER_EXTS),$(wildcard examples/*.$(ext)))
INPUT_FILES := $(patsubst examples/%,/input/%,$(EXAMPLES))

verify-render:
	@rm -rf out/verify-default out/verify-sketch
	@mkdir -p out/verify-default out/verify-sketch
	$(ENGINE) run --rm \
		-v $(CURDIR)/examples:/input:ro,z \
		-v $(CURDIR)/out/verify-default:/output:z \
		$(IMAGE):$(TAG) \
		swgraph render $(INPUT_FILES)
	$(ENGINE) run --rm \
		-v $(CURDIR)/examples:/input:ro,z \
		-v $(CURDIR)/out/verify-sketch:/output:z \
		$(IMAGE):$(TAG) \
		swgraph render --sketch $(INPUT_FILES)
	@echo "=== verify-render passed ==="
	@echo "  default: $$(ls out/verify-default | wc -l) files"
	@echo "  sketch:  $$(ls out/verify-sketch | wc -l) files"

size:
	$(ENGINE) images $(IMAGE):$(TAG) --format '{{.Repository}}:{{.Tag}}\t{{.Size}}'

shell:
	$(ENGINE) run --rm -it --entrypoint /bin/bash $(IMAGE):$(TAG)

# Run swgraph with arbitrary arguments inside the container.
# Input files must be under examples/ (mounted at /input).
# Usage: make run ARGS="render /input/deps.gv"
run:
	$(ENGINE) run --rm \
		-v $(CURDIR)/examples:/input:ro,z \
		-v $(CURDIR)/out:/output:z \
		$(IMAGE):$(TAG) \
		swgraph $(ARGS)

# Full gallery render: calls swgraph render per variant, produces index.html
render:
	./scripts/render.sh

serve:
	./scripts/serve.sh

clean:
	rm -rf out/
