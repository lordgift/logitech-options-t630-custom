import AppKit

/// Rewrites clicks and scrolls that come from the T630, leaving every other device alone.
final class EventTap: ObservableObject {
    static let shared = EventTap()

    @Published private(set) var running = false
    private var tap: CFMachPort?
    private let senderField = CGEventField(rawValue: 87)!  // registry ID of the HID service
    /// Action of the T630 button currently held down, so its drags and release follow it.
    private var heldAction: ClickAction?

    /// Needs Accessibility; keeps retrying until it is granted.
    func start() {
        guard tap == nil else { return }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .leftMouseDragged,
                                    .rightMouseDown, .rightMouseUp, .rightMouseDragged, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: mask, callback: { _, type, event, _ in
            EventTap.shared.handle(type, event).map { Unmanaged.passUnretained($0) }
        }, userInfo: nil)
        guard let tap else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.start() }
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        running = true
        log.info("event tap started")
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return event
        }
        let settings = Settings.shared, t630 = T630.shared
        guard settings.enabled, t630.isT630(sender: event.getIntegerValueField(senderField)) else { return event }

        switch type {
        case .scrollWheel:
            return scroll(event)
        case .leftMouseDown, .rightMouseDown:
            // Left or right from where the finger is, rather than the mouse's own guess;
            // fall back to the mouse when no finger position is known.
            let x = t630.firstFingerX, y = t630.firstFingerY
            let kind: ClickKind = t630.fingers >= 2 ? .twoFinger
                : T630.middleZoneX.contains(x) && y >= 0 && y <= T630.middleMaxY ? .middle
                : x >= 0 ? (x >= T630.rightSideX ? .right : .left)
                : type == .rightMouseDown ? .right : .left
            let action = settings.clickAction(for: kind)
            log.info("click: \(String(describing: kind), privacy: .public) at \(x, privacy: .public),\(y, privacy: .public), \(t630.fingers, privacy: .public) fingers → \(action.rawValue, privacy: .public)")
            heldAction = action
            return remap(event, to: action, phase: 0)
        case .leftMouseDragged, .rightMouseDragged:
            guard let action = heldAction else { return event }
            return remap(event, to: action, phase: 1)
        case .leftMouseUp, .rightMouseUp:
            guard let action = heldAction else { return event }
            heldAction = nil
            return remap(event, to: action, phase: 2)
        default:
            return event
        }
    }

    /// phase: 0 down, 1 dragged, 2 up.
    private func remap(_ event: CGEvent, to action: ClickAction, phase: Int) -> CGEvent? {
        let button: CGMouseButton, types: [CGEventType]
        switch action {
        case .left: (button, types) = (.left, [.leftMouseDown, .leftMouseDragged, .leftMouseUp])
        case .right: (button, types) = (.right, [.rightMouseDown, .rightMouseDragged, .rightMouseUp])
        case .middle: (button, types) = (.center, [.otherMouseDown, .otherMouseDragged, .otherMouseUp])
        case .back, .forward, .missionControl, .none:
            if phase == 0 { Actions.perform(action) }
            return nil
        }
        event.type = types[phase]
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button.rawValue))
        return event
    }

    private func scroll(_ event: CGEvent) -> CGEvent? {
        let settings = Settings.shared, t630 = T630.shared
        // SmoothScroller posts its own scrolling from the finger position instead.
        if settings.smoothScrolling { return nil }
        // Each axis is carried three ways: line delta and point delta (integers), fixed-point delta.
        let vertical: (Int, Double, Int) = (Int(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)),
                                            event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1),
                                            Int(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)))
        var horizontal: (Int, Double, Int) = (Int(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)),
                                              event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2),
                                              Int(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)))
        // A sideways swipe that has its own action shouldn't also scroll.
        let swipe = t630.touchMaxFingers >= 2 ? settings.twoFingerSwipe : settings.oneFingerSwipe
        if swipe != .scroll {
            horizontal = (0, 0, 0)
            if vertical == (0, 0, 0) { return nil }
        }
        let sign = settings.reverseScrolling ? -1 : 1
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64(sign * vertical.0))
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Double(sign) * vertical.1)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(sign * vertical.2))
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: Int64(sign * horizontal.0))
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Double(sign) * horizontal.1)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(sign * horizontal.2))
        return event
    }
}
