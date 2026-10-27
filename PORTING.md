# Porting Kove to Windows

This document is the spec for a Windows port. It is written so an agent (or a
person) with no memory of the macOS work can implement it without re-deriving
decisions, and without reading every Swift file.

**Status:** not started. The macOS app is the reference implementation and is the
only thing in this repository today.

---

## 1. What Kove is

A pill-shaped overlay fused to the top edge of the screen that expands into a small
panel showing either:

- **Now playing** — whatever player owns the media session (Apple Music, Spotify, …):
  artwork, title, artist, album, scrubbable progress, play/pause/next/previous.
- **Command Code usage**: session (5 h) and weekly credit windows, credits left,
  reset countdowns, request count, success rate.

It lives only in the notification area — no taskbar button, no main window.

## 2. Ground rules

1. **Do not modify `Sources/`, `Resources/Info.plist`, `build.sh` or
   `Tools/MakeIcon.swift`.** They are the reference implementation.
2. **Match behaviour, not implementation.** SwiftUI view structure does not need to
   survive; the geometry, timings and interactions in §6 do.
3. **No mock data in shipping code.** Any demo data must sit behind a debug-only
   flag (macOS does this with `--demo`).
4. **No Apple APIs through shims.** Use the native Windows API for each job — the
   mapping in §4 is deliberate.
5. Windows only: do not add cross-platform abstractions. A separate port beats a
   shared layer here.

## 3. Acceptance checklist

The port is done when all of these pass on a Windows 11 machine.

- [ ] A pill appears at the top of the chosen display while media is loaded, with no
      window frame, and no taskbar button or entry in Alt-Tab for it.
- [ ] Clicking the pill expands it to a 420 × 178 panel; clicking again collapses it.
- [ ] A click outside the pill but inside the overlay window reaches the app
      underneath (the transparent margin is click-through).
- [ ] The overlay never steals focus: the previously focused app keeps its caret,
      keyboard focus and window shadow.
- [ ] Once expanded, artwork, title, artist, album, elapsed/total time, and working
      transport buttons are shown; dragging the progress bar seeks.
- [ ] Pressing play in **any** SMTC-capable app (Spotify, Apple Music, a browser)
      puts the pill on screen in well under a second.
- [ ] Pausing keeps the pill on screen (so playback can be resumed from it); having
      no media session at all hides it.
- [ ] Opening a full-screen app (video player, game, presentation) hides the overlay
      within ~250 ms, and it comes back afterwards.
- [ ] Command Code usage renders session/week percentages, credits used, reset
      countdowns, request count and success rate, refreshing every 60 s while shown.
- [ ] Tray icon menu has Expand/Collapse, Open Player, Settings…, Quit.
- [ ] Settings window shows both source toggles, the full-screen toggle and a live
      island preview, and survives a restart.
- [ ] With both sources off, the overlay disappears and the tray menu still works.

## 4. Platform mapping

| macOS (reference) | Windows | Notes |
| --- | --- | --- |
| `NSPanel` borderless, `.statusBar` level, `canBecomeKey = false` | `HWND` + `WS_EX_TOPMOST \| WS_EX_TOOLWINDOW \| WS_EX_NOACTIVATE`, `WM_MOUSEACTIVATE → MA_NOACTIVATE` | `WS_EX_LAYERED` for per-pixel alpha |
| `IslandContainerView.hitTest` | `WM_NCHITTEST` → `HTTRANSPARENT` outside the island rect, `HTCLIENT` inside | this is what makes the margin click-through |
| `.canJoinAllSpaces` | no public API; undocumented `IVirtualDesktopManagerInternal` or accept per-desktop | see §8 |
| notch from `auxiliaryTopLeftArea` / `safeAreaInsets.top` | Win11 `DisplayArea` (`Bounds` vs `WorkArea`); most PCs have none | fall back to a top-centre pill on a user-chosen monitor |
| `FullScreenMonitor` (CGWindowList) | `SHQueryUserNotificationState`: `QUNS_RUNNING_D3D_FULL_SCREEN`, `QUNS_PRESENTATION_MODE`, `QUNS_BUSY` | more reliable than the macOS heuristic |
| `activeSpaceDidChange` / `didActivateApplication` | `SetWinEventHook(EVENT_SYSTEM_FOREGROUND)` + 250 ms timer | |
| `MediaService` + one adapter per player (`AppleMusicPlayer`, `SpotifyPlayer`) driving `osascript`, plus per-player change notifications | `Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager` | **one** API covers Music, Spotify, browsers and VLC, so the whole adapter layer collapses into a single service |
| `TrackInfo.artworkURL` / AppleScript artwork export | `MediaProperties.Thumbnail` | no download step needed |
| `AppleScriptRunner` | delete | no subprocess, no permission prompt |
| `CommandCodeUsageService` (`URLSession`) | `HttpClient`, same endpoints and JSON | |
| `UserDefaults` (`com.kove.island`) | JSON at `%APPDATA%\Kove\settings.json` | same three keys |
| `NSStatusItem` + `NSMenu` | `Shell_NotifyIcon` + `TrackPopupMenu`, or `H.NotifyIcon` | |
| `LSUIElement` | no taskbar button (`WS_EX_TOOLWINDOW`, `ShowInTaskbar = false`) | |
| `icns`, template glyph | `Resources/AppIcon.ico`, `Resources/TrayIcon-{Black,White}.ico` | Windows does not tint tray icons — switch on `SystemUsesLightTheme` |

## 5. Suggested stack

**C# / .NET 8 + WPF.** WPF gives transparent, borderless, always-on-top windows and
per-region hit testing with almost no ceremony, which is exactly the shape of this
app; WinUI 3 makes transparency and `HWND` styling harder for no benefit here.
Reach into WinRT for the media session (`Windows.Media.Control`) and P/Invoke for
`SHQueryUserNotificationState`, `Shell_NotifyIcon` and the window styles.

Electron/Tauri would work (transparent + `setIgnoreMouseEvents(forward: true)`) but
you still need a native module for SMTC, so you pay the runtime weight for nothing.

## 6. Behaviour and constants to match

**Geometry** (device-independent pixels, at 100 % scaling):

| Thing | Value |
| --- | --- |
| Collapsed pill | notch width + 2 × 32 wide, notch height (32) tall |
| Collapsed bottom corner radius | 12 |
| Expanded panel | 420 × 178 |
| Expanded bottom corner radius | 26 |
| Header strip / content row | 32 (or 26 without a notch) / 146 |
| Overlay window | expanded size + 96 × 92 padding, centred on the notch, top edge on the screen's top edge |

The panel's top edge is flush with the screen's top edge and only the bottom corners
are rounded — the shape is "hanging" from the edge, not a floating capsule.

**Timings:**

| Behaviour | Value |
| --- | --- |
| Fade in / out | 180 ms ease-out / 140 ms ease-in |
| Expand / collapse animation | spring-ish, ~300 ms; expand may overshoot, collapse must not |
| Quiet period before showing | 3 × 100 ms of "no full-screen app" |
| Visibility poll ("watchdog") | every 250 ms |
| Media poll backstop | 1.8 s while playing, 2.5 s idle (events make this a backstop) |
| Usage refresh | 60 s, only while the usage source is visible |
| Seek settle | ~350 ms before trusting the reported position again |

**States:**

- A player has a track (paused counts) → pill visible.
- No media session anywhere → hide and collapse.
- Two players → the one that is *playing* wins; otherwise keep the current one, so the
  pill does not flip between two idle players.
- Full-screen app (and the opt-in setting) → hide immediately; showing requires the
  quiet period.
- Both sources off → hide, and collapse.
- Media session events → re-evaluate visibility immediately, skipping the quiet
  period (that delay exists to avoid flashing during window transitions).

**Content:**

- Expanded header: source name, `NOW PLAYING` / `COMMAND CODE`, and a segmented
  switcher (only when more than one source is enabled).
- Now playing: 96 px artwork tile, three text lines (title, artist, album), progress
  bar with elapsed/total, prev/play-pause/next.
- Usage: plan name + renewal date, credits left, `SESSION` and `WEEK` columns with
  percent, used/cap, a bar, and a reset countdown, then requests / success rate /
  updated time.

## 7. Project layout

Mirror the macOS tree so the two can be read side by side:

```
windows/
├── Kove.Windows.sln
├── src/Kove.App/
│   ├── App.xaml(.cs)                  ← main.swift + AppDelegate.swift
│   ├── Island/
│   │   ├── IslandWindow.xaml(.cs)     ← IslandPanel + IslandContainerView
│   │   ├── IslandViewModel.cs         ← IslandController
│   │   ├── IslandPreferences.cs
│   │   ├── CollapsedView / ExpandedView / MediaView / UsageView.xaml
│   │   └── Theme.xaml                 ← Theme.swift + IslandShape as Geometry
│   ├── Settings/                      ← SettingsView + live preview
│   ├── Shell/TrayIcon.cs              ← StatusItemController
│   ├── Services/
│   │   ├── MediaSessionService.cs     ← Services/Media (all players, one service)
│   │   ├── CommandCodeUsageService.cs
│   │   └── FullScreenMonitor.cs
│   └── Assets/                        ← copy the .ico files from Resources/
```

## 8. Known hard parts

- **All virtual desktops.** A topmost window belongs to one desktop. Options: accept
  it (document it), or use the undocumented desktop GUID APIs (fragile per Windows
  build). Do not block the rest of the port on this.
- **No notch.** Windows laptops rarely have one; use the work-area inset if the OS
  reports one, otherwise hang the pill from the top edge of a monitor the user picks
  in Settings. Add that monitor picker — multi-monitor is the common case on Windows.
- **Taskbar auto-hide and maximised windows** can both sit over the top edge; the
  overlay should still be above them, which is what `WS_EX_TOPMOST` plus a periodic
  `SetWindowPos(HWND_TOPMOST)` reassert handles.
- **DPI changes and monitor hot-plug** require recomputing the overlay rect; hook
  `WM_DISPLAYCHANGE` and `WM_DPICHANGED`.
- **Fullscreen browsers** report `QUNS_BUSY`, not `QUNS_RUNNING_D3D_FULL_SCREEN`;
  treat both as full screen.
- **SMTC has no "which player is paused" bias knob.** Session precedence is whatever
  `GetCurrentSession()` reports; if a paused session keeps winning over a playing one,
  scan `GetSessions()` and prefer a session whose `PlaybackInfo.PlaybackStatus` is
  `Playing`.

## 9. Credentials and settings

- Command Code: `COMMAND_CODE_API_KEY` env var, else `%USERPROFILE%\.commandcode\auth.json`
  with an `apiKey` field (same file the CLI writes). Never store the key yourself.
- Settings JSON at `%APPDATA%\Kove\settings.json`:
  `{ "enabledSources": ["music", "commandCode"], "mode": "music", "hideOverFullScreen": true }`.

## 10. Definition of done

1. Everything in §3 passes.
2. `dotnet build -c Release` and `dotnet publish` produce a runnable app.
3. A `windows.yml` workflow builds on `windows-latest` so regressions are caught.
4. Screenshots of the collapsed pill, expanded panel and settings window are
   committed to `docs/windows/` and linked from the README.
