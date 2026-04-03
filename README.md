# PlayTorrio

Stream anything, anywhere. Movies, TV shows, music, manga, comics, audiobooks, live TV from Stremio. All in one app.

Made by me. If you like it, star it or whatever.

## What it does

Movies & TV Shows:
- Search and browse movies/TV shows with TMDB metadata
- Stream torrents directly with built-in libtorrent engine
- Stremio addon support
- Real-Debrid and TorBox integration
- Auto-resume from where you left off
- Watch history tracking
- Jellyfin server integration

Music:
- Search and stream music from Deezer
- Fetches audio from YouTube
- Synced lyrics
- Create playlists
- Download tracks for offline playback
- Like songs and save albums
- Full-featured player with shuffle, repeat, queue management

Manga & Comics:
- Read manga from multiple sources
- comics support
- Chapter tracking and history
- page-by-page or continuous scroll reading

Audiobooks:
- Stream audiobooks
- Chapter navigation
- Playback speed control

Live TV (Stremio):
- Browse TV channel catalogs from installed Stremio addons
- Play streams through the same Stremio flow as movies and series

IPTV:
- Xtream Codes API support
- M3U playlist support
- Live TV and VOD

Other stuff:
- Torrent search with Prowlarr/Jackett integration
- Cross-platform (Windows, Linux, macOS, Android)
- Dark theme because obviously

## Download

Check the releases page for the latest builds.

Android: APK files
Windows: Installer
Linux: AppImage
macOS: Zip

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
docker run --rm -p 8080:80 playtorrio-web
```

Then open http://localhost:8080

## License


GPL-2.0 license