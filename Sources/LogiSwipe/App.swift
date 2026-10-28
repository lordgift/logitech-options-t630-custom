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
    @State private var confirmRestore = false

    // Two columns of cards, like Control Center's modules, so the panel fits on screen without scrolling.
    var body: some View {
        HStack(alignment: .top, spacing: Self.spacing) {
            VStack(spacing: Self.spacing) {
                statusSection
                pointerSection
                scrollingSection
                appSection
            }
            VStack(spacing: Self.spacing) {
                clicksSection
                gesturesSection
            }
        }
        .labeledContentStyle(RowStyle())
        .toggleStyle(RowToggleStyle())
        // Plain text and a chevron, as menus look in a grouped form, rather than bezeled buttons.
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.visible)
        .padding(Self.spacing)
        .frame(width: 680)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { t630.readBattery() }
        .modifier(GlassPanel())
    }

    private static let spacing = 14.0

    private var statusSection: some View {
        Card {
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
        Card("Pointer") {
            Toggle("Custom tracking speed", isOn: $settings.customSpeed)
            if settings.customSpeed {
                speedSlider(String(format: "%.1f", settings.trackingSpeed), $settings.trackingSpeed,
                            in: 0...Self.maxTrackingSpeed, mark: Settings.systemFastSpeed)
                Text("The mark is Fast in System Settings (3.0).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// macOS takes speeds past its own fastest, 3.0.
    private static let maxTrackingSpeed = 6.0

    /// A Slow–Fast slider, with a tick on its track at `mark`.
    private func speedSlider(_ title: String, _ value: Binding<Double>, in range: ClosedRange<Double>,
                             mark: Double? = nil) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Text("Slow")
                Slider(value: value, in: range)
                    .labelsHidden()
                    .background {
                        if let mark {
                            GeometryReader { g in
                                let knob = 10.0  // the track's ends are half a knob in from the slider's sides
                                Capsule()
                                    .fill(.secondary)
                                    .frame(width: 2, height: 12)
                                    .position(x: knob + (g.size.width - 2 * knob) * (mark - range.lowerBound)
                                                / (range.upperBound - range.lowerBound),
                                              y: g.size.height / 2)
                            }
                            .allowsHitTesting(false)
                        }
                    }
                Text("Fast")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private var scrollingSection: some View {
        Card("Scrolling") {
            Toggle("Smooth scrolling", isOn: $settings.smoothScrolling)
            if settings.smoothScrolling {
                speedSlider(String(format: "%.2g×", settings.scrollSpeed), $settings.scrollSpeed, in: 0.25...3, mark: 1)
            }
            Text("Follows your finger like a trackpad, with momentum.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Reverse scroll direction", isOn: $settings.reverseScrolling)
            Text(settings.reverseScrolling
                 ? "Your mouse scrolls the other way from your Mac's Natural scrolling. The trackpad is unchanged."
                 : "Your mouse follows your Mac's Natural scrolling setting, like the trackpad.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var clicksSection: some View {
        Card("Clicks") {
            SubGroup("Normal") {
                actionPicker("Left", $settings.leftClick, key: ClickKind.left.key)
                actionPicker("Right", $settings.rightClick, key: ClickKind.right.key)
                actionPicker("Middle", $settings.middleClick, key: ClickKind.middle.key)
            }
            Divider()
            SubGroup("Advanced") {
                actionPicker("Hold middle", $settings.middleClickHold, key: Gesture.middleClickHold.rawValue)
                actionPicker("Two-finger click", $settings.twoFingerClick, key: ClickKind.twoFinger.key,
                             options: ClickAction.twoFingerOptions)
            }
        }
    }

    private var gesturesSection: some View {
        Card("Gestures") {
            SubGroup("Swipe") {
                swipePicker("1 finger", $settings.oneFingerSwipe, scroll: "Scroll sideways")
                swipePicker("2 fingers", $settings.twoFingerSwipe, scroll: "Scroll freely")
                swipePicker("3 fingers", $settings.threeFingerSwipe, scroll: nil)
                actionPicker("3 fingers up", $settings.threeFingerSwipeUp, key: Gesture.threeFingerSwipeUp.rawValue)
                actionPicker("3 fingers down", $settings.threeFingerSwipeDown, key: Gesture.threeFingerSwipeDown.rawValue)
            }
            Divider()
            SubGroup("Double-tap") {
                actionPicker("1 finger", $settings.oneFingerDoubleTap, key: Gesture.oneFingerDoubleTap.rawValue)
                actionPicker("2 fingers", $settings.twoFingerDoubleTap, key: Gesture.twoFingerDoubleTap.rawValue)
            }
            Divider()
            SubGroup("Pinch & Spread") {
                actionPicker("4 fingers spread", $settings.fourFingerSpread, key: Gesture.fourFingerSpread.rawValue)
                Toggle("Zoom in and out", isOn: $settings.pinchToZoom)
            }
        }
    }

    private var appSection: some View {
        Card {
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
                Button("Restore Defaults…") { confirmRestore = true }
                Spacer()
                Button("Quit LogiSwipe") { NSApp.terminate(nil) }
            }
            .buttonStyle(.bordered)
            .confirmationDialog("Restore all settings to their defaults?", isPresented: $confirmRestore) {
                Button("Restore Defaults", role: .destructive) { settings.restoreDefaults() }
            } message: {
                Text("This also forgets the apps chosen for Open app. Launch at login stays as it is.")
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

    /// `scroll` titles the scroll option, which is left out when nil.
    private func swipePicker(_ title: String, _ value: Binding<SwipeAction>, scroll: String?) -> some View {
        LabeledContent(title) {
            Picker(title, selection: value) {
                ForEach(SwipeAction.allCases.filter { $0 != .scroll || scroll != nil }) {
                    Text($0 == .scroll ? scroll! : $0.title).tag($0)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    /// A menu rather than a Picker, so Cut / Copy / Paste can sit in an Edit submenu.
    /// `key` is the setting's UserDefaults key, under which the app for "Open app" is kept.
    /// Once an app is chosen, "Open app" shows its name, and "Choose another app…" picks a new one.
    private func actionPicker<Action: MenuAction>(_ title: String, _ value: Binding<Action>, key: String,
                                                  options: [Action] = Array(Action.allCases)) -> some View {
        let app = settings.apps[key].map { FileManager.default.displayName(atPath: $0) }
        let appIcon = settings.apps[key].map(Self.icon)
        func name(_ action: Action) -> String {
            action == .openApp ? app.map { "Open \($0)" } ?? action.title : action.title
        }
        func choose(_ action: Action) {
            guard action == .openApp else {
                value.wrappedValue = action
                return
            }
            // After the menu has closed.
            DispatchQueue.main.async {
                guard let path = chooseApp() else { return }
                settings.apps[key] = path
                value.wrappedValue = .openApp
            }
        }
        /// The action's name, with the chosen app's icon for Open app.
        func label(_ action: Action) -> some View {
            Label {
                Text(name(action))
            } icon: {
                if action == .openApp, let appIcon { Image(nsImage: appIcon).renderingMode(.original) }
            }
        }
        func item(_ action: Action) -> some View {
            Toggle(isOn: Binding(get: { value.wrappedValue == action },
                                 set: { if $0 || action == .openApp { choose(action) } })) {
                label(action)
            }
        }
        // Mouse and macOS actions under headers, Capture screen and Edit as submenus, then Open app and Do nothing.
        let groups = ActionGroup.allCases.map { group in (group, options.filter { $0.group == group }) }
            .filter { !$0.1.isEmpty }
        return LabeledContent(title) {
            Menu {
                ForEach(groups, id: \.0) { group, actions in
                    switch group {
                    case .mouse, .navigate, .system:
                        Section(group.title!) { ForEach(actions) { item($0) } }
                    case .capture:
                        Divider()
                        Menu(group.title!) { ForEach(actions) { item($0) } }
                    case .edit:
                        if !groups.contains(where: { $0.0 == .capture }) { Divider() }
                        Menu(group.title!) { ForEach(actions) { item($0) } }
                    case .app:
                        Divider()
                        ForEach(actions) { item($0) }
                        if app != nil { Button("Choose another app…") { choose(.openApp) } }
                    case .none:
                        Divider()
                        ForEach(actions) { item($0) }
                    }
                }
                // Menu items are checkmarks, not the panel's switch rows.
                .toggleStyle(.automatic)
                .buttonStyle(.automatic)
            } label: {
                // Just the app's name: its icon says it opens it, and keeps the setting's title to one line.
                if value.wrappedValue == .openApp, let app, let appIcon {
                    Label { Text(app) } icon: { Image(nsImage: appIcon).renderingMode(.original) }
                } else {
                    Text(name(value.wrappedValue))
                }
            }
            .fixedSize()
        }
    }

    /// An app's icon at menu size.
    private static func icon(_ path: String) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 16, height: 16)
        icon.isTemplate = false  // menus otherwise draw it in one color
        return icon
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

/// The panel as Liquid Glass on macOS 26 and later, instead of the menu bar extra's own background.
private struct GlassPanel: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .background { Color.clear.glassEffect(.regular, in: .rect(cornerRadius: 26)) }
                .containerBackground(.clear, for: .window)
        } else {
            content
        }
    }
}

/// A group of settings: an optional header, then its rows on a rounded card, glass on macOS 26 and later.
private struct Card<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title).font(.headline).padding(.leading, 8)
            }
            VStack(alignment: .leading, spacing: 10) { content }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(CardBackground())
        }
    }
}

private struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 20))
        } else {
            content.background(.background.secondary.opacity(0.6), in: .rect(cornerRadius: 12))
        }
    }
}

/// A row: the title on the left, the value or control on the right, as in a grouped form.
private struct RowStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 12)
            configuration.content.foregroundStyle(.secondary)
        }
    }
}

/// A switch on the right of its title, as in a grouped form.
private struct RowToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 12)
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

/// A group of rows inside a card, under a small header of its own.
private struct SubGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            content.padding(.leading, 10)
        }
    }
}
