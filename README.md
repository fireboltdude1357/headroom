# Headroom

A Mac app that explains where your disk space went and clears the parts that are safe to clear. It's our own take on [Macaroom](https://getmacaroom.com).

Apple's Storage settings lump most of it into one grey "System Data" bar. Headroom splits that into named sources: Xcode build data, the npm cache, Chrome's cache, a two-year-old iPhone backup. For each one it says what clearing it does.

## What it does

- **Named sources.** About 35 catalogued locations for developer tools, app caches, app data and device files. It also discovers per-app caches, old installers in Downloads, iPhone and iPad backups, and data left behind by deleted apps.
- **Project build folders.** It finds `node_modules`, `target`, `.build`, `.venv`, `Pods`, `.next` and Gradle `build` folders. A folder only counts when the project's own files confirm it, such as `package.json` next to `node_modules` or `CACHEDIR.TAG` inside Cargo's `target`. Projects nobody has touched in 90 days get flagged, and one button selects them all.
- **Safe cleanup.** Nothing is ever preselected. You review a plan grouped by consequence (rebuildable, can be downloaded again, leftover, personal data). Right before moving each item, Headroom checks it again. It skips items whose app is open or whose identifying file is gone. Everything goes to the Trash, and the Trash tab puts items back in one click. Photos, Mail, Messages, iCloud Drive, Docker's disk image and simulator devices can't be selected. Headroom points you to the right setting instead.
- **Menu bar panel.** Free space, the change since the last scan, a fill-date estimate from recent scans and a short "Worth a look" list. An optional weekly background check, plus an alert when free space drops under 10%.
- **Example data.** "Try example data" runs the whole interface on a made-up Mac without touching your disk.

It never makes network requests. Full Disk Access is optional. Without it, Headroom skips Mail, Messages, device backups and app containers, and lists what it couldn't read.

## Layout

| Path | What it is |
| --- | --- |
| `Sources/HeadroomCore` | Scanning, the source catalog, project detection, cleanup, the Trash log and history. No UI. |
| `Sources/Headroom` | The SwiftUI app: main window, menu bar panel and settings. |
| `Tests/HeadroomCoreTests` | Swift Testing tests for detection, cleanup safety checks and trends. |
| `scripts/bundle.sh` | Builds a universal `dist/Headroom.app` and `dist/Headroom.dmg`: signed, notarized and stapled once `setup-signing.sh` has run, ad-hoc signed otherwise. |
| `scripts/make-icon.swift` | Regenerates `Resources/AppIcon.icns`. |
| `site/` | The website, a Vite + React + Tailwind page served from Vercel project `headroom`. |

## Build

Requires macOS 14 or later and Xcode 16 or later.

```sh
swift test                 # core tests
swift run Headroom         # run unbundled (notifications and login item are disabled)
scripts/bundle.sh          # dist/Headroom.app and dist/Headroom.dmg
open dist/Headroom.app
```

`bundle.sh` ad-hoc signs by default, so Gatekeeper blocks a downloaded copy until the user clicks Open Anyway in System Settings > Privacy & Security. A release that opens normally needs a Developer ID Application certificate. Only the Apple Developer account holder can create one (Xcode > Settings > Accounts > Manage Certificates). Then run the setup once in Terminal on that Mac:

```sh
APPLE_ID=you@example.com scripts/setup-signing.sh
```

It copies the identity into a separate keychain that `bundle.sh` can unlock over SSH, and stores notarization credentials there. From then on `bundle.sh` signs, notarizes and staples on its own.

`swift run Headroom --snapshot /tmp/shots` renders every screen with example data to PNGs, in light and dark mode.

Headroom measures allocated file sizes itself, so its totals won't match Storage settings exactly. macOS counts local snapshots and purgeable space differently. A file hard-linked inside one folder counts once. Links shared between folders (a pnpm store and a project's `node_modules`) and APFS clones still count in each place. That's why cleanup reports space as "up to" what you'll get back.

The first scan looks inside Documents, Desktop, Downloads and iCloud Drive, so macOS asks once for each folder unless Headroom has Full Disk Access.

## Website

The site is live at https://headroom-pink.vercel.app. `Headroom.dmg` isn't in git, so deploy from a machine that has a fresh build:

```sh
scripts/bundle.sh                        # on a Mac
cp dist/Headroom.dmg site/public/
cd site && pnpm install
vercel pull --yes --environment=production
vercel build --prod && vercel deploy --prebuilt --prod
```

`pnpm shots` in `site/` turns the PNGs from `--snapshot` into the site's WebP screenshots.
