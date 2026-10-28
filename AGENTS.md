# Architecture & Technical Reference (`AGENTS.md`)

This document describes the internal architecture, hardware protocol details, and development workflows of **LogiSwipe** for AI agents and developers.

## Background: Why Logi Options Stopped Working on macOS 27

- **Logi Options 10.26.49 (`LogiMgrDaemon`)** posts synthetic dock-swipe events (`CGEvent` type `30`, gesture `23`).
- Starting in **macOS 27**, the WindowServer ignores synthetic dock-swipe gestures that do not originate from genuine Apple trackpad hardware.
- Patching `CGEvent` fields to match Apple trackpad events or re-posting them at the HID level does not bypass this check.
- **Logi Options** is discontinued, and **Logi Options+** does not support the Logitech T630 (`VendorID: 0x046D`, `ProductID: 0xB00D`).
- When Logi Options is running, the mouse firmware converts a 2-finger swipe into button 4/5 presses, which Logi's HID filter driver intercepts.
- **Without Logi Options** (app, daemon, and `Logitech Options HID Driver Extension` disabled/removed), the T630 reports raw capacitive finger coordinates via **HID Input Report 2**, which LogiSwipe reads directly.

---

## Codebase Structure

- [`Package.swift`](Package.swift) — Swift Package Manager manifest (`macOS 14+`, executable target `LogiSwipe`).
- [`Support/Info.plist`](Support/Info.plist) — App bundle metadata (`LSUIElement = true` for menu-bar-only app, version & build numbers).
- [`build.sh`](build.sh) — Builds release binary, packages `build/LogiSwipe.app`, signs it (`SIGN_IDENTITY`, defaulting to the "LogiSwipe Self-Signed" keychain identity when present, else ad-hoc `-`), and installs to `/Applications/LogiSwipe.app`.
- [`Sources/LogiSwipe/`](Sources/LogiSwipe/):
  - [`App.swift`](Sources/LogiSwipe/App.swift) — SwiftUI `MenuBarExtra` entry point (`LogiSwipeApp`), the menu bar icon (`MenuBarIcon`: a mouse outline that fills with the battery level, faded while it is unknown), `AppDelegate`, and `SettingsView` UI.
  - [`T630.swift`](Sources/LogiSwipe/T630.swift) — Opens the T630 via `IOHIDManager`, parses HID Input Report 2 for finger positions/swipes, tracks sender IDs, and applies per-device tracking speed.
  - [`EventTap.swift`](Sources/LogiSwipe/EventTap.swift) — `CGEvent.tapCreate` session event tap that intercepts and remaps clicks and scroll wheel events coming specifically from the T630's `senderIDs`.
  - [`HIDService.swift`](Sources/LogiSwipe/HIDService.swift) — Private `IOKit` symbol bindings (`IOHIDEventSystemClient*` / `IOHIDServiceClient*`) to query the T630's event service `registryID` (matching `CGEventField(87)`) and set `kIOHIDMouseAccelerationType`.
  - [`Actions.swift`](Sources/LogiSwipe/Actions.swift) — Synthesizes keyboard shortcuts (`Ctrl+Fn+Left/Right` for desktop switching, `Cmd+[/]` for Back/Forward, `Cmd+Shift+4` for Capture screen, `Ctrl+Fn+Down` for App windows) and launches `Mission Control.app` and Launchpad (`Apps.app` on macOS 26+, else `Launchpad.app`).
  - [`Settings.swift`](Sources/LogiSwipe/Settings.swift) — `ObservableObject` backed by `UserDefaults` for all user preferences.
  - [`Permissions.swift`](Sources/LogiSwipe/Permissions.swift) — Polls and requests `Input Monitoring` (`IOHIDCheckAccess` / `IOHIDRequestAccess`) and `Accessibility` (`AXIsProcessTrusted`).

---

## Hardware & Event Pipeline Details

### 1. HID Input Report 2 Layout (`T630.swift`)
The T630 (`0x046D:0xB00D`) sends touch data on report ID `2`:
- `report[0]` = `2` (Report ID)
- `report[1]` = Button bitmask (`bit 0` = left, `bit 1` = right; the mouse firmware chooses left/right based on finger position when pressing the physical click switch)
- `report[8]` = Finger presence bitmask (`bit 0` = slot 0, `bit 1` = slot 1, etc.; `0` when no fingers touch)
- `report[9...]` = 4 bytes per active finger slot in bit order: `X, Y, ?, ?` where `X` ranges roughly `0...76` across the surface width.

Report ID `3` is Battery Strength (Generic Device Controls usage `0x20`): `report[1]` = percent `0...100`. macOS doesn't surface it, so `T630.readBattery()` requests it with `IOHIDDeviceGetReport` on connect and whenever the menu opens, and `handle` picks up any report 3 the mouse sends on its own.

### 2. Click Classification (`T630.swift` & `EventTap.swift`)
- **Two-finger click**: A physical click (`leftMouseDown` or `rightMouseDown`) while the last two fingers landed within `T630.twoFingerClickWindow` (0.25 s) of each other (`fingersLandedTogether`). Measured two-finger clicks land 0.01–0.08 s apart. A finger that has been resting on the mouse while another clicks doesn't count, so that is a one-finger click. The T630 has no tap-to-click: a touch without pressing the switch never sends a button.
- **Middle click**: The T630 has no physical middle button. A single-finger click in the upper center (`pressX` in `T630.middleZoneX` `30...55` and `pressY <= T630.middleMaxY` `53`) is a middle click. Measured middle clicks land at X 34–48, Y 39–52; left and right clicks all land at Y ≥ 55. A press in the lower center can't be told from a left click.
- **Left / Right click**: Decided from the finger position, not the hardware button bit: `pressX >= T630.rightSideX` (`53`) is right, otherwise left. `pressX`/`pressY` are the finger that landed last, which is the one clicking when another rests on the mouse. Measured left clicks land at X 6–43, right clicks at 62–76; the firmware sometimes reports a left (X 43) or middle press as right. Falls back to the hardware button when no finger position is known.
- `heldAction` remembers the resolved `ClickAction` on `mouseDown` so subsequent `mouseDragged` and `mouseUp` events are remapped consistently.
- The second finger of a two-finger click often arrives in the same HID report as the press, and that report can reach LogiSwipe just after the `mouseDown` event. So a `mouseDown` that comes before `T630.pressReported` is held in `EventTap.waiting`, along with any drags and release, until the press report arrives or `fingerWait` (0.05 s) passes. Then it is classified and reposted, marked with `eventSourceUserData` `0x7630` so the tap lets it through.

### 3. Swipe Detection (`T630.swift`)
- Finger deltas (`dx`, `dy`) are averaged across all fingers present in both the previous and current report while no button is held down (`!buttonsDown`).
- Once `!swiped`, `abs(travelX) >= 15.0` (`swipeDistance`), and `abs(travelX) > abs(travelY) * 1.5` (`swipeRatio`; 1-finger swipes drift upwards), a swipe triggers immediately without waiting for finger lift.
- The second finger of a 2-finger swipe lands up to ~0.1 s after the first, so a touch only counts as a 1-finger swipe once it is `oneFingerDelay` (0.15 s) old. A 1-finger swipe set to "Scroll sideways" doesn't end the touch's swipe check, so a late second finger still triggers the 2-finger action.
- Only one swipe fires per touch (`swiped = true` until `fingers == 0`).
- When a swipe action (`desktops`, `backForward`, `none`) is configured for the active finger count (`touchMaxFingers`), `EventTap.scroll` zeroes out the horizontal scroll delta (`Axis2`) so the gesture does not also scroll the window underneath.

### 3b. Double Tap Detection (`T630.swift`)
- The T630 has no tap-to-click, so taps are detected from the finger reports alone, when the touch ends (`touchEnded`).
- A tap is a touch with no button press (`touchPressed`) and no swipe that lasts at most `tapDuration` (0.4 s) and travels at most `tapTravel` (4 units) on each axis. Measured taps last 0.06–0.35 s and travel ≤ 1 unit.
- A double tap is a second tap with the same finger count (1, or 2 for 2 or more) that lands within `doubleTapGap` (0.35 s) of the first one lifting. Measured gaps are 0.06–0.29 s; separate single taps were ≥ 0.7 s apart. It fires `oneFingerDoubleTap` / `twoFingerDoubleTap` (`TapAction`) when the second tap lifts, then starts over, so a triple tap doesn't fire twice.

### 4. Device Isolation & Pointer Speed (`HIDService.swift`)
- Every pointer/scroll `CGEvent` carries the originating `IOHIDServiceClient` registry ID in `CGEventField(rawValue: 87)`.
- `EventTap` checks `t630.isT630(sender:)` before modifying any event, guaranteeing zero impact on built-in trackpads or other mice. The registry ID changes on every Bluetooth reconnect and the new service can appear after `deviceConnected` looks, so a sender seen for the first time triggers a fresh lookup (`HIDService.all` makes a new client each call; a long-lived one can miss new services). If the lookup misses, the mouse's own scroll events leak through next to `SmoothScroller`'s.
- `SmoothScroller` posts its own scroll events, which macOS does not flip for Natural scrolling (`com.apple.swipescrolldirection`) the way it flips the mouse's own, so it applies Natural scrolling itself before Reverse.
- Pointer speed is set per-service on the T630's `IOHIDServiceClient` via `kIOHIDMouseAccelerationType` in 16.16 fixed-point format (`Int(speed * 65536)`), matching macOS's `com.apple.mouse.scaling` scale (`0.0...6.0`, where System Settings "Fast" is `3.0`).

---

## Building, Signing & Releasing

- **Local build & install**:
  ```sh
  ./build.sh
  ```
  Signing uses the self-signed "LogiSwipe Self-Signed" identity in the login keychain when present. Its designated requirement pins that certificate (`certificate leaf = H"31d139e5…"`), so TCC permissions survive rebuilds and updates, for users too. It is not trusted by Gatekeeper, so downloads still need "Open Anyway" or `xattr -dr com.apple.quarantine`. Losing the key means everyone re-grants permissions once. Without it, signing falls back to ad-hoc, and macOS treats every build as a new app. Never sign with the company team `D82BAQ85JN`. To use another identity:
  ```sh
  SIGN_IDENTITY="Developer ID Application: ..." ./build.sh
  ```
- **Creating a release**:
  Use the `release` skill ([`.agents/skills/release/SKILL.md`](.agents/skills/release/SKILL.md)), which builds, tags, writes release notes, pushes, and publishes the GitHub release with `gh`. To only build the zip, run:
  ```sh
  ./.agents/skills/release/scripts/release.sh <VERSION> [BUILD_NUMBER]
  ```
