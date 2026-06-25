# Stories

Standalone **Flutter** audiobook player — browse Audiobook Bay, stream via torrent, save bookmarks/favorites/progress, and sync across devices with email login.

**Repository:** https://github.com/killamfkr/Stories

## Publish / update this repo

From a machine logged into GitHub as `killamfkr` (or with push access to [killamfkr/Stories](https://github.com/killamfkr/Stories)):

```bash
# From PlayTorrioV2 repo root — pushes standalone_audiobook_app/ as the Stories repo root
bash standalone_audiobook_app/tool/publish_to_stories.sh
```

If you see `git: 'subtree' is not a git command`, either install it (`sudo apt install git-subtree` on Debian/Ubuntu) or use the script above — it falls back to a plain copy + push without subtree.

**Manual publish without subtree:**

```bash
cd /path/to/PlayTorrioV2
TMP=$(mktemp -d)
rsync -a --exclude='.dart_tool' --exclude='build' --exclude='android' --exclude='ios' \
  standalone_audiobook_app/ "$TMP/"
cd "$TMP"
git init -b main
git add -A
git commit -m "Publish Stories from PlayTorrioV2"
git remote add origin https://github.com/killamfkr/Stories.git
git push -u origin main
rm -rf "$TMP"
```

Or with subtree (if installed):

```bash
cd /path/to/PlayTorrioV2
git fetch origin
git subtree split --prefix=standalone_audiobook_app -b stories-publish-main
git push https://github.com/killamfkr/Stories.git stories-publish-main:main
```

First-time setup (empty repo already created on GitHub):

```bash
cd standalone_audiobook_app
bash tool/init_standalone_repo.sh
git commit -m "Initial commit: Stories audiobook app"
git remote add origin https://github.com/killamfkr/Stories.git
git push -u origin main
```

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
