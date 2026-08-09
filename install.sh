#!/usr/bin/env bash
# StillHere node installer.
#
#   curl -fsSL https://raw.githubusercontent.com/<owner>/stillhere/main/install.sh | sudo bash
#
# Turns a fresh Debian/Ubuntu server into a StillHere node: installs Docker
# if needed, generates all secrets, sets up TLS (self-signed by IP, or your
# domain's existing certificate, or a fresh Let's Encrypt one via Caddy),
# and brings the whole stack up. Safe to re-run — it refuses to touch an
# existing installation instead of silently overwriting secrets.
set -euo pipefail

# TODO: update this once the repository is published.
REPO_URL="${STILLHERE_REPO_URL:-https://github.com/CHANGE_ME/stillhere.git}"
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
    git -C "$INSTALL_DIR" pull --ff-only
  else
    git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
  fi
}

# Prompts for a value, honoring an env var override for non-interactive runs.
prompt() {
  local var_name="$1" prompt_text="$2" default_value="${3:-}"
  local env_value="${!var_name:-}"
  if [ -n "$env_value" ]; then
    printf '%s\n' "$env_value"
    return
  fi
  local reply
  read -rp "$prompt_text" reply
  printf '%s\n' "${reply:-$default_value}"
}

prompt_node_password() {
  local env_value="${STILLHERE_NODE_PASSWORD:-}"
  if [ -n "$env_value" ]; then
    printf '%s\n' "$env_value"
    return
  fi
  local pass1 pass2
  while true; do
    read -rsp "Пароль узла (минимум 8 символов, его будут вводить друзья в приложении): " pass1
    echo >&2
    if [ "${#pass1}" -lt 8 ]; then
      warn "Слишком короткий, минимум 8 символов."
      continue
    fi
    read -rsp "Повторите пароль: " pass2
    echo >&2
    if [ "$pass1" != "$pass2" ]; then
      warn "Пароли не совпали, попробуйте ещё раз."
      continue
    fi
    printf '%s\n' "$pass1"
    return
  done
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
  local node_password domain acme_email node_host
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
EOF
  chmod 600 "$docker_dir/.env"

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
