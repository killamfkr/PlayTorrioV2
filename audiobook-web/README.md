# PlayTorrio Audiobooks Web App

A self-hosted web application for browsing and streaming audiobooks. This is extracted from the [PlayTorrio](https://github.com/killamfkr/PlayTorrioV2) audiobook feature and runs as a standalone Docker container.

## Features

- Browse audiobook catalog (Tokybook)
- Search across 5 sources: Tokybook, GoldenAudiobook, Audiozaic, AppAudiobooks, and **AudioBookBay** (audiobookbay.lu)
- Full audiobook player with chapter navigation
- Playback speed control (0.5x – 3x)
- Continue listening / listening history
- Liked books
- HLS streaming support for Tokybook sources
- Media Session API for lock-screen controls (mobile/desktop browsers)

## Quick Start (Docker)

```bash
cd audiobook-web
docker compose up -d --build
```

Open **http://localhost:3000** in your browser.

## Unraid Installation

### Option 1: One-click script

SSH into your Unraid server and run:

```bash
curl -fsSL https://raw.githubusercontent.com/killamfkr/PlayTorrioV2/main/audiobook-web/install.sh | bash
```

Or clone the repo and run locally:

```bash
git clone https://github.com/killamfkr/PlayTorrioV2.git
cd PlayTorrioV2/audiobook-web
bash install.sh
```

Custom port:

```bash
PORT=8080 bash install.sh
```

### Option 2: Unraid Docker template

1. In Unraid, go to **Docker** → **Add Container**
2. Set **Template URL** to:
   ```
   https://raw.githubusercontent.com/killamfkr/PlayTorrioV2/main/audiobook-web/unraid/playtorrio-audiobooks.xml
   ```
3. Set the **Repository** to build from source, or use docker-compose:
   - **Repository**: `playtorrio-audiobooks:latest`
   - Build first on the server: `cd /path/to/audiobook-web && docker compose build`
4. Set your desired **Web Port** (default: 3000)
5. Click **Apply**

### Option 3: Manual docker-compose on Unraid

1. Copy the `audiobook-web` folder to `/mnt/user/appdata/playtorrio-audiobooks/`
2. SSH in and run:

```bash
cd /mnt/user/appdata/playtorrio-audiobooks/audiobook-web
docker compose up -d --build
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT`   | `3000`  | Web server port |
| `TZ`     | `America/New_York` | Container timezone |

| `ALLOW_REGISTRATION` | `true` | Allow new user sign-ups |
| `JWT_SECRET` | auto-generated | Session signing key (set to persist across rebuilds) |
| `DATA_DIR` | `./data` | SQLite database location |

## User accounts

Built-in **SQLite database** stores user accounts, continue listening progress, and bookmarks per user.

- Click **Sign in** to register or log in
- **Guests** can still use the app — progress is saved in the browser only
- On login, any guest progress in the browser is **merged** into your account
- Data is stored in `DATA_DIR` (default `./data/audiobooks.db`) and persists across restarts

To disable public registration (e.g. family server):

```env
ALLOW_REGISTRATION=false
```

## Built-in PIA VPN (optional)

Route **all traffic** (including AudioBookBay torrents) through **Private Internet Access** so your home IP is not exposed to peers or your ISP.

### Quick setup

```bash
cd audiobook-web
cp .env.example .env
# Edit .env — set OPENVPN_USER and OPENVPN_PASSWORD (your PIA login)
bash start-with-vpn.sh
```

### Unraid with PIA

```bash
VPN=1 bash install.sh
```

On first run this creates `.env` — add your PIA credentials, then run again.

### What to put in `.env`

```env
OPENVPN_USER=p1234567          # PIA username from client control panel
OPENVPN_PASSWORD=your_password
SERVER_REGIONS=Netherlands     # any PIA region (Netherlands is good for P2P)
PORT_FORWARD_ONLY=true         # use P2P servers (recommended for torrents)
VPN_PORT_FORWARDING=on
GLUETUN_DATA=./gluetun         # persists port-forward assignment
```

PIA credentials: https://www.privateinternetaccess.com/account/client-control-panel

When VPN is active, a **🔒 PIA** badge appears in the web UI header showing your VPN exit IP on hover.

### Without VPN

```bash
docker compose up -d --build
```

## AudioBookBay

Switch to the **AudioBookBay** tab in the web UI to browse and search [audiobookbay.lu](https://audiobookbay.lu).

AudioBookBay books are streamed via **torrent** on the server (WebTorrent). The first time you open a book, the server connects to peers to fetch metadata and begin buffering — this can take 30–60 seconds depending on seeders.

If torrent playback is slow or fails to connect, try:

- Enabling the **built-in PIA VPN** (recommended — hides torrent traffic from your ISP)
- Ensuring your server has outbound UDP access (for BitTorrent DHT)
- Books with no seeders may only play the Audible preview sample (when available)

AudioBookBay results also appear in global search alongside other sources.

## Development

### Backend only

```bash
cd server
npm install
npm run dev
```

### Frontend with hot reload

```bash
cd client
npm install
npm run dev
```

The Vite dev server proxies API requests to `localhost:3000`.

### Production build

```bash
cd client && npm install && npm run build
cd ../server && npm install && npm start
```

## Architecture

```
Browser (React)
  ├── Browse / Search UI
  ├── HLS.js + HTML5 audio player
  └── localStorage (history, likes)

Node.js Express Server
  ├── /api/audiobooks          — catalog
  ├── /api/audiobooks/search   — multi-source search (incl. AudioBookBay)
  ├── /api/audiobooks/chapters — chapter resolution
  ├── /toky-proxy              — HLS proxy for Tokybook
  ├── /audio-proxy             — audio proxy for scraped sources
  └── /abb-stream              — torrent stream proxy for AudioBookBay
```

## Updating

```bash
cd audiobook-web
git pull
docker compose up -d --build
```

## License

GPL-2.0 — same as PlayTorrio.
