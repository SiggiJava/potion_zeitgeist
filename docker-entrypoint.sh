#!/bin/sh
# Start script of the Potion Zeitgeist Docker image.
#
# 1. Keys: SECRET_KEY_BASE and VAULT_KEY come from the environment (.env).
#    A key that is not set there is generated once and kept in
#    $DATA_DIR/secrets.env (a Docker volume), so restarts and updates of the
#    container keep using the same keys. config/runtime.exs reads that file.
# 2. Database: waits until it is reachable, refuses to start when VAULT_KEY
#    cannot read the data already stored, then runs pending migrations.
# 3. Starts the server.
#
# Any arguments are run as a command instead of the server, with the keys
# prepared, e.g.: docker compose run --rm app bin/potion_zeitgeist remote
set -eu

DATA_DIR="${DATA_DIR:-/app/data}"
SECRETS_FILE="$DATA_DIR/secrets.env"
RELEASE_BIN=/app/bin/potion_zeitgeist

log() {
  echo "[entrypoint] $*"
}

# Prints the value stored for $1 in the secrets file, or nothing.
stored_secret() {
  if [ -f "$SECRETS_FILE" ]; then
    sed -n "s/^$1=//p" "$SECRETS_FILE" | tail -n 1 | tr -d '\r'
  fi
}

# Makes sure the key named $1 exists: in the environment or in the secrets
# file. Otherwise generates $2 random bytes, Base64 encoded, into the file.
ensure_secret() {
  name="$1"
  bytes="$2"
  eval "value=\${$name:-}"
  value="$(printf '%s' "$value" | tr -d '[:space:]')"

  if [ -n "$value" ] || [ -n "$(stored_secret "$name")" ]; then
    return 0
  fi

  if ! touch "$SECRETS_FILE" 2>/dev/null; then
    echo "[entrypoint] ERROR: $name is not set and $SECRETS_FILE cannot be written." >&2
    echo "[entrypoint] Set $name in .env, or make $DATA_DIR writable for user id $(id -u)." >&2
    exit 1
  fi

  if [ ! -s "$SECRETS_FILE" ]; then
    {
      echo "# Potion Zeitgeist keys, generated on the first start of the container."
      echo "# Keep a copy of this file in a safe place. VAULT_KEY decrypts the names"
      echo "# and e-mail addresses in the database: without it they cannot be read."
    } >>"$SECRETS_FILE"
  fi

  printf '%s=%s\n' "$name" "$(head -c "$bytes" /dev/urandom | base64 -w 0)" >>"$SECRETS_FILE"
  GENERATED="$GENERATED $name"
}

umask 077
GENERATED=""
ensure_secret SECRET_KEY_BASE 64
ensure_secret VAULT_KEY 32

if [ -n "$GENERATED" ]; then
  log "New keys generated:${GENERATED}. They are saved in $SECRETS_FILE (app data volume)."
  log "Back up this file now, e.g.:  docker compose cp app:$SECRETS_FILE ./secrets.env.backup"
fi

# The Erlang cookie of a published image is the same for everyone who
# downloads it. Give every container its own, unless RELEASE_COOKIE is set.
if [ -z "${RELEASE_COOKIE:-}" ] && [ -w /app/releases/COOKIE ]; then
  head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' >/app/releases/COOKIE
fi

if [ "$#" -gt 0 ]; then
  exec "$@"
fi

log "Checking the database and running migrations..."
"$RELEASE_BIN" eval "PotionZeitgeist.Release.setup()"

log "Starting Potion Zeitgeist on port ${PORT:-4000}..."
exec "$RELEASE_BIN" start
