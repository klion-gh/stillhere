#!/usr/bin/env bash
# Turns push notifications on for an already-installed node.
#
# Both Firebase files come from a browser, so they land on your own machine
# and have to be copied over. This script checks they're in place, valid, and
# restarts the backend. Safe to run repeatedly.
set -euo pipefail

INSTALL_DIR="${STILLHERE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
DOCKER_DIR="$INSTALL_DIR/docker"
SECRETS_DIR="$DOCKER_DIR/secrets"

log()  { printf '\n\033[1;36m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$1" >&2; }
die()  { printf '\033[1;31mError:\033[0m %s\n' "$1" >&2; exit 1; }

[ -f "$DOCKER_DIR/.env" ] || die "Не найден $DOCKER_DIR/.env — сначала установите узел (install.sh)."

mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

missing=0
for f in google-services.json firebase-service-account.json; do
  if [ ! -f "$SECRETS_DIR/$f" ]; then
    warn "Не найден $SECRETS_DIR/$f"
    missing=1
  elif ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$SECRETS_DIR/$f" 2>/dev/null; then
    die "$SECRETS_DIR/$f не читается как JSON — возможно, файл скопировался не полностью."
  fi
done

if [ "$missing" -ne 0 ]; then
  host="$(grep -E '^NODE_HOST=' "$DOCKER_DIR/.env" | cut -d= -f2- || echo '<адрес-сервера>')"
  cat <<EOF

Нужны два файла из вашего проекта Firebase (console.firebase.google.com):

  google-services.json          — Настройки проекта -> Ваши приложения -> Android
                                  (package name должен быть com.stillhere.stillhere)
  firebase-service-account.json — Настройки проекта -> Сервисные аккаунты
                                  -> Создать закрытый ключ

Скопируйте их НА СВОЁМ КОМПЬЮТЕРЕ:

  scp google-services.json root@$host:$SECRETS_DIR/
  scp <ваш-ключ>.json root@$host:$SECRETS_DIR/firebase-service-account.json

Затем запустите этот скрипт снова.
EOF
  exit 1
fi

chmod 600 "$SECRETS_DIR"/*.json

# The installer writes these, but a node set up before push existed won't have
# them.
for line in \
  "FIREBASE_SERVICE_ACCOUNT_FILE=/run/secrets/firebase-service-account.json" \
  "FIREBASE_CLIENT_CONFIG_FILE=/run/secrets/google-services.json" \
  "FIREBASE_ANDROID_PACKAGE=com.stillhere.stillhere"; do
  key="${line%%=*}"
  grep -q "^$key=" "$DOCKER_DIR/.env" || echo "$line" >> "$DOCKER_DIR/.env"
done

log "Перезапускаю backend..."
(cd "$DOCKER_DIR" && docker compose up -d --build backend)

log "Проверяю..."
sleep 6
if (cd "$DOCKER_DIR" && docker compose logs backend --tail=40 2>&1) | grep -q "push: firebase initialised"; then
  echo "Push включён — звонки и сообщения будут доходить в фоне."
else
  warn "В логах нет 'push: firebase initialised'. Посмотрите:"
  echo "  cd $DOCKER_DIR && docker compose logs backend --tail=40"
  exit 1
fi
