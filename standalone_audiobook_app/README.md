# Audiobooks (standalone)

Self-contained **Flutter** app for **audiobooks**: browse and search (including **Audiobook Bay** via HTML scrape + magnet/torrent streaming), continue listening, liked titles, bookmarks, offline downloads, magnet import, and EPUB-to-audiobook generation. Extracted from PlayTorrio for use as a **separate repository**.

## Create the repo and run locally

```bash
# From a machine with Flutter + Android SDK installed
cp -r /path/to/PlayTorrioV2/standalone_audiobook_app /path/to/audiobook-app
cd /path/to/audiobook-app

# Generate android/, ios/, etc. (project ships lib/ + pubspec only)
flutter create . --project-name audiobook_app --org com.playtorrio.audiobook

flutter pub get
flutter run
```

Then `git init`, commit, and push to a new GitHub repo.

## Audiobook Bay

Catalog and search use the same client-side scraping as PlayTorrio against `https://audiobookbay.lu`. Playback resolves detail pages to magnet links and streams chapters through **libtorrent** (native/desktop/Android). Torrent playback is **not available on web**.

Browse falls back to Audiobook Bay when Tokybook returns no results; search merges Audiobook Bay with other sources and deduplicates by title.

## What is included

- `lib/screens/` — audiobook hub, player, downloads, magnet picker, generate-from-EPUB
- `lib/api/audiobook_service.dart` — all catalog sources (ABB scrape, Tokybook API, etc.)
- `lib/api/torrent_stream_service*.dart` — libtorrent streaming for ABB and magnets
- `lib/api/local_server_service*.dart` — minimal Tokybook audio proxy (localhost)
- `lib/api/settings_service.dart` — audiobook prefs + torrent cache settings
- `lib/services/playtorrio_cloud_sync_service.dart` — no-op stub (local prefs only)

## Syncing with main PlayTorrio

The canonical source of truth is still `PlayTorrioV2/lib/screens/audiobook_*.dart`, `lib/api/audiobook_*.dart`, and related widgets. When you change audiobooks upstream, re-copy those files into this project and keep the minimal stubs in `lib/api/settings_service.dart`, `lib/main.dart`, etc.

## GitHub Actions

Workflow **Build Audiobook APK** (`.github/workflows/standalone_audiobook_app_apk.yml`) runs `flutter create` in `standalone_audiobook_app/` and builds a **release APK**.

- **Actions** → **Build Audiobook APK** → **Run workflow** (after merged to default branch)
- Or push a change under `standalone_audiobook_app/` to run automatically

## License

Match the parent PlayTorrio / your fork’s license when you publish the new repository.
