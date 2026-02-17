# syntax=docker/dockerfile:1

# ── Stage 1: Build ────────────────────────────────────────────
FROM rust:1.93-slim-trixie@sha256:9663b80a1621253d30b146454f903de48f0af925c967be48c84745537cd35d8b AS builder
WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# 1. Copy manifests to cache dependencies
COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo "fn main() {}" > src/main.rs
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    cargo build --release --locked
RUN rm -rf src

# 2. Copy source code
COPY . .
RUN touch src/main.rs
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    cargo build --release --locked && \
    strip target/release/zeroclaw

# ── Stage 2: Permissions & Config Prep ───────────────────────
FROM busybox:1.37@sha256:b3255e7dfbcd10cb367af0d409747d511aeb66dfac98cf30e97e87e4207dd76f AS permissions

RUN mkdir -p /zeroclaw-data/.zeroclaw /zeroclaw-data/workspace

# Minimal config — API_KEY and Telegram set via onboard or manual edit
RUN cat > /zeroclaw-data/.zeroclaw/config.toml << 'EOF'
workspace_dir = "/zeroclaw-data/workspace"
config_path = "/zeroclaw-data/.zeroclaw/config.toml"
api_key = ""
default_provider = "openrouter"
default_model = "anthropic/claude-sonnet-4-20250514"
default_temperature = 0.7

[memory]
backend = "sqlite"
auto_save = true
embedding_provider = "noop"

[gateway]
port = 3000
host = "127.0.0.1"
allow_public_bind = false

[autonomy]
level = "supervised"
workspace_only = true

[runtime]
kind = "native"

[tunnel]
provider = "none"

[secrets]
encrypt = false
EOF

RUN chown -R 65534:65534 /zeroclaw-data

# ── Stage 3: Runtime (Debian slim — with shell for Coolify terminal) ──
FROM debian:trixie-slim@sha256:f6e2cfac5cf956ea044b4bd75e6397b4372ad88fe00908045e9a0d21712ae3ba

# Minimal runtime deps only (no dev tools bloat)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=permissions /zeroclaw-data /zeroclaw-data
COPY --from=builder /app/target/release/zeroclaw /usr/local/bin/zeroclaw

ENV ZEROCLAW_WORKSPACE=/zeroclaw-data/workspace
ENV HOME=/zeroclaw-data
ENV PROVIDER="openrouter"

WORKDIR /zeroclaw-data
USER 65534:65534

# No EXPOSE — no ports needed for Telegram-only setup
# Using daemon mode: runs Telegram polling + autonomy loop
ENTRYPOINT ["zeroclaw"]
CMD ["daemon"]
