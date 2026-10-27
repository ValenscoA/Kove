# Kove

A Dynamic Island for macOS: a black pill fused to the top edge of the notched
display that expands on hover to show what's playing in Apple Music.

## Build & run

```sh
./build.sh          # builds build/Kove.app
open build/Kove.app
open build/Kove.app --args --settings   # launch straight into the settings window
```

Requires macOS 14+ and the Swift toolchain (Command Line Tools is enough — no Xcode needed).

`Kove.app` runs as a menu bar item with no Dock icon. The menu has Expand Island,
Open Music, Settings… (⌘,), and Quit. Settings opens a real preferences window —
the app is an accessory, so there is no app menu to hang a Settings item off.

## Permissions

Kove controls Apple Music via AppleScript, so macOS asks once for Automation access
("Kove wants to control Music"). The app is ad-hoc signed, so rebuilding may cause
that prompt to appear again.

## Layout

- `Sources/Kove/Island/` — the panel, hit testing/hover handling, and the SwiftUI views
- `Sources/Kove/Island/IslandPreferences.swift` — which sources the island may show
  and the full-screen behaviour, persisted in `UserDefaults`
- `Sources/Kove/Settings/` — the preferences window and its SwiftUI form
- `Sources/Kove/Services/MusicService.swift` — Music state polling plus playback controls
- `Sources/Kove/AppDelegate.swift` — window setup and screen positioning

Music is polled lazily on a background queue (Apple Events cost ~80 ms per round trip)
and the playback position is interpolated locally between polls. Music's own
`com.apple.Music.playerInfo` notification triggers an immediate poll, so pressing
play shows up on the island in a fraction of a second instead of waiting for the
next tick.

## Icon

`Resources/AppIcon.icns` and the menu bar glyph (`Resources/StatusIcon*.png`, a
template image) are generated, not hand-drawn:

```sh
swift Tools/MakeIcon.swift                    # regenerate the shipped assets
swift Tools/MakeIcon.swift --sheet out.png    # render the design variants
```

The mark is a dark squircle with the island pill fused to its top edge and the
MacBook notch bitten out of it. All geometry lives in `Tools/MakeIcon.swift`, so
changing the pill's proportions means re-running that script.
