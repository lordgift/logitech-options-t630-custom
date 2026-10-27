import AppKit
import IOKit.hid

/// Reads the T630's touch surface straight from HID and turns sideways swipes into actions.
///
/// Input report 2 layout (byte 0 is the report ID):
///   [1]   buttons (bit 0 = left, bit 1 = right; the mouse picks the side from where you press)
///   [8]   finger bitmask (bit 0 = finger 1, bit 1 = finger 2); 0 when nothing touches
///   [9…]  4 bytes per finger present, in bit order: X, Y, ?, ?   (X runs about 0–76)
final class T630: ObservableObject {
    static let shared = T630()
    static let vendor = 0x046D, product = 0xB00D

    /// How far (in X units) fingers must travel sideways to count as a swipe.
    static let swipeDistance = 15.0
    /// A swipe must move this many times more sideways than up/down; 1-finger swipes drift upwards.
    static let swipeRatio = 1.5
    /// The second finger of a 2-finger swipe lands up to ~0.1 s after the first, so a touch
    /// isn't treated as a 1-finger swipe before it is this old (seconds).
    static let oneFingerDelay = 0.15
    /// Presses at or right of this X are right clicks, left of it left clicks. Measured: left
    /// clicks land at X 6–43 (the mouse itself called one at 43 a right click), right clicks at 62–76.
    static let rightSideX = 53
    /// A press in the upper center is a middle click. Measured: middle clicks at X 34–48, Y 39–52
    /// (the mouse itself called some right clicks); left and right clicks all at Y 55 or more.
    /// Y can't tell a middle click in the lower center from a left click there, so it must be up high.
    static let middleZoneX = 30...55, middleMaxY = 53

    @Published private(set) var connected = false
    /// Sender IDs (CGEvent field 87) of the events the T630 produces.
    private(set) var senderIDs: Set<Int64> = []

    // Current touch.
    private(set) var fingers = 0           // fingers on the surface now
    private(set) var touchMaxFingers = 0   // most fingers seen since the touch began
    private(set) var firstFingerX = -1     // -1 when nothing touches
    private(set) var firstFingerY = -1
    private var lastPosition: [Int: (x: Int, y: Int)] = [:]
    private var travelX = 0.0, travelY = 0.0
    private var touchStart = 0.0           // system uptime when the touch began
    private var swiped = false

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var devices = Set<IOHIDDevice>()  // with an input report callback registered

    func start() {
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: Self.vendor,
                                                kIOHIDProductIDKey: Self.product] as CFDictionary)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { _, _, _, device in
            // Matching fires again when the manager is reopened after a failed open.
            guard T630.shared.devices.insert(device).inserted else { return }
            let size = max(IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? 64, 1)
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)  // lives as long as the device
            IOHIDDeviceRegisterInputReportCallback(device, buffer, size, { _, _, _, _, _, report, length in
                T630.shared.handle(report, length)
            }, nil)
            T630.shared.deviceConnected()
        }, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { _, _, _, device in
            T630.shared.devices.remove(device)
            T630.shared.connected = !T630.shared.devices.isEmpty
        }, nil)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        open()
    }

    /// Needs Input Monitoring; keeps retrying until it is granted.
    private func open(attempt: Int = 0) {
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result == kIOReturnSuccess {
            log.info("HID opened")
            return
        }
        if attempt == 0 { log.error("HID open failed: \(String(format: "0x%X", result), privacy: .public), retrying") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.open(attempt: attempt + 1) }
    }

    private func deviceConnected() {
        connected = true
        // The event service shows up a moment after the HID device, and macOS applies the
        // system tracking speed to it when it does.
        for delay in [0.5, 2.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.senderIDs = Set(HIDService.all(vendor: Self.vendor, product: Self.product).map(\.registryID))
                log.info("T630 connected, sender IDs \(self.senderIDs.map(String.init).joined(separator: ","), privacy: .public)")
                self.applyTrackingSpeed()
            }
        }
    }

    func applyTrackingSpeed() {
        let settings = Settings.shared
        let system = UserDefaults.standard.object(forKey: "com.apple.mouse.scaling") as? Double ?? 1.0
        let speed = settings.enabled && settings.customSpeed ? settings.trackingSpeed : system
        for service in HIDService.all(vendor: Self.vendor, product: Self.product) {
            service.set(kIOHIDMouseAccelerationType, NSNumber(value: Int(speed * 65536)))
        }
    }

    private func handle(_ r: UnsafeMutablePointer<UInt8>, _ length: Int) {
        guard length > 8, r[0] == 2 else { return }
        let buttonsDown = r[1] & 0x03 != 0
        let mask = Int(r[8])
        var position: [Int: (x: Int, y: Int)] = [:]
        var offset = 9
        for slot in 0..<8 where mask & (1 << slot) != 0 && offset + 1 < length {
            position[slot] = (Int(r[offset]), Int(r[offset + 1]))
            offset += 4
        }
        fingers = position.count
        let firstFinger = position.keys.min().map { position[$0]! }
        firstFingerX = firstFinger?.x ?? -1
        firstFingerY = firstFinger?.y ?? -1

        guard !position.isEmpty else {
            SmoothScroller.shared.lift()
            lastPosition = [:]; travelX = 0; travelY = 0; touchMaxFingers = 0; swiped = false
            return
        }
        // Only fingers present in both reports count, so a finger landing or lifting doesn't jump.
        if lastPosition.isEmpty { touchStart = ProcessInfo.processInfo.systemUptime }
        let moved = position.compactMap { slot, p in lastPosition[slot].map { (x: p.x - $0.x, y: p.y - $0.y) } }
        if !moved.isEmpty {
            travelX += Double(moved.map(\.x).reduce(0, +)) / Double(moved.count)
            travelY += Double(moved.map(\.y).reduce(0, +)) / Double(moved.count)
        }
        touchMaxFingers = max(touchMaxFingers, position.count)
        lastPosition = position

        let settings = Settings.shared
        let touchAge = ProcessInfo.processInfo.systemUptime - touchStart
        if settings.enabled && settings.smoothScrolling && touchMaxFingers == 1 && !buttonsDown,
           let finger = position.values.first {
            SmoothScroller.shared.move(x: finger.x, y: finger.y,
                                       allowHorizontal: settings.oneFingerSwipe == .scroll, touchAge: touchAge)
        } else {
            SmoothScroller.shared.lift()
        }

        // One action per touch, as soon as it is far enough and mostly sideways.
        guard settings.enabled, !swiped, !buttonsDown,
              abs(travelX) >= Self.swipeDistance, abs(travelX) > Self.swipeRatio * abs(travelY)
        else { return }
        let twoFingers = touchMaxFingers >= 2
        if !twoFingers && touchAge < Self.oneFingerDelay { return }
        let action = twoFingers ? settings.twoFingerSwipe : settings.oneFingerSwipe
        // Plain scrolling needs nothing from us; keep watching in case a second finger lands.
        if !twoFingers && action == .scroll { return }
        swiped = true
        log.info("swipe: \(self.touchMaxFingers, privacy: .public) fingers, x \(self.travelX, privacy: .public), y \(self.travelY, privacy: .public) → \(action.rawValue, privacy: .public)")
        Actions.swipe(action, fingersMovedLeft: travelX < 0)
    }
}

enum ClickKind {
    case left, right, middle, twoFinger
}
