# swgraph — diagram-rendering toolkit
# Multi-stage Alpine build. Stage 1 fetches/builds artifacts; stage 2 is the runtime.

# ---------------------------------------------------------------------------
# Versions (bump in one place)
# ---------------------------------------------------------------------------
ARG ALPINE_VERSION=3.24
ARG PLANTUML_VERSION=1.2026.6
ARG DITAA_VERSION=0.11.0
ARG D2_VERSION=0.7.1
ARG STRUCTURIZR_VERSION=2025.11.09
ARG GRAPHVIZ_VERSION=15.0.0

# ---------------------------------------------------------------------------
# Stage 1 — downloader / builder
# ---------------------------------------------------------------------------
FROM alpine:${ALPINE_VERSION} AS downloader

ARG PLANTUML_VERSION
ARG DITAA_VERSION
ARG D2_VERSION
ARG STRUCTURIZR_VERSION

RUN apk add --no-cache \
        curl tar unzip git \
        nodejs npm \
        build-base libjpeg-turbo-dev libpng-dev libwebp-dev libexif-dev autoconf automake

RUN mkdir -p /out
WORKDIR /out

# PlantUML jar
RUN curl -fsSL -o /tmp/plantuml.jar \
      "https://github.com/plantuml/plantuml/releases/download/v${PLANTUML_VERSION}/plantuml-${PLANTUML_VERSION}.jar" \
 && mv /tmp/plantuml.jar /out/plantuml.jar

# ditaa jar
RUN curl -fsSL -o /tmp/ditaa.jar \
      "https://github.com/stathissideris/ditaa/releases/download/v${DITAA_VERSION}/ditaa-${DITAA_VERSION}-standalone.jar" \
 && mv /tmp/ditaa.jar /out/ditaa.jar

# d2 binary (linux/amd64, static)
RUN curl -fsSL -o /tmp/d2.tar.gz \
      "https://github.com/terrastruct/d2/releases/download/v${D2_VERSION}/d2-v${D2_VERSION}-linux-amd64.tar.gz" \
 && mkdir /tmp/d2 \
 && tar -xzf /tmp/d2.tar.gz -C /tmp/d2 \
 && find /tmp/d2 -type f -name d2 -exec cp {} /out/d2 \; \
 && chmod +x /out/d2 \
 && rm -rf /tmp/d2 /tmp/d2.tar.gz

# Structurizr CLI
RUN curl -fsSL -o /tmp/structurizr.zip \
      "https://github.com/structurizr/cli/releases/download/v${STRUCTURIZR_VERSION}/structurizr-cli.zip" \
 && mkdir -p /out/structurizr \
 && unzip -q /tmp/structurizr.zip -d /out/structurizr \
 && chmod +x /out/structurizr/structurizr.sh \
 && rm /tmp/structurizr.zip

# PlantUML stdlibs (vendored offline). The icon repos ship dev tooling
# (sample bundled PlantUML jars, Batik libs, mermaid JSON, SVG sources)
# that we don't need at runtime. Strip aggressively: keep only .puml/.iuml
# files plus the directory structure that contains them.
RUN mkdir -p /out/plantuml-stdlib \
 && git clone --depth=1 https://github.com/plantuml-stdlib/C4-PlantUML.git \
      /out/plantuml-stdlib/c4 \
 && git clone --depth=1 https://github.com/awslabs/aws-icons-for-plantuml.git \
      /out/plantuml-stdlib/aws \
 && git clone --depth=1 https://github.com/plantuml-stdlib/Azure-PlantUML.git \
      /out/plantuml-stdlib/azure \
 && git clone --depth=1 https://github.com/davidholsgrove/gcp-icons-for-plantuml.git \
      /out/plantuml-stdlib/gcp \
 && find /out/plantuml-stdlib -type d \
      \( -name .git -o -name scripts -o -name source -o -name images \
       -o -name screenshots -o -name examples -o -name docs -o -name doc \
       -o -name tests -o -name test -o -name presentation -o -name .github \
      \) -exec rm -rf {} + 2>/dev/null \
 ; find /out/plantuml-stdlib -type f \
      ! -name "*.puml" ! -name "*.iuml" -delete \
 && find /out/plantuml-stdlib -type d -empty -delete

# xkcd handwriting fonts
RUN mkdir -p /out/fonts \
 && curl -fsSL -o /tmp/xkcd-script.ttf \
      https://github.com/ipython/xkcd-font/raw/master/xkcd-script/font/xkcd-script.ttf \
 && curl -fsSL -o /tmp/xkcd.otf \
      https://github.com/ipython/xkcd-font/raw/master/xkcd/build/xkcd.otf \
 && mv /tmp/xkcd-script.ttf /out/fonts/xkcd-script.ttf \
 && mv /tmp/xkcd.otf /out/fonts/xkcd.otf

# sketchviz — gpotter2's CLI clone of sketchviz.com (renders .dot as a
# hand-drawn SVG via roughjs + jsdom). Not on npm registry (the npm package
# of that name is a typosquat); install from the GitHub repo.
RUN git clone --depth=1 https://github.com/gpotter2/sketchviz.git /out/sketchviz \
 && cd /out/sketchviz \
 && npm install --omit=dev --no-audit --no-fund --no-progress \
 && rm -rf /out/sketchviz/.git /out/sketchviz/examples

# jp2a (JPEG → ASCII), built from source — not packaged in Alpine.
# Talinx/jp2a uses autotools; autogen.sh runs autoreconf -i.
RUN git clone --depth=1 https://github.com/Talinx/jp2a.git /tmp/jp2a \
 && cd /tmp/jp2a \
 && sh autogen.sh \
 && sh configure --prefix=/usr/local --disable-curl \
 && make -j"$(nproc)" \
 && cp src/jp2a /out/jp2a \
 && chmod +x /out/jp2a \
 && rm -rf /tmp/jp2a

# ---------------------------------------------------------------------------
# Stage 2 — graphviz built from source
# Alpine's apk graphviz omits sfdp (no GTS triangulation) and prism overlap
# removal. Build the latest stable from upstream with full features. Result
# lands in /opt/graphviz/{bin,lib,...}; runtime libs are added in stage 3.
# ---------------------------------------------------------------------------
FROM alpine:${ALPINE_VERSION} AS graphviz-builder
ARG GRAPHVIZ_VERSION

# GTS (the GNU Triangulated Surface library) is NOT packaged in Alpine, so
# graphviz's sfdp + prism overlap features need it built from source first.
# We install it to /opt/graphviz so a single COPY in stage 3 brings both.
RUN apk add --no-cache \
        curl git \
        autoconf automake libtool bison flex m4 pkgconf \
        build-base python3 \
        glib-dev \
        cairo-dev pango-dev gd-dev librsvg-dev \
        libxml2-dev expat-dev libpng-dev libjpeg-turbo-dev \
        freetype-dev fontconfig-dev

# Build GTS 0.7.6 (Debian's repackaged darcs snapshot — last known stable).
RUN curl -fsSL -o /tmp/gts.tar.gz \
      "https://launchpad.net/ubuntu/+archive/primary/+sourcefiles/gts/0.7.6+darcs121130-4/gts_0.7.6+darcs121130.orig.tar.gz" \
 && mkdir /tmp/gts && tar -xzf /tmp/gts.tar.gz -C /tmp/gts --strip-components=1 \
 && cd /tmp/gts \
 && ./configure --prefix=/opt/graphviz --enable-static=no \
 && make -j"$(nproc)" \
 && make install \
 && rm -rf /tmp/gts /tmp/gts.tar.gz

# Build graphviz against the freshly-installed GTS. PKG_CONFIG_PATH points
# to /opt/graphviz/lib/pkgconfig so configure's --with-gts can locate it.
ENV PKG_CONFIG_PATH=/opt/graphviz/lib/pkgconfig
ENV LD_LIBRARY_PATH=/opt/graphviz/lib

RUN git clone --depth=1 --branch="${GRAPHVIZ_VERSION}" \
        https://gitlab.com/graphviz/graphviz.git /tmp/graphviz \
 && cd /tmp/graphviz \
 && find . -name "*.py" -exec chmod +x {} + \
 && sh autogen.sh NOCONFIG \
 && ./configure --prefix=/opt/graphviz \
        --enable-static=no \
        --with-gts --with-pangocairo --with-libgd --with-rsvg \
        --enable-perl=no --enable-python=no --enable-ruby=no \
        --enable-tcl=no --enable-lua=no --enable-php=no \
        --enable-go=no --enable-d=no --enable-guile=no \
        --enable-java=no --enable-ocaml=no --enable-r=no \
        --enable-sharp=no --enable-swig=no \
 && make -j"$(nproc)" \
 && make install \
 && rm -rf /tmp/graphviz

# Separate RUN so a strip failure doesn't mask a build failure above.
RUN strip /opt/graphviz/bin/* /opt/graphviz/lib/*.so* 2>/dev/null || true

# ---------------------------------------------------------------------------
# Stage 3 — final runtime image
# ---------------------------------------------------------------------------
FROM alpine:${ALPINE_VERSION}

LABEL org.opencontainers.image.title="swgraph"
LABEL org.opencontainers.image.description="Diagram-rendering toolkit for software architecture & design"
LABEL org.opencontainers.image.source="local"

# Base runtime + diagram tools available in apk.
# NOTE: `graphviz` is intentionally NOT installed via apk — we use the
# from-source build in /opt/graphviz/ (see graphviz-builder stage) for
# sfdp + prism overlap support. The runtime libs that build dynamically
# links against (gts, cairo, pango, gd, librsvg) are still apk packages.
RUN apk add --no-cache \
        bash tini \
        fontconfig font-dejavu \
        glib cairo pango gd librsvg \
        openjdk17-jre \
        rsvg-convert \
        imagemagick \
        python3 py3-pip py3-cairosvg py3-jinja2 \
        uv \
        chafa \
        perl perl-app-cpanminus \
        libjpeg-turbo libpng libwebp libexif \
        nodejs npm \
        git \
        coreutils findutils \
        chromium ttf-dejavu ttf-freefont

# Graph::Easy (pure Perl) via cpanm; remove cpanm afterwards to slim down
RUN cpanm --notest --no-man-pages Graph::Easy \
 && apk del perl-app-cpanminus \
 && rm -rf /root/.cpanm /var/cache/apk/*

# Custom graphviz build (full features: sfdp + prism overlap).
# /opt/graphviz contains both libgts and the graphviz binaries built against it.
COPY --from=graphviz-builder /opt/graphviz/    /opt/graphviz/
ENV PATH=/opt/graphviz/bin:$PATH
ENV LD_LIBRARY_PATH=/opt/graphviz/lib

# Artifacts from the downloader stage
COPY --from=downloader /out/plantuml.jar       /opt/plantuml.jar
COPY --from=downloader /out/ditaa.jar          /opt/ditaa.jar
COPY --from=downloader /out/d2                 /usr/local/bin/d2
COPY --from=downloader /out/structurizr/       /opt/structurizr/
COPY --from=downloader /out/plantuml-stdlib/   /opt/plantuml-stdlib/
COPY --from=downloader /out/fonts/             /usr/share/fonts/xkcd/
COPY --from=downloader /out/jp2a               /usr/local/bin/jp2a
COPY --from=downloader /out/sketchviz/         /opt/sketchviz/

RUN fc-cache -fv

# ---------------------------------------------------------------------------
# Mermaid CLI (mmdc) — server-side rendering via headless Chromium.
# Uses Alpine's system chromium; skips Puppeteer's bundled download.
# ---------------------------------------------------------------------------
ENV PUPPETEER_SKIP_DOWNLOAD=true
RUN npm install -g @mermaid-js/mermaid-cli \
 && echo '{"executablePath":"/usr/bin/chromium-browser","args":["--no-sandbox","--disable-gpu","--disable-dev-shm-usage"]}' > /etc/mmdc.json \
 && rm -rf /root/.npm /tmp/*

# isomorphic-mermaid (experimental browserless renderer for evaluation)
RUN npm install -g isomorphic-mermaid \
 && rm -rf /root/.npm /tmp/*

# Allow require() of globally-installed npm modules from any working directory
ENV NODE_PATH=/usr/local/lib/node_modules

# Wrappers + entrypoint
COPY scripts/wrappers/    /opt/swgraph/wrappers/
COPY scripts/swgraph      /opt/swgraph/swgraph

RUN chmod +x /opt/swgraph/wrappers/* /opt/swgraph/swgraph \
 && ln -sf /opt/swgraph/wrappers/plantuml    /usr/local/bin/plantuml \
 && ln -sf /opt/swgraph/wrappers/ditaa       /usr/local/bin/ditaa \
 && ln -sf /opt/swgraph/wrappers/structurizr /usr/local/bin/structurizr \
 && ln -sf /opt/swgraph/wrappers/sketchviz   /usr/local/bin/sketchviz \
 && ln -sf /opt/swgraph/swgraph              /usr/local/bin/swgraph

# PlantUML !include search path — lets users do !include C4_Container.puml
# without absolute paths. plantuml honours -DPLANTUML_INCLUDE_PATH.
ENV PLANTUML_INCLUDE_PATH=/opt/plantuml-stdlib/c4:/opt/plantuml-stdlib/aws/dist:/opt/plantuml-stdlib/azure/dist:/opt/plantuml-stdlib/gcp/dist

# Pre-warm uv cache for asciidag so first run is fast (best effort; ignore failure)
RUN uvx --from asciidag python3 -c "import asciidag" 2>/dev/null || true

WORKDIR /input
VOLUME ["/input", "/output"]
EXPOSE 8080

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["swgraph", "--help"]
