# PlayTorrio TV (Kotlin)

Native **Android TV** shell for PlayTorrio, intended as a **separate repository** from the Flutter codebase.

This is a **starting point**: Gradle project, TV manifest, Compose for TV navigation scaffold, and package `com.playtorrio.tv`. Port features incrementally from the Flutter app.

## Use as another repository

```bash
cd /path/to/parent
cp -r path/to/PlayTorrioV2/kotlin-android-tv playtorrio-android-tv
cd playtorrio-android-tv
git init
git add .
git commit -m "Initial Android TV Kotlin scaffold"
git remote add origin https://github.com/YOUR_ORG/playtorrio-android-tv.git
git push -u origin main
```

Or create an empty repo on GitHub and push this folder’s contents into it.

## Open in Android Studio

1. **File → Open** → select the `kotlin-android-tv` directory (not the Flutter repo root).
2. Let Gradle sync. If `gradlew` is missing, Android Studio usually generates it; or install Gradle locally and run `gradle wrapper --gradle-version 8.9` in this folder.
3. Run on an **Android TV** emulator or device (API 24+).

## What’s included

- `LEANBACK` launcher, touchscreen not required, TV banner.
- Jetpack **Compose** + **Compose Material3** + TV-friendly theme.
- Min SDK **24**, compile/target **35**, Kotlin **2.0**, Java **17**.

## Next steps (suggested)

- Integrate **media playback** (e.g. Media3 / ExoPlayer) for IPTV and local streams.
- Add **Supabase** Kotlin client for auth + sync (mirror `PlaytorrioCloudSyncService` concepts).
- Implement **browse / details** flows using `androidx.tv` libraries when you adopt the TV-specific UI kit.

## License

Match the parent PlayTorrio project’s license when you split this into its own repo.
