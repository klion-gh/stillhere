#!/usr/bin/env bash
# StillHere node installer.
#
#   curl -fsSL https://raw.githubusercontent.com/klion-gh/stillhere/main/install.sh | sudo bash
#
# Turns a fresh Debian/Ubuntu server into a StillHere node: installs Docker
# if needed, generates all secrets, sets up TLS (self-signed by IP, or your
# domain's existing certificate, or a fresh Let's Encrypt one via Caddy),
# and brings the whole stack up. Safe to re-run — it refuses to touch an
# existing installation instead of silently overwriting secrets.
set -euo pipefail

REPO_URL="${STILLHERE_REPO_URL:-https://github.com/klion-gh/stillhere.git}"
RAW_URL="${STILLHERE_RAW_URL:-https://raw.githubusercontent.com/klion-gh/stillhere/main/install.sh}"
INSTALL_DIR="${STILLHERE_DIR:-$HOME/stillhere}"

log()  { printf '\n\033[1;36m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$1" >&2; }
die()  { printf '\033[1;31mError:\033[0m %s\n' "$1" >&2; exit 1; }

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    die "Запустите установщик от root (например: curl ... | sudo bash)."
  fi
}

check_os() {
  [ -r /etc/os-release ] || die "Не удалось определить дистрибутив (/etc/os-release не найден)."
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}:${ID_LIKE:-}" in
    debian:*|ubuntu:*|*:*debian*)
      ;;
    *)
      die "Поддерживаются только Debian/Ubuntu в первой версии установщика (обнаружено: ${PRETTY_NAME:-unknown})."
      ;;
  esac
}

install_docker() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    log "Docker уже установлен, пропускаю."
    return
  fi
  log "Устанавливаю Docker (get.docker.com)..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
}

fetch_repo() {
  log "Получаю код StillHere в $INSTALL_DIR..."
  if [ -d "$INSTALL_DIR/.git" ]; then
    # docker/Caddyfile used to be tracked and is now generated per node. Git
    # won't fast-forward past the commit that drops it while the local copy
    # differs, so put the tracked version back first — write_config rewrites
    # the real one further down anyway.
    if git -C "$INSTALL_DIR" ls-files --error-unmatch docker/Caddyfile >/dev/null 2>&1; then
      git -C "$INSTALL_DIR" checkout -- docker/Caddyfile
    fi
    git -C "$INSTALL_DIR" pull --ff-only
  else
    git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
  fi
}

# Every interactive read goes through the terminal explicitly.
#
# The documented entry point is `curl ... | sudo bash`, which makes the
# script itself stdin. A plain `read` would then consume the remaining
# script text instead of waiting for the user — silently returning empty,
# and sending the password loop below spinning forever.
require_tty() {
  # /dev/tty passes a -r test even with no controlling terminal — the device
  # node exists, opening it is what fails. Actually try to open it.
  if ! { : < /dev/tty; } 2>/dev/null; then
    die "Нужен терминал для ввода. Скачайте установщик и запустите его отдельно:
  curl -fsSL $RAW_URL -o install.sh && sudo bash install.sh
Либо задайте всё переменными окружения (STILLHERE_NODE_PASSWORD, STILLHERE_DOMAIN, ...)."
  fi
}

# Prompts for a value, honoring an env var override for non-interactive runs.
prompt() {
  local var_name="$1" prompt_text="$2" default_value="${3:-}"
  # Test whether the var is SET at all (even to an empty string), not just
  # non-empty — STILLHERE_DOMAIN="" must be able to mean "skip the prompt,
  # no domain" for non-interactive runs.
  if [ -n "${!var_name+x}" ]; then
    printf '%s\n' "${!var_name}"
    return
  fi
  require_tty
  local reply
  read -rp "$prompt_text" reply < /dev/tty
  printf '%s\n' "${reply:-$default_value}"
}

confirm() {
  local var_name="$1" prompt_text="$2"
  if [ -n "${!var_name+x}" ]; then
    [ "${!var_name}" = "yes" ] || [ "${!var_name}" = "y" ]
    return
  fi
  require_tty
  local reply
  read -rp "$prompt_text" reply < /dev/tty
  [[ "$reply" =~ ^[yYдД] ]]
}

prompt_node_password() {
  local env_value="${STILLHERE_NODE_PASSWORD:-}"
  if [ -n "$env_value" ]; then
    printf '%s\n' "$env_value"
    return
  fi
  require_tty
  local pass1 pass2
  while true; do
    read -rsp "Пароль узла (минимум 8 символов, его будут вводить друзья в приложении): " pass1 < /dev/tty
    echo >&2
    if [ "${#pass1}" -lt 8 ]; then
      warn "Слишком короткий, минимум 8 символов."
      continue
    fi
    read -rsp "Повторите пароль: " pass2 < /dev/tty
    echo >&2
    if [ "$pass1" != "$pass2" ]; then
      warn "Пароли не совпали, попробуйте ещё раз."
      continue
    fi
    printf '%s\n' "$pass1"
    return
  done
}

# Optional Firebase setup.
#
# Both files come from the Firebase console in a browser, so they land on the
# operator's own machine — there's nothing to download here. The practical
# move is to tell them exactly what to copy and wait, rather than trying to
# fetch anything ourselves. Skipping is fine: the node runs without push and
# enable-push.sh turns it on later.
setup_push() {
  local certs_dir="$1" node_host="$2"
  local secrets_dir="$INSTALL_DIR/docker/secrets"
  mkdir -p "$secrets_dir"
  chmod 700 "$secrets_dir"

  echo
  log "Push-уведомления (необязательно)"
  cat <<'EOF'
Без них звонки и сообщения на Android доходят, только пока приложение открыто.
Чтобы включить, нужен свой проект Firebase — это бесплатно и занимает пару минут.
EOF

  if ! confirm STILLHERE_SETUP_PUSH "Настроить сейчас? [y/N]: "; then
    echo "Пропускаю. Включить позже: $INSTALL_DIR/enable-push.sh"
    return
  fi

  cat <<EOF

1. Откройте https://console.firebase.google.com и создайте проект.
2. Добавьте в него Android-приложение с package name:
     com.stillhere.stillhere
   (именно такой — иначе готовый APK не сможет работать с вашим проектом)
   Скачайте google-services.json.
3. Настройки проекта -> Сервисные аккаунты -> Создать закрытый ключ.

Теперь скопируйте оба файла сюда — выполните НА СВОЁМ КОМПЬЮТЕРЕ:

  scp google-services.json root@$node_host:$secrets_dir/
  scp <ваш-ключ>.json root@$node_host:$secrets_dir/firebase-service-account.json

EOF

  require_tty
  local reply
  while true; do
    read -rp "Когда файлы будут на месте, нажмите Enter (или 's' чтобы пропустить): " reply < /dev/tty
    if [[ "$reply" =~ ^[sSпП] ]]; then
      echo "Пропускаю. Включить позже: $INSTALL_DIR/enable-push.sh"
      return
    fi
    if validate_push_files "$secrets_dir"; then
      log "Push настроен."
      return
    fi
    warn "Проверьте пути и попробуйте ещё раз, либо нажмите 's' чтобы пропустить."
  done
}

# Both files must be present and parse as JSON before we claim push works.
validate_push_files() {
  local dir="$1"
  local ok=0
  if [ ! -f "$dir/google-services.json" ]; then
    warn "Не найден $dir/google-services.json"
    ok=1
  elif ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$dir/google-services.json" 2>/dev/null; then
    warn "google-services.json не читается как JSON"
    ok=1
  fi
  if [ ! -f "$dir/firebase-service-account.json" ]; then
    warn "Не найден $dir/firebase-service-account.json"
    ok=1
  elif ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$dir/firebase-service-account.json" 2>/dev/null; then
    warn "firebase-service-account.json не читается как JSON"
    ok=1
  fi
  [ "$ok" -eq 0 ] || return 1
  chmod 600 "$dir"/*.json
  return 0
}

detect_public_ip() {
  local ip
  ip="$(curl -fsSL -4 https://ifconfig.me 2>/dev/null || true)"
  if [ -z "$ip" ]; then
    ip="$(curl -fsSL https://api.ipify.org 2>/dev/null || true)"
  fi
  printf '%s\n' "$ip"
}

main() {
  require_root
  check_os
  install_docker
  fetch_repo

  local docker_dir="$INSTALL_DIR/docker"
  local certs_dir="$docker_dir/certs"
  mkdir -p "$certs_dir"

  if [ -f "$docker_dir/.env" ]; then
    die "$docker_dir/.env уже существует — похоже, узел уже установлен. Удалите файл вручную, если хотите переустановить с нуля (это сотрёт текущие секреты)."
  fi

  log "Настройка узла"
  local node_password domain node_host
  local acme_email=""
  node_password="$(prompt_node_password)"
  domain="$(prompt STILLHERE_DOMAIN "Домен, указывающий на этот сервер (Enter, если нет — подключение будет по IP): ")"

  if [ -n "$domain" ]; then
    node_host="$domain"
    acme_email="$(prompt STILLHERE_ACME_EMAIL "Email для Let's Encrypt (нужен, если сертификата для домена ещё нет): ")"
  else
    log "Определяю публичный IP..."
    local detected_ip
    detected_ip="$(detect_public_ip)"
    if [ -n "$detected_ip" ]; then
      node_host="$(prompt STILLHERE_NODE_HOST "Публичный IP [$detected_ip], Enter чтобы принять: " "$detected_ip")"
    else
      warn "Не удалось определить IP автоматически."
      node_host="$(prompt STILLHERE_NODE_HOST "Введите публичный IP этого сервера вручную: ")"
    fi
    [ -n "$node_host" ] || die "Публичный адрес узла обязателен."
  fi

  log "Генерирую секреты..."
  local jwt_access jwt_refresh node_token_secret turn_secret postgres_password
  jwt_access="$(openssl rand -hex 32)"
  jwt_refresh="$(openssl rand -hex 32)"
  node_token_secret="$(openssl rand -hex 32)"
  turn_secret="$(openssl rand -hex 32)"
  postgres_password="$(openssl rand -hex 32)"

  local cert_fingerprint=""

  if [ -z "$domain" ]; then
    log "Домена нет — выпускаю self-signed сертификат для $node_host..."
    openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
      -keyout "$certs_dir/selfsigned.key" -out "$certs_dir/selfsigned.crt" \
      -subj "/CN=$node_host" \
      -addext "subjectAltName=IP:$node_host" >/dev/null 2>&1
    cert_fingerprint="$(openssl x509 -in "$certs_dir/selfsigned.crt" -noout -fingerprint -sha256 | cut -d= -f2)"

    cat > "$docker_dir/Caddyfile" <<EOF
:443 {
	tls /etc/caddy/certs/selfsigned.crt /etc/caddy/certs/selfsigned.key
	reverse_proxy backend:3000
}
EOF
  else
    local existing_cert="/etc/letsencrypt/live/$domain/fullchain.pem"
    local existing_key="/etc/letsencrypt/live/$domain/privkey.pem"

    if [ -r "$existing_cert" ] && [ -r "$existing_key" ]; then
      log "Найден существующий сертификат для $domain, использую его..."
      cp "$existing_cert" "$certs_dir/domain.crt"
      cp "$existing_key" "$certs_dir/domain.key"
      cat > "$docker_dir/Caddyfile" <<EOF
$domain {
	tls /etc/caddy/certs/domain.crt /etc/caddy/certs/domain.key
	reverse_proxy backend:3000
}
EOF
    else
      log "Существующего сертификата не нашёл — Caddy выпустит новый через Let's Encrypt автоматически при старте."
      {
        echo "$domain {"
        if [ -n "$acme_email" ]; then
          echo -e "\ttls $acme_email"
        fi
        echo -e "\treverse_proxy backend:3000"
        echo "}"
      } > "$docker_dir/Caddyfile"
    fi
  fi

  log "Записываю $docker_dir/.env..."
  cat > "$docker_dir/.env" <<EOF
NODE_HOST=$node_host
DOMAIN=$domain
ACME_EMAIL=$acme_email

POSTGRES_USER=stillhere
POSTGRES_PASSWORD=$postgres_password
POSTGRES_DB=stillhere
DATABASE_URL=postgresql://stillhere:$postgres_password@postgres:5432/stillhere?schema=public

JWT_ACCESS_SECRET=$jwt_access
JWT_REFRESH_SECRET=$jwt_refresh
ACCESS_TOKEN_TTL=15m
REFRESH_TOKEN_TTL=30d

TURN_SECRET=$turn_secret

NODE_TOKEN_SECRET=$node_token_secret
NODE_TOKEN_TTL=365d
NODE_SETUP_PASSWORD=$node_password

CORS_ORIGIN=*

# Push. The paths are always set; the server treats missing files as
# "push disabled", so dropping them in later and restarting is all it takes.
FIREBASE_SERVICE_ACCOUNT_FILE=/run/secrets/firebase-service-account.json
FIREBASE_CLIENT_CONFIG_FILE=/run/secrets/google-services.json
FIREBASE_ANDROID_PACKAGE=com.stillhere.stillhere
EOF
  chmod 600 "$docker_dir/.env"

  setup_push "$certs_dir" "$node_host"

  log "Поднимаю стек (docker compose up -d --build)..."
  (cd "$docker_dir" && docker compose up -d --build)

  log "Готово!"
  echo "Адрес узла для приложения StillHere: ${domain:-$node_host}"
  if [ -n "$cert_fingerprint" ]; then
    echo "SHA-256 отпечаток сертификата (для сверки при первом подключении): $cert_fingerprint"
  fi
  cat <<'EOF'

Не забудьте открыть порты в файрволе (пример для ufw):
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw allow 3478/tcp
  ufw allow 3478/udp
  ufw allow 5349/tcp
  ufw allow 5349/udp
  ufw allow 49160:49200/udp

Пароль узла нигде не сохранён в открытом виде за пределами docker/.env —
он понадобится каждому, кто будет подключаться к этому узлу из приложения.
EOF
}

main "$@"
