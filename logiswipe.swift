// logiswipe — turn Logi Options' 2-finger swipe (which macOS 27 ignores)
// into Ctrl+← / Ctrl+→ so it switches desktops again.
//
// Logi Options still posts dock-swipe events (CGEvent type 30, gesture 23),
// but macOS drops them because they don't come from real hardware. We watch
// those events and, when the swipe ends, press the Mission Control shortcut.
//
// Run:    swift logiswipe.swift [threshold] [seconds]
//   threshold  how far (0–1) you must swipe before releasing; default 0.3.
//              Pull back below it before lifting your fingers to cancel.
//   seconds    stop automatically after this long (for testing); default: run until Ctrl+C.
// Needs Accessibility permission for the app you run it from (to press keys).
import AppKit
import CoreGraphics

let args = CommandLine.arguments
let threshold = Double(args.count > 1 ? args[1] : "0.3") ?? 0.3
let duration = Double(args.count > 2 ? args[2] : "0") ?? 0

let typeDockSwipe: UInt32 = 30
let fieldSourcePid = CGEventField(rawValue: 41)!
let fieldGestureType = CGEventField(rawValue: 110)!  // 23 = dock swipe
let fieldSwipeAxis = CGEventField(rawValue: 123)!    // 1 = horizontal
let fieldProgress = CGEventField(rawValue: 124)!
let fieldPhase = CGEventField(rawValue: 132)!        // 1 began, 2 changed, 4 ended, 8 cancelled

let keyLeft: CGKeyCode = 123, keyRight: CGKeyCode = 124
var gTap: CFMachPort?

func log(_ s: String) {
    let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    print("[\(ts)] \(s)")
    fflush(stdout)
}

func pressCtrl(_ key: CGKeyCode) {
    // Same modifiers macOS registers for "Move left/right a space" (control + fn).
    let flags: CGEventFlags = [.maskControl, .maskSecondaryFn]
    let src = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down)
        e?.flags = flags
        e?.post(tap: .cghidEventTap)
    }
}

let callback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = gTap { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    // Only synthetic horizontal dock swipes (real trackpad ones have pid 0 and still work).
    guard type.rawValue == typeDockSwipe,
          event.getIntegerValueField(fieldSourcePid) != 0,
          event.getIntegerValueField(fieldGestureType) == 23,
          event.getIntegerValueField(fieldSwipeAxis) == 1,
          event.getIntegerValueField(fieldPhase) == 4
    else { return Unmanaged.passUnretained(event) }

    let progress = event.getDoubleValueField(fieldProgress)
    if progress <= -threshold {
        log(String(format: "swipe left  (%.2f) → Ctrl+→", progress))
        pressCtrl(keyRight)
    } else if progress >= threshold {
        log(String(format: "swipe right (%.2f) → Ctrl+←", progress))
        pressCtrl(keyLeft)
    } else {
        log(String(format: "swipe too short (%.2f), ignored", progress))
    }
    return Unmanaged.passUnretained(event)
}

guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
                                  options: .listenOnly,
                                  eventsOfInterest: CGEventMask(1) << typeDockSwipe,
                                  callback: callback, userInfo: nil) else {
    print("ERROR: cannot create event tap — grant Input Monitoring/Accessibility to this terminal app")
    exit(1)
}
gTap = tap
CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
log(String(format: "logiswipe running (threshold %.2f). Ctrl+C to stop.", threshold))
if duration > 0 {
    Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in exit(0) }
}
RunLoop.current.run()
