import Foundation

/// An action list shown as a menu grouped by `ActionGroup`, with Cut / Copy / Paste in an Edit
/// submenu and an action that opens an app the user picks, stored per setting in `Settings.apps`.
protocol MenuAction: Hashable, Identifiable, CaseIterable {
    static var openApp: Self { get }
    var title: String { get }
    var group: ActionGroup { get }
}

/// The groups of an action menu, in menu order.
enum ActionGroup: CaseIterable {
    case mouse, navigate, system, edit, app, none

    /// Header of the group's section; nil for the groups shown without one.
    var title: String? {
        switch self {
        case .mouse: "Click"
        case .navigate: "Navigate"
        case .system: "macOS"
        case .edit: "Edit"
        case .app, .none: nil
        }
    }
}

enum ClickAction: String, MenuAction {
    case left, right, middle, back, forward, launchpad, screenshot, appWindows, missionControl, showDesktop, cut, copy, paste,
         openApp, none

    /// What a two-finger click can do: the gestures' actions, plus a middle click.
    static let twoFingerOptions: [ClickAction] = [.middle, .launchpad, .screenshot, .appWindows, .missionControl, .showDesktop,
                                                  .cut, .copy, .paste, .openApp, .none]

    var id: Self { self }
    var group: ActionGroup {
        switch self {
        case .left, .right, .middle: .mouse
        case .back, .forward: .navigate
        case .launchpad, .screenshot, .appWindows, .missionControl, .showDesktop: .system
        case .cut, .copy, .paste: .edit
        case .openApp: .app
        case .none: .none
        }
    }
    var title: String {
        switch self {
        case .left: "Left click"
        case .right: "Right click"
        case .middle: "Middle click"
        case .back: "Back"
        case .forward: "Forward"
        case .launchpad: GestureAction.launchpad.title
        case .screenshot: GestureAction.screenshot.title
        case .appWindows: GestureAction.appWindows.title
        case .missionControl: GestureAction.missionControl.title
        case .showDesktop: GestureAction.showDesktop.title
        case .cut: GestureAction.cut.title
        case .copy: GestureAction.copy.title
        case .paste: GestureAction.paste.title
        case .openApp: GestureAction.openApp.title
        case .none: "Do nothing"
        }
    }
}

enum SwipeAction: String, CaseIterable, Identifiable {
    case scroll, desktops, backForward, none

    var id: Self { self }
    var title: String {
        switch self {
        case .scroll: "Scroll sideways"
        case .desktops: "Switch desktops"
        case .backForward: "Back / Forward"
        case .none: "Do nothing"
        }
    }
}

enum GestureAction: String, MenuAction {
    case launchpad, screenshot, appWindows, missionControl, showDesktop, cut, copy, paste, openApp, none

    var id: Self { self }
    var group: ActionGroup {
        switch self {
        case .launchpad, .screenshot, .appWindows, .missionControl, .showDesktop: .system
        case .cut, .copy, .paste: .edit
        case .openApp: .app
        case .none: .none
        }
    }
    var title: String {
        switch self {
        case .launchpad: "Launchpad"
        case .screenshot: "Capture screen"
        case .appWindows: "App Exposé"
        case .missionControl: "Mission Control"
        case .showDesktop: "Show Desktop"
        case .cut: "Cut"
        case .copy: "Copy"
        case .paste: "Paste"
        case .openApp: "Open app…"
        case .none: "Do nothing"
        }
    }
}

/// The gestures that perform a `GestureAction`; the raw value is the setting's UserDefaults key.
enum Gesture: String {
    case oneFingerDoubleTap, twoFingerDoubleTap, threeFingerSwipeUp, threeFingerSwipeDown, fourFingerSpread, middleClickHold
}

/// User settings, saved in UserDefaults. Read from the event tap and HID callbacks,
/// so everything here runs on the main thread.
final class Settings: ObservableObject {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    @Published var enabled: Bool { didSet { save(enabled, "enabled"); T630.shared.applyTrackingSpeed() } }
    @Published var customSpeed: Bool { didSet { save(customSpeed, "customSpeed"); T630.shared.applyTrackingSpeed() } }
    /// Same scale as System Settings → Mouse → Tracking speed, where Fast is 3.
    @Published var trackingSpeed: Double { didSet { save(trackingSpeed, "trackingSpeed"); T630.shared.applyTrackingSpeed() } }
    /// System Settings' Fast, its fastest pointer speed.
    static let systemFastSpeed = 3.0
    /// Flips the T630's scroll direction.
    @Published var reverseScrolling: Bool { didSet { save(reverseScrolling, "reverseScrolling") } }
    /// Scroll from the finger position like a trackpad, instead of the mouse's coarse wheel steps.
    @Published var smoothScrolling: Bool { didSet { save(smoothScrolling, "smoothScrolling") } }
    /// Two fingers spreading or closing zoom in or out.
    @Published var pinchToZoom: Bool { didSet { save(pinchToZoom, "pinchToZoom") } }
    /// Multiplier for smooth scrolling distance.
    @Published var scrollSpeed: Double { didSet { save(scrollSpeed, "scrollSpeed") } }
    @Published var leftClick: ClickAction { didSet { save(leftClick.rawValue, "leftClick") } }
    @Published var rightClick: ClickAction { didSet { save(rightClick.rawValue, "rightClick") } }
    @Published var middleClick: ClickAction { didSet { save(middleClick.rawValue, "middleClick") } }
    @Published var twoFingerClick: ClickAction { didSet { save(twoFingerClick.rawValue, "twoFingerClick") } }
    @Published var oneFingerSwipe: SwipeAction { didSet { save(oneFingerSwipe.rawValue, "oneFingerSwipe") } }
    /// `.scroll` scrolls in any direction with two fingers.
    @Published var twoFingerSwipe: SwipeAction { didSet { save(twoFingerSwipe.rawValue, "twoFingerSwipe") } }
    /// Sideways; never `.scroll`.
    @Published var threeFingerSwipe: SwipeAction { didSet { save(threeFingerSwipe.rawValue, "threeFingerSwipe") } }
    @Published var oneFingerDoubleTap: GestureAction { didSet { save(oneFingerDoubleTap.rawValue, "oneFingerDoubleTap") } }
    @Published var twoFingerDoubleTap: GestureAction { didSet { save(twoFingerDoubleTap.rawValue, "twoFingerDoubleTap") } }
    @Published var threeFingerSwipeUp: GestureAction { didSet { save(threeFingerSwipeUp.rawValue, "threeFingerSwipeUp") } }
    @Published var threeFingerSwipeDown: GestureAction { didSet { save(threeFingerSwipeDown.rawValue, "threeFingerSwipeDown") } }
    /// Spreading four or more fingers apart, as a trackpad shows the desktop.
    @Published var fourFingerSpread: GestureAction { didSet { save(fourFingerSpread.rawValue, "fourFingerSpread") } }
    /// Holding a middle click; Do nothing makes middle clicks go through without waiting.
    @Published var middleClickHold: GestureAction { didSet { save(middleClickHold.rawValue, "middleClickHold") } }
    /// Path of the app each "Open app" action opens, keyed by its setting's UserDefaults key.
    @Published var apps: [String: String] { didSet { save(apps, "apps") } }

    private init() {
        defaults.register(defaults: [
            "enabled": true,
            "customSpeed": false,
            "trackingSpeed": defaults.object(forKey: "com.apple.mouse.scaling") as? Double ?? 1.0,
            "reverseScrolling": false,
            "smoothScrolling": true,
            "pinchToZoom": true,
            "scrollSpeed": 1.0,
        ])
        enabled = defaults.bool(forKey: "enabled")
        customSpeed = defaults.bool(forKey: "customSpeed")
        trackingSpeed = defaults.double(forKey: "trackingSpeed")
        reverseScrolling = defaults.bool(forKey: "reverseScrolling")
        smoothScrolling = defaults.bool(forKey: "smoothScrolling")
        pinchToZoom = defaults.bool(forKey: "pinchToZoom")
        scrollSpeed = defaults.double(forKey: "scrollSpeed")
        leftClick = Self.load(defaults, "leftClick") ?? .left
        rightClick = Self.load(defaults, "rightClick") ?? .right
        middleClick = Self.load(defaults, "middleClick") ?? .middle
        twoFingerClick = (Self.load(defaults, "twoFingerClick") as ClickAction?)
            .flatMap { ClickAction.twoFingerOptions.contains($0) ? $0 : nil } ?? .copy
        oneFingerSwipe = Self.load(defaults, "oneFingerSwipe") ?? .backForward
        // Like a Mac trackpad: two fingers scroll, three switch desktops.
        twoFingerSwipe = Self.load(defaults, "twoFingerSwipe") ?? .scroll
        threeFingerSwipe = (Self.load(defaults, "threeFingerSwipe") as SwipeAction?).flatMap { $0 == .scroll ? nil : $0 } ?? .desktops
        oneFingerDoubleTap = Self.load(defaults, "oneFingerDoubleTap") ?? .appWindows
        twoFingerDoubleTap = Self.load(defaults, "twoFingerDoubleTap") ?? .paste
        threeFingerSwipeUp = Self.load(defaults, "threeFingerSwipeUp") ?? .missionControl
        threeFingerSwipeDown = Self.load(defaults, "threeFingerSwipeDown") ?? .none
        fourFingerSpread = Self.load(defaults, "fourFingerSpread") ?? .showDesktop
        middleClickHold = Self.load(defaults, "middleClickHold") ?? .screenshot
        apps = defaults.dictionary(forKey: "apps") as? [String: String] ?? [:]
    }

    /// Every setting back to its default, including the apps chosen for Open app.
    func restoreDefaults() {
        for key in defaults.dictionaryRepresentation().keys where Self.keys.contains(key) {
            defaults.removeObject(forKey: key)
        }
        // A fresh instance reads the defaults, the same way launching does.
        let fresh = Settings()
        enabled = fresh.enabled
        customSpeed = fresh.customSpeed
        trackingSpeed = fresh.trackingSpeed
        reverseScrolling = fresh.reverseScrolling
        smoothScrolling = fresh.smoothScrolling
        pinchToZoom = fresh.pinchToZoom
        scrollSpeed = fresh.scrollSpeed
        leftClick = fresh.leftClick
        rightClick = fresh.rightClick
        middleClick = fresh.middleClick
        twoFingerClick = fresh.twoFingerClick
        oneFingerSwipe = fresh.oneFingerSwipe
        twoFingerSwipe = fresh.twoFingerSwipe
        threeFingerSwipe = fresh.threeFingerSwipe
        oneFingerDoubleTap = fresh.oneFingerDoubleTap
        twoFingerDoubleTap = fresh.twoFingerDoubleTap
        threeFingerSwipeUp = fresh.threeFingerSwipeUp
        threeFingerSwipeDown = fresh.threeFingerSwipeDown
        fourFingerSpread = fresh.fourFingerSpread
        middleClickHold = fresh.middleClickHold
        apps = fresh.apps
    }

    /// The UserDefaults keys of the settings above.
    private static let keys: Set<String> = [
        "enabled", "customSpeed", "trackingSpeed", "reverseScrolling", "smoothScrolling", "pinchToZoom", "scrollSpeed",
        "leftClick", "rightClick", "middleClick", "twoFingerClick", "oneFingerSwipe", "twoFingerSwipe", "threeFingerSwipe",
        "oneFingerDoubleTap", "twoFingerDoubleTap", "threeFingerSwipeUp", "threeFingerSwipeDown", "fourFingerSpread",
        "middleClickHold", "apps",
    ]

    func clickAction(for kind: ClickKind) -> ClickAction {
        switch kind {
        case .left: leftClick
        case .right: rightClick
        case .middle: middleClick
        case .twoFinger: twoFingerClick
        }
    }

    func swipeAction(fingers: Int) -> SwipeAction {
        fingers >= 3 ? threeFingerSwipe : fingers == 2 ? twoFingerSwipe : oneFingerSwipe
    }

    func gestureAction(for gesture: Gesture) -> GestureAction {
        switch gesture {
        case .oneFingerDoubleTap: oneFingerDoubleTap
        case .twoFingerDoubleTap: twoFingerDoubleTap
        case .threeFingerSwipeUp: threeFingerSwipeUp
        case .threeFingerSwipeDown: threeFingerSwipeDown
        case .fourFingerSpread: fourFingerSpread
        case .middleClickHold: middleClickHold
        }
    }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }

    private static func load<T: RawRepresentable<String>>(_ defaults: UserDefaults, _ key: String) -> T? {
        defaults.string(forKey: key).flatMap(T.init(rawValue:))
    }
}
