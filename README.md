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
- Conan **owns all timing** and writes completed frames to watson when intervals close —
  it never calls `watson start`/`stop` and never touches watson's running state. Side
  frames are tagged `+conan` so you can spot them in `watson report`/`watson log`.
- **Tags** set on a project (main or side) pass straight through to watson's frames and
  show up in the daily summary's per-tag breakdown.
- A live **today** report (from `watson report --day --json`) shows committed time, broken
  down by project and tag. The in-progress session is written to watson when you stop it.

## Requirements

- macOS 13+ (uses SwiftUI `MenuBarExtra`)
- `watson` on `PATH` — `brew install watson`

## Build & run

```sh
swift test            # run the unit tests
./scripts/build-app.sh   # build + assemble + ad-hoc sign Conan.app
open Conan.app           # launch (menu-bar only, no dock icon)
```

To sign with your own identity: `SIGN_IDENTITY="Apple Development: …" ./scripts/build-app.sh`.
Install by copying `Conan.app` to `/Applications`. To start at login, add it under
System Settings → General → Login Items.

## Usage

1. Click the menu-bar timer. Type a project (or pick a recently-used project/tag
   variant — or any known project — from the chooser), add optional
   space-separated **tags**, and **Start**.
2. **Add side projects** with a percentage and optional tags; each shows its live accrued time.
3. **Stop all** ends the session; **stop** a single side project to close just that one.
4. Open the popover any time to see today's totals, broken down by project and tag.

## Settings

In the popover footer:

- **Start at login** — registers Conan as a macOS login item (`SMAppService`).
- **Remind me when I'm not tracking** — while Conan is running, if you've been
  active at the Mac for 5 minutes with no project tracked, it posts a
  notification nudge. It fires once per active streak and re-arms after you
  start tracking or step away from the Mac. Requires notification permission
  (requested when you enable it).

## Data

- Conan stores its in-flight session at `~/Library/Application Support/Conan/state.json`
  (dates as epoch seconds) and replays it on launch after a crash, flushing tracked time
  up to the last 30-second heartbeat.
- All finished time lives in watson's own store; Conan adds frames via `watson add`.
