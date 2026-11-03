# syntax=docker/dockerfile:1

# Potion Zeitgeist as a Docker image: a compiled Elixir release on Debian.
#
# The build and runtime stages use the same Debian snapshot, so the Erlang
# runtime inside the release finds exactly the system libraries it was built
# against. Elixir and Erlang/OTP match the versions CI tests with
# (.github/workflows/ci.yml). Find newer tags on
# https://hub.docker.com/r/hexpm/elixir/tags?name=1.18.4-erlang-27.3.4
# and keep DEBIAN_VERSION identical to the suffix of the builder tag.
ARG ELIXIR_VERSION=1.18.4
ARG OTP_VERSION=27.3.4.16
ARG DEBIAN_VERSION=bookworm-20260824-slim

ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="docker.io/library/debian:${DEBIAN_VERSION}"

# ---- Build stage ----
FROM ${BUILDER_IMAGE} AS build

# git fetches the heroicons dependency, build-essential compiles bcrypt.
RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force \
  && mix local.rebar --force

ENV MIX_ENV=prod

# Dependencies first, so they stay cached while only the app code changes.
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Compile-time config before the dependencies, so a change to it recompiles them.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# Downloads the tailwind and esbuild binaries for this platform.
RUN mix assets.setup

COPY priv priv
COPY lib lib
RUN mix compile

# Stylesheet and JavaScript are built into the image, so every update ships
# matching assets (no separate asset rebuild needed after an update).
COPY assets assets
RUN mix assets.deploy

# Changes to config/runtime.exs don't require recompiling the code.
COPY config/runtime.exs config/
RUN mix release

# ---- Runtime stage ----
FROM ${RUNNER_IMAGE} AS runtime

# curl is used by the health check below.
RUN apt-get update \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 ca-certificates curl \
  && rm -rf /var/lib/apt/lists/*

# UTF-8 everywhere, so names and texts with umlauts are handled correctly.
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    MIX_ENV=prod \
    PHX_SERVER=true \
    PORT=4000 \
    FORCE_SSL=false \
    DATA_DIR=/app/data

# Run as an unprivileged user. /app/data holds the keys generated on first
# start; docker-compose.yml mounts a named volume there. When Docker creates
# that volume it copies the owner set here, so the app can write to it.
RUN groupadd --gid 1000 app \
  && useradd --uid 1000 --gid app --home-dir /app --no-create-home --shell /usr/sbin/nologin app \
  && mkdir -p /app/data \
  && chown app:app /app /app/data

WORKDIR /app

COPY --from=build --chown=app:app /app/_build/prod/rel/potion_zeitgeist ./

# The start script must have Unix line endings even when the repository was
# checked out on Windows; strip any carriage returns.
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN sed -i 's/\r$//' /usr/local/bin/docker-entrypoint.sh \
  && chmod 755 /usr/local/bin/docker-entrypoint.sh

USER app

EXPOSE 4000

# /health answers 200 when the app runs and reaches its database.
HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --start-interval=3s --retries=3 \
  CMD curl -fsS -o /dev/null "http://127.0.0.1:${PORT:-4000}/health" || exit 1

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
