# logitech-option-t630-custom

Restores 2-finger swipe between desktops for the **Logitech T630 Ultrathin Touch Mouse** on macOS 27.

## Problem

Since macOS 27, swiping left/right with 2 fingers on the T630 no longer switches desktops. Other Logi Options gestures still work.

Testing showed:

- Logi Options 10.26.49 (`LogiMgrDaemon`) still posts dock-swipe events (CGEvent type 30, gesture 23).
- macOS ignores them because they are synthetic rather than coming from real hardware.
- Patching the event fields to match the trackpad's events didn't help, and neither did re-posting them at the HID level.
- Logi Options is discontinued, and Logi Options+ doesn't support the T630.
- With Logi Options running, the mouse itself turns a 2-finger swipe into a button 4/5 press, but its HID filter driver keeps those from reaching macOS.
- Without Logi Options (app, daemon and driver extension removed or disabled), the mouse no longer does that. It still reports the raw finger positions.

## Workaround

`logiswipe.swift` reads the T630's raw finger positions (HID input report 2) directly, so Logi Options isn't needed. As soon as 2 fingers have moved far enough sideways, it presses the Mission Control shortcut for that direction, without waiting for you to lift your fingers:

| Swipe | Key sent | Result |
|---|---|---|
| left | Ctrl+→ | desktop on the right |
| right | Ctrl+← | desktop on the left |

A swipe has to travel at least `minDistance` (15 units, about a fifth of the surface width) to count. Each touch switches at most once: after that, moving back and forth does nothing until you lift your fingers. Touches with only 1 finger are ignored, since 1 finger scrolls.

Unlike the trackpad, the desktop doesn't follow your fingers while you swipe. The slide animation plays once the swipe is far enough.

## Usage

```sh
swift logiswipe.swift            # run until Ctrl+C
swift logiswipe.swift 90         # stop after 90 s (testing)
```

Requirements:

- Logi Options **not** running. Its driver extension (Logitech Options HID Driver Extension) should be turned off under System Settings → General → Login Items & Extensions → Driver Extensions.
- Input Monitoring permission for the terminal app you run it from, so the script can read the mouse.
- Accessibility permission for the same app, so the script can press keys.
- Ctrl+←/→ enabled under System Settings → Keyboard → Keyboard Shortcuts → Mission Control.
