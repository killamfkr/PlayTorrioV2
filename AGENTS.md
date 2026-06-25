# AGENTS.md

## Cursor Cloud specific instructions

PlayTorrio is a **Flutter** app (Dart SDK `^3.11.0`). CI pins **Flutter 3.41.0 stable**
(`.github/workflows/build.yml`), which is what is installed here. `flutter` and `dart`
are on `PATH` (symlinked into `/usr/local/bin`). The update script runs `flutter pub get`.

### Standard commands
- Dependencies: `flutter pub get`
- Lint: `flutter analyze` (the repo has ~97 pre-existing info/warning lints and no errors)
- Tests: `flutter test`
- Build targets: see `README.md` ("Building") and `.github/workflows/build.yml`.

### Running the app in this headless VM (use the Linux desktop target)
The documented **web** build (`flutter build web` / `flutter run -d ... chrome`) currently
**fails to compile on `main`** — `media_kit`'s web `NativePlayer` stub lacks
`setProperty`/`getProperty`/`command`, plus two 64-bit int literals can't be represented
in JavaScript. This is a pre-existing app bug, reproduced by the `docker-web` CI workflow;
it is not an environment problem. Run the **Linux desktop** build instead (the native code
compiles fine — those errors are web-target-only).

The Linux platform folder (`/linux/`) is git-ignored and generated on the fly. If it is
missing, recreate it with `flutter create --platforms=linux .` (then `flutter pub get`),
exactly like the commented-out CI Linux job and the standalone scraper README do.

Run it with the helper (already in the home dir): `~/run_playtorrio.sh`
(it `tee`s logs and runs `flutter run -d linux`). It exists because two services must be
running first, otherwise the app gets stuck or blocked:

1. **NetworkManager** (for `connectivity_plus`). Without it the splash hangs at
   `[Boot] Step 1: Checking network connectivity...` (the check throws). Start once per VM:
   `sudo dbus-daemon --system --fork` (if `/run/dbus/system_bus_socket` is missing) then
   `sudo NetworkManager --no-daemon &`. When running, the boot log prints
   `[Boot] Network status: ONLINE`.
2. **An unlocked passwordless gnome-keyring** on a D-Bus *session* bus (for
   `flutter_secure_storage`). Without it a "Choose password for new keyring" GUI dialog
   pops up and blocks the UI. `~/run_playtorrio.sh` handles this via `dbus-launch` +
   `printf '\n' | gnome-keyring-daemon --unlock`.

The GUI renders on `DISPLAY=:1` (the same display the computer-use tooling drives).

### Notes
- First screen is **"WHO'S WATCHING?"** — pick a local profile (e.g. Profile 1); no
  account/login is required. The TMDB API key is hardcoded, so movie/TV content loads
  with no secrets.
- The connectivity check (and thus NetworkManager) is only hit *after* a profile is
  selected, not on the initial profile screen.
- Harmless runtime log noise: `ALSA ... cannot find card`, `Failed to attach mixer`
  (no audio device), and `libEGL ... DRI3` (software rendering).
