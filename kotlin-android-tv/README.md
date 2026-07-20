# PlayTorrio (Kotlin) — Android & Android TV

Native Kotlin / Jetpack Compose app for **phones, tablets, and Android TV**. Port of the core PlayTorrio streaming experience from the Flutter app.

**Package:** `com.playtorrio.tv`

## Features

- **Home** — TMDB trending / popular / now playing / top rated, continue watching
- **Search** — TMDB multi-search
- **Details + Play** — IMDb-backed Stremio addon streams via Media3 (ExoPlayer + HLS)
- **Stremio addons** — install/remove manifests (defaults to `https://dlstreams.top/manifest.json`)
- **IPTV** — full Xtream live / movies / series + M3U playlists, favorites, short EPG
- **Dual UI** — bottom nav on phone; side nav + D-pad focus on Android TV
- Leanback launcher + phone launcher in one APK

## Open in Android Studio

1. **File → Open** → select this `kotlin-android-tv` directory (not the Flutter repo root).
2. Sync Gradle, then run on a phone emulator, device, or Android TV emulator (API 24+).

```bash
./gradlew :app:assembleDebug
# APK: app/build/outputs/apk/debug/app-debug.apk

./gradlew :app:assembleRelease
```

## Architecture

```
app/src/main/java/com/playtorrio/tv/
  data/          TMDB, Stremio, IPTV, prefs, watch history
  ui/            Compose screens + Media3 PlayerActivity
  util/          TV detection
```

Streams use the Stremio protocol: `{addon}/stream/movie|series/{imdbId[:s:e]}.json` with optional `behaviorHints.proxyHeaders.request` passed into ExoPlayer.

## Split into its own repo

```bash
cp -r kotlin-android-tv playtorrio-android-native
cd playtorrio-android-native
git init && git add . && git commit -m "PlayTorrio Kotlin Android + TV"
```

## License

Same as the parent PlayTorrio project.
