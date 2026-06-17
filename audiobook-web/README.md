# PlayTorrio Audiobooks Web App

A self-hosted web application for browsing and streaming audiobooks. This is extracted from the [PlayTorrio](https://github.com/killamfkr/PlayTorrioV2) audiobook feature and runs as a standalone Docker container.

## Features

- Browse audiobook catalog (Tokybook)
- Search across 4 sources: Tokybook, GoldenAudiobook, Audiozaic, AppAudiobooks
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
  ├── /api/audiobooks/search   — multi-source search
  ├── /api/audiobooks/chapters — chapter resolution
  ├── /toky-proxy              — HLS proxy for Tokybook
  └── /audio-proxy             — audio proxy for scraped sources
```

## Updating

```bash
cd audiobook-web
git pull
docker compose up -d --build
```

## License

GPL-2.0 — same as PlayTorrio.
