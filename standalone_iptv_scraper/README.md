# PT IPTV Scraper (standalone)

Self-contained **Flutter** app: **PT IPTV** (portal list, Reddit/catalog scraper, live/VOD/series browser, channels hub, `media_kit` player). Extracted from PlayTorrio for use as a **separate repository**.

## Create the repo and open in Android Studio

```bash
# From a machine with Flutter + Android SDK installed
cp -r /path/to/PlayTorrioV2/standalone_iptv_scraper /path/to/iptv-scraper-app
cd /path/to/iptv-scraper-app

# Generate android/, ios/, etc. (project ships lib/ + pubspec only)
flutter create . --project-name iptv_scraper_app --org com.playtorrio.iptvscraper

flutter pub get
flutter run
```

Then `git init`, commit, and push to a new GitHub repo.

## What is included

- `lib/features/iptv/playtorrio_tv/` — copied from PlayTorrio (updated imports for this package)
- `lib/api/settings_service.dart` — minimal (background-play toggle for the player)
- `lib/services/playtorrio_cloud_sync_service.dart` — no-op stub (favorites are local only here)
- `lib/services/built_in_video_media_session.dart` — no-op (no AudioService in this app)
- `lib/platform_flags.dart`, `lib/utils/device_profile.dart` — lightweight; TV detection defaults to false unless you add a `MethodChannel` in `MainActivity` like the main app

## Syncing with main PlayTorrio

The canonical source of truth for the feature is still `PlayTorrioV2/lib/features/iptv/playtorrio_tv/`. When you change it upstream, re-copy that folder into this project’s `lib/features/iptv/` and re-apply any import path tweaks (this tree uses `../../` to `lib/` instead of deep `../../../..` from the monolith).

## GitHub Actions

In the PlayTorrio repo, workflow **Build IPTV Scraper APK** (`.github/workflows/standalone_iptv_scraper_apk.yml`) runs `flutter create` in `standalone_iptv_scraper/` and builds a **release APK**. Trigger manually via **Actions → Build IPTV Scraper APK → Run workflow**, or push changes under `standalone_iptv_scraper/`. The artifact is named `IPTV-Scraper-Android-universal`.

## License

Match the parent PlayTorrio / your fork’s license when you publish the new repository.
