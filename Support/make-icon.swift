// Draws the LogiSwipe icon and writes docs/logo.png and Support/AppIcon.icns.
// Run from the repo root:  swift Support/make-icon.swift
//
// Flat Logitech green background; a dark mouse outline with two staggered finger strokes
// swiping out of it (with a gap where they cross the outline) and an arrow, all in thick
// round strokes. Content stays about 80 pt inside the macOS icon grid's 824 pt rounded square.
import AppKit

let green = NSColor(srgbRed: 0 / 255.0, green: 253 / 255.0, blue: 207 / 255.0, alpha: 1)  // Logitech #00FDCF
let ink = NSColor(srgbRed: 0x10 / 255.0, green: 0x20 / 255.0, blue: 0x1E / 255.0, alpha: 1)   // #10201E
let stroke: CGFloat = 60, gap: CGFloat = 22

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: size / 1024, y: size / 1024)  // draw on a 1024 grid; y runs up

    // Background: the macOS icon grid's 824 pt rounded square.
    green.setFill()
    NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185).fill()

    func line(_ points: [NSPoint], color: NSColor = ink, width: CGFloat = stroke) {
        let path = NSBezierPath()
        path.move(to: points[0])
        points.dropFirst().forEach { path.line(to: $0) }
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        color.setStroke()
        path.stroke()
    }

    // Mouse body.
    ink.setStroke()
    let body = NSBezierPath(roundedRect: NSRect(x: 340, y: 212, width: 320, height: 600), xRadius: 160, yRadius: 160)
    body.lineWidth = stroke
    body.stroke()
    // Two fingers swiping out of the mouse, staggered, each cut into the outline by a background-colored gap.
    // They end clear of the right wall, and are far enough apart to leave a solid piece of the left wall between them.
    let fingers = [[NSPoint(x: 210, y: 600), NSPoint(x: 530, y: 600)],
                   [NSPoint(x: 250, y: 440), NSPoint(x: 570, y: 440)]]
    for finger in fingers {
        line(finger, color: green, width: stroke + 2 * gap)
        line(finger)
    }
    // Arrow.
    line([NSPoint(x: 722, y: 610), NSPoint(x: 812, y: 520), NSPoint(x: 722, y: 430)])

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, to path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

write(drawIcon(size: 1024), to: "docs/logo.png")

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    write(drawIcon(size: CGFloat(points)), to: iconset.appendingPathComponent("icon_\(points)x\(points).png").path)
    write(drawIcon(size: CGFloat(points * 2)), to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png").path)
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Support/AppIcon.icns"]
try! iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "wrote docs/logo.png and Support/AppIcon.icns" : "iconutil failed")
