import AppKit

enum Actions {
    private static let keyLeftArrow: CGKeyCode = 123, keyRightArrow: CGKeyCode = 124

    /// Follows the trackpad: fingers moving left go to the desktop on the right.
    static func switchDesktop(fingersMovedLeft left: Bool) {
        // Same modifiers macOS registers for "Move left/right a space" (control + fn).
        press(left ? keyRightArrow : keyLeftArrow, [.maskControl, .maskSecondaryFn])
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
