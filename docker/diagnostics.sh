#!/usr/bin/env bash
# Turns the diagnostic trail on and off, and reads it back.
#
#   ./diagnostics.sh on        начать запись действий
#   ./diagnostics.sh off       прекратить
#   ./diagnostics.sh status    состояние и число событий
#   ./diagnostics.sh tail 100  последние 100 событий
#   ./diagnostics.sh export > trail.json
#
# Everything happens inside the backend container, against the node's own
# database — nothing is exposed on the network. The running server picks the
# change up within about 15 seconds; no restart, no dropped calls.
set -euo pipefail

cd "$(dirname "$0")"

if ! docker compose ps --status running backend | grep -q backend; then
  echo "Контейнер backend не запущен. Сначала: docker compose up -d" >&2
  exit 1
fi

exec docker compose exec -T backend node dist/diagnostics_cli.js "$@"
