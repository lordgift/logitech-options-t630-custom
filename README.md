# logitech-option-t630-custom

Restores 2-finger swipe between desktops for the **Logitech T630 Ultrathin Touch Mouse** on macOS 27.

## Problem

Since macOS 27, swiping left/right with 2 fingers on the T630 no longer switches desktops. Other Logi Options gestures still work.

Testing showed:

- Logi Options 10.26.49 (`LogiMgrDaemon`) still posts dock-swipe events (CGEvent type 30, gesture 23).
- macOS ignores them because they are synthetic rather than coming from real hardware.
- Patching the event fields to match the trackpad's events didn't help, and neither did re-posting them at the HID level.
- Logi Options is discontinued, and Logi Options+ doesn't support the T630.

## Workaround

`logiswipe.swift` watches those dock-swipe events. When a swipe ends, it presses the Mission Control shortcut for that direction:

| Swipe | Key sent | Result |
|---|---|---|
| left | Ctrl+→ | desktop on the right |
| right | Ctrl+← | desktop on the left |

A swipe shorter than the threshold is ignored. To cancel a swipe, pull back before lifting your fingers.

Unlike the trackpad, the desktop doesn't follow your fingers while you swipe. The slide animation plays after you release.

## Usage

```sh
swift logiswipe.swift            # run until Ctrl+C, threshold 0.3
swift logiswipe.swift 0.5        # require a longer swipe
swift logiswipe.swift 0.3 90     # stop after 90 s (testing)
```

Requirements:

- Logi Options running, with "Swipe between full-screen apps" set to 2 fingers.
- Accessibility permission for the terminal app you run it from, so the script can press keys.
- Ctrl+←/→ enabled under System Settings → Keyboard → Keyboard Shortcuts → Mission Control.
