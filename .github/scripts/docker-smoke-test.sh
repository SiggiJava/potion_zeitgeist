#!/usr/bin/env bash
# End-to-end test of the Docker package, run by CI (.github/workflows/ci.yml).
#
# Uses only docker-compose.yml, as another installation would, with a freshly
# built image. Creates an admin, then updates and recreates the containers and
# checks that the data, the generated keys and the login survive. Also checks
# the key guard, access by IP or host name, the HTTPS switch, and the backup
# and restore commands from the README.
#
# Usage: .github/scripts/docker-smoke-test.sh IMAGE
set -euo pipefail

IMAGE="${1:?usage: $0 IMAGE}"
REPO_IMAGE=ghcr.io/siggijava/potion_zeitgeist
BASE=http://localhost:4000
ADMIN_NAME="Zeit Prüferin"
ADMIN_EMAIL=admin@example.com
ADMIN_PASSWORD=smoke-test-password-123

SOURCE_DIR="$(pwd)"
WORK="$(mktemp -d)"
cp docker-compose.yml "$WORK/"
cd "$WORK"

dc() { docker compose "$@"; }

cleanup() {
  dc down -v --remove-orphans >/dev/null 2>&1 || true
  cd "$SOURCE_DIR"
  rm -rf "$WORK"
}
trap cleanup EXIT

step() { printf '\n=== %s\n' "$*"; }

fail() {
  echo "FAIL: $*" >&2
  dc ps -a >&2 || true
  dc logs --no-color --tail=150 >&2 || true
  exit 1
}

# Sets KEY=VALUE in .env (the file users edit next to docker-compose.yml).
set_env() {
  touch .env
  grep -v "^$1=" .env >.env.new || true
  echo "$1=$2" >>.env.new
  mv .env.new .env
}

up() {
  dc up -d --wait --wait-timeout 240 "$@" || fail "docker compose up $* did not get healthy"
}

app_container() { dc ps -q app; }

# Logs of the current app container. (Captured first: with pipefail, piping
# into `grep -q` can fail when grep stops reading early.)
app_logs() { dc logs --no-color app 2>&1 || true; }

app_logs_contain() { [[ "$(app_logs)" == *"$1"* ]]; }

# Reads a page from stdin and prints its CSRF token.
csrf_token() {
  local html
  html="$(cat)"
  if [[ $html =~ \<meta\ name=\"csrf-token\"\ content=\"([^\"]+)\" ]]; then
    echo "${BASH_REMATCH[1]}"
  fi
}

status_of() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

# Logs in as the admin and checks that the dashboard shows the admin's name,
# which is stored encrypted: this only works with the original VAULT_KEY.
login_and_check() {
  local jar token result page
  jar="$(mktemp)"
  token="$(curl -fsS -c "$jar" -b "$jar" "$BASE/login" | csrf_token)"
  [ -n "$token" ] || fail "no CSRF token on /login"

  result="$(curl -sS -c "$jar" -b "$jar" -o /dev/null -w '%{http_code} %{redirect_url}' \
    --data-urlencode "_csrf_token=$token" \
    --data-urlencode "user[email]=$ADMIN_EMAIL" \
    --data-urlencode "user[password]=$ADMIN_PASSWORD" \
    "$BASE/login")"
  [ "$result" = "302 $BASE/" ] || fail "login failed: $result"

  page="$(curl -fsS -b "$jar" "$BASE/")" || fail "dashboard not reachable after login"
  [[ $page == *"$ADMIN_NAME"* ]] || fail "dashboard does not show the admin's name"
  rm -f "$jar"
  echo "login ok, admin name readable"
}

# HTTP status of a LiveView websocket handshake sent with the given Origin.
websocket_status() {
  curl -s -o /dev/null -w '%{http_code}' --max-time 3 --http1.1 \
    -H "Connection: Upgrade" -H "Upgrade: websocket" \
    -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
    -H "Origin: $1" "$BASE/live/websocket?vsn=2.0.0" || true
}

step "Compose files are valid"
dc config -q
(cd "$SOURCE_DIR" && docker compose config -q)

step "First start of a new installation"
docker tag "$IMAGE" "$REPO_IMAGE:smoke1"
set_env APP_VERSION smoke1
up
app_logs_contain "New keys generated: SECRET_KEY_BASE VAULT_KEY" || fail "keys were not generated"
[ "$(dc exec -T app id -u)" = "1000" ] || fail "app does not run as user 1000"
[ "$(dc exec -T app stat -c '%a %U' /app/data/secrets.env)" = "600 app" ] || fail "secrets.env permissions"
dc cp app:/app/data/secrets.env ./secrets.before
grep -q '^VAULT_KEY=' secrets.before || fail "no VAULT_KEY in secrets.env"
[ "$(dc exec -T app sh -c 'echo $LANG')" = "C.UTF-8" ] || fail "LANG is not UTF-8"

step "Health check, setup page and assets"
[ "$(curl -fsS "$BASE/health")" = "ok" ] || fail "/health"
[ "$(docker inspect -f '{{.State.Health.Status}}' "$(app_container)")" = "healthy" ] || fail "container not healthy"
[ "$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' "$BASE/")" = "302 $BASE/setup" ] || fail "/ does not lead to /setup"
curl -fsS "$BASE/setup" >setup.html
assets="$(grep -oE '/assets/[^"?]+\.(css|js)' setup.html | sort -u || true)"
[ "$(echo "$assets" | grep -c .)" -ge 2 ] || fail "setup page links no CSS/JS: $assets"
for asset in $assets /fonts/inter/inter-latin-400-normal.woff2 /images/logo.svg; do
  [ "$(status_of "$BASE$asset")" = "200" ] || fail "asset $asset is not served"
done
echo "assets ok: $(echo $assets)"

step "Create the admin through /setup"
jar="$(mktemp)"
token="$(curl -fsS -c "$jar" -b "$jar" "$BASE/setup" | csrf_token)"
result="$(curl -sS -c "$jar" -b "$jar" -o /dev/null -w '%{http_code} %{redirect_url}' \
  --data-urlencode "_csrf_token=$token" \
  --data-urlencode "user[name]=$ADMIN_NAME" \
  --data-urlencode "user[email]=$ADMIN_EMAIL" \
  --data-urlencode "user[password]=$ADMIN_PASSWORD" \
  "$BASE/setup")"
[ "$result" = "302 $BASE/login" ] || fail "setup failed: $result"
login_and_check

step "Database time zone used by invoices"
dc exec -T db psql -U postgres -d potion_zeitgeist_prod -tAc "SELECT (now() AT TIME ZONE 'Europe/Berlin')::date" \
  || fail "Europe/Berlin unknown to the database"

step "Live pages: allowed and foreign origins"
[ "$(websocket_status "$BASE")" = "101" ] || fail "websocket from localhost refused"
[ "$(websocket_status http://127.0.0.1:4000)" = "101" ] || fail "websocket from 127.0.0.1 refused"
[ "$(websocket_status http://evil.example)" = "403" ] || fail "websocket from a foreign origin accepted"
[ "$(websocket_status http://192.168.77.7:4000)" = "403" ] || fail "unlisted host accepted"

step "Access by IP address in the local network (PHX_HOST, plain HTTP)"
[ "$(status_of -H 'Host: 192.168.77.7:4000' "$BASE/login")" = "200" ] || fail "plain HTTP by IP is redirected"
set_env PHX_HOST "localhost,192.168.77.7"
up
[ "$(websocket_status http://192.168.77.7:4000)" = "101" ] || fail "websocket from PHX_HOST address refused"
login_and_check

step "FORCE_SSL=true behind an HTTPS reverse proxy"
set_env FORCE_SSL true
up
[ "$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' -H 'Host: zeit.example.com' "$BASE/login")" = \
  "301 https://zeit.example.com/login" ] || fail "no redirect to HTTPS"
curl -fsS -o /dev/null -D headers.txt -H 'Host: zeit.example.com' -H 'X-Forwarded-Proto: https' "$BASE/login" \
  || fail "HTTPS request through the proxy failed"
grep -qi '^strict-transport-security:' headers.txt || fail "no HSTS header"
login_and_check
set_env FORCE_SSL false

step "Update to a new image keeps data and keys"
old_container="$(app_container)"
# The default builder sees the local images (a docker-container builder would not).
printf 'FROM %s\nLABEL smoke.update=2\n' "$REPO_IMAGE:smoke1" |
  docker buildx build --builder default --load -t "$REPO_IMAGE:smoke2" -
set_env APP_VERSION smoke2
up
[ "$(app_container)" != "$old_container" ] || fail "app container was not recreated"
[ "$(docker inspect -f '{{.Config.Image}}' "$(app_container)")" = "$REPO_IMAGE:smoke2" ] || fail "new image not used"
app_logs_contain "New keys generated" && fail "keys were generated again"
dc cp app:/app/data/secrets.env ./secrets.after
cmp -s secrets.before secrets.after || fail "secrets.env changed"
login_and_check

step "docker compose down and up again keeps data"
dc down
up
login_and_check

step "A different VAULT_KEY is refused and the data stays readable"
set_env VAULT_KEY "$(head -c 32 /dev/urandom | base64 -w 0)"
dc up -d app
for _ in $(seq 1 60); do
  app_logs_contain "VAULT_KEY does not match the data in the database" && break
  sleep 2
done
app_logs_contain "VAULT_KEY does not match the data in the database" || fail "wrong key not reported"
[ "$(status_of "$BASE/health")" != "200" ] || fail "app runs with a wrong key"
set_env VAULT_KEY ""
up
login_and_check

step "Backup, then restore into a new installation (README commands)"
dc exec -T db pg_dump -U postgres -Fc -f /tmp/backup.dump potion_zeitgeist_prod
dc cp db:/tmp/backup.dump ./backup.dump
dc cp app:/app/data/secrets.env ./secrets.env.backup
[ -s backup.dump ] || fail "empty backup"
dc down -v
[ -z "$(docker volume ls -q --filter name=potion_zeitgeist_)" ] || fail "volumes not removed by down -v"
# README: put the lines of the key backup into .env.
sed -i '/^SECRET_KEY_BASE=/d; /^VAULT_KEY=/d' .env
cat secrets.env.backup >>.env
up db
dc cp ./backup.dump db:/tmp/backup.dump
dc exec -T db pg_restore -U postgres -d potion_zeitgeist_prod --clean --if-exists /tmp/backup.dump
up
app_logs_contain "New keys generated" && fail "keys generated although .env has them"
login_and_check

step "All Docker checks passed"
