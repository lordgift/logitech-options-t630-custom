import AppKit

/// Turns 1-finger movement on the T630 into trackpad-style scrolling: pixel deltas on every
/// report (~12 ms), scroll phases, and momentum after lifting. It replaces the mouse's own
/// wheel-like scrolling, which comes in coarse steps 30–140 ms apart.
///
/// Direction matches the mouse's own scrolling: its wheel ticks follow the sign of the finger's
/// X/Y movement, so positive finger movement scrolls positive here too (before Reverse).
final class SmoothScroller {
    static let shared = SmoothScroller()

    /// Pixels per X/Y unit at slow finger speeds (the surface is about 76 units wide).
    private static let pixelsPerUnit = 6.0
    /// Finger speed (units/s) at which each unit scrolls twice as far.
    private static let accelerationSpeed = 150.0
    /// Units the finger must move before scrolling starts, so clicks don't scroll.
    private static let deadZone = 2.0
    /// Momentum keeps this fraction of its speed every 1/60 s, and stops below `momentumStop` px/s.
    private static let momentumDecay = 0.95, momentumStop = 30.0

    private enum Axis { case vertical, horizontal }
    private var axis: Axis?                          // set once scrolling has started
    private var start: (x: Int, y: Int, time: Double)?
    private var last: (x: Int, y: Int, time: Double)?
    private var remainder = 0.0                      // sub-pixel scroll not posted yet
    private var velocity = 0.0                       // px/s, smoothed
    private var momentum: (timer: Timer, axis: Axis, velocity: Double, time: Double, started: Bool)?

    /// Every report while exactly one finger touches and no button is down.
    func move(x: Int, y: Int, allowHorizontal: Bool, touchAge: Double) {
        let now = ProcessInfo.processInfo.systemUptime
        guard let previous = last, let start else {
            stopMomentum()  // a new touch catches the page, as on a trackpad
            self.start = (x, y, now); last = (x, y, now)
            return
        }
        last = (x, y, now)

        guard let axis else {
            let tx = Double(x - start.x), ty = Double(y - start.y)
            if abs(ty) >= Self.deadZone && abs(ty) >= abs(tx) {
                self.axis = .vertical
                scroll(ty, over: now - start.time, phase: 1)
            } else if allowHorizontal && touchAge >= T630.oneFingerDelay
                        && abs(tx) >= Self.deadZone && abs(tx) > abs(ty) {
                self.axis = .horizontal
                scroll(tx, over: now - start.time, phase: 1)
            }
            return
        }
        scroll(Double(axis == .vertical ? y - previous.y : x - previous.x), over: now - previous.time, phase: 2)
    }

    /// The finger lifted, or the touch stopped being a 1-finger scroll.
    func lift() {
        defer { axis = nil; start = nil; last = nil }
        guard let axis else { return }
        post(axis, 0, phase: 4, momentum: 0)
        if abs(velocity) >= Self.momentumStop * 5 {
            let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in self?.momentumStep() }
            RunLoop.main.add(timer, forMode: .common)
            momentum = (timer, axis, velocity, ProcessInfo.processInfo.systemUptime, false)
        }
        velocity = 0
    }

    /// `phase`: 1 began, 2 changed.
    private func scroll(_ units: Double, over seconds: Double, phase: Int64) {
        guard let axis else { return }
        let dt = max(seconds, 0.008)  // reports can arrive back to back
        let speed = abs(units) / dt
        let pixels = units * Self.pixelsPerUnit * Settings.shared.scrollSpeed * (1 + speed / Self.accelerationSpeed)
        velocity = 0.6 * velocity + 0.4 * pixels / dt
        post(axis, pixels, phase: phase, momentum: 0)
    }

    private func momentumStep() {
        guard var m = momentum else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let dt = now - m.time
        m.velocity *= pow(Self.momentumDecay, dt * 60)
        m.time = now
        if abs(m.velocity) < Self.momentumStop {
            stopMomentum()
            return
        }
        post(m.axis, m.velocity * dt, phase: 0, momentum: m.started ? 2 : 1)
        m.started = true
        momentum = m
    }

    private func stopMomentum() {
        guard let m = momentum else { return }
        m.timer.invalidate()
        momentum = nil
        if m.started { post(m.axis, 0, phase: 0, momentum: 3) }
    }

    /// Posts a continuous (trackpad-like) scroll event. `momentum`: 0 none, 1 begin, 2 continue, 3 end.
    private func post(_ axis: Axis, _ pixels: Double, phase: Int64, momentum: Int64) {
        remainder += Settings.shared.reverseScrolling ? -pixels : pixels
        let whole = remainder.rounded(.towardZero)
        remainder -= whole
        if phase == 4 || momentum == 3 { remainder = 0 }
        let delta = Int32(clamping: Int(whole))
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                  wheel1: axis == .vertical ? delta : 0,
                                  wheel2: axis == .horizontal ? delta : 0, wheel3: 0)
        else { return }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        event.post(tap: .cghidEventTap)
    }
}
