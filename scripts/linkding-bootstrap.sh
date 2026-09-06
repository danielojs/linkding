#!/usr/bin/env bash

set +x
set -Eeuo pipefail
umask 077

readonly LOG_FILE="/var/log/linkding-bootstrap.log"
readonly APP_DIR="/opt/linkding"
readonly DATA_DIR="${APP_DIR}/data"
readonly NGINX_DIR="${APP_DIR}/nginx"
readonly COMPOSE_FILE="${APP_DIR}/compose.yaml"
readonly NGINX_CONFIG="${NGINX_DIR}/default.conf"
readonly CERTBOT_WEBROOT="${APP_DIR}/certbot/www"
readonly DOMAIN_NAME="rezedev.site"
readonly CREDENTIALS_FILE="/root/linkding-credentials.txt"

touch "${LOG_FILE}"
chmod 0600 "${LOG_FILE}"
exec >>"${LOG_FILE}" 2>&1

trap 'status=$?; printf "[%s] ERROR: bootstrap failed at line %s (exit %s)\n" "$(date --iso-8601=seconds)" "${LINENO}" "${status}"' ERR

if [[ "${EUID}" -ne 0 ]]; then
  echo "This script must run as root." >&2
  exit 1
fi

log() {
  printf '[%s] %s\n' "$(date --iso-8601=seconds)" "$1"
}

install_docker() {
  export DEBIAN_FRONTEND=noninteractive

  # shellcheck disable=SC1091
  source /etc/os-release
  if [[ "${ID}" != "ubuntu" ]]; then
    echo "This bootstrap supports Ubuntu only; detected ${ID}." >&2
    exit 1
  fi

  log "Installing TLS prerequisites"
  apt-get update -o Acquire::Retries=5
  apt-get install -y ca-certificates certbot curl

  if docker compose version >/dev/null 2>&1; then
    log "Docker Compose is already installed"
    return
  fi

  log "Installing Docker CE and Docker Compose"
  apt-get remove -y \
    docker.io \
    docker-compose \
    docker-compose-v2 \
    docker-doc \
    podman-docker \
    containerd \
    runc || true

  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL --retry 5 \
    https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc
  chmod 0644 /etc/apt/keyrings/docker.asc

  local architecture
  architecture="$(dpkg --print-architecture)"

  cat >/etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${VERSION_CODENAME}
Components: stable
Architectures: ${architecture}
Signed-By: /etc/apt/keyrings/docker.asc
EOF

  apt-get update -o Acquire::Retries=5
  apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin
}

write_application_config() {
  log "Writing Linkding and Nginx configuration"
  install -d -m 0755 "${APP_DIR}" "${DATA_DIR}" "${NGINX_DIR}" "${CERTBOT_WEBROOT}"

  cat >"${COMPOSE_FILE}" <<'COMPOSE'
services:
  linkding:
    image: sissbruecker/linkding:latest
    restart: unless-stopped
    init: true
    expose:
      - "9090"
    volumes:
      - /opt/linkding/data:/etc/linkding/data
    networks:
      - web

  nginx:
    image: nginx:stable-alpine
    restart: unless-stopped
    init: true
    depends_on:
      - linkding
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /opt/linkding/nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
      - /opt/linkding/certbot/www:/var/www/certbot:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro
    networks:
      - web

networks:
  web:
    driver: bridge
COMPOSE
  chmod 0644 "${COMPOSE_FILE}"

  cat >"${NGINX_CONFIG}" <<'NGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name rezedev.site;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        resolver 127.0.0.11 valid=10s ipv6=off;
        set $linkding_upstream http://linkding:9090;

        proxy_pass $linkding_upstream;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 10s;
        proxy_read_timeout 60s;
        proxy_send_timeout 60s;
    }
}
NGINX
  chmod 0644 "${NGINX_CONFIG}"
}

obtain_certificate() {
  if [[ -f "/etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem" ]]; then
    log "A TLS certificate for ${DOMAIN_NAME} already exists"
    return
  fi

  log "Requesting a Let's Encrypt certificate for ${DOMAIN_NAME}"
  local attempt
  for attempt in $(seq 1 30); do
    if certbot certonly \
      --non-interactive \
      --agree-tos \
      --register-unsafely-without-email \
      --webroot \
      --webroot-path "${CERTBOT_WEBROOT}" \
      --cert-name "${DOMAIN_NAME}" \
      --domain "${DOMAIN_NAME}"; then
      return
    fi

    log "Certificate request failed (${attempt}/30); waiting for DNS propagation"
    sleep 20
  done

  echo "Could not obtain a TLS certificate for ${DOMAIN_NAME}. Verify the Route 53 nameservers are configured at Hostinger." >&2
  exit 1
}

enable_https() {
  log "Enabling HTTPS and automatic certificate renewal"

  cat >"${NGINX_CONFIG}" <<'NGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name rezedev.site;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name rezedev.site;

    ssl_certificate /etc/letsencrypt/live/rezedev.site/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/rezedev.site/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;

    location / {
        resolver 127.0.0.11 valid=10s ipv6=off;
        set $linkding_upstream http://linkding:9090;

        proxy_pass $linkding_upstream;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 10s;
        proxy_read_timeout 60s;
        proxy_send_timeout 60s;
    }
}
NGINX
  chmod 0644 "${NGINX_CONFIG}"

  install -d -m 0755 /etc/letsencrypt/renewal-hooks/deploy
  cat >/etc/letsencrypt/renewal-hooks/deploy/reload-linkding-nginx.sh <<'HOOK'
#!/usr/bin/env bash
set -Eeuo pipefail
docker compose -f /opt/linkding/compose.yaml exec -T nginx nginx -s reload
HOOK
  chmod 0755 /etc/letsencrypt/renewal-hooks/deploy/reload-linkding-nginx.sh

  docker compose -f "${COMPOSE_FILE}" exec -T nginx nginx -t
  docker compose -f "${COMPOSE_FILE}" exec -T nginx nginx -s reload
  systemctl enable --now certbot.timer
}

ensure_admin_user() {
  local admin_password

  if [[ ! -f "${CREDENTIALS_FILE}" ]]; then
    admin_password="$(openssl rand -hex 24)"
    printf 'Username: admin\nPassword: %s\n' "${admin_password}" >"${CREDENTIALS_FILE}"
    chmod 0600 "${CREDENTIALS_FILE}"
  else
    admin_password="$(awk '/^Password: / { sub(/^Password: /, ""); print; exit }' "${CREDENTIALS_FILE}")"
  fi

  if [[ -z "${admin_password}" ]]; then
    echo "Could not read the generated Linkding administrator password." >&2
    exit 1
  fi

  log "Waiting for Linkding and creating the administrator if needed"

  local attempt
  for attempt in $(seq 1 60); do
    if printf '%s' "${admin_password}" | docker compose -f "${COMPOSE_FILE}" exec \
      -T \
      linkding \
      python manage.py shell -c '
import sys
from django.contrib.auth import get_user_model

User = get_user_model()
user, created = User.objects.get_or_create(username="admin")
changed = created

for attribute in ("is_active", "is_staff", "is_superuser"):
    if not getattr(user, attribute):
        setattr(user, attribute, True)
        changed = True

if created:
    user.set_password(sys.stdin.read())

if changed:
    user.save()
'
    then
      unset admin_password
      return
    fi

    log "Linkding is not ready yet (${attempt}/60); retrying"
    sleep 3
  done

  unset admin_password
  echo "Linkding did not become ready for administrator creation." >&2
  exit 1
}

log "Starting Linkding bootstrap"
install_docker
systemctl enable --now docker
write_application_config

docker compose -f "${COMPOSE_FILE}" config --quiet
log "Pulling container images"
docker compose -f "${COMPOSE_FILE}" pull
log "Starting Linkding and Nginx"
docker compose -f "${COMPOSE_FILE}" up -d --remove-orphans

obtain_certificate
enable_https
ensure_admin_user

curl --fail --silent --show-error --retry 10 --retry-delay 3 \
  --output /dev/null \
  --resolve "${DOMAIN_NAME}:443:127.0.0.1" \
  "https://${DOMAIN_NAME}/"

log "Bootstrap complete; Linkding is available at https://${DOMAIN_NAME}; credentials are in ${CREDENTIALS_FILE}"
