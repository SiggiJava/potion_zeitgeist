# Potion Zeitgeist

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A time clocking application for small and medium-sized businesses. Built with Elixir, Phoenix LiveView, and PostgreSQL.

## Features

- Clock in / clock out with a real-time live timer
- Personal time entry history — view, edit, delete, and export
- CSV export for any user's entries
- Role-based access: `admin` and `user`
- First-run setup wizard — no manual seeding required
- Field-level AES-256-GCM encryption for personal data (GDPR-compliant)

---

## Requirements

- Elixir 1.15+
- Erlang/OTP 25+
- PostgreSQL 14+
- Node.js (for asset bundling via esbuild — installed automatically by Mix)

---

## Installation

### 1. Clone the repository

```bash
git clone <your-repo-url>
cd potion_zeitgeist
```

### 2. Install dependencies

```bash
mix deps.get
```

### 3. Configure the database

Edit `config/dev.exs` and adjust the database credentials if needed:

```elixir
config :potion_zeitgeist, PotionZeitgeist.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "potion_zeitgeist_dev"
```

### 4. Set up the database and assets

```bash
mix setup
```

This runs `ecto.create`, `ecto.migrate`, and builds the frontend assets in one step.

### 5. Start the server

```bash
mix phx.server
```

The app is now running at [http://localhost:4000](http://localhost:4000).

### 6. Create the administrator account

On first launch, visiting any page will redirect you to **`/setup`**, where you create the initial administrator account. This page is only shown once — it becomes inaccessible as soon as an admin exists.

---

## Development

Start an interactive server session:

```bash
iex -S mix phx.server
```

Reset the database (drops and recreates everything):

```bash
mix ecto.reset
```

---

## Production Deployment

### Required environment variables

| Variable | Description |
|---|---|
| `DATABASE_URL` | PostgreSQL connection string, e.g. `ecto://user:pass@host/db` |
| `SECRET_KEY_BASE` | Phoenix secret key — generate with `mix phx.gen.secret` |
| `VAULT_KEY` | 32-byte AES encryption key encoded as Base64 (see below) |
| `PHX_HOST` | Public hostname, e.g. `example.com` |

### Generate a vault key

Run this once and store the result securely (e.g. in your secrets manager):

```bash
iex -e ':crypto.strong_rand_bytes(32) |> Base.encode64() |> IO.puts()'
```

Set the output as `VAULT_KEY` in your production environment. **Never use the development key in production.**

> **Important:** The `VAULT_KEY` encrypts all personal data in the database. Losing this key makes encrypted data permanently unrecoverable. Back it up securely.

### Build and migrate

```bash
PHX_SERVER=true mix phx.server
```

Or using a release:

```bash
mix release
DATABASE_URL=... SECRET_KEY_BASE=... VAULT_KEY=... PHX_HOST=... bin/potion_zeitgeist start
```

See the [Phoenix deployment guide](https://hexdocs.pm/phoenix/deployment.html) for full instructions including reverse proxy setup.

---

## Docker

The application ships with a `Dockerfile` and `docker-compose.yml`. The database runs in a separate container with a named Docker volume so that **upgrading the application never touches the database data**.

Pre-built images are published to Docker Hub: [`siggijava/potion_zeitgeist`](https://hub.docker.com/r/siggijava/potion_zeitgeist)

---

### Option A — Pull from Docker Hub (recommended)

No Elixir or Node.js toolchain required. Use the published image directly.

#### 1. Create your `.env` file

```bash
cp .env.example .env
```

Fill in the three required values (`SECRET_KEY_BASE`, `VAULT_KEY`, `PHX_HOST`). If you don't have an Elixir install to generate them, use these one-liners via Docker:

```bash
# Generate SECRET_KEY_BASE
docker run --rm hexpm/elixir:1.16-erlang-26-alpine mix phx.gen.secret

# Generate VAULT_KEY
docker run --rm hexpm/elixir:1.16-erlang-26-alpine \
  sh -c "iex -e ':crypto.strong_rand_bytes(32) |> Base.encode64() |> IO.puts()'"
```

#### 2. Start with the pre-built image

Replace the `build: .` line in `docker-compose.yml` with the Hub image, then start:

```yaml
app:
  image: siggijava/potion_zeitgeist:latest
  # (remove the "build: ." line)
```

```bash
docker compose up
```

#### 3. Updating to a newer release

```bash
docker compose pull app
docker compose up app
```

The `db` container and its volume are never touched during an update.

---

### Option B — Build from source

#### 1. Create your `.env` file

```bash
cp .env.example .env
```

Fill in the three required values:

```bash
# Generate secret key base
mix phx.gen.secret

# Generate vault key
iex -e ':crypto.strong_rand_bytes(32) |> Base.encode64() |> IO.puts()'
```

#### 2. Start both containers

```bash
docker compose up --build
```

The app container waits for PostgreSQL to be healthy, then runs all pending migrations automatically before starting the server.

#### Updating the application

Rebuild and restart only the `app` container. The `db` container and its volume are untouched:

```bash
docker compose up --build app
```

---

### First-run admin setup

Visit [http://localhost:4000/setup](http://localhost:4000/setup) to create the initial administrator account.

### Manual migration (if needed)

```bash
docker compose exec app ./bin/potion_zeitgeist eval "PotionZeitgeist.Release.migrate()"
```

### Rollback a migration

```bash
docker compose exec app ./bin/potion_zeitgeist eval "PotionZeitgeist.Release.rollback(PotionZeitgeist.Repo, <version>)"
```

---

## License

[MIT](LICENSE) — Copyright (c) 2026 Michael Piegza
