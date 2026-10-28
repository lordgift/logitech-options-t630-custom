import AppKit

enum Actions {
    private static let keyLeftArrow: CGKeyCode = 123, keyRightArrow: CGKeyCode = 124
    private static let keyLeftBracket: CGKeyCode = 33, keyRightBracket: CGKeyCode = 30
    private static let keyDownArrow: CGKeyCode = 125, key3: CGKeyCode = 20, key4: CGKeyCode = 21, key5: CGKeyCode = 23
    private static let keyX: CGKeyCode = 7, keyC: CGKeyCode = 8, keyV: CGKeyCode = 9, keyF11: CGKeyCode = 103

    /// A trackpad pinch under the pointer: `magnification` since the previous event (1.0 doubles the
    /// size). `phase`: 1 began, 2 changed, 4 ended. Wrapped in begin and end gesture events like a
    /// trackpad's. Unlike dock swipes, macOS 27 still delivers posted magnify gestures.
    static func magnify(_ magnification: Double, phase: Int64) {
        if phase == 1 { postGesture(hidType: 61) }
        postGesture(hidType: 8) {
            $0.setIntegerValueField(CGEventField(rawValue: 132)!, value: phase)
            $0.setDoubleValueField(CGEventField(rawValue: 113)!, value: magnification)
        }
        if phase == 4 { postGesture(hidType: 62) }
    }

    /// Posts a gesture event (type 29). `hidType`: 8 magnify, 61 begin gesture, 62 end gesture.
    private static func postGesture(hidType: Int64, _ fill: (CGEvent) -> Void = { _ in }) {
        guard let e = CGEvent(source: nil) else { return }
        e.setIntegerValueField(CGEventField(rawValue: 55)!, value: 29)
        e.setIntegerValueField(CGEventField(rawValue: 110)!, value: hidType)
        fill(e)
        e.post(tap: .cghidEventTap)
    }

    /// `fingersMovedLeft` follows the trackpad: fingers moving left go to the next desktop / page.
    static func swipe(_ action: SwipeAction, fingersMovedLeft left: Bool) {
        switch action {
        case .scroll, .none:
            break
        case .desktops:
            // Same modifiers macOS registers for "Move left/right a space" (control + fn).
            // Pressed even at the last desktop, in case the HUD's idea of where we are is wrong.
            DesktopHUD.shared.swiped(next: left)
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
        case .screenshotScreen: perform(GestureAction.screenshotScreen)
        case .screenshot: perform(GestureAction.screenshot)
        case .screenshotTools: perform(GestureAction.screenshotTools)
        case .appWindows: perform(GestureAction.appWindows)
        case .missionControl: perform(GestureAction.missionControl)
        case .showDesktop: perform(GestureAction.showDesktop)
        case .cut: perform(GestureAction.cut)
        case .copy: perform(GestureAction.copy)
        case .paste: perform(GestureAction.paste)
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
        case .screenshotScreen: press(key3, [.maskCommand, .maskShift])
        case .screenshot: press(key4, [.maskCommand, .maskShift])
        case .screenshotTools: press(key5, [.maskCommand, .maskShift])
        // Same modifiers macOS registers for "Application windows" (control + fn, like the desktop switch).
        case .appWindows: press(keyDownArrow, [.maskControl, .maskSecondaryFn])
        case .missionControl: open("/System/Applications/Mission Control.app")
        // F11 is "Show Desktop" in Keyboard Shortcuts → Mission Control; a function key carries fn.
        case .showDesktop: press(keyF11, .maskSecondaryFn)
        case .cut: press(keyX, .maskCommand)
        case .copy: press(keyC, .maskCommand)
        case .paste: press(keyV, .maskCommand)
        case .openApp: if let app { open(app) }
        case .none: break
        }
    }

    private static func open(_ path: String) {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration())
    }

    private static let modifierKeys: [(flag: CGEventFlags, key: CGKeyCode)] =
        [(.maskCommand, 55), (.maskShift, 56), (.maskAlternate, 58), (.maskControl, 59)]

    /// Presses and releases the modifier keys around `key` like a keyboard does. Apps that track
    /// modifiers themselves (Figma) otherwise think Command stays down, and scrolling then zooms.
    /// Fn is only a flag: pressing it can bring up the emoji picker or dictation.
    private static func press(_ key: CGKeyCode, _ flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        let modifiers = modifierKeys.filter { flags.contains($0.flag) }
        var held = flags.intersection(.maskSecondaryFn)
        func post(_ key: CGKeyCode, down: Bool) {
            let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down)
            e?.flags = held
            e?.post(tap: .cghidEventTap)
        }
        for modifier in modifiers {
            held.insert(modifier.flag)
            post(modifier.key, down: true)
        }
        post(key, down: true)
        post(key, down: false)
        for modifier in modifiers.reversed() {
            held.remove(modifier.flag)
            post(modifier.key, down: false)
        }
    }
}
