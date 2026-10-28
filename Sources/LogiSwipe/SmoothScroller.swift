import AppKit

/// Turns finger movement on the T630 into trackpad-style scrolling: pixel deltas on every
/// report (~12 ms), scroll phases, and momentum after lifting. It replaces the mouse's own
/// wheel-like scrolling, which comes in coarse steps 30–140 ms apart. One finger scrolls along
/// one axis, picked when it starts moving; two fingers scroll freely in any direction.
///
/// Finger Y grows towards the front of the mouse and X to the right, while a wheel's positive
/// directions are up and left, so Y scrolls with its own sign and X with the opposite one
/// (then a diagonal scrolls the way the fingers go). That is before the system's Natural
/// scrolling flips it: the system flips the mouse's own events but not posted ones, so `post`
/// applies Natural scrolling itself (then Reverse).
final class SmoothScroller {
    static let shared = SmoothScroller()

    /// Pixels per X/Y unit at slow finger speeds (the surface is about 76 units wide).
    private static let pixelsPerUnit = 6.0
    /// Finger speed (units/s) at which each unit scrolls twice as far.
    private static let accelerationSpeed = 150.0
    /// Units the finger must move before scrolling starts, so clicks don't scroll.
    static let deadZone = 2.0
    /// Momentum keeps this fraction of its speed every 1/60 s, and stops below `momentumStop` px/s.
    private static let momentumDecay = 0.95, momentumStop = 30.0

    private enum Axis { case vertical, horizontal, free }
    private struct Vector {
        var x = 0.0, y = 0.0
        var length: Double { (x * x + y * y).squareRoot() }
        static func * (v: Vector, k: Double) -> Vector { Vector(x: v.x * k, y: v.y * k) }
        static func + (a: Vector, b: Vector) -> Vector { Vector(x: a.x + b.x, y: a.y + b.y) }
    }
    private var axis: Axis?                          // set once scrolling has started
    private var free = false                         // the current touch scrolls freely
    private var start: Double?                       // system uptime when the touch began
    private var last = 0.0                           // system uptime of the previous report
    private var travel = Vector()                    // finger units moved before scrolling started
    private var remainder = Vector()                 // sub-pixel scroll not posted yet
    private var velocity = Vector()                  // px/s, smoothed
    private var momentum: (timer: Timer, velocity: Vector, time: Double, started: Bool)?

    /// Every report while scrolling with no button down. `dx`/`dy` are the units the fingers moved
    /// since the previous report; `free` scrolls in any direction instead of along one axis.
    func move(dx: Double, dy: Double, free: Bool, allowHorizontal: Bool, touchAge: Double) {
        let now = ProcessInfo.processInfo.systemUptime
        if start != nil && free != self.free { lift() }  // a finger landed and changed the kind of scroll
        guard let start else {
            stopMomentum()  // a new touch catches the page, as on a trackpad
            self.start = now; last = now; travel = Vector(); self.free = free
            return
        }
        let dt = now - last
        last = now

        guard let axis else {
            travel = travel + Vector(x: dx, y: dy)
            if free {
                // A second finger may still be landing on its way to a three-finger swipe.
                if touchAge >= T630.oneFingerDelay && travel.length >= Self.deadZone {
                    self.axis = .free
                    scroll(travel, over: now - start, phase: 1)
                }
            } else if abs(travel.y) >= Self.deadZone && abs(travel.y) >= abs(travel.x) {
                self.axis = .vertical
                scroll(Vector(y: travel.y), over: now - start, phase: 1)
            } else if allowHorizontal && touchAge >= T630.oneFingerDelay
                        && abs(travel.x) >= Self.deadZone && abs(travel.x) > abs(travel.y) {
                self.axis = .horizontal
                scroll(Vector(x: travel.x), over: now - start, phase: 1)
            }
            return
        }
        scroll(Vector(x: axis == .vertical ? 0 : dx, y: axis == .horizontal ? 0 : dy), over: dt, phase: 2)
    }

    /// The fingers lifted, or the touch stopped being a scroll.
    func lift() {
        defer { axis = nil; start = nil }
        guard axis != nil else { return }
        post(Vector(), phase: 4, momentum: 0)
        if velocity.length >= Self.momentumStop * 5 {
            let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in self?.momentumStep() }
            RunLoop.main.add(timer, forMode: .common)
            momentum = (timer, velocity, ProcessInfo.processInfo.systemUptime, false)
        }
        velocity = Vector()
    }

    /// `phase`: 1 began, 2 changed.
    private func scroll(_ units: Vector, over seconds: Double, phase: Int64) {
        let dt = max(seconds, 0.008)  // reports can arrive back to back
        let speed = units.length / dt
        let pixels = units * (Self.pixelsPerUnit * Settings.shared.scrollSpeed * (1 + speed / Self.accelerationSpeed))
        velocity = velocity * 0.6 + pixels * (0.4 / dt)
        post(pixels, phase: phase, momentum: 0)
    }

    private func momentumStep() {
        guard var m = momentum else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let dt = now - m.time
        m.velocity = m.velocity * pow(Self.momentumDecay, dt * 60)
        m.time = now
        if m.velocity.length < Self.momentumStop {
            stopMomentum()
            return
        }
        post(m.velocity * dt, phase: 0, momentum: m.started ? 2 : 1)
        m.started = true
        momentum = m
    }

    private func stopMomentum() {
        guard let m = momentum else { return }
        m.timer.invalidate()
        momentum = nil
        if m.started { post(Vector(), phase: 0, momentum: 3) }
    }

    /// Posts a continuous (trackpad-like) scroll event. `momentum`: 0 none, 1 begin, 2 continue, 3 end.
    private func post(_ pixels: Vector, phase: Int64, momentum: Int64) {
        let natural = UserDefaults.standard.object(forKey: "com.apple.swipescrolldirection") as? Bool ?? true
        remainder = remainder + pixels * (natural != Settings.shared.reverseScrolling ? -1 : 1)
        let whole = Vector(x: remainder.x.rounded(.towardZero), y: remainder.y.rounded(.towardZero))
        remainder = remainder + whole * -1
        if phase == 4 || momentum == 3 { remainder = Vector() }
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                  wheel1: Int32(clamping: Int(whole.y)),
                                  wheel2: Int32(clamping: -Int(whole.x)), wheel3: 0)
        else { return }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        // isDirectionInvertedFromDevice, as on the mouse's own events
        event.setIntegerValueField(CGEventField(rawValue: 137)!, value: natural ? 1 : 0)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        event.post(tap: .cghidEventTap)
    }
}
