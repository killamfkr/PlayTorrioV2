#!/bin/bash
# Start with PIA VPN sidecar (COMPOSE_PROFILES=pia)
set -e
cd "$(dirname "$0")"

if [ ! -f .env ]; then
  echo "Create .env from .env.example and set PIA credentials:"
  echo "  cp .env.example .env"
  exit 1
fi

# shellcheck disable=SC1091
source .env

if [ -z "${OPENVPN_USER}" ] || [ -z "${OPENVPN_PASSWORD}" ]; then
  echo "ERROR: Set OPENVPN_USER and OPENVPN_PASSWORD in .env"
  exit 1
fi

export COMPOSE_PROFILES=pia
echo "Starting with PIA VPN sidecar..."
docker compose up -d --build "$@"

echo ""
echo "Web UI: http://localhost:${PORT:-3000}"
echo "VPN logs: docker logs -f playtorrio-audiobooks-vpn"
