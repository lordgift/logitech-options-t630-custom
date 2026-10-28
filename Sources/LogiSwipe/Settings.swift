import Foundation

/// An action list with Cut / Copy / Paste (shown in an Edit submenu) and an action that opens
/// an app the user picks, stored per setting in `Settings.apps`.
protocol MenuAction: Hashable, Identifiable, CaseIterable {
    static var cut: Self { get }
    static var copy: Self { get }
    static var paste: Self { get }
    static var openApp: Self { get }
    var title: String { get }
}

extension MenuAction {
    var isEdit: Bool { self == .cut || self == .copy || self == .paste }
}

enum ClickAction: String, MenuAction {
    case left, right, middle, back, forward, launchpad, screenshot, appWindows, missionControl, cut, copy, paste, openApp, none

    /// What a two-finger click can do: the gestures' actions, plus a middle click.
    static let twoFingerOptions: [ClickAction] = [.middle, .launchpad, .screenshot, .appWindows, .missionControl,
                                                  .cut, .copy, .paste, .openApp, .none]

    var id: Self { self }
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
    case launchpad, screenshot, appWindows, missionControl, cut, copy, paste, openApp, none

    var id: Self { self }
    var title: String {
        switch self {
        case .launchpad: "Launchpad"
        case .screenshot: "Capture screen"
        case .appWindows: "App windows"
        case .missionControl: "Mission Control"
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
    case oneFingerDoubleTap, twoFingerDoubleTap, threeFingerSwipeUp, threeFingerSwipeDown
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
    /// Flips the T630's scroll direction.
    @Published var reverseScrolling: Bool { didSet { save(reverseScrolling, "reverseScrolling") } }
    /// Scroll from the finger position like a trackpad, instead of the mouse's coarse wheel steps.
    @Published var smoothScrolling: Bool { didSet { save(smoothScrolling, "smoothScrolling") } }
    /// Multiplier for smooth scrolling distance.
    @Published var scrollSpeed: Double { didSet { save(scrollSpeed, "scrollSpeed") } }
    @Published var leftClick: ClickAction { didSet { save(leftClick.rawValue, "leftClick") } }
    @Published var rightClick: ClickAction { didSet { save(rightClick.rawValue, "rightClick") } }
    @Published var middleClick: ClickAction { didSet { save(middleClick.rawValue, "middleClick") } }
    @Published var twoFingerClick: ClickAction { didSet { save(twoFingerClick.rawValue, "twoFingerClick") } }
    @Published var oneFingerSwipe: SwipeAction { didSet { save(oneFingerSwipe.rawValue, "oneFingerSwipe") } }
    @Published var twoFingerSwipe: SwipeAction { didSet { save(twoFingerSwipe.rawValue, "twoFingerSwipe") } }
    @Published var oneFingerDoubleTap: GestureAction { didSet { save(oneFingerDoubleTap.rawValue, "oneFingerDoubleTap") } }
    @Published var twoFingerDoubleTap: GestureAction { didSet { save(twoFingerDoubleTap.rawValue, "twoFingerDoubleTap") } }
    @Published var threeFingerSwipeUp: GestureAction { didSet { save(threeFingerSwipeUp.rawValue, "threeFingerSwipeUp") } }
    @Published var threeFingerSwipeDown: GestureAction { didSet { save(threeFingerSwipeDown.rawValue, "threeFingerSwipeDown") } }
    /// Path of the app each "Open app" action opens, keyed by its setting's UserDefaults key.
    @Published var apps: [String: String] { didSet { save(apps, "apps") } }

    private init() {
        defaults.register(defaults: [
            "enabled": true,
            "customSpeed": false,
            "trackingSpeed": defaults.object(forKey: "com.apple.mouse.scaling") as? Double ?? 1.0,
            "reverseScrolling": false,
            "smoothScrolling": true,
            "scrollSpeed": 1.0,
        ])
        enabled = defaults.bool(forKey: "enabled")
        customSpeed = defaults.bool(forKey: "customSpeed")
        trackingSpeed = defaults.double(forKey: "trackingSpeed")
        reverseScrolling = defaults.bool(forKey: "reverseScrolling")
        smoothScrolling = defaults.bool(forKey: "smoothScrolling")
        scrollSpeed = defaults.double(forKey: "scrollSpeed")
        leftClick = Self.load(defaults, "leftClick") ?? .left
        rightClick = Self.load(defaults, "rightClick") ?? .right
        middleClick = Self.load(defaults, "middleClick") ?? .middle
        twoFingerClick = (Self.load(defaults, "twoFingerClick") as ClickAction?)
            .flatMap { ClickAction.twoFingerOptions.contains($0) ? $0 : nil } ?? .none
        oneFingerSwipe = Self.load(defaults, "oneFingerSwipe") ?? .scroll
        twoFingerSwipe = Self.load(defaults, "twoFingerSwipe") ?? .desktops
        oneFingerDoubleTap = Self.load(defaults, "oneFingerDoubleTap") ?? .none
        twoFingerDoubleTap = Self.load(defaults, "twoFingerDoubleTap") ?? .none
        // Same as a Mac trackpad.
        threeFingerSwipeUp = Self.load(defaults, "threeFingerSwipeUp") ?? .missionControl
        threeFingerSwipeDown = Self.load(defaults, "threeFingerSwipeDown") ?? .appWindows
        apps = defaults.dictionary(forKey: "apps") as? [String: String] ?? [:]
    }

    func clickAction(for kind: ClickKind) -> ClickAction {
        switch kind {
        case .left: leftClick
        case .right: rightClick
        case .middle: middleClick
        case .twoFinger: twoFingerClick
        }
    }

    func gestureAction(for gesture: Gesture) -> GestureAction {
        switch gesture {
        case .oneFingerDoubleTap: oneFingerDoubleTap
        case .twoFingerDoubleTap: twoFingerDoubleTap
        case .threeFingerSwipeUp: threeFingerSwipeUp
        case .threeFingerSwipeDown: threeFingerSwipeDown
        }
    }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }

    private static func load<T: RawRepresentable<String>>(_ defaults: UserDefaults, _ key: String) -> T? {
        defaults.string(forKey: key).flatMap(T.init(rawValue:))
    }
}
