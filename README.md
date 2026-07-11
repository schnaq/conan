# Conan

A macOS **menu-bar** time tracker for working several projects in parallel — built for
the "one main project, agents running, you pick up side work in the gaps" workflow.
Conan layers on top of [`watson`](https://github.com/jazzband/Watson): everything it
tracks lands in watson, so `watson report --day` keeps working as before.

## How it works

- **Main project** is tracked 1:1, exactly like watson today (1h worked → 1h tracked).
- **Side projects** accrue a **percentage** of main time while switched on, *additively*
  (main keeps its full hour; the side time is extra). 10% → every hour on main adds 6 min.
  Forward-only: a side project accrues only from the moment you start it.
- **Stop** the main project (stops everything) or any side project individually.
- Conan **owns all timing** and appends completed frames straight into watson's `frames`
  file when intervals close (no `watson` binary or Python needed). Side frames are tagged
  `+conan` so you can spot them in `watson report`/`watson log`.
- **Terminal-aware:** Conan keeps watson's running-frame `state` in sync, so
  `watson start <project>` in the terminal shows up in Conan (marked *started in terminal*)
  and `watson stop` stops it there too. The running frame is closed **exactly once** — by
  whoever stops it, Conan or the CLI — so time is never double-counted. While a session is
  running the frame is "taken", so a second terminal `watson start` is refused until you stop.
- **Tags** set on a project (main or side) pass straight through to watson's frames and
  show up in the daily summary's per-tag breakdown.
- A live **today** report (from `watson report --day --json`) shows committed time, broken
  down by project and tag. The in-progress session is written to watson when you stop it.

## Requirements

- macOS 13+ (uses SwiftUI `MenuBarExtra`)
- **No external dependencies.** Conan reads and writes watson's data file
  (`~/Library/Application Support/watson/frames`) directly, so a `watson` install
  is optional. If you do have the `watson` CLI, Conan shares its data — `watson
  report --day` keeps working alongside Conan, and vice versa.

## Install via Homebrew

> Available once the [`schnaq/homebrew-tap`](https://github.com/schnaq/homebrew-tap) repo
> exists — the cask lives in this repo at `packaging/homebrew/conan.rb` and is synced
> there on each release.

```sh
brew tap schnaq/tap
brew install --cask conan
```

Note: homebrew-core ships a `conan` *formula* (the C++ package manager). The cask is
namespaced by the tap, so `brew install --cask schnaq/tap/conan` always resolves
unambiguously. Conan self-updates via Sparkle (`auto_updates true`), so `brew upgrade`
leaves it alone unless you pass `--greedy`.

## Build & run

```sh
swift test            # run the unit tests
./scripts/build-app.sh   # build + assemble + ad-hoc sign Conan.app
open Conan.app           # launch (menu-bar only, no dock icon)
```

To sign with your own identity: `SIGN_IDENTITY="Apple Development: …" ./scripts/build-app.sh`.
Install by copying `Conan.app` to `/Applications`. To start at login, add it under
System Settings → General → Login Items.

## Distribution (signed + notarized DMG)

`build-app.sh` ad-hoc signs, which only runs cleanly on the build machine. To hand the app
to other Macs without Gatekeeper warnings, `scripts/release.sh` builds a **universal**
(arm64 + x86_64), Developer-ID-signed, **notarized**, stapled `dist/Conan.dmg`.

One-time setup (needs a paid Apple Developer Program membership):

1. Create a **Developer ID Application** certificate — Xcode → Settings → Accounts → your
   team → Manage Certificates → **+** → Developer ID Application. (This is *different* from
   the "Apple Distribution" cert used for the App Store / iOS.) Find its name with
   `security find-identity -v -p codesigning | grep "Developer ID Application"`.
2. Create an app-specific password at appleid.apple.com (or an App Store Connect API key).
3. Store notary credentials once (Team ID must match the cert):

   ```sh
   xcrun notarytool store-credentials "conan-notary" \
     --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-password"
   ```

Then build the release:

```sh
DEV_ID="Developer ID Application: Your Name (TEAMID)" ./scripts/release.sh
# → dist/Conan.dmg  (signed, notarized, stapled, universal)
```

Recipients double-click the DMG and drag Conan to Applications — no warnings.
`SKIP_NOTARIZE=1` produces a signed-but-not-notarized build for local inspection.

### Cutting a versioned GitHub release

`scripts/publish.sh` wraps the whole flow: it auto-detects your installed Developer ID
identity, stamps the version into `Info.plist`, builds the notarized DMG (via `release.sh`),
then commits the version bump, tags, pushes, and creates a GitHub release with the DMG
attached.

```sh
./scripts/publish.sh 0.2.0      # needs a clean working tree; a leading "v" is fine too
```

It also stamps the new version + DMG sha256 into the Homebrew cask
(`packaging/homebrew/conan.rb`, part of the release commit) and, after the GitHub release
is up, syncs the cask into a local clone of `schnaq/homebrew-tap` and pushes it (looked
for at `../homebrew-tap`, override with `TAP_DIR=…`). No tap clone present → the release
still succeeds and `scripts/update-cask.sh` prints the manual steps.

`DRY_RUN=1 ./scripts/publish.sh 0.2.0` builds and previews everything without committing,
tagging, pushing, or releasing.

### Auto-update (Sparkle)

Conan self-updates via [Sparkle](https://sparkle-project.org). It reads the appcast at
`https://github.com/schnaq/conan/releases/latest/download/appcast.xml`, and when a newer build
is published it downloads, verifies (EdDSA + Developer ID), installs, and relaunches — gated by
the **Automatically check for updates** toggle, with a manual **Check for Updates…** button in
the popover footer. Sparkle compares the monotonic `CFBundleVersion`.

`publish.sh` handles the release side: it generates an EdDSA-signed `appcast.xml` (via Sparkle's
`generate_appcast`) pointing at the new DMG and uploads it alongside `Conan-X.Y.Z.dmg`.
`scripts/embed-sparkle.sh` embeds + inside-out-signs `Sparkle.framework` into the bundle (called
by both `build-app.sh` and `release.sh` before the app is signed).

One-time setup (already done for this repo): a Sparkle EdDSA key pair was created with
`generate_keys` — the private key lives in the login keychain (needed by `publish.sh`), and the
public key is in `Info.plist` as `SUPublicEDKey`.

## Usage

1. Click the menu-bar timer. Type a project (or pick a recently-used project/tag
   variant — or any known project — from the chooser), add optional
   space-separated **tags**, and **Start**.
2. **Add side projects** with a percentage and optional tags; each shows its live accrued time.
3. **Stop all** ends the session; **stop** a single side project to close just that one.
4. Open the popover any time to see today's totals, broken down by project and tag.

You can also `watson start`/`watson stop` from the terminal — Conan picks the change up
automatically (instantly when you open the popover, otherwise within ~30 s).

## Settings

In the popover footer:

- **Start at login** — registers Conan as a macOS login item (`SMAppService`).
- **Remind me when I'm not tracking** — while Conan is running, if you've been
  active at the Mac for 5 minutes with no project tracked, it posts a
  notification nudge. It fires once per active streak and re-arms after you
  start tracking or step away from the Mac. Requires notification permission
  (requested when you enable it).
- **Automatically check for updates** — Conan checks GitHub for newer releases (via Sparkle)
  and offers to install them. Use **Check for Updates…** for a manual check.

## Data

- Conan stores its in-flight session at `~/Library/Application Support/Conan/state.json`
  (dates as epoch seconds) and replays it on launch after a crash, flushing tracked time
  up to the last 30-second heartbeat.
- The running session is mirrored into watson's own `state` file
  (`~/Library/Application Support/watson/state`) to keep the `watson` CLI in sync. On launch
  Conan reconciles the two: if `watson stop` ran while Conan was closed, the main frame
  watson already wrote is **not** re-counted (only side-project time is flushed).
- Finished time is appended directly to watson's `frames` file (same JSON format watson
  uses), so the `watson` CLI reads it natively — no separate watson install required.
