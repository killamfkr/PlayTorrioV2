# Stories

Standalone **Flutter** audiobook player — browse Audiobook Bay, stream via torrent, save bookmarks/favorites/progress, and sync across devices with email login.

## Publish as its own GitHub repo

This folder is designed to be a **separate repository**. It does not depend on the PlayTorrio monorepo at runtime.

### Option A — New repo from this folder (recommended)

```bash
# 1. Copy the app folder anywhere you like
cp -r /path/to/PlayTorrioV2/standalone_audiobook_app ~/stories-app
cd ~/stories-app

# 2. Initialize git (skip if you used git filter-repo / subtree — see Option B)
git init
git add .
git commit -m "Initial commit: Stories audiobook app"

# 3. Create an empty repo on GitHub (no README), then:
git remote add origin https://github.com/YOUR_USER/stories.git
git branch -M main
git push -u origin main
```

CI is included at `.github/workflows/build_apk.yml` — it builds a release APK on every push to `main`.

### Option B — Split history from PlayTorrioV2 (keeps commits)

From the PlayTorrioV2 repo root:

```bash
git subtree split --prefix=standalone_audiobook_app -b stories-standalone
git push https://github.com/YOUR_USER/stories.git stories-standalone:main
```

### Option C — GitHub “Import repository”

1. Push PlayTorrioV2 to GitHub (if not already).
2. Use **Import** or clone, then keep only `standalone_audiobook_app/` as the root of a new repo (copy files + new `git init` as in Option A).

---

## Run locally

Requires **Flutter 3.41+** and Android SDK for mobile builds.

```bash
cd stories-app   # or standalone_audiobook_app inside the monorepo

# Generate android/ + ios/ (not checked in — keeps the repo small)
flutter create . --project-name audiobook_app --org com.playtorrio.audiobook
bash tool/patch_android.sh

flutter pub get
dart run flutter_launcher_icons   # optional: regenerate launcher icons
flutter run
```

`tool/patch_android.sh` sets `MainActivity` to extend `AudioServiceActivity` so lock-screen controls work.

## Build release APK

```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

Or use **Actions → Build APK → Run workflow** on GitHub.

## Features

- Audiobook Bay catalog + search (HTML scrape)
- Magnet / torrent chapter streaming (Android, desktop — not web)
- Continue listening, liked titles, bookmarks
- Cloud sync (Supabase email/password — same backend as PlayTorrio, optional)
- Literary character profile avatars
- Offline downloads, magnet import, EPUB → audiobook generation

## Cloud sync (optional)

Sign in under **Settings** to sync bookmarks, favorites, and progress. Uses PlayTorrio’s Supabase project by default; override at build time:

```bash
flutter build apk --release \
  --dart-define=PLAYTORRIO_SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=PLAYTORRIO_SUPABASE_ANON_KEY=your_anon_jwt
```

## Project layout

| Path | Purpose |
|------|---------|
| `lib/screens/` | Library, player, settings, downloads |
| `lib/api/` | Catalog, playback, torrent engine |
| `lib/services/` | Cloud sync |
| `tool/patch_android.sh` | AudioService + notification fix for Android |
| `.github/workflows/build_apk.yml` | CI APK build |

## Forking from PlayTorrio

If you maintain both repos: audiobook changes historically lived in `PlayTorrioV2/standalone_audiobook_app/`. After splitting, treat **this repo as the source of truth** for Stories, or periodically merge from the monorepo subtree.

## License

GPL-2.0 — see [LICENSE](LICENSE) (same as PlayTorrioV2).
