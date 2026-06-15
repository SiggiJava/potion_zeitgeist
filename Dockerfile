# ---- Build Stage ----
FROM elixir:1.19-alpine AS build

RUN apk add --no-cache build-base git curl

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

# Install and compile dependencies first for layer caching
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mix deps.compile

# Copy config before compiling application code
COPY config config/

# Copy assets and priv (migrations included in priv/)
COPY priv priv/
COPY assets assets/

# Download tailwind and esbuild platform binaries
RUN mix assets.setup

# Copy application source and compile
COPY lib lib/
RUN mix compile

# Build and digest production assets
RUN mix assets.deploy

# Build the release
RUN mix release

# ---- Runtime Stage ----
FROM alpine:3.21 AS runtime

RUN apk add --no-cache libstdc++ openssl ncurses-libs ca-certificates

WORKDIR /app

# Run as non-root
RUN addgroup -g 1000 app && adduser -u 1000 -G app -s /bin/sh -D app

COPY --from=build --chown=app:app /app/_build/prod/rel/potion_zeitgeist ./
COPY --chown=app:app docker-entrypoint.sh ./
RUN chmod +x docker-entrypoint.sh

USER app

# PHX_SERVER=true tells runtime.exs to start the HTTP listener
ENV PHX_SERVER=true

EXPOSE 4000

ENTRYPOINT ["./docker-entrypoint.sh"]
