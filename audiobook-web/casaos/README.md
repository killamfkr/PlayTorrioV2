# CasaOS install guide

Add PlayTorrio Audiobooks to [CasaOS](https://casaos.io) on Ubuntu using the single `docker-compose.yml` — **no `.env` file required**. All settings are variables you edit in the CasaOS UI or directly in the compose file.

## Install

1. Clone the repo:

```bash
sudo git clone https://github.com/killamfkr/PlayTorrioV2.git /DATA/AppData/playtorrio-audiobooks/src
```

2. In **CasaOS** → **App Store** → **Custom install** → **Import**:
   - Select folder: `/DATA/AppData/playtorrio-audiobooks/src/audiobook-web`

3. Set these **app variables** in the CasaOS UI before deploying:

| Variable | Value | Required |
|----------|-------|----------|
| `COMPOSE_PROFILES` | `standard` | Yes |
| `AppID` | `playtorrio-audiobooks` | Auto-set by CasaOS |

4. Open `http://<server-ip>:3000`

## Variables (CasaOS UI)

Edit on the **audiobooks** service:

| Variable | Default | Description |
|----------|---------|-------------|
| `TZ` | `America/New_York` | Timezone |
| `ALLOW_REGISTRATION` | `true` | Allow new user sign-ups |
| `JWT_SECRET` | *(empty)* | Session secret (auto-generated if empty) |

Data is stored at `/DATA/AppData/$AppID/data` (SQLite database).

## Enable PIA VPN

1. Set app variable: `COMPOSE_PROFILES` = `pia`
2. On the **gluetun** service, set:

| Variable | Example |
|----------|---------|
| `OPENVPN_USER` | `p1234567` |
| `OPENVPN_PASSWORD` | `your_password` |
| `SERVER_REGIONS` | `Netherlands` |

3. Redeploy

## Or edit docker-compose.yml directly

All defaults are inline in `docker-compose.yml` under each service's `environment:` block. Change values there instead of using a `.env` file.

## Command line

```bash
cd /DATA/AppData/playtorrio-audiobooks/src/audiobook-web

# Standard
COMPOSE_PROFILES=standard docker compose up -d --build

# PIA VPN
COMPOSE_PROFILES=pia OPENVPN_USER=p1234567 OPENVPN_PASSWORD=secret docker compose up -d --build
```
