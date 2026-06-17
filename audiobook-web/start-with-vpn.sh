#!/bin/bash
# Start with PIA VPN sidecar
# Usage: OPENVPN_USER=p1234567 OPENVPN_PASSWORD=secret bash start-with-vpn.sh
set -e
cd "$(dirname "$0")"

if [ -z "${OPENVPN_USER}" ] || [ -z "${OPENVPN_PASSWORD}" ]; then
  echo "Set PIA credentials as variables:"
  echo "  OPENVPN_USER=p1234567 OPENVPN_PASSWORD=secret bash start-with-vpn.sh"
  exit 1
fi

export COMPOSE_PROFILES=pia
echo "Starting with PIA VPN (region: ${SERVER_REGIONS:-Netherlands})..."
docker compose up -d --build "$@"

echo ""
echo "Web UI: http://localhost:3000"
echo "VPN logs: docker logs -f playtorrio-audiobooks-vpn"
