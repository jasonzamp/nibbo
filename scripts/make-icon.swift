// Draws Nibbo's app icon (the "Peeking Buddy") and writes Resources/AppIcon.icns.
// Run from the repo root: swift scripts/make-icon.swift
import AppKit

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let px = Int(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024 // design on a 1024 grid
    // The logo is drawn on a 100-unit grid (y down), mapped onto the 824 px icon body.
    let u = 8.24 * s
    func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: 100 * s + x * u, y: 924 * s - (y + h) * u, width: w * u, height: h * u)
    }

    // Squircle body, inset like standard macOS icons.
    let body = box(0, 0, 100, 100)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: 23 * u, yRadius: 23 * u)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.set()
    NSColor(srgbRed: 0.294, green: 0.333, blue: 0.91, alpha: 1).setFill() // #4B55E8
    bodyPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    let ink = NSColor(srgbRed: 0.043, green: 0.043, blue: 0.059, alpha: 1) // #0B0B0F

    // "Peeking Buddy": the notch, hanging from the top edge, with two eyes reading down.
    NSGraphicsContext.saveGraphicsState()
    bodyPath.addClip()
    ink.setFill()
    NSBezierPath(roundedRect: box(20, -22, 60, 66), xRadius: 22 * u, yRadius: 22 * u).fill()
    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.setFill()
    NSBezierPath(ovalIn: box(32.5, 12.5, 15, 17)).fill()
    NSBezierPath(ovalIn: box(52.5, 12.5, 15, 17)).fill()
    ink.setFill()
    NSBezierPath(ovalIn: box(37.2, 21.2, 7.6, 7.6)).fill()
    NSBezierPath(ovalIn: box(57.2, 21.2, 7.6, 7.6)).fill()
    NSColor(srgbRed: 0.24, green: 0.82, blue: 0.48, alpha: 1).setFill() // camera light
    NSBezierPath(ovalIn: box(70.2, 5.2, 3.6, 3.6)).fill()

    // The script it's reading: the current line bright, the next ones fading.
    let lines: [(x: CGFloat, y: CGFloat, w: CGFloat, alpha: CGFloat)] = [(27, 57, 46, 1), (33, 69, 34, 0.55), (38, 81, 24, 0.25)]
    for line in lines {
        NSColor.white.withAlphaComponent(line.alpha).setFill()
        NSBezierPath(roundedRect: box(line.x, line.y, line.w, 6), xRadius: 3 * u, yRadius: 3 * u).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let png = drawIcon(size: CGFloat(base * scale)).representation(using: .png, properties: [:])!
        try! png.write(to: iconset.appendingPathComponent(name))
    }
}
try! drawIcon(size: 1024).representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: "Resources/AppIcon.png"))

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
