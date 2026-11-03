// Draws the T630 click zones diagram and writes docs/click-zones.png.
// Run from the repo root:  swift Support/make-click-zones.swift
//
// The mouse seen from above, its touch surface split into the single-finger click zones
// (T630.zone: middle is T630.middleZoneX, right from T630.rightSideX outside it), with a card
// for each kind of click on either side and the X axis underneath.
import AppKit

let width: CGFloat = 680, height: CGFloat = 430, scale: CGFloat = 2
let maxX: CGFloat = 76                                     // X runs 0...76 across the surface
let zones: [(name: String, from: Int, to: Int, color: NSColor)] = [
    ("Left", 0, 29, rgb(0x2D4369)),
    ("Middle", 30, 55, rgb(0x1C6B5C)),
    ("Right", 56, 76, rgb(0x52376E)),
]

func rgb(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
let background = rgb(0x26272A), cardFill = rgb(0x323337), text = rgb(0xF2F2F2)
let secondary = rgb(0xC8C8CC), tertiary = rgb(0x9A9AA0), outline = rgb(0x77777C)

func draw(_ string: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight = .regular,
          color: NSColor = text, centered: Bool = false) {
    let attributed = NSAttributedString(string: string, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color,
    ])
    let x = centered ? point.x - attributed.size().width / 2 : point.x
    attributed.draw(at: NSPoint(x: x, y: point.y - attributed.size().height / 2))
}

func card(_ frame: NSRect, color: NSColor, title: String, detail: String, note: String) {
    let box = NSBezierPath(roundedRect: frame, xRadius: 10, yRadius: 10)
    cardFill.setFill()
    box.fill()
    color.withAlphaComponent(0.75).setStroke()
    box.lineWidth = 1
    box.stroke()
    color.setFill()
    NSBezierPath(ovalIn: NSRect(x: frame.minX + 18, y: frame.minY + 15.5, width: 6, height: 6)).fill()
    draw(title, at: NSPoint(x: frame.minX + 30, y: frame.minY + 18.5), size: 10, weight: .semibold)
    draw(detail, at: NSPoint(x: frame.minX + 10, y: frame.minY + 34), size: 7.5, weight: .medium, color: secondary)
    draw(note, at: NSPoint(x: frame.minX + 10, y: frame.minY + 48), size: 7, color: tertiary)
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let cg = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
cg.translateBy(x: 0, y: height * scale)
cg.scaleBy(x: scale, y: -scale)                           // points, y runs down
NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)

// Background.
let frame = NSBezierPath(roundedRect: NSRect(x: 0.5, y: 0.5, width: width - 1, height: height - 1), xRadius: 20, yRadius: 20)
background.setFill()
frame.fill()
rgb(0x45464A).setStroke()
frame.stroke()

draw("T630 Click Zones", at: NSPoint(x: width / 2, y: 28), size: 14, weight: .bold, centered: true)
draw("Single-finger click zones across the touch surface (X = 0…76)",
     at: NSPoint(x: width / 2, y: 46), size: 9, color: secondary, centered: true)

// Mouse: a capsule whose top part, down to the logo, is the touch surface.
let mouse = NSRect(x: 257, y: 65, width: 166, height: 290)
let surfaceBottom: CGFloat = 288
func surfaceX(_ x: CGFloat) -> CGFloat { mouse.minX + x / maxX * mouse.width }
let body = NSBezierPath(roundedRect: mouse, xRadius: mouse.width / 2, yRadius: mouse.width / 2)
NSGraphicsContext.saveGraphicsState()
body.addClip()
rgb(0x38393D).setFill()
mouse.fill()
for zone in zones {
    zone.color.setFill()
    let left = surfaceX(CGFloat(zone.from)), right = zone.to == Int(maxX) ? mouse.maxX : surfaceX(CGFloat(zone.to + 1))
    NSRect(x: left, y: mouse.minY, width: right - left, height: surfaceBottom - mouse.minY).fill()
}
for zone in zones.dropFirst() {                           // zone borders
    let x = surfaceX(CGFloat(zone.from))
    rgb(0xD8D8DC).setFill()
    NSRect(x: x - 0.75, y: mouse.minY, width: 1.5, height: surfaceBottom - mouse.minY).fill()
}
let center = NSBezierPath()                               // geometric center
center.move(to: NSPoint(x: surfaceX(38), y: mouse.minY))
center.line(to: NSPoint(x: surfaceX(38), y: surfaceBottom))
center.setLineDash([3, 3], count: 2, phase: 0)
rgb(0xFFFFFF, 0.3).setStroke()
center.stroke()
rgb(0x1A1A1C).setFill()
NSRect(x: mouse.minX, y: surfaceBottom - 0.75, width: mouse.width, height: 1.5).fill()
NSGraphicsContext.restoreGraphicsState()
body.lineWidth = 2
outline.setStroke()
body.stroke()
draw("logi", at: NSPoint(x: mouse.midX, y: 325), size: 9, weight: .bold, color: rgb(0x77777C), centered: true)

for zone in zones {
    let left = surfaceX(CGFloat(zone.from)), right = zone.to == Int(maxX) ? mouse.maxX : surfaceX(CGFloat(zone.to + 1))
    let middle = zone.name == "Middle", x = (left + right) / 2
    draw(zone.name, at: NSPoint(x: x, y: 166), size: 11, weight: .bold, color: middle ? rgb(0x2EF5C8) : text, centered: true)
    draw("X \(zone.from)–\(zone.to)", at: NSPoint(x: x, y: 182), size: 7.5, weight: .medium,
         color: middle ? text : secondary, centered: true)
    draw("(\(zone.to - zone.from + 1) units)", at: NSPoint(x: x, y: 194), size: 6.5, color: tertiary, centered: true)
}

// Cards.
let blue = rgb(0x3B82F6), teal = rgb(0x14C9A2), purple = rgb(0xA855F7), orange = rgb(0xF59E0B)
card(NSRect(x: 32, y: 121, width: 185, height: 59), color: blue, title: "Left Click",
     detail: "1 finger on the left side (X 0–29)", note: "Default: Left click")
card(NSRect(x: 32, y: 196, width: 185, height: 59), color: teal, title: "Middle Click & Hold",
     detail: "1 finger along center strip (X 30–55)", note: "Click: Middle click • Hold ½ s: Capture area")
card(NSRect(x: 463, y: 121, width: 185, height: 59), color: purple, title: "Right Click",
     detail: "1 finger on the right side (X 56–76)", note: "Default: Right click")
card(NSRect(x: 463, y: 196, width: 185, height: 59), color: orange, title: "Two-Finger Click",
     detail: "Land 2 fingers together, press within 1 s", note: "Default: Copy (⌘C) • Resting finger ignored")

// X axis.
let axisY: CGFloat = 370
let axis = NSBezierPath()
axis.move(to: NSPoint(x: surfaceX(0), y: axisY))
axis.line(to: NSPoint(x: surfaceX(maxX), y: axisY))
for tick in [0, 30, 38, 55, 76] {
    let x = surfaceX(CGFloat(tick))
    axis.move(to: NSPoint(x: x, y: axisY - 4))
    axis.line(to: NSPoint(x: x, y: axisY + 4))
    draw("\(tick)", at: NSPoint(x: x, y: axisY + 11), size: 6.5, weight: .semibold,
         color: tick == 38 ? tertiary : secondary, centered: true)
}
axis.lineWidth = 1
outline.setStroke()
axis.stroke()
draw("X coordinate (38 = geometric center)", at: NSPoint(x: width / 2, y: axisY + 25), size: 6.5, color: tertiary, centered: true)
draw("With a finger resting, the clicking finger is the latest to land on the side the mouse pressed",
     at: NSPoint(x: width / 2, y: axisY + 43), size: 7.5, weight: .medium, color: secondary, centered: true)

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "docs/click-zones.png"))
