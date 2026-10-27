import AppKit
import IOKit.hid

/// Reads the T630's touch surface straight from HID and turns 2-finger sideways swipes
/// into desktop switches.
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

    @Published private(set) var connected = false

    // Current touch.
    private var touchMaxFingers = 0   // most fingers seen since the touch began
    private var lastPosition: [Int: (x: Int, y: Int)] = [:]
    private var travelX = 0.0, travelY = 0.0
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
            T630.shared.connected = true
        }, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { _, _, _, device in
            T630.shared.devices.remove(device)
            T630.shared.connected = !T630.shared.devices.isEmpty
        }, nil)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        open()
    }

    /// Needs Input Monitoring; keeps retrying until it is granted.
    private func open() {
        if IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) != kIOReturnSuccess {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.open() }
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

        guard !position.isEmpty else {
            lastPosition = [:]; travelX = 0; travelY = 0; touchMaxFingers = 0; swiped = false
            return
        }
        // Only fingers present in both reports count, so a finger landing or lifting doesn't jump.
        let moved = position.compactMap { slot, p in lastPosition[slot].map { (x: p.x - $0.x, y: p.y - $0.y) } }
        if !moved.isEmpty {
            travelX += Double(moved.map(\.x).reduce(0, +)) / Double(moved.count)
            travelY += Double(moved.map(\.y).reduce(0, +)) / Double(moved.count)
        }
        touchMaxFingers = max(touchMaxFingers, position.count)
        lastPosition = position

        // One switch per touch, as soon as it is far enough and mostly sideways.
        // 1 finger is scrolling, so only a touch that has had 2 fingers counts.
        guard !swiped, !buttonsDown, touchMaxFingers >= 2,
              abs(travelX) >= Self.swipeDistance, abs(travelX) > 2 * abs(travelY)
        else { return }
        swiped = true
        Actions.switchDesktop(fingersMovedLeft: travelX < 0)
    }
}
