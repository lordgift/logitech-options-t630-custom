import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

@main
struct LogiSwipeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            SettingsView(settings: .shared, t630: .shared, permissions: .shared)
        } label: {
            MenuBarIcon(t630: .shared)
        }
        .menuBarExtraStyle(.window)
    }
}

/// A mouse outline that fills from the bottom with the T630's battery level, faded while the level is unknown.
struct MenuBarIcon: View {
    @ObservedObject var t630: T630

    var body: some View {
        Image(nsImage: .menuBarIcon(battery: t630.connected ? t630.battery : nil))
    }
}

extension NSImage {
    /// An 18 pt template image, so the menu bar tints it for light and dark mode.
    static func menuBarIcon(battery: Int?) -> NSImage {
        let image = NSImage(size: NSSize(width: 12, height: 18), flipped: false) { _ in
            let stroke: CGFloat = 1.5, gap: CGFloat = 1
            let outline = NSRect(x: 0, y: 0, width: 12, height: 18).insetBy(dx: 0.5 + stroke / 2, dy: 0.5 + stroke / 2)
            NSColor.black.withAlphaComponent(battery == nil ? 0.4 : 1).set()
            // The line between the buttons.
            let split = NSBezierPath()
            split.move(to: NSPoint(x: outline.midX, y: outline.maxY))
            split.line(to: NSPoint(x: outline.midX, y: outline.maxY - 5))

            if let battery {
                NSGraphicsContext.saveGraphicsState()
                let inner = outline.insetBy(dx: stroke / 2 + gap, dy: stroke / 2 + gap)
                NSBezierPath(roundedRect: inner, xRadius: inner.width / 2, yRadius: inner.width / 2).addClip()
                var level = inner
                level.size.height *= CGFloat(min(max(battery, 0), 100)) / 100
                level.fill()
                // Keep the button line visible where the level reaches it.
                NSGraphicsContext.current!.cgContext.setBlendMode(.clear)
                split.lineWidth = stroke * 2
                split.lineCapStyle = .round
                split.stroke()
                NSGraphicsContext.restoreGraphicsState()
            }
            // One path, so the faded outline doesn't darken where the button line meets it.
            let mouse = NSBezierPath(roundedRect: outline, xRadius: outline.width / 2, yRadius: outline.width / 2)
            mouse.append(split)
            mouse.lineWidth = stroke
            mouse.lineCapStyle = .round
            mouse.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        log.info("LogiSwipe started")
        // Ask for both permissions up front; the system shows its own prompts.
        Permissions.shared.request()
        T630.shared.start()
        EventTap.shared.start()
    }
}

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var t630: T630
    @ObservedObject var permissions: Permissions
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    // Two columns, so the panel fits on screen without scrolling.
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Form {
                statusSection
                pointerSection
                scrollingSection
            }
            Form {
                clicksSection
                gesturesSection
                appSection
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 680)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { t630.readBattery() }
    }

    private var statusSection: some View {
        Section {
            Toggle("Enabled", isOn: $settings.enabled)
            LabeledContent("T630", value: t630.connected ? "Connected" : "Not connected")
            if t630.connected, let battery = t630.battery {
                LabeledContent("Battery") {
                    // battery.0percent … battery.100percent, nearest quarter
                    Label("\(battery)%", systemImage: "battery.\(min(100, (battery + 12) / 25 * 25))percent")
                }
            }
            permissionRow("Input Monitoring", allowed: permissions.inputMonitoring, pane: "Privacy_ListenEvent")
            permissionRow("Accessibility", allowed: permissions.accessibility, pane: "Privacy_Accessibility")
            if !permissions.inputMonitoring || !permissions.accessibility {
                Text("Allow LogiSwipe under System Settings → Privacy & Security, then quit and reopen it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var pointerSection: some View {
        Section("Pointer") {
            Toggle("Custom tracking speed", isOn: $settings.customSpeed)
            if settings.customSpeed {
                Slider(value: $settings.trackingSpeed, in: 0...6) {
                    Text(String(format: "%.1f", settings.trackingSpeed))
                } minimumValueLabel: { Text("Slow") } maximumValueLabel: { Text("Fast") }
                Text("3.0 is Fast in System Settings.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var scrollingSection: some View {
        Section("Scrolling") {
            Toggle("Smooth scrolling", isOn: $settings.smoothScrolling)
            if settings.smoothScrolling {
                Slider(value: $settings.scrollSpeed, in: 0.25...3) {
                    Text(String(format: "%.2g×", settings.scrollSpeed))
                } minimumValueLabel: { Text("Slow") } maximumValueLabel: { Text("Fast") }
            }
            Toggle("Reverse scroll direction", isOn: $settings.reverseScrolling)
            Text("Smooth scrolling follows your finger like a trackpad, with momentum.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var clicksSection: some View {
        Section("Clicks") {
            actionPicker("Left click", $settings.leftClick, key: ClickKind.left.key)
            actionPicker("Right click", $settings.rightClick, key: ClickKind.right.key)
            actionPicker("Middle click", $settings.middleClick, key: ClickKind.middle.key)
            actionPicker("Two-finger click", $settings.twoFingerClick, key: ClickKind.twoFinger.key,
                         options: ClickAction.twoFingerOptions)
        }
    }

    private var gesturesSection: some View {
        Section("Gestures") {
            swipePicker("Swipe with 1 finger", $settings.oneFingerSwipe)
            swipePicker("Swipe with 2 fingers", $settings.twoFingerSwipe)
            actionPicker("Double-tap with 1 finger", $settings.oneFingerDoubleTap, key: Gesture.oneFingerDoubleTap.rawValue)
            actionPicker("Double-tap with 2 fingers", $settings.twoFingerDoubleTap, key: Gesture.twoFingerDoubleTap.rawValue)
            actionPicker("Swipe up with 3 fingers", $settings.threeFingerSwipeUp, key: Gesture.threeFingerSwipeUp.rawValue)
            actionPicker("Swipe down with 3 fingers", $settings.threeFingerSwipeDown, key: Gesture.threeFingerSwipeDown.rawValue)
        }
    }

    private var appSection: some View {
        Section {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            LabeledContent("Version", value: Self.version)
            HStack {
                Spacer()
                Button("Quit LogiSwipe") { NSApp.terminate(nil) }
            }
        }
    }

    /// CFBundleShortVersionString from Info.plist.
    private static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"

    /// Status plus a button that opens that list in System Settings → Privacy & Security.
    private func permissionRow(_ title: String, allowed: Bool, pane: String) -> some View {
        LabeledContent(title) {
            HStack {
                Text(allowed ? "Allowed" : "Not allowed")
                Button {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Open \(title) in System Settings")
            }
        }
    }

    private func swipePicker(_ title: String, _ value: Binding<SwipeAction>) -> some View {
        Picker(title, selection: value) {
            ForEach(SwipeAction.allCases) { Text($0.title).tag($0) }
        }
    }

    private enum Choice<Action: Hashable>: Hashable {
        case action(Action), chooseApp
    }

    /// `key` is the setting's UserDefaults key, under which the app for "Open app" is kept.
    /// Once an app is chosen, "Open app" shows its name, and "Choose another app…" picks a new one.
    private func actionPicker<Action: AppOpeningAction>(_ title: String, _ value: Binding<Action>, key: String,
                                                        options: [Action] = Array(Action.allCases)) -> some View {
        let app = settings.apps[key].map { FileManager.default.displayName(atPath: $0) }
        let selection = Binding<Choice<Action>>(
            get: { .action(value.wrappedValue) },
            set: { choice in
                if case .action(let action) = choice, action != .openApp || app != nil {
                    value.wrappedValue = action
                    return
                }
                // After the picker's menu has closed.
                DispatchQueue.main.async {
                    guard let path = chooseApp() else {
                        value.wrappedValue = value.wrappedValue  // put the picker back
                        return
                    }
                    settings.apps[key] = path
                    value.wrappedValue = .openApp
                }
            })
        return Picker(title, selection: selection) {
            ForEach(options) { action in
                Text(action == .openApp ? app.map { "Open \($0)" } ?? action.title : action.title)
                    .tag(Choice.action(action))
            }
            if app != nil && options.contains(.openApp) {
                Text("Choose another app…").tag(Choice<Action>.chooseApp)
            }
        }
    }

    private func chooseApp() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Choose"
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}
