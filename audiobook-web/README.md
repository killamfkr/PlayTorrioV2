# PlayTorrio Audiobooks Web App

A self-hosted web application for browsing and streaming audiobooks. Runs as a single Docker Compose stack — **no `.env` file required**. All settings are variables in `docker-compose.yml` or the CasaOS UI.

## Features

- Browse/search: Tokybook, GoldenAudiobook, Audiozaic, AppAudiobooks, AudioBookBay
- Full player with chapters, speed control, continue listening
- **User accounts** with SQLite — bookmarks and progress per user
- Optional **PIA VPN sidecar**
- **CasaOS** ready with `x-casaos` variable definitions

## Quick Start

```bash
cd audiobook-web
COMPOSE_PROFILES=standard docker compose up -d --build
```

Open **http://localhost:3000**.

## Variables (no .env file)

Edit directly in `docker-compose.yml` or set in the **CasaOS UI** under each service's environment:

| Variable | Default | Service | Description |
|----------|---------|---------|-------------|
| `COMPOSE_PROFILES` | `standard` | *(compose)* | `standard` or `pia` |
| `TZ` | `America/New_York` | audiobooks | Timezone |
| `ALLOW_REGISTRATION` | `true` | audiobooks | Allow new sign-ups |
| `JWT_SECRET` | *(empty)* | audiobooks | Session secret (auto-generated) |
| `OPENVPN_USER` | *(empty)* | gluetun | PIA username |
| `OPENVPN_PASSWORD` | *(empty)* | gluetun | PIA password |
| `SERVER_REGIONS` | `Netherlands` | gluetun | PIA region |

Data volume: `/DATA/AppData/$AppID/data` (CasaOS) — SQLite database.

## CasaOS (Ubuntu)

See **[casaos/README.md](casaos/README.md)**.

1. Import `audiobook-web` folder via Custom install
2. Set `COMPOSE_PROFILES=standard` in app variables
3. Edit other variables in the CasaOS UI
4. Open port **3000**

## Compose profiles

| `COMPOSE_PROFILES` | Containers |
|--------------------|------------|
| `standard` | `audiobooks` |
| `pia` | `gluetun` + `audiobooks-pia` |

```bash
# Standard
COMPOSE_PROFILES=standard docker compose up -d --build

# PIA VPN
COMPOSE_PROFILES=pia OPENVPN_USER=p1234567 OPENVPN_PASSWORD=secret docker compose up -d --build
```

## Unraid

```bash
curl -fsSL https://raw.githubusercontent.com/killamfkr/PlayTorrioV2/main/audiobook-web/install.sh | bash
```

With PIA:

```bash
VPN=1 OPENVPN_USER=p1234567 OPENVPN_PASSWORD=secret bash install.sh
```

## User accounts

- **Sign in** to register — progress and bookmarks save to the server database
- **Guests** use browser storage until they log in (then data merges)
- Set `ALLOW_REGISTRATION=false` in compose to lock down a family server

## PIA VPN

Set `COMPOSE_PROFILES=pia` and fill in `OPENVPN_USER` / `OPENVPN_PASSWORD` on the **gluetun** service (CasaOS UI or compose file).

```bash
OPENVPN_USER=p1234567 OPENVPN_PASSWORD=secret bash start-with-vpn.sh
```

PIA credentials: https://www.privateinternetaccess.com/account/client-control-panel

## Updating

```bash
cd audiobook-web
git pull
COMPOSE_PROFILES=standard docker compose up -d --build
```

## License

GPL-2.0 — same as PlayTorrio.
