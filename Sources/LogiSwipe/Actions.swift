import AppKit

enum Actions {
    private static let keyLeftArrow: CGKeyCode = 123, keyRightArrow: CGKeyCode = 124
    private static let keyLeftBracket: CGKeyCode = 33, keyRightBracket: CGKeyCode = 30

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

    /// Click actions that aren't a mouse button.
    static func perform(_ action: ClickAction) {
        switch action {
        case .back: press(keyLeftBracket, .maskCommand)
        case .forward: press(keyRightBracket, .maskCommand)
        case .missionControl:
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Mission Control.app"),
                                               configuration: NSWorkspace.OpenConfiguration())
        case .left, .right, .middle, .none:
            break
        }
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
