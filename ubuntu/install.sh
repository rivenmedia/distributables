#!/usr/bin/env bash
set -e

# ================= CONFIG =================
DOWNLOAD_DIR="/opt/riven"
COMPOSE_URL="https://raw.githubusercontent.com/AquaHorizonGaming/distributables/main/ubuntu/docker-compose.yml"

# ================= PRECHECK =================
if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root"
  exit 1
fi

. /etc/os-release || exit 1
[ "$ID" = "ubuntu" ] || exit 1

# ================= TIMEZONE =================
TZ_SELECTED="$(timedatectl show --property=Timezone --value 2>/dev/null || echo UTC)"
timedatectl set-timezone "$TZ_SELECTED"
echo "Timezone: $TZ_SELECTED"

# ================= DEPENDENCIES =================
if ! command -v curl >/dev/null; then
  apt-get update
  apt-get install -y curl ca-certificates
fi

if ! command -v docker >/dev/null; then
  apt-get update
  apt-get install -y ca-certificates gnupg lsb-release

  mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor > /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  systemctl enable docker
fi

# ================= FILES =================
mkdir -p "$DOWNLOAD_DIR"
cd "$DOWNLOAD_DIR"

curl -fsSL "$COMPOSE_URL" -o docker-compose.yml || exit 1

if [ ! -f .env ]; then
  printf "TZ=%s\nPOSTGRES_DB=riven\nPOSTGRES_USER=postgres\nPOSTGRES_PASSWORD=%s\nBACKEND_API_KEY=%s\nAUTH_SECRET=%s\n" \
    "$TZ_SELECTED" \
    "$(openssl rand -hex 24)" \
    "$(openssl rand -hex 32)" \
    "$(openssl rand -hex 32)" > .env
fi

# ================= MOUNTS =================
mkdir -p /mnt/riven/backend /mnt/riven/mount
chown -R 1000:1000 /mnt/riven

printf "[Unit]
Description=Make Riven mount bind shared
After=local-fs.target
Before=docker.service

[Service]
Type=oneshot
ExecStart=/usr/bin/mount --bind /mnt/riven/mount /mnt/riven/mount
ExecStart=/usr/bin/mount --make-rshared /mnt/riven/mount
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
" > /etc/systemd/system/riven-bind-shared.service

systemctl daemon-reload
systemctl enable --now riven-bind-shared.service

# ================= START =================
systemctl start docker
docker compose pull
docker compose up -d

echo "Riven install complete"
