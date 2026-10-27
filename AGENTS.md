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
- [`build.sh`](build.sh) — Builds release binary, packages `build/LogiSwipe.app`, signs it (`SIGN_IDENTITY`, defaulting to ad-hoc `-`), and installs to `/Applications/LogiSwipe.app`.
- [`Sources/LogiSwipe/`](Sources/LogiSwipe/):
  - [`App.swift`](Sources/LogiSwipe/App.swift) — SwiftUI `MenuBarExtra` entry point (`LogiSwipeApp`), `AppDelegate`, and `SettingsView` UI.
  - [`T630.swift`](Sources/LogiSwipe/T630.swift) — Opens the T630 via `IOHIDManager`, parses HID Input Report 2 for finger positions/swipes, tracks sender IDs, and applies per-device tracking speed.
  - [`EventTap.swift`](Sources/LogiSwipe/EventTap.swift) — `CGEvent.tapCreate` session event tap that intercepts and remaps clicks and scroll wheel events coming specifically from the T630's `senderIDs`.
  - [`HIDService.swift`](Sources/LogiSwipe/HIDService.swift) — Private `IOKit` symbol bindings (`IOHIDEventSystemClient*` / `IOHIDServiceClient*`) to query the T630's event service `registryID` (matching `CGEventField(87)`) and set `kIOHIDMouseAccelerationType`.
  - [`Actions.swift`](Sources/LogiSwipe/Actions.swift) — Synthesizes keyboard shortcuts (`Ctrl+Fn+Left/Right` for desktop switching, `Cmd+[/]` for Back/Forward) and launches `Mission Control.app`.
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

### 2. Click Classification (`T630.swift` & `EventTap.swift`)
- **Two-finger click**: Any physical click (`leftMouseDown` or `rightMouseDown`) while `fingers >= 2`.
- **Middle click**: The T630 has no physical middle button. A single-finger click where `firstFingerX` is within `T630.middleZone` (`30...46`) is classified as a middle click.
- **Left / Right click**: Outside `middleZone` with `< 2` fingers, determined by the hardware button event.
- `heldAction` remembers the resolved `ClickAction` on `mouseDown` so subsequent `mouseDragged` and `mouseUp` events are remapped consistently.

### 3. Swipe Detection (`T630.swift`)
- Finger deltas (`dx`, `dy`) are averaged across all fingers present in both the previous and current report while no button is held down (`!buttonsDown`).
- Once `!swiped`, `abs(travelX) >= 15.0` (`swipeDistance`), and `abs(travelX) > abs(travelY) * 1.3`, a swipe triggers immediately without waiting for finger lift.
- Only one swipe fires per touch (`swiped = true` until `fingers == 0`).
- When a swipe action (`desktops`, `backForward`, `none`) is configured for the active finger count (`touchMaxFingers`), `EventTap.scroll` zeroes out the horizontal scroll delta (`Axis2`) so the gesture does not also scroll the window underneath.

### 4. Device Isolation & Pointer Speed (`HIDService.swift`)
- Every pointer/scroll `CGEvent` carries the originating `IOHIDServiceClient` registry ID in `CGEventField(rawValue: 87)`.
- `EventTap` checks `t630.senderIDs.contains(event.getIntegerValueField(senderField))` before modifying any event, guaranteeing zero impact on built-in trackpads or other mice.
- Pointer speed is set per-service on the T630's `IOHIDServiceClient` via `kIOHIDMouseAccelerationType` in 16.16 fixed-point format (`Int(speed * 65536)`), matching macOS's `com.apple.mouse.scaling` scale (`0.0...6.0`, where System Settings "Fast" is `3.0`).

---

## Building, Signing & Releasing

- **Local build & install**:
  ```sh
  ./build.sh
  ```
  To persist TCC permissions across rebuilds, sign with a certificate identity instead of ad-hoc:
  ```sh
  SIGN_IDENTITY="Developer ID Application: ..." ./build.sh
  ```
- **Creating a release**:
  Use the `release` skill ([`.agents/skills/release/SKILL.md`](.agents/skills/release/SKILL.md)) or run:
  ```sh
  ./.agents/skills/release/scripts/release.sh <VERSION> [BUILD_NUMBER]
  ```
