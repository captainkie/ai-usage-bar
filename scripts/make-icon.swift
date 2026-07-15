#!/usr/bin/env swift
// Generates the AI Usage Bar app icon (gauge-arc mark) with pure CoreGraphics.
//   swift scripts/make-icon.swift preview <path.png>     one 512px preview
//   swift scripts/make-icon.swift all                     iconset -> AppIcon.icns + banner
import AppKit

// MARK: - Palette
let purple = NSColor(srgbRed: 0.56, green: 0.45, blue: 0.96, alpha: 1)
let cyan   = NSColor(srgbRed: 0.28, green: 0.76, blue: 0.92, alpha: 1)

func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

/// Draw the icon into the current NSGraphicsContext at edge length `s`.
func drawIcon(_ s: CGFloat) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }

    // Rounded-square background with diagonal gradient.
    let inset = s * 0.06
    let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let corner = (s - 2 * inset) * 0.235
    let bg = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
    ctx.saveGState()
    bg.addClip()
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [purple.cgColor, cyan.cgColor] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(grad,
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.maxX, y: rect.minY),
        options: [])
    ctx.restoreGState()

    // Gauge geometry (open at the bottom, ~270° sweep).
    let center = CGPoint(x: s / 2, y: s * 0.475)
    let radius = s * 0.285
    let width = s * 0.085
    let startA: CGFloat = 225, endA: CGFloat = -45
    let fill: CGFloat = 0.70

    // Track.
    let track = NSBezierPath()
    track.appendArc(withCenter: center, radius: radius, startAngle: startA, endAngle: endA, clockwise: true)
    track.lineWidth = width
    track.lineCapStyle = .round
    NSColor.white.withAlphaComponent(0.28).setStroke()
    track.stroke()

    // Value arc.
    let valueEnd = startA - (startA - endA) * fill
    let value = NSBezierPath()
    value.appendArc(withCenter: center, radius: radius, startAngle: startA, endAngle: valueEnd, clockwise: true)
    value.lineWidth = width
    value.lineCapStyle = .round
    NSColor.white.setStroke()
    value.stroke()

    // Needle to the value angle + hub.
    let rad = valueEnd * .pi / 180
    let tip = CGPoint(x: center.x + cos(rad) * radius * 0.82,
                      y: center.y + sin(rad) * radius * 0.82)
    let needle = NSBezierPath()
    needle.move(to: center)
    needle.line(to: tip)
    needle.lineWidth = s * 0.055
    needle.lineCapStyle = .round
    NSColor.white.setStroke()
    needle.stroke()

    let hubR = s * 0.055
    let hub = NSBezierPath(ovalIn: CGRect(x: center.x - hubR, y: center.y - hubR, width: hubR * 2, height: hubR * 2))
    NSColor.white.setFill()
    hub.fill()
    purple.setFill()
    let hubR2 = hubR * 0.45
    NSBezierPath(ovalIn: CGRect(x: center.x - hubR2, y: center.y - hubR2, width: hubR2 * 2, height: hubR2 * 2)).fill()
}

func render(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(CGFloat(px))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ px: Int, _ path: String) {
    let data = render(px).representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
}

// MARK: - main
let args = CommandLine.arguments
let mode = args.count > 1 ? args[1] : "preview"

if mode == "preview" {
    let out = args.count > 2 ? args[2] : "icon-preview.png"
    writePNG(512, out)
    print("wrote \(out)")
} else if mode == "all" {
    let fm = FileManager.default
    let iconset = "AppIcon.iconset"
    try? fm.removeItem(atPath: iconset)
    try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)
    let sizes = [16, 32, 128, 256, 512]
    for base in sizes {
        writePNG(base, "\(iconset)/icon_\(base)x\(base).png")
        writePNG(base * 2, "\(iconset)/icon_\(base)x\(base)@2x.png")
    }
    try? fm.createDirectory(atPath: "Resources", withIntermediateDirectories: true)
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    p.arguments = ["-c", "icns", iconset, "-o", "Resources/AppIcon.icns"]
    try! p.run(); p.waitUntilExit()
    try? fm.removeItem(atPath: iconset)
    print("wrote Resources/AppIcon.icns")
}
