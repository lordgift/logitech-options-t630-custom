# logitech-option-t630-custom

Restores 2-finger swipe between desktops for the **Logitech T630 Ultrathin Touch Mouse** on macOS 27.

![Logitech Ultrathin Touch Mouse T630](https://secure.logitech.com/assets/49924/2/ultrathin-touch-mouse-t630.jpg)

Reference: [Logitech Ultrathin Touch Mouse T630 Technical Specifications](https://support.logi.com/hc/th/articles/360023466613-Logitech-Ultrathin-Touch-Mouse-T630-Technical-Specifications)

## Problem

Since macOS 27, swiping left/right with 2 fingers on the T630 no longer switches desktops. Other Logi Options gestures still work.

Testing showed:

- Logi Options 10.26.49 (`LogiMgrDaemon`) still posts dock-swipe events (CGEvent type 30, gesture 23).
- macOS ignores them because they are synthetic rather than coming from real hardware.
- Patching the event fields to match the trackpad's events didn't help, and neither did re-posting them at the HID level.
- Logi Options is discontinued, and Logi Options+ doesn't support the T630.
- With Logi Options running, the mouse itself turns a 2-finger swipe into a button 4/5 press, but its HID filter driver keeps those from reaching macOS.
- Without Logi Options (app, daemon and driver extension removed or disabled), the mouse no longer does that. It still reports the raw finger positions.

## LogiSwipe

LogiSwipe is a menu bar app that reads the T630 directly, so Logi Options isn't needed. It only changes events that come from the T630. Other mice and the trackpad are left alone.

| Setting | What it does |
|---|---|
| Custom tracking speed | Pointer speed for the T630 only, on the same scale as System Settings → Mouse → Tracking speed (Fast = 3.0). The slider goes up to 6.0. The T630's hardware DPI can't be changed. |
| Reverse scroll direction | Flips the Natural scrolling setting for the T630 only. |
| Left / Right / Middle / Two-finger click | Left click, right click, middle click, Back (Cmd+[), Forward (Cmd+]), Mission Control, or nothing. |
| Swipe with 1 / 2 fingers | Scroll sideways, switch desktops (Ctrl+←/→), Back / Forward, or nothing. |
| Launch at login | Starts LogiSwipe when you log in. |

How the clicks are told apart:

- The mouse picks left or right from where you press.
- The mouse has no middle button. LogiSwipe counts a press in the center of the surface (X 30–46 of about 0–76) as a middle click.
- A press while 2 fingers touch the surface is a two-finger click.

How swipes work:

- A swipe fires as soon as the fingers have moved 15 units (about a fifth of the surface width) sideways, and mostly sideways rather than up/down. You don't have to lift your fingers first.
- Each touch fires at most once. After that, moving back and forth does nothing until you lift your fingers.
- When a swipe has an action other than "Scroll sideways", the sideways scrolling it would also cause is dropped.
- Swiping left goes to the desktop on the right (or Forward), as on a trackpad.
- Unlike the trackpad, the desktop doesn't follow your fingers while you swipe. The slide animation plays once the swipe is far enough.

## Build and install

```sh
./build.sh
```

This builds `LogiSwipe.app`, signs it ad hoc and installs it in `/Applications`. Because the signature changes on every build, macOS asks for the permissions below again after each rebuild. To sign with a code signing identity of your own instead, set `SIGN_IDENTITY`.

Requirements:

- Logi Options **not** running. Its driver extension (Logitech Options HID Driver Extension) should be turned off under System Settings → General → Login Items & Extensions → Driver Extensions.
- **Input Monitoring** for LogiSwipe, so it can read the mouse.
- **Accessibility** for LogiSwipe, so it can change clicks and scrolls and press keys.
- Ctrl+←/→ enabled under System Settings → Keyboard → Keyboard Shortcuts → Mission Control.
