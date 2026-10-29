<p align="center">
  <img src="docs/logo.png" alt="LogiSwipe logo" width="128">
</p>

# LogiSwipe for Logitech T630

Bring your **Logitech T630 Ultrathin Touch Mouse** back to life on modern macOS—without needing Logi Options.

**LogiSwipe** is a lightweight menu bar app that restores 2-finger desktop swipes and lets you customize clicks, gestures, scroll direction, and pointer speed specifically for your T630.

<a href="https://buymeacoffee.com/lordgift"><img src="https://img.buymeacoffee.com/button-api/?text=Buy%20me%20a%20coffee&slug=lordgift&button_colour=FFDD00&font_colour=000000" alt="Buy Me a Coffee" height="40"></a>

![Logitech Ultrathin Touch Mouse T630](https://secure.logitech.com/assets/49924/2/ultrathin-touch-mouse-t630.jpg)
![Logitech Ultrathin Touch Mouse T630](https://secure.logitech.com/assets/49924/4/ultrathin-touch-mouse-t630.jpg)

Mouse specs: [Logitech Ultrathin Touch Mouse T630 Technical Specifications](https://support.logi.com/hc/th/articles/360023466613-Logitech-Ultrathin-Touch-Mouse-T630-Technical-Specifications)

## Why LogiSwipe?

Logitech discontinued **Logi Options**, and the newer **Logi Options+** does not support the T630. On macOS 27 and later, 2-finger swiping to switch desktops stopped working altogether.

LogiSwipe replaces Logi Options for the T630 in a tiny menu bar app—and only touches events from your T630, leaving your trackpad and other mice completely alone.

## Features & Settings

Click the mouse icon in the menu bar. Settings only apply to the T630. Other mice and the trackpad are left alone.

<img src="docs/settings.png" alt="LogiSwipe settings panel" width="680">

<img src="docs/click-zones.png" alt="T630 click zones" width="680">

| Feature / Setting | Options | Default |
|---|---|---|
| **Battery level** | Shown in the menu bar icon and settings panel | — |
| **Custom tracking speed** | `0.0` – `6.0`, marked at macOS's fastest, "Fast" (`3.0`) | On, starting at your system speed |
| **Smooth scrolling** | Trackpad-style scrolling with momentum (`0.25×` – `3×` speed) | On (`1×`) |
| **Reverse scroll direction** | Flips Natural scrolling for the T630 only | Off |
| **Left click** | Left click, Right click, Middle click, Back, Forward, Launchpad, Capture screen → Entire screen / Area / Screenshot tools, App Exposé, Mission Control, Show Desktop, Edit → Cut / Copy / Paste, Open app…, Do nothing | Left click |
| **Right click** | *(same as above)* | Right click |
| **Middle click** (press along the center) | *(same as above)* | Middle click |
| **Hold middle click** (½ s) | Launchpad, Capture screen → Entire screen / Area / Screenshot tools, App Exposé, Mission Control, Show Desktop, Edit → Cut / Copy / Paste, Open app…, Do nothing | Capture area (⌘⇧4) |
| **Two-finger click** | Middle click, Launchpad, Capture screen → Entire screen / Area / Screenshot tools, App Exposé, Mission Control, Show Desktop, Edit → Cut / Copy / Paste, Open app…, Do nothing | Copy |
| **Swipe with 1 finger** | Scroll sideways, Switch desktops, Back / Forward, Do nothing | Back / Forward |
| **Swipe with 2 fingers** | Scroll freely (any direction), Switch desktops, Back / Forward, Do nothing | Scroll freely |
| **Swipe with 3 fingers** (left / right) | Switch desktops, Back / Forward, Do nothing | Switch desktops |
| **Swipe up with 3 fingers** | *(same as Hold middle click)* | Mission Control |
| **Swipe down with 3 fingers** | *(same as Hold middle click)* | Do nothing |
| **Double-tap with 1 finger** | Launchpad, Capture screen → Entire screen (⌘⇧3) / Area (⌘⇧4) / Screenshot tools (⌘⇧5), App Exposé (like ⌃↓), Mission Control, Show Desktop (like F11), Edit → Cut / Copy / Paste, Open app… (pick any app), Do nothing | App Exposé |
| **Double-tap with 2 fingers** | *(same as above)* | Paste |
| **4 fingers spread** (pinch back to undo Show Desktop) | *(same as Double-tap)* | Show Desktop |
| **4 fingers pinch** | *(same as Double-tap)* | Launchpad |
| **Pinch to zoom** | Pinch 2 fingers to zoom in and out smoothly, like a trackpad | On |
| **Launch at login** | On / Off | Off |

**Restore Defaults…** puts every setting back to the default above, and forgets the apps chosen for Open app. Launch at login stays as it is.

## Installation

### Before you start
1. **Quit or uninstall Logi Options.**
2. Turn off **Logitech Options HID Driver Extension** in **System Settings → General → Login Items & Extensions → Driver Extensions**.
3. Make sure **Ctrl+←** and **Ctrl+→** are enabled in **System Settings → Keyboard → Keyboard Shortcuts → Mission Control** (used for switching desktops).

### Option A: Download from Releases (Recommended)
1. Download the latest `LogiSwipe-<version>.zip` from the **Releases** page and unzip it.
2. Move **LogiSwipe.app** to your `/Applications` folder.
3. If macOS says the app cannot be opened, run this once in Terminal:
   ```sh
   xattr -cr /Applications/LogiSwipe.app
   ```

### Option B: Build from Source
If you have Xcode or the Command Line Tools installed:
```sh
./build.sh
```
This builds and installs `/Applications/LogiSwipe.app`.

### Grant Permissions
1. Open **LogiSwipe**.
2. Allow both permissions in **System Settings → Privacy & Security** (you can click the gear icons inside LogiSwipe to jump right to them):
   - **Input Monitoring** (so LogiSwipe can detect your finger touches on the T630)
   - **Accessibility** (so LogiSwipe can perform custom clicks, scrolls, and shortcuts)
3. **Quit and reopen LogiSwipe** from the menu bar icon. Both permissions should now say **Allowed**.

## Tips & Troubleshooting

- **How swipes feel**: Swiping left moves to the desktop on the right (just like a MacBook trackpad). Once your fingers slide about a fifth of the way across the surface, the desktop switches immediately—you don't need to lift your fingers first.
- **T630 shows "Not connected"**: Move or click the mouse to wake it up, and check that it is connected in Bluetooth settings.
- **Nothing works after rebuilding from source**: Without the maintainer's signing identity, local builds are signed ad hoc, so macOS treats each build as a new app. Open **Input Monitoring** and **Accessibility** in System Settings, remove (`−`) LogiSwipe, add (`+`) it again, then quit and reopen LogiSwipe.
