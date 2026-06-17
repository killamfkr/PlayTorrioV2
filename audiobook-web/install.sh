#!/bin/bash
# PlayTorrio Audiobooks installer
# Standard:  bash install.sh
# With VPN:   VPN=1 bash install.sh

set -e

APP_NAME="playtorrio-audiobooks"
INSTALL_DIR="${INSTALL_DIR:-/mnt/user/appdata/${APP_NAME}}"
PORT="${PORT:-3000}"
REPO_URL="${REPO_URL:-https://github.com/killamfkr/PlayTorrioV2.git}"
BRANCH="${BRANCH:-main}"
VPN="${VPN:-0}"

echo "============================================"
echo "  PlayTorrio Audiobooks Installer"
echo "============================================"
echo "Install dir: ${INSTALL_DIR}"
echo "Port:        ${PORT}"
echo "VPN profile: $([ "$VPN" = "1" ] && echo "pia" || echo "standard")"
echo ""

mkdir -p "${INSTALL_DIR}"
cd "${INSTALL_DIR}"

if [ -d ".git" ]; then
  echo "Updating..."
  git pull origin "${BRANCH}" 2>/dev/null || true
else
  echo "Cloning..."
  git clone --depth 1 --branch "${BRANCH}" "${REPO_URL}" .
fi

cd audiobook-web

if ! command -v docker &> /dev/null; then
  echo "ERROR: Docker not found."
  exit 1
fi

if [ "$VPN" = "1" ]; then
  export COMPOSE_PROFILES=pia
  if [ ! -f .env ]; then
    cp .env.example .env
    sed -i "s|/DATA/AppData/playtorrio-audiobooks|${INSTALL_DIR}|g" .env 2>/dev/null || \
      sed -i '' "s|/DATA/AppData/playtorrio-audiobooks|${INSTALL_DIR}|g" .env
    echo "Edit .env with PIA credentials, then re-run: VPN=1 bash install.sh"
    exit 0
  fi
  # shellcheck disable=SC1091
  source .env
  if [ -z "${OPENVPN_USER}" ] || [ -z "${OPENVPN_PASSWORD}" ]; then
    echo "ERROR: Set OPENVPN_USER and OPENVPN_PASSWORD in .env"
    exit 1
  fi
else
  export COMPOSE_PROFILES=standard
fi

mkdir -p "${DATA_DIR:-${INSTALL_DIR}/data}"

echo "Building..."
docker compose up -d --build

echo ""
echo "Done! http://$(hostname -I 2>/dev/null | awk '{print $1}'):${PORT}"
