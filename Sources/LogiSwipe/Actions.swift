import AppKit

enum Actions {
    private static let keyLeftArrow: CGKeyCode = 123, keyRightArrow: CGKeyCode = 124
    private static let keyLeftBracket: CGKeyCode = 33, keyRightBracket: CGKeyCode = 30
    private static let keyDownArrow: CGKeyCode = 125, key4: CGKeyCode = 21

    /// `fingersMovedLeft` follows the trackpad: fingers moving left go to the next desktop / page.
    static func swipe(_ action: SwipeAction, fingersMovedLeft left: Bool) {
        switch action {
        case .scroll, .none:
            break
        case .desktops:
            // Same modifiers macOS registers for "Move left/right a space" (control + fn).
            press(left ? keyRightArrow : keyLeftArrow, [.maskControl, .maskSecondaryFn])
        case .backForward:
            press(left ? keyRightBracket : keyLeftBracket, .maskCommand)
        }
    }

    /// Click actions that aren't a mouse button. `app` is the path that `.openApp` opens.
    static func perform(_ action: ClickAction, app: String?) {
        switch action {
        case .back: press(keyLeftBracket, .maskCommand)
        case .forward: press(keyRightBracket, .maskCommand)
        case .launchpad: perform(GestureAction.launchpad)
        case .screenshot: perform(GestureAction.screenshot)
        case .appWindows: perform(GestureAction.appWindows)
        case .missionControl: perform(GestureAction.missionControl)
        case .openApp: perform(GestureAction.openApp, app: app)
        case .left, .right, .middle, .none:
            break
        }
    }

    static func perform(_ action: GestureAction, app: String? = nil) {
        switch action {
        case .launchpad:
            // macOS 26 replaced Launchpad with Apps.
            let apps = "/System/Applications/Apps.app"
            open(FileManager.default.fileExists(atPath: apps) ? apps : "/System/Applications/Launchpad.app")
        case .screenshot: press(key4, [.maskCommand, .maskShift])
        // Same modifiers macOS registers for "Application windows" (control + fn, like the desktop switch).
        case .appWindows: press(keyDownArrow, [.maskControl, .maskSecondaryFn])
        case .missionControl: open("/System/Applications/Mission Control.app")
        case .openApp: if let app { open(app) }
        case .none: break
        }
    }

    private static func open(_ path: String) {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration())
    }

    private static func press(_ key: CGKeyCode, _ flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
    }
}
