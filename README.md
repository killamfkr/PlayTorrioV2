# PlayTorrio

Stream anything, anywhere. Movies, TV shows, music, manga, comics, audiobooks, live TV, sports, and IPTV — all in one app.

**Current version:** 1.2.2

Made by [ayman708-UX](https://github.com/ayman708-UX), updates made by [killamfkr](https://github.com/killamfkr) with the assistance of Cursor AI. If you like it, star it or whatever.

## What it does

### Home

- **Tonight's Pick** — a randomized featured title with shuffle
- **Mood chips** — quick browse by vibe (action, comedy, horror, etc.) via TMDB discover
- **Because you watched** — recommendations from BestSimilar.com, mapped back to TMDB
- **dlstreams.top shelves** — grouped live-TV-style Stremio catalogs when that addon is installed
- **Continue watching** — local history plus PlayTorrio Cloud sync; can resume with the exact saved stream URL and headers
- **Android TV** — split layout with a focused hero banner for D-pad navigation

### Movies & TV

- Search and browse movies/TV shows with TMDB metadata
- Stream torrents directly with the built-in libtorrent engine
- Stremio addon support (catalogs, streams, live channels)
- **WebStreamr** — on-device embed scraper as a streaming source (country/extractor toggles in settings)
- Real-Debrid and TorBox integration
- Auto-resume and watch history tracking
- **Trakt** and **Simkl** integration
- Jellyfin server integration

### Live TV (Stremio)

- **TV Channels** — browse live channel catalogs from installed Stremio addons
- **Sports** — live sports events and channels (CDN Live TV and related feeds)
- Plays through the same Stremio/HLS flow as movies and series

### IPTV

Three related tabs; hide or reorder any of them in **Settings → Navigation**:

| Tab | What it is |
|-----|------------|
| **IPTV (M3U)** | Classic IPTV login — Xtream Codes API or M3U/M3U8 playlists, live TV and VOD |
| **PT IPTV** | PlayTorrio IPTV hub — discover Xtream portals, add portals manually, manage M3U playlists, star favorite channels, inline EPG on tiles, alive-check for live streams |
| **PT TV Guide** | Full TV guide grid (EPG) for PT IPTV channels; stays in sync when favorites or IPTV data change |

### Audiobooks

- Browse and search **[AudiobookBay.lu](https://audiobookbay.lu)** (`audiobookbay.lu`)
- Stream magnet/torrent-backed audiobooks with chapter navigation
- **Bookmarks** shelf and liked titles
- **Cloud sync** — continue playback position and bookmarks across devices (with removal support)
- **Generate audiobook** — upload an EPUB and convert via Paper2audio into a playable audiobook
- Playback speed control and background playback

### Music

- Search and stream music from Deezer
- Fetches audio from YouTube
- Synced lyrics
- Create playlists
- Download tracks for offline playback
- Like songs and save albums
- Full player with shuffle, repeat, and queue management

### Manga, comics, books & anime

- Read manga from multiple sources — chapter tracking, page-by-page or continuous scroll
- Comics support with history
- Books library
- Anime browsing and streaming

### Cloud & account

- **PlayTorrio Cloud** — optional Supabase-backed sync for watch progress, app settings, and audiobook bookmarks (sign in from Settings)
- **Trakt** — connect your Trakt account for history and stats

### Other

- **Magnet** tab — paste a magnet link and play
- Torrent search with Prowlarr/Jackett integration
- Customizable bottom/side navigation (show, hide, reorder tabs)
- **Android TV** — TV-optimized focus handling and LAN settings import from your phone
- Cross-platform: **Windows**, **Linux**, **macOS**, **Android**
- Dark theme because obviously

## Download

Check the [releases](https://github.com/killamfkr/PlayTorrioV2/releases) page for the latest builds.

| Platform | Artifact |
|----------|----------|
| Android | APK |
| Windows | Installer |
| Linux | AppImage |
| macOS | Zip |

## Building

You need Flutter and the usual build tools.

```
flutter pub get
flutter build windows
flutter build linux
flutter build apk
```

### Web (experimental)

A **browser build** is supported for browsing and streaming where the platform allows (no magnet/torrent engine, no local Shelf proxy, simplified player, some tabs stubbed). Build static files with:

```
flutter pub get
flutter build web --release
```

Serve `build/web` with any static file server, or use Docker:

```
docker build -f docker/web/Dockerfile -t playtorrio-web .
docker run --rm -p 8089:80 playtorrio-web
```

**Docker Compose — build locally** (from repo root):

```
docker compose -f docker/web/docker-compose.yml up -d --build
```

**Docker Compose — pull pre-built image** (no clone/build; image from GitHub Container Registry after CI runs on `main`):

```
docker compose -f docker/web/docker-compose.ghcr.yml pull
docker compose -f docker/web/docker-compose.ghcr.yml up -d
```

Default image: `ghcr.io/killamfkr/playtorrio-web:latest`. Forks: run the **Docker Web (GHCR)** workflow on your repo, then set `PLAYTORRIO_WEB_IMAGE=ghcr.io/<your-github-user>/playtorrio-web:latest`.

Then open http://localhost:8089

### Unraid

Use the Community Applications–style template in [`docker/unraid/playtorrio-web.xml`](docker/unraid/playtorrio-web.xml). Copy it to `config/plugins/dockerMan/templates-user/` on your Unraid flash drive, build the image on the server (`docker build -f docker/web/Dockerfile -t playtorrio-web:latest .`), then add the container from the template. Full steps: [`docker/unraid/README.md`](docker/unraid/README.md).

## License

GPL-2.0 license
