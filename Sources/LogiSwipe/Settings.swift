import Foundation

enum ClickAction: String, CaseIterable, Identifiable {
    case left, right, middle, back, forward, missionControl, none

    var id: Self { self }
    var title: String {
        switch self {
        case .left: "Left click"
        case .right: "Right click"
        case .middle: "Middle click"
        case .back: "Back"
        case .forward: "Forward"
        case .missionControl: "Mission Control"
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

enum TapAction: String, CaseIterable, Identifiable {
    case launchpad, screenshot, appWindows, missionControl, none

    var id: Self { self }
    var title: String {
        switch self {
        case .launchpad: "Launchpad"
        case .screenshot: "Capture screen"
        case .appWindows: "App windows"
        case .missionControl: "Mission Control"
        case .none: "Do nothing"
        }
    }
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
    @Published var oneFingerDoubleTap: TapAction { didSet { save(oneFingerDoubleTap.rawValue, "oneFingerDoubleTap") } }
    @Published var twoFingerDoubleTap: TapAction { didSet { save(twoFingerDoubleTap.rawValue, "twoFingerDoubleTap") } }

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
        twoFingerClick = Self.load(defaults, "twoFingerClick") ?? .right
        oneFingerSwipe = Self.load(defaults, "oneFingerSwipe") ?? .scroll
        twoFingerSwipe = Self.load(defaults, "twoFingerSwipe") ?? .desktops
        oneFingerDoubleTap = Self.load(defaults, "oneFingerDoubleTap") ?? .none
        twoFingerDoubleTap = Self.load(defaults, "twoFingerDoubleTap") ?? .none
    }

    func clickAction(for kind: ClickKind) -> ClickAction {
        switch kind {
        case .left: leftClick
        case .right: rightClick
        case .middle: middleClick
        case .twoFinger: twoFingerClick
        }
    }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }

    private static func load<T: RawRepresentable<String>>(_ defaults: UserDefaults, _ key: String) -> T? {
        defaults.string(forKey: key).flatMap(T.init(rawValue:))
    }
}
