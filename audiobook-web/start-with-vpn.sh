#!/bin/bash
# Start PlayTorrio Audiobooks with built-in PIA VPN (Gluetun)
set -e
cd "$(dirname "$0")"

if [ ! -f .env ]; then
  echo "Create .env with your PIA credentials first:"
  echo "  cp .env.example .env"
  echo "  nano .env   # set OPENVPN_USER and OPENVPN_PASSWORD"
  exit 1
fi

# shellcheck disable=SC1091
source .env

if [ -z "${OPENVPN_USER}" ] || [ -z "${OPENVPN_PASSWORD}" ]; then
  echo "ERROR: Set OPENVPN_USER and OPENVPN_PASSWORD in .env (your PIA login)"
  exit 1
fi

echo "Starting with PIA VPN (region: ${SERVER_REGIONS:-Netherlands})..."
docker compose -f docker-compose.yml -f docker-compose.vpn.yml up -d --build "$@"

echo ""
echo "VPN container logs: docker logs -f playtorrio-audiobooks-vpn"
echo "Web UI: http://localhost:${PORT:-3000}"
