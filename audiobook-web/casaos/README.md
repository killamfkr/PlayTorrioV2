# CasaOS install guide

Use the single `docker-compose.yml` in this folder to add PlayTorrio Audiobooks to [CasaOS](https://casaos.io) on Ubuntu.

## Option A: Import from Git (recommended)

1. SSH into your CasaOS server and clone the repo:

```bash
sudo mkdir -p /DATA/AppData/playtorrio-audiobooks
sudo git clone https://github.com/killamfkr/PlayTorrioV2.git /DATA/AppData/playtorrio-audiobooks/src
cd /DATA/AppData/playtorrio-audiobooks/src/audiobook-web
```

2. Create your environment file:

```bash
cp .env.example .env
nano .env
```

Set at minimum:

```env
COMPOSE_PROFILES=standard
DATA_DIR=/DATA/AppData/playtorrio-audiobooks/data
```

3. In **CasaOS** → **App Store** → **Custom install** → **Import**:
   - Select the folder `/DATA/AppData/playtorrio-audiobooks/src/audiobook-web`
   - Or paste the contents of `docker-compose.yml`

4. Click **Install / Deploy**.

5. Open `http://<your-server-ip>:3000`

## Option B: Paste compose in CasaOS UI

1. Copy `docker-compose.yml` from this repo
2. CasaOS → **App Store** → **Custom install** → paste YAML
3. Set environment variables in the CasaOS UI (see below)
4. **Note:** `build: .` requires the full repo on disk — use Option A if build fails

## Environment variables (CasaOS UI)

| Variable | Default | Description |
|----------|---------|-------------|
| `COMPOSE_PROFILES` | `standard` | `standard` = no VPN, `pia` = PIA VPN sidecar |
| `PORT` | `3000` | Web UI port |
| `DATA_DIR` | `/DATA/AppData/playtorrio-audiobooks/data` | SQLite + user data |
| `ALLOW_REGISTRATION` | `true` | Allow new sign-ups |
| `OPENVPN_USER` | — | PIA username (profile `pia` only) |
| `OPENVPN_PASSWORD` | — | PIA password (profile `pia` only) |
| `SERVER_REGIONS` | `Netherlands` | PIA region (profile `pia` only) |

## Enable PIA VPN

In `.env` or CasaOS environment:

```env
COMPOSE_PROFILES=pia
OPENVPN_USER=p1234567
OPENVPN_PASSWORD=your_password
SERVER_REGIONS=Netherlands
```

Then redeploy. This starts two containers:

- `gluetun` — PIA VPN sidecar (exposes port 3000)
- `audiobooks-pia` — app traffic routed through VPN

## Profiles

| Profile | Containers | Use when |
|---------|------------|----------|
| `standard` | `audiobooks` | Normal use, no VPN |
| `pia` | `gluetun` + `audiobooks-pia` | Hide torrent traffic from ISP |

## Command line (without CasaOS UI)

```bash
cd /DATA/AppData/playtorrio-audiobooks/src/audiobook-web
cp .env.example .env
# edit .env

# Standard
COMPOSE_PROFILES=standard docker compose up -d --build

# With PIA VPN
COMPOSE_PROFILES=pia docker compose up -d --build
```

## Data persistence

All user accounts, bookmarks, and listening history are stored in:

```
/DATA/AppData/playtorrio-audiobooks/data/audiobooks.db
```

Back up this folder before major updates.
