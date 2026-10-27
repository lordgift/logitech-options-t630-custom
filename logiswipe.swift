// logiswipe — 2-finger swipe on the Logitech T630 switches desktops again,
// without Logi Options.
//
// The T630 reports raw finger positions in its HID input report 2. We read
// them directly and, as soon as 2 fingers have travelled far enough sideways, press
// Ctrl+← / Ctrl+→ once for that touch (anything after that, until you lift, is ignored).
//
// Report 2 layout (byte 0 is the report ID):
//   [8]   finger bitmask (bit 0 = finger 1, bit 1 = finger 2); 0 when nothing touches
//   [9…]  4 bytes per finger present, in bit order: X, Y, ?, ?   (X runs about 0–76)
//
// Run:    swift logiswipe.swift [seconds]
//   seconds    stop automatically after this long (for testing); default: run until Ctrl+C.
// Needs Input Monitoring (to read the mouse) and Accessibility (to press keys)
// for the app you run it from.
import AppKit
import IOKit.hid

let args = CommandLine.arguments
let duration = Double(args.count > 1 ? args[1] : "0") ?? 0

let vendorLogitech = 0x046D, productT630 = 0xB00D
let minDistance = 15.0  // how far (in X units) the fingers must travel to count as a swipe

let keyLeft: CGKeyCode = 123, keyRight: CGKeyCode = 124

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

// Current touch.
var lastX: [Int: Int] = [:]  // finger slot → X in the previous report
var travel = 0.0             // average X movement of the fingers since the touch began
var maxFingers = 0
var fired = false            // already switched desktop during this touch

func handleReport(_ r: UnsafeMutablePointer<UInt8>, _ len: Int) {
    guard len > 8, r[0] == 2 else { return }
    let mask = Int(r[8])
    var x: [Int: Int] = [:]
    var offset = 9
    for slot in 0..<8 where mask & (1 << slot) != 0 && offset < len {
        x[slot] = Int(r[offset])
        offset += 4
    }

    if !x.isEmpty {
        // Only fingers present in both reports count, so a finger landing or lifting doesn't jump.
        let moved = x.compactMap { slot, v in lastX[slot].map { Double(v - $0) } }
        if !moved.isEmpty { travel += moved.reduce(0, +) / Double(moved.count) }
        maxFingers = max(maxFingers, x.count)
        lastX = x
        // 1 finger is scrolling, so only a touch that has had 2 fingers counts.
        if !fired && maxFingers >= 2 && abs(travel) >= minDistance {
            fired = true
            if travel < 0 {
                log(String(format: "swipe left  (%.0f) → Ctrl+→", travel))
                pressCtrl(keyRight)
            } else {
                log(String(format: "swipe right (%.0f) → Ctrl+←", travel))
                pressCtrl(keyLeft)
            }
        }
        return
    }

    guard !lastX.isEmpty else { return }  // no touch in progress
    if !fired && maxFingers >= 2 {
        log(String(format: "swipe too short (%.0f), ignored", travel))
    }
    lastX = [:]; travel = 0; maxFingers = 0; fired = false
}

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: vendorLogitech,
                                        kIOHIDProductIDKey: productT630] as CFDictionary)
IOHIDManagerRegisterDeviceMatchingCallback(manager, { _, _, _, device in
    let size = max(IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? 64, 1)
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)  // lives as long as the device
    IOHIDDeviceRegisterInputReportCallback(device, buffer, size, { _, _, _, _, _, report, len in
        handleReport(report, len)
    }, nil)
    log("T630 connected")
}, nil)
IOHIDManagerRegisterDeviceRemovalCallback(manager, { _, _, _, _ in log("T630 disconnected") }, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
guard result == kIOReturnSuccess else {
    print(String(format: "ERROR: cannot open HID devices (0x%X) — grant Input Monitoring to this terminal app", result))
    exit(1)
}
log("logiswipe running. Ctrl+C to stop.")
if duration > 0 {
    Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in exit(0) }
}
RunLoop.current.run()
