# PlayTorrio

Stream anything, anywhere. Movies, TV shows, music, manga, comics, audiobooks, live sports. All in one app.

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

Live Sports:
- Watch live matches and events
- Multiple stream sources

IPTV:
- Xtream Codes API support
- M3U playlist support
- Live TV and VOD

Other stuff:
- Torrent search with Prowlarr/Jackett integration
- Auto-updates (checks on launch)
- Cross-platform (Windows, Linux, macOS, Android, iOS)
- Dark theme because obviously

## What this fork adds

This repo ([PlayTorrioV2](https://github.com/killamfkr/PlayTorrioV2)) builds on the original PlayTorrio baseline with the following additions and fixes.

**Updates, signing, and CI**

- Cross-platform **auto-updater** (checks on launch; platform-specific installers/packages).
- **Signed releases** and GitHub Actions workflows: Android APK, desktop builds, optional **iOS simulator smoke test**, builds on `main` / manual dispatch.

**Streaming, Stremio, and discovery**

- **Trakt** integration (sync and library features).
- **Stremio** improvements: **collection** addon support, fixes for custom addon IDs, optional **default to Stremio streams** on title details (Settings toggle).
- **Anime** and **Arabic** home sections with extra stream providers and player fixes.
- **CDN Live TV** where applicable.
- **External player** option for opening streams in another app.

**Built-in player**

- **Player settings**: continue playback in **background**, **picture-in-picture** where the platform supports it.
- **Subtitles**: respect default embedded track; choosing **Off** stays off until the user picks subtitles again.
- On **Android / iOS**, when background playback is enabled, the built-in video session appears in the **system media notification** (play / pause / stop from the shade or lock screen), alongside existing **Android Auto** support for **music and audiobooks**.

**IPTV**

- **EPG TV guide** for **Xtream** playlists (provider short EPG; plain M3U has no server EPG in-app).
- Various **IPTV and macOS** fixes from earlier releases.

**Network and devices**

- Optional app-wide **SOCKS5 proxy** (Settings).
- **LAN settings sync**: host settings from a phone on the local network for **Android TV** (or pull on the TV).
- **Android TV** banner asset for launcher polish.

**Platform-specific**

- **iOS** support: networking (e.g. arbitrary loads where needed), **User-Agent** handling, updater integration, **libtorrent** / **SystemConfiguration** build fixes, and lifecycle fixes for a stable launch.
- **macOS**: sandbox-related fixes, **TorrServer** improvements, **DMG** packaging.

**UI and data**

- **My List** and **Continue Watching** improvements, **Continue Watching** info affordance, poster/layout fixes.

**Other**

- **GPL-2.0** license file included in-repo; crash fix for **TorrentStreamService** double-dispose on native teardown.

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
flutter build ios   # requires Xcode / Apple toolchain
```

### Android release signing (in-app / OTA updates)

The built-in updater installs a new APK over the old one. **Android only allows that if both APKs are signed with the same key.** Debug-signed builds and release-signed builds use different keys; mixing keys forces an uninstall first.

**Local release builds**

1. Generate a keystore once (keep a secure backup; losing it blocks updates forever):

   `keytool -genkeypair -v -keystore android/release.keystore -alias playtorrio -keyalg RSA -keysize 2048 -validity 10000`

2. Copy `android/key.properties.example` to `android/key.properties` and set `storePassword`, `keyPassword`, `keyAlias`, and `storeFile` (paths in `storeFile` are relative to the `android/` folder). Both files are gitignored.

3. Run `flutter build apk --release` as usual.

**GitHub Actions**

Add repository **secrets** (Settings → Secrets and variables → Actions):

| Secret | Purpose |
|--------|---------|
| `ANDROID_KEYSTORE_BASE64` | Base64-encoded contents of your `.keystore` / `.jks` file |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_PASSWORD` | Key password |
| `ANDROID_KEY_ALIAS` | Optional; default `playtorrio` |

Encode the keystore: `base64 -w0 android/release.keystore` (Linux) or `[Convert]::ToBase64String([IO.File]::ReadAllBytes("android\release.keystore"))` (PowerShell).

If `ANDROID_KEYSTORE_BASE64` is **not** set, CI still produces an APK signed with the **debug** key (fine for testing; users cannot upgrade from a future release-signed build without reinstalling).

## License


GPL-2.0 license