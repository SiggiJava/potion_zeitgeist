#!/bin/sh
set -e

echo "[entrypoint] Running database migrations..."
/app/bin/potion_zeitgeist eval "PotionZeitgeist.Release.migrate()"

echo "[entrypoint] Starting server..."
exec /app/bin/potion_zeitgeist start
