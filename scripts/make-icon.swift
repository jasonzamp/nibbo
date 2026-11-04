// Draws Cue's app icon and writes Resources/AppIcon.icns.
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

    // Squircle body, inset like standard macOS icons.
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.set()
    NSColor.black.setFill()
    bodyPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [NSColor(calibratedRed: 0.36, green: 0.42, blue: 0.98, alpha: 1),
                        NSColor(calibratedRed: 0.62, green: 0.33, blue: 0.93, alpha: 1)])!
        .draw(in: bodyPath, angle: -60)

    // Prompter panel hanging from the top edge (the notch).
    NSGraphicsContext.saveGraphicsState()
    bodyPath.addClip()
    let panel = NSRect(x: 232 * s, y: 430 * s, width: 560 * s, height: 494 * s)
    let panelPath = NSBezierPath()
    let r = 90 * s
    panelPath.move(to: NSPoint(x: panel.minX, y: panel.maxY))
    panelPath.line(to: NSPoint(x: panel.minX, y: panel.minY + r))
    panelPath.appendArc(withCenter: NSPoint(x: panel.minX + r, y: panel.minY + r), radius: r, startAngle: 180, endAngle: 270)
    panelPath.line(to: NSPoint(x: panel.maxX - r, y: panel.minY))
    panelPath.appendArc(withCenter: NSPoint(x: panel.maxX - r, y: panel.minY + r), radius: r, startAngle: 270, endAngle: 360)
    panelPath.line(to: NSPoint(x: panel.maxX, y: panel.maxY))
    panelPath.close()
    NSColor(calibratedWhite: 0.04, alpha: 1).setFill()
    panelPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Camera lens with a green "live" light.
    let lens = NSRect(x: 492 * s, y: 830 * s, width: 40 * s, height: 40 * s)
    NSColor(calibratedWhite: 0.22, alpha: 1).setFill()
    NSBezierPath(ovalIn: lens).fill()
    NSColor(calibratedRed: 0.2, green: 0.85, blue: 0.45, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 600 * s, y: 838 * s, width: 22 * s, height: 22 * s)).fill()

    // Script lines: the one being read is bright, the rest fade.
    let lines: [(width: CGFloat, y: CGFloat, alpha: CGFloat)] = [
        (380, 720, 1.0), (300, 640, 0.55), (340, 560, 0.3), (220, 480, 0.15),
    ]
    for line in lines {
        let rect = NSRect(x: (512 - line.width / 2) * s, y: line.y * s, width: line.width * s, height: 34 * s)
        NSColor.white.withAlphaComponent(line.alpha).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 17 * s, yRadius: 17 * s).fill()
    }

    // Eye-line marker beside the current line.
    NSColor(calibratedRed: 0.55, green: 0.6, blue: 1, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 262 * s, y: 712 * s, width: 12 * s, height: 50 * s), xRadius: 6 * s, yRadius: 6 * s).fill()

    // Base line suggesting the bottom of the screen.
    NSColor.white.withAlphaComponent(0.25).setFill()
    NSBezierPath(roundedRect: NSRect(x: 330 * s, y: 250 * s, width: 364 * s, height: 22 * s), xRadius: 11 * s, yRadius: 11 * s).fill()
    NSColor.white.withAlphaComponent(0.15).setFill()
    NSBezierPath(roundedRect: NSRect(x: 400 * s, y: 196 * s, width: 224 * s, height: 22 * s), xRadius: 11 * s, yRadius: 11 * s).fill()

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
