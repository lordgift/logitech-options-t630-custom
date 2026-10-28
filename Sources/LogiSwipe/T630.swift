import AppKit
import IOKit.hid

/// Reads the T630's touch surface straight from HID and turns sideways swipes into actions.
///
/// Input report 2 layout (byte 0 is the report ID):
///   [1]   buttons (bit 0 = left, bit 1 = right; the mouse picks the side from where you press)
///   [8]   finger bitmask (bit 0 = finger 1, bit 1 = finger 2); 0 when nothing touches
///   [9…]  4 bytes per finger present, in bit order: X, Y, ?, ?   (X runs about 0–76)
///
/// Input report 3 is the battery: [1] = percent (0–100). macOS doesn't show it anywhere.
final class T630: ObservableObject {
    static let shared = T630()
    static let vendor = 0x046D, product = 0xB00D

    /// How far (in X units, or Y units for a three-finger swipe up or down) fingers must travel
    /// to count as a swipe. Measured: three-finger swipes up or down travel 37–51 Y units.
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
    /// The last two fingers must land within this many seconds of each other for a click to be a
    /// two-finger click; otherwise one is resting on the mouse while the other clicks.
    /// Measured: two-finger clicks land 0.01–0.08 s apart.
    static let twoFingerClickWindow = 0.25
    /// A tap is a touch without a press that lifts within this many seconds and moves at most
    /// `tapTravel` X/Y units. Measured: taps last 0.06–0.35 s and travel 1 unit at most.
    static let tapDuration = 0.4, tapTravel = 4.0
    /// The second tap of a double tap must land within this many seconds of the first lifting.
    static let doubleTapGap = 0.35

    @Published private(set) var connected = false
    /// Battery percent, nil until the mouse reports it.
    @Published private(set) var battery: Int?
    /// Sender IDs (CGEvent field 87) of the events the T630 produces.
    private(set) var senderIDs: Set<Int64> = []
    /// Senders already looked up and found not to be the T630.
    private var otherSenders: Set<Int64> = []

    // Current touch.
    private(set) var fingers = 0           // fingers on the surface now
    private(set) var touchMaxFingers = 0   // most fingers seen since the touch began
    /// The finger that landed last, which is the one clicking when another rests on the mouse.
    private(set) var pressX = -1           // -1 when nothing touches
    private(set) var pressY = -1
    /// Whether the last two fingers landed together, as in a two-finger click.
    private(set) var fingersLandedTogether = false
    /// Whether the latest report has a button down, so the fingers of the current click are known.
    private(set) var pressReported = false
    private var lastPosition: [Int: (x: Int, y: Int)] = [:]
    private var landed: [Int: Double] = [:]  // slot → system uptime when that finger landed
    private var travelX = 0.0, travelY = 0.0
    private var touchStart = 0.0           // system uptime when the touch began
    private var swiped = false
    private var touchPressed = false       // a button went down during the touch
    private var lastTap: (fingers: Int, end: Double)?

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
            T630.shared.readBattery()
        }, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { _, _, _, device in
            T630.shared.devices.remove(device)
            T630.shared.connected = !T630.shared.devices.isEmpty
            if !T630.shared.connected { T630.shared.battery = nil }
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
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.findServices() }
        }
    }

    /// Whether an event came from the T630. After a reconnect its event service can show up
    /// later than `deviceConnected` looks, so a sender seen for the first time is looked up.
    func isT630(sender: Int64) -> Bool {
        if senderIDs.contains(sender) { return true }
        if otherSenders.contains(sender) { return false }
        findServices()
        if senderIDs.contains(sender) { return true }
        otherSenders.insert(sender)
        return false
    }

    /// Asks the mouse for its battery report, which it otherwise sends only now and then.
    func readBattery() {
        for device in devices {
            var report: [UInt8] = [3, 0]
            var length = report.count
            if IOHIDDeviceGetReport(device, kIOHIDReportTypeInput, 3, &report, &length) == kIOReturnSuccess,
               length >= 2 {
                battery = Int(report[1])
            }
        }
    }

    private func findServices() {
        senderIDs = Set(HIDService.all(vendor: Self.vendor, product: Self.product).map(\.registryID))
        log.info("T630 sender IDs \(self.senderIDs.map(String.init).joined(separator: ","), privacy: .public)")
        applyTrackingSpeed()
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
        if r[0] == 3, length >= 2 {
            battery = Int(r[1])
            return
        }
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
        let now = ProcessInfo.processInfo.systemUptime
        landed = position.keys.reduce(into: [:]) { $0[$1] = landed[$1] ?? now }
        let order = position.keys.sorted { (landed[$0]!, $0) < (landed[$1]!, $1) }
        let pressing = order.last.map { position[$0]! }
        pressX = pressing?.x ?? -1
        pressY = pressing?.y ?? -1
        fingersLandedTogether = order.count >= 2
            && landed[order[order.count - 1]]! - landed[order[order.count - 2]]! <= Self.twoFingerClickWindow
        let pressed = buttonsDown && !pressReported
        pressReported = buttonsDown
        if pressed { EventTap.shared.fingersReported() }

        touchPressed = touchPressed || buttonsDown
        guard !position.isEmpty else {
            SmoothScroller.shared.lift()
            if !lastPosition.isEmpty { touchEnded(at: now) }
            lastPosition = [:]; travelX = 0; travelY = 0; touchMaxFingers = 0; swiped = false; touchPressed = false
            return
        }
        // Only fingers present in both reports count, so a finger landing or lifting doesn't jump.
        if lastPosition.isEmpty { touchStart = now }
        let moved = position.compactMap { slot, p in lastPosition[slot].map { (x: p.x - $0.x, y: p.y - $0.y) } }
        if !moved.isEmpty {
            travelX += Double(moved.map(\.x).reduce(0, +)) / Double(moved.count)
            travelY += Double(moved.map(\.y).reduce(0, +)) / Double(moved.count)
        }
        touchMaxFingers = max(touchMaxFingers, position.count)
        lastPosition = position

        let settings = Settings.shared
        let touchAge = now - touchStart
        if settings.enabled && settings.smoothScrolling && touchMaxFingers == 1 && !buttonsDown,
           let finger = position.values.first {
            SmoothScroller.shared.move(x: finger.x, y: finger.y,
                                       allowHorizontal: settings.oneFingerSwipe == .scroll, touchAge: touchAge)
        } else {
            SmoothScroller.shared.lift()
        }

        // One action per touch, as soon as it is far enough and mostly sideways.
        guard settings.enabled, !swiped, !buttonsDown else { return }
        // Y grows towards the front of the mouse, away from the palm, so moving up is positive.
        if touchMaxFingers >= 3, abs(travelY) >= Self.swipeDistance,
           abs(travelY) > Self.swipeRatio * abs(travelX) {
            swiped = true
            let gesture: Gesture = travelY > 0 ? .threeFingerSwipeUp : .threeFingerSwipeDown
            let action = settings.gestureAction(for: gesture)
            log.info("swipe: 3 fingers, x \(self.travelX, privacy: .public), y \(self.travelY, privacy: .public) → \(action.rawValue, privacy: .public)")
            Actions.perform(action, app: settings.apps[gesture.rawValue])
            return
        }
        guard abs(travelX) >= Self.swipeDistance, abs(travelX) > Self.swipeRatio * abs(travelY)
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

    /// Fires a double tap when this touch is the second of two quick taps with the same number of fingers.
    private func touchEnded(at now: Double) {
        let duration = now - touchStart
        guard Settings.shared.enabled, !touchPressed, !swiped, duration <= Self.tapDuration,
              abs(travelX) <= Self.tapTravel, abs(travelY) <= Self.tapTravel else {
            lastTap = nil
            return
        }
        let fingers = min(touchMaxFingers, 2)
        guard let last = lastTap, last.fingers == fingers, touchStart - last.end <= Self.doubleTapGap else {
            lastTap = (fingers, now)
            return
        }
        lastTap = nil
        let gesture: Gesture = fingers == 2 ? .twoFingerDoubleTap : .oneFingerDoubleTap
        let action = Settings.shared.gestureAction(for: gesture)
        log.info("double tap: \(fingers, privacy: .public) fingers, gap \(self.touchStart - last.end, privacy: .public) → \(action.rawValue, privacy: .public)")
        Actions.perform(action, app: Settings.shared.apps[gesture.rawValue])
    }
}

enum ClickKind {
    case left, right, middle, twoFinger

    /// UserDefaults key of the setting for this click.
    var key: String {
        switch self {
        case .left: "leftClick"
        case .right: "rightClick"
        case .middle: "middleClick"
        case .twoFinger: "twoFingerClick"
        }
    }
}
