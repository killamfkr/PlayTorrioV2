#!/bin/bash
# PlayTorrio Audiobooks - One-click installer for Unraid
# Run from terminal: bash install.sh
# With PIA VPN:      VPN=1 bash install.sh

set -e

APP_NAME="playtorrio-audiobooks"
INSTALL_DIR="${INSTALL_DIR:-/mnt/user/appdata/${APP_NAME}}"
PORT="${PORT:-3000}"
REPO_URL="${REPO_URL:-https://github.com/killamfkr/PlayTorrioV2.git}"
BRANCH="${BRANCH:-main}"
VPN="${VPN:-0}"

echo "============================================"
echo "  PlayTorrio Audiobooks - Unraid Installer"
echo "============================================"
echo ""
echo "Install directory: ${INSTALL_DIR}"
echo "Port:              ${PORT}"
echo "PIA VPN:           $([ "$VPN" = "1" ] && echo "enabled" || echo "disabled")"
echo ""

mkdir -p "${INSTALL_DIR}"
cd "${INSTALL_DIR}"

if [ -d ".git" ]; then
  echo "Updating existing installation..."
  git pull origin "${BRANCH}" 2>/dev/null || true
else
  echo "Cloning repository..."
  git clone --depth 1 --branch "${BRANCH}" "${REPO_URL}" .
fi

cd audiobook-web

if ! command -v docker &> /dev/null; then
  echo "ERROR: Docker is not installed or not in PATH."
  exit 1
fi

# Setup .env for VPN installs
if [ "$VPN" = "1" ]; then
  if [ ! -f .env ]; then
    cp .env.example .env
    mkdir -p "${INSTALL_DIR}/gluetun"
    sed -i "s|GLUETUN_DATA=./gluetun|GLUETUN_DATA=${INSTALL_DIR}/gluetun|" .env 2>/dev/null || \
      sed -i '' "s|GLUETUN_DATA=./gluetun|GLUETUN_DATA=${INSTALL_DIR}/gluetun|" .env
    echo ""
    echo "Created .env — edit it with your PIA credentials before continuing:"
    echo "  nano ${INSTALL_DIR}/audiobook-web/.env"
    echo ""
    echo "Set OPENVPN_USER and OPENVPN_PASSWORD, then re-run:"
    echo "  VPN=1 bash install.sh"
    exit 0
  fi
  # shellcheck disable=SC1091
  source .env
  if [ -z "${OPENVPN_USER}" ] || [ -z "${OPENVPN_PASSWORD}" ]; then
    echo "ERROR: Set OPENVPN_USER and OPENVPN_PASSWORD in .env"
    exit 1
  fi
  COMPOSE_ARGS="-f docker-compose.yml -f docker-compose.vpn.yml"
else
  COMPOSE_ARGS="-f docker-compose.yml"
fi

echo ""
echo "Building Docker image (this may take a few minutes)..."
docker compose ${COMPOSE_ARGS} build

echo ""
echo "Starting container..."
PORT="${PORT}" docker compose ${COMPOSE_ARGS} up -d

echo ""
echo "============================================"
echo "  Installation complete!"
echo "============================================"
echo ""
echo "  Access your audiobooks at:"
echo "  http://$(hostname -I 2>/dev/null | awk '{print $1}'):${PORT}"
echo "  or http://localhost:${PORT}"
echo ""
if [ "$VPN" = "1" ]; then
  echo "  PIA VPN logs: docker logs -f playtorrio-audiobooks-vpn"
  echo ""
fi
echo "  To stop:    cd ${INSTALL_DIR}/audiobook-web && docker compose ${COMPOSE_ARGS} down"
echo "  To update:  cd ${INSTALL_DIR}/audiobook-web && git pull && docker compose ${COMPOSE_ARGS} up -d --build"
echo ""
