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

#### Updating a local install

After pulling new code, stop the server and run:

```bash
mix deps.get
mix ecto.migrate
mix assets.build
mix phx.server
```

`mix assets.build` rebuilds the stylesheet and JavaScript, so new pages get their icons and styles even when the asset watchers of `mix phx.server` did not pick up the change. Reload the page with Ctrl+F5 afterwards.

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
| `PHX_HOST` | Host names people use to open the app, comma-separated, e.g. `example.com` (default `localhost`) |
| `FORCE_SSL` | `true` to redirect HTTP to HTTPS and send HSTS (behind a reverse proxy that sets `X-Forwarded-Proto`) |

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

The Docker package brings everything the app needs: the app itself and its own PostgreSQL 16 database, started together by `docker-compose.yml`. You only need [Docker](https://docs.docker.com/get-docker/) (Docker Desktop on Windows and macOS), no Elixir, Node.js or PostgreSQL.

- **Your data survives updates.** It lives in two named Docker volumes, not in the containers: `potion_zeitgeist_postgres_data` (the database) and `potion_zeitgeist_app_data` (the keys). Updating, restarting or recreating the containers never touches them.
- **Database changes are applied automatically.** On every start the app waits for the database, checks the encryption key and runs any pending migrations. Migrations extend the database; they don't reset it.
- **Keys are generated on the first start** and kept in the app's volume, unless you set them yourself in `.env`.
- Images are published for Intel/AMD and ARM (including Apple Silicon) as [`ghcr.io/siggijava/potion_zeitgeist`](https://github.com/SiggiJava/potion_zeitgeist/pkgs/container/potion_zeitgeist).

### Install

1. Create a folder, e.g. `potion_zeitgeist`, and save [`docker-compose.yml`](https://raw.githubusercontent.com/SiggiJava/potion_zeitgeist/main/docker-compose.yml) in it. Optionally save [`.env.example`](https://raw.githubusercontent.com/SiggiJava/potion_zeitgeist/main/.env.example) there as `.env` to change settings (see below).
2. Open a terminal in that folder and start the app:

   ```bash
   docker compose up -d
   ```

3. Open [http://localhost:4000](http://localhost:4000). On the first visit you are taken to `/setup`, where you create the administrator account.
4. **Back up the keys right away** and keep the copy somewhere safe (not only on this computer):

   ```bash
   docker compose cp app:/app/data/secrets.env ./secrets.env.backup
   ```

   `VAULT_KEY` in that file encrypts the names and e-mail addresses in the database. A database backup is useless without it.

### Settings

Settings go into a file named `.env` next to `docker-compose.yml` (all optional, see `.env.example`). After changing it, run `docker compose up -d` again.

| Variable | Default | Meaning |
|---|---|---|
| `PHX_HOST` | `localhost` | Host names or IP addresses used to open the app, separated by commas, e.g. `zeit.example.com,192.168.1.20`. The live pages (clocking in, dialogs, buttons) only work from these hosts and from localhost. |
| `APP_PORT` | `4000` | Port on the computer running Docker. |
| `FORCE_SSL` | `false` | `true` when the app is served over HTTPS by a reverse proxy: plain HTTP is then redirected to HTTPS. |
| `APP_VERSION` | `latest` | Image version: `latest`, a release such as `1.2.0`, or `sha-<commit>`. |
| `SECRET_KEY_BASE`, `VAULT_KEY` | generated | Set them only if you want to manage the keys yourself. Never change `VAULT_KEY` of an existing installation. |
| `POSTGRES_PASSWORD` | `postgres` | Database password. Only used when the database volume is created for the first time; letters and digits only. The database is not reachable from outside Docker. |

**Using the app from other computers in your network:** open it with the address of the computer running Docker, e.g. `http://192.168.1.20:4000`, and put that address into `PHX_HOST` (e.g. `PHX_HOST=192.168.1.20`). Without it the pages load, but the live parts don't react.

**HTTPS:** put a reverse proxy (e.g. Caddy, Traefik, nginx) in front of port 4000, set `PHX_HOST=your.domain` and `FORCE_SSL=true`. The proxy must send `X-Forwarded-Proto` and pass WebSocket connections on `/live`.

### Update

```bash
docker compose pull
docker compose up -d
```

`pull` downloads the new image, `up -d` replaces the app container and leaves the database container and both volumes alone. The new version applies its database migrations by itself when it starts. Watch it with `docker compose logs -f app`.

Making a backup first (see below) is a good habit. To stay on a version, set `APP_VERSION` in `.env`.

### What keeps and what deletes your data

| Command | Data |
|---|---|
| `docker compose up -d`, `restart`, `stop`, `down`, `pull` | kept |
| Moving or renaming the folder with `docker-compose.yml` | kept (the volume names are fixed) |
| `docker compose down -v`, `docker volume rm …`, `docker system prune --volumes` | **deleted** |

The app keeps running with PostgreSQL 16. Don't change `postgres:16-alpine` in `docker-compose.yml` to a newer major version: it can't open the existing database. A major upgrade is a backup, a new volume and a restore.

### Backup and restore

Backup (database dump plus keys), written to the current folder:

```bash
docker compose exec -T db pg_dump -U postgres -Fc -f /tmp/backup.dump potion_zeitgeist_prod
docker compose cp db:/tmp/backup.dump ./backup.dump
docker compose cp app:/app/data/secrets.env ./secrets.env.backup
```

Restore, e.g. on a new computer (with `docker-compose.yml`, `backup.dump` and `secrets.env.backup` in the folder):

```bash
# 1. The keys: add the lines of the key backup to .env
cat secrets.env.backup >> .env
# 2. Start only the database and load the dump into it
docker compose up -d --wait db
docker compose cp ./backup.dump db:/tmp/backup.dump
docker compose exec -T db pg_restore -U postgres -d potion_zeitgeist_prod --clean --if-exists /tmp/backup.dump
# 3. Start the app
docker compose up -d
```

On Windows, use `type secrets.env.backup >> .env` in the Command Prompt or copy the lines with an editor. CI runs these exact commands on every change (`.github/scripts/docker-smoke-test.sh`).

### Build the image from the source code

In a clone of this repository, Docker Compose also reads `docker-compose.override.yml`, which builds the app image from the source instead of downloading it:

```bash
git pull
docker compose up -d --build
```

The database and volumes are the same as with the published image. The build compiles the stylesheet and JavaScript into the image, so no separate asset rebuild is needed.

### Coming from the earlier Docker setup

- Keys you already have in `.env` (`SECRET_KEY_BASE`, `VAULT_KEY`) keep being used. Keep that `.env` file.
- The database volume is now always called `potion_zeitgeist_postgres_data`. That is the name the earlier setup used when the folder was called `potion_zeitgeist`. If your folder had another name, `docker volume ls` shows the old volume as `<folder>_postgres_data`; move the data over with a backup and restore, or set `name:` under `volumes: postgres_data:` in `docker-compose.yml` to the old name.

### Troubleshooting

- **The setup page appears although you had data:** the app is looking at an empty database volume, e.g. after `docker compose down -v` or with another volume name. Check `docker volume ls`.
- **Buttons or live pages don't react when the app is opened by IP or host name:** add that address to `PHX_HOST`.
- **The app does not start and the log says "VAULT_KEY does not match the data in the database":** the key is not the one the data was encrypted with. Put the original key back (from `secrets.env.backup` into `.env`). The data has not been changed.
- See what the app does: `docker compose logs -f app`.

### Manual migration and rollback

Migrations run automatically on start. To run them by hand, or to roll back to a version:

```bash
docker compose exec app bin/potion_zeitgeist eval "PotionZeitgeist.Release.migrate()"
docker compose exec app bin/potion_zeitgeist eval "PotionZeitgeist.Release.rollback(PotionZeitgeist.Repo, <version>)"
```

### Publishing images (maintainers)

The CI workflow builds and tests the image for both platforms on every pull request. After a push to `main` it publishes `latest` and `sha-<commit>`, after a tag `v1.2.3` also `1.2.3`, `1.2` and `1`. A copy on Docker Hub is published as well when the repository variable `DOCKERHUB_USERNAME` and the secret `DOCKERHUB_TOKEN` are set.

---

## License

[MIT](LICENSE) — Copyright (c) 2026 Michael Piegza
