# syntax=docker/dockerfile:1

FROM rust:1.93-slim-trixie@sha256:9663b80a1621253d30b146454f903de48f0af925c967be48c84745537cd35d8b AS builder
WORKDIR /app

RUN apt-get update && apt-get install -y \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo "fn main() {}" > src/main.rs
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    cargo build --release --locked
RUN rm -rf src

COPY . .
RUN touch src/main.rs
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    cargo build --release --locked && \
    strip target/release/zeroclaw

FROM busybox:1.37@sha256:b3255e7dfbcd10cb367af0d409747d511aeb66dfac98cf30e97e87e4207dd76f AS permissions

RUN mkdir -p /zeroclaw-data/.zeroclaw /zeroclaw-data/workspace

RUN cat > /zeroclaw-data/.zeroclaw/config.toml << 'EOF'
workspace_dir = "/zeroclaw-data/workspace"
config_path = "/zeroclaw-data/.zeroclaw/config.toml"
api_key = ""
default_provider = "openrouter"
default_model = "anthropic/claude-sonnet-4-20250514"
default_temperature = 0.7

[gateway]
port = 7040
host = "[::]"
allow_public_bind = false
EOF

RUN chown -R 65534:65534 /zeroclaw-data

FROM debian:trixie-slim@sha256:f6e2cfac5cf956ea044b4bd75e6397b4372ad88fe00908045e9a0d21712ae3ba

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=permissions /zeroclaw-data /zeroclaw-data
COPY --from=builder /app/target/release/zeroclaw /usr/local/bin/zeroclaw

ENV ZEROCLAW_WORKSPACE=/zeroclaw-data/workspace
ENV HOME=/zeroclaw-data
ENV PROVIDER="openrouter"
ENV ZEROCLAW_GATEWAY_PORT=7040

WORKDIR /zeroclaw-data
USER 65534:65534


ENTRYPOINT ["zeroclaw"]
CMD ["gateway", "--host", "[::]"]
