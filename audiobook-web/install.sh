#!/bin/bash
# PlayTorrio Audiobooks - One-click installer for Unraid
# Run from terminal: bash install.sh

set -e

APP_NAME="playtorrio-audiobooks"
INSTALL_DIR="${INSTALL_DIR:-/mnt/user/appdata/${APP_NAME}}"
PORT="${PORT:-3000}"
REPO_URL="${REPO_URL:-https://github.com/playtorrio/play_torrio_native.git}"
BRANCH="${BRANCH:-main}"

echo "============================================"
echo "  PlayTorrio Audiobooks - Unraid Installer"
echo "============================================"
echo ""
echo "Install directory: ${INSTALL_DIR}"
echo "Port:              ${PORT}"
echo ""

# Create install directory
mkdir -p "${INSTALL_DIR}"
cd "${INSTALL_DIR}"

# Clone or update repo
if [ -d ".git" ]; then
  echo "Updating existing installation..."
  git pull origin "${BRANCH}" 2>/dev/null || true
else
  echo "Cloning repository..."
  git clone --depth 1 --branch "${BRANCH}" "${REPO_URL}" .
fi

cd audiobook-web

# Check Docker is available
if ! command -v docker &> /dev/null; then
  echo "ERROR: Docker is not installed or not in PATH."
  exit 1
fi

# Build and start
echo ""
echo "Building Docker image (this may take a few minutes)..."
docker compose build

echo ""
echo "Starting container..."
PORT="${PORT}" docker compose up -d

echo ""
echo "============================================"
echo "  Installation complete!"
echo "============================================"
echo ""
echo "  Access your audiobooks at:"
echo "  http://$(hostname -I 2>/dev/null | awk '{print $1}'):${PORT}"
echo "  or http://localhost:${PORT}"
echo ""
echo "  To stop:    cd ${INSTALL_DIR}/audiobook-web && docker compose down"
echo "  To update:  cd ${INSTALL_DIR}/audiobook-web && git pull && docker compose up -d --build"
echo ""
