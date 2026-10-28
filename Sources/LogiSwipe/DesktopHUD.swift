import AppKit
import SwiftUI

// SkyLight calls, exported through CoreGraphics without public headers.
@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> Int32
@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ connection: Int32) -> Unmanaged<CFArray>

/// Shows the desktops of the screen when a swipe can't switch any further, nudging them the way
/// the fingers went and springing back, like a trackpad's rubber band.
final class DesktopHUD {
    static let shared = DesktopHUD()

    /// The window server reports the new desktop only after the switch animation (> 0.75 s), so a
    /// swipe this soon after the last one goes on from where that one went instead.
    private static let switchTime = 1.5
    private var lastSwitch: (display: String, index: Int, time: TimeInterval)?
    private var panel: NSPanel?
    private var shown = 0  // counts shows, so an old fade-out doesn't hide a newer one
    private static let cornerRadius = 20.0

    /// Called for every desktop swipe; `next` is towards the desktop on the right.
    func swiped(next: Bool) {
        guard let desktops = Self.desktopsUnderPointer() else { return }
        let now = ProcessInfo.processInfo.systemUptime
        var index = desktops.index
        if let last = lastSwitch, last.display == desktops.display, now - last.time < Self.switchTime {
            index = last.index
        }
        let target = index + (next ? 1 : -1)
        guard desktops.count > target && target >= 0 else {
            log.info("desktops: \(index + 1, privacy: .public) of \(desktops.count, privacy: .public), can't go \(next ? "right" : "left", privacy: .public)")
            show(on: desktops.screen, index: index, count: desktops.count, next: next)
            return
        }
        lastSwitch = (desktops.display, target, now)
    }

    /// The screen under the pointer, whose desktops Ctrl+Left/Right switches, with its desktops
    /// (full-screen apps included) in order.
    private static func desktopsUnderPointer() -> (screen: NSScreen, display: String, index: Int, count: Int)? {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) ?? NSScreen.main,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue(),
              let id = CFUUIDCreateString(nil, uuid) as String?
        else { return nil }
        let displays = CGSCopyManagedDisplaySpaces(CGSMainConnectionID()).takeRetainedValue() as? [[String: Any]] ?? []
        // Without "Displays have separate Spaces" there is one entry for all screens.
        guard let display = displays.first(where: { $0["Display Identifier"] as? String == id })
                ?? (displays.count == 1 ? displays.first : nil),
              let spaces = display["Spaces"] as? [[String: Any]],
              let current = (display["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int,
              let index = spaces.firstIndex(where: { $0["ManagedSpaceID"] as? Int == current })
        else { return nil }
        return (screen, id, index, spaces.count)
    }

    private func show(on screen: NSScreen, index: Int, count: Int, next: Bool) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let content = NSHostingView(rootView: EdgeView(index: index, count: count, nudge: next ? -1 : 1))
        let size = content.fittingSize
        content.frame = NSRect(origin: .zero, size: size)
        panel.contentView = background(for: content)
        panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2,
                              width: size.width, height: size.height), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        shown += 1
        let shown = shown
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard self?.shown == shown else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; panel.animator().alphaValue = 0 }) {
                if self?.shown == shown { panel.orderOut(nil) }
            }
        }
    }

    /// Liquid Glass on macOS 26 and later, clear or tinted as set in System Settings → Appearance,
    /// else a blurred HUD background.
    private func background(for content: NSView) -> NSView {
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView(frame: content.frame)
            glass.cornerRadius = Self.cornerRadius
            glass.contentView = content
            return glass
        }
        let blur = NSVisualEffectView(frame: content.frame)
        blur.material = .hudWindow
        blur.state = .active
        // A mask, not a layer corner radius: it also clips the blur behind the window.
        blur.maskImage = NSImage(size: content.frame.size, flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius).fill()
            return true
        }
        blur.addSubview(content)
        return blur
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false  // the glass draws its own edges
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        // Glass follows the system appearance; the older HUD background is always dark.
        if #unavailable(macOS 26) { panel.appearance = NSAppearance(named: .darkAqua) }
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }
}

/// A row of desktops with the current one lit, nudged `nudge` (-1 left, 1 right) and sprung back.
private struct EdgeView: View {
    let index: Int, count: Int, nudge: CGFloat
    @State private var offset: CGFloat = 0

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(i == index ? 0.8 : 0.2))
                    .frame(width: 32, height: 20)
            }
        }
        .offset(x: offset)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .onAppear {
            withAnimation(.easeOut(duration: 0.1)) { offset = nudge * 12 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.4)) { offset = 0 }
            }
        }
    }
}
