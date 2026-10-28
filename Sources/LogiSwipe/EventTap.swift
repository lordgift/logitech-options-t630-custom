import AppKit

/// Rewrites clicks and scrolls that come from the T630, leaving every other device alone.
final class EventTap: ObservableObject {
    static let shared = EventTap()

    @Published private(set) var running = false
    private var tap: CFMachPort?
    private let senderField = CGEventField(rawValue: 87)!  // registry ID of the HID service
    /// Action of the T630 button currently held down, so its drags and release follow it.
    private var heldAction: ClickAction?
    /// A click (and its drags and release) held back until the mouse reports the fingers it was made with.
    private var waiting: [CGEvent] = []
    /// How long a click may wait for its finger report (seconds).
    private static let fingerWait = 0.05
    /// eventSourceUserData of the clicks posted after waiting, so the tap lets them through.
    private static let repostedMark: Int64 = 0x7630
    /// A middle click held back until it is let go (a click) or held for `holdTime` (Hold middle click).
    private var holding: (down: CGEvent, timer: DispatchWorkItem)?
    /// Seconds a middle click must be held, and points it may move meanwhile, to be a hold.
    private static let holdTime = 0.5, holdSlop = 6.0

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
        guard settings.enabled, event.getIntegerValueField(.eventSourceUserData) != Self.repostedMark,
              t630.isT630(sender: event.getIntegerValueField(senderField)) else { return event }

        switch type {
        case .scrollWheel:
            return scroll(event)
        case .leftMouseDown, .rightMouseDown:
            if t630.pressReported { return click(event) }
            // The second finger of a two-finger click can arrive in the same report as the press,
            // and that report can reach us just after the click does.
            waiting = [event.copy()!]
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.fingerWait) { self.fingersReported() }
            return nil
        case .leftMouseDragged, .rightMouseDragged, .leftMouseUp, .rightMouseUp:
            if !waiting.isEmpty {
                waiting.append(event.copy()!)
                return nil
            }
            return follow(event)
        default:
            return event
        }
    }

    /// Called when the mouse reports a press, and when a waiting click gives up on that.
    func fingersReported() {
        guard !waiting.isEmpty else { return }
        let events = waiting
        waiting = []
        for event in events {
            repost(event.type == .leftMouseDown || event.type == .rightMouseDown ? click(event) : follow(event))
        }
    }

    private func repost(_ event: CGEvent?) {
        event?.setIntegerValueField(.eventSourceUserData, value: Self.repostedMark)
        event?.post(tap: .cgSessionEventTap)
    }

    private func click(_ event: CGEvent) -> CGEvent? {
        let t630 = T630.shared
        // Left or right from where the clicking finger is, rather than the mouse's own guess;
        // fall back to the mouse when no finger position is known. A finger resting on the
        // mouse while another clicks doesn't make it a two-finger click.
        let x = t630.pressX, y = t630.pressY
        let kind: ClickKind = t630.fingersLandedTogether ? .twoFinger
            : T630.middleZoneX.contains(x) && y >= 0 && y <= T630.middleMaxY ? .middle
            : x >= 0 ? (x >= T630.rightSideX ? .right : .left)
            : event.type == .rightMouseDown ? .right : .left
        let action = Settings.shared.clickAction(for: kind)
        log.info("click: \(String(describing: kind), privacy: .public) at \(x, privacy: .public),\(y, privacy: .public), \(t630.fingers, privacy: .public) fingers → \(action.rawValue, privacy: .public)")
        heldAction = action
        let hold = Settings.shared.middleClickHold
        if kind == .middle && hold != .none {
            let timer = DispatchWorkItem { [weak self] in self?.held(hold) }
            holding = (event.copy()!, timer)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdTime, execute: timer)
            return nil
        }
        return remap(event, to: action, phase: 0, app: Settings.shared.apps[kind.key])
    }

    /// The held-back middle click was held down long enough.
    private func held(_ action: GestureAction) {
        guard holding != nil else { return }
        holding = nil
        heldAction = ClickAction.none  // its drags and release do nothing
        log.info("click: middle held → \(action.rawValue, privacy: .public)")
        Actions.perform(action, app: Settings.shared.apps[Gesture.middleClickHold.rawValue])
    }

    /// The drags and release of a click follow its action.
    private func follow(_ event: CGEvent) -> CGEvent? {
        guard let action = heldAction else { return event }
        let up = event.type == .leftMouseUp || event.type == .rightMouseUp
        if let holding {
            let start = holding.down.location, p = event.location
            if !up && hypot(p.x - start.x, p.y - start.y) <= Self.holdSlop { return nil }
            // Let go or dragged before the hold time: a middle click after all. Post the press and
            // this event ourselves, so they arrive in order.
            holding.timer.cancel()
            self.holding = nil
            repost(remap(holding.down, to: action, phase: 0, app: Settings.shared.apps[ClickKind.middle.key]))
            if up { heldAction = nil }
            repost(remap(event, to: action, phase: up ? 2 : 1))
            return nil
        }
        if up { heldAction = nil }
        return remap(event, to: action, phase: up ? 2 : 1)
    }

    /// phase: 0 down, 1 dragged, 2 up.
    /// `app` is the path an `.openApp` action opens.
    private func remap(_ event: CGEvent, to action: ClickAction, phase: Int, app: String? = nil) -> CGEvent? {
        let button: CGMouseButton, types: [CGEventType]
        switch action {
        case .left: (button, types) = (.left, [.leftMouseDown, .leftMouseDragged, .leftMouseUp])
        case .right: (button, types) = (.right, [.rightMouseDown, .rightMouseDragged, .rightMouseUp])
        case .middle: (button, types) = (.center, [.otherMouseDown, .otherMouseDragged, .otherMouseUp])
        case .back, .forward, .launchpad, .screenshot, .appWindows, .missionControl, .showDesktop, .cut, .copy, .paste,
             .openApp, .none:
            if phase == 0 { Actions.perform(action, app: app) }
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
        var vertical: (Int, Double, Int) = (Int(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)),
                                            event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1),
                                            Int(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)))
        var horizontal: (Int, Double, Int) = (Int(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)),
                                              event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2),
                                              Int(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)))
        // A sideways swipe that has its own action shouldn't also scroll.
        let swipe = settings.swipeAction(fingers: t630.touchMaxFingers)
        if swipe != .scroll {
            horizontal = (0, 0, 0)
            if vertical == (0, 0, 0) { return nil }
        }
        // Nor should a three-finger swipe up or down.
        if t630.touchMaxFingers >= 3 && (settings.threeFingerSwipeUp != .none || settings.threeFingerSwipeDown != .none) {
            vertical = (0, 0, 0)
            if horizontal == (0, 0, 0) { return nil }
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
