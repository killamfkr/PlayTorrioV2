#!/bin/bash
# PlayTorrio Audiobooks installer
# Standard:  bash install.sh
# With VPN:   VPN=1 OPENVPN_USER=p123 OPENVPN_PASSWORD=secret bash install.sh

set -e

APP_NAME="playtorrio-audiobooks"
INSTALL_DIR="${INSTALL_DIR:-/mnt/user/appdata/${APP_NAME}}"
REPO_URL="${REPO_URL:-https://github.com/killamfkr/PlayTorrioV2.git}"
BRANCH="${BRANCH:-main}"
VPN="${VPN:-0}"

echo "============================================"
echo "  PlayTorrio Audiobooks Installer"
echo "============================================"
echo "Install dir:   ${INSTALL_DIR}"
echo "VPN profile:   $([ "$VPN" = "1" ] && echo "pia" || echo "standard")"
echo ""

mkdir -p "${INSTALL_DIR}/data"
cd "${INSTALL_DIR}"

if [ -d "src/.git" ]; then
  echo "Updating..."
  git -C src pull origin "${BRANCH}" 2>/dev/null || true
else
  echo "Cloning..."
  git clone --depth 1 --branch "${BRANCH}" "${REPO_URL}" src
fi

cd src/audiobook-web

if ! command -v docker &> /dev/null; then
  echo "ERROR: Docker not found."
  exit 1
fi

if [ "$VPN" = "1" ]; then
  export COMPOSE_PROFILES=pia
  if [ -z "${OPENVPN_USER}" ] || [ -z "${OPENVPN_PASSWORD}" ]; then
    echo "ERROR: Set OPENVPN_USER and OPENVPN_PASSWORD variables"
    echo "  VPN=1 OPENVPN_USER=p123 OPENVPN_PASSWORD=secret bash install.sh"
    exit 1
  fi
  export OPENVPN_USER OPENVPN_PASSWORD
else
  export COMPOSE_PROFILES=standard
fi

echo "Building..."
docker compose up -d --build

echo ""
echo "Done! http://$(hostname -I 2>/dev/null | awk '{print $1}'):3000"
