import AppKit
import IOKit.hid
import os

let log = Logger(subsystem: "th.in.lordgift.LogiSwipe", category: "main")

/// Live state of the two permissions LogiSwipe needs, for the settings panel.
final class Permissions: ObservableObject {
    static let shared = Permissions()

    /// Reading the mouse.
    @Published private(set) var inputMonitoring = false
    /// Rewriting clicks / scrolls and pressing keys.
    @Published private(set) var accessibility = false

    private init() {
        refresh()
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in self.refresh() }
    }

    func request() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    private func refresh() {
        let input = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        let ax = AXIsProcessTrusted()
        if input != inputMonitoring || ax != accessibility {
            log.info("permissions: input monitoring \(input, privacy: .public), accessibility \(ax, privacy: .public)")
        }
        if input != inputMonitoring { inputMonitoring = input }
        if ax != accessibility { accessibility = ax }
    }
}
