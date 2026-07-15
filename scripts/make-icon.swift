#!/usr/bin/env swift
// Generates the AI Usage Bar app icon (modern gauge-arc mark), CoreGraphics only.
//   swift scripts/make-icon.swift sheet <out.png>          contact sheet of all themes
//   swift scripts/make-icon.swift preview <theme> <out.png>
//   swift scripts/make-icon.swift all <theme>              iconset -> Resources/AppIcon.icns (+ icon-512.png)
import AppKit

struct Theme {
    let name: String
    let bg: [NSColor]          // 1 = solid, 2 = gradient
    let arc: NSColor
    let track: CGFloat         // track alpha
    let dotInner: NSColor      // small center of the value dot
}

func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: 1)
}

let themes: [Theme] = [
    Theme(name: "mono",   bg: [c(18,18,22)],              arc: .white,          track: 0.14, dotInner: c(18,18,22)),
    Theme(name: "sunset", bg: [c(255,138,61), c(255,45,120)], arc: .white,      track: 0.28, dotInner: c(255,45,120)),
    Theme(name: "mint",   bg: [c(11,18,32)],              arc: c(52,229,160),   track: 0.10, dotInner: c(11,18,32)),
    Theme(name: "indigo", bg: [c(94,92,230), c(10,132,255)], arc: .white,       track: 0.26, dotInner: c(52,60,220)),
    Theme(name: "amber",  bg: [c(23,23,28)],              arc: c(255,176,32),   track: 0.10, dotInner: c(23,23,28)),
]

func drawIcon(_ s: CGFloat, _ t: Theme) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }

    let inset = s * 0.06
    let rect = CGRect(x: inset, y: inset, width: s - 2*inset, height: s - 2*inset)
    let corner = (s - 2*inset) * 0.235
    let bg = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
    ctx.saveGState(); bg.addClip()
    if t.bg.count >= 2 {
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [t.bg[0].cgColor, t.bg[1].cgColor] as CFArray, locations: [0,1])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: rect.minX, y: rect.maxY),
                               end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
    } else {
        t.bg[0].setFill(); bg.fill()
    }
    ctx.restoreGState()

    // Modern gauge: thin arc, no needle, a clean dot marker at the value.
    let center = CGPoint(x: s/2, y: s*0.52)
    let radius = s*0.29
    let width = s*0.062
    let startA: CGFloat = 225, endA: CGFloat = -45
    let fill: CGFloat = 0.68

    let track = NSBezierPath()
    track.appendArc(withCenter: center, radius: radius, startAngle: startA, endAngle: endA, clockwise: true)
    track.lineWidth = width; track.lineCapStyle = .round
    NSColor.white.withAlphaComponent(t.track).setStroke(); track.stroke()

    let valueEnd = startA - (startA - endA) * fill
    let value = NSBezierPath()
    value.appendArc(withCenter: center, radius: radius, startAngle: startA, endAngle: valueEnd, clockwise: true)
    value.lineWidth = width; value.lineCapStyle = .round
    t.arc.setStroke(); value.stroke()

    // Value dot marker.
    let rad = valueEnd * .pi/180
    let dot = CGPoint(x: center.x + cos(rad)*radius, y: center.y + sin(rad)*radius)
    let dR = s*0.075
    t.arc.setFill()
    NSBezierPath(ovalIn: CGRect(x: dot.x-dR, y: dot.y-dR, width: dR*2, height: dR*2)).fill()
    let dR2 = dR*0.42
    t.dotInner.setFill()
    NSBezierPath(ovalIn: CGRect(x: dot.x-dR2, y: dot.y-dR2, width: dR2*2, height: dR2*2)).fill()
}

func render(_ px: Int, _ t: Theme, draw: (CGFloat, Theme) -> Void = drawIcon) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(CGFloat(px), t)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, _ path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

func theme(_ name: String) -> Theme { themes.first { $0.name == name } ?? themes[0] }

let args = CommandLine.arguments
let mode = args.count > 1 ? args[1] : "sheet"

switch mode {
case "sheet":
    let out = args.count > 2 ? args[2] : "sheet.png"
    let tile = 220, pad = 24, labelH = 34
    let W = tile*themes.count + pad*(themes.count+1)
    let H = tile + pad*2 + labelH
    let sheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
    c(28,28,32).setFill(); NSBezierPath(rect: CGRect(x:0,y:0,width:W,height:H)).fill()
    for (i, t) in themes.enumerated() {
        let x = pad + i*(tile+pad)
        let img = render(tile, t)
        img.draw(in: CGRect(x: x, y: pad+labelH, width: tile, height: tile))
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .semibold)]
        NSString(string: "\(i+1). \(t.name)").draw(at: CGPoint(x: x+4, y: 8), withAttributes: attrs)
    }
    NSGraphicsContext.restoreGraphicsState()
    writePNG(sheet, out)
    print("wrote \(out)")

case "preview":
    let t = theme(args.count > 2 ? args[2] : "mono")
    let out = args.count > 3 ? args[3] : "preview.png"
    writePNG(render(512, t), out)
    print("wrote \(out)")

case "all":
    let t = theme(args.count > 2 ? args[2] : "mono")
    let fm = FileManager.default
    let iconset = "AppIcon.iconset"
    try? fm.removeItem(atPath: iconset)
    try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)
    for base in [16,32,128,256,512] {
        writePNG(render(base, t), "\(iconset)/icon_\(base)x\(base).png")
        writePNG(render(base*2, t), "\(iconset)/icon_\(base)x\(base)@2x.png")
    }
    try? fm.createDirectory(atPath: "Resources", withIntermediateDirectories: true)
    writePNG(render(512, t), "Resources/icon-512.png")
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    p.arguments = ["-c","icns", iconset, "-o", "Resources/AppIcon.icns"]
    try! p.run(); p.waitUntilExit()
    try? fm.removeItem(atPath: iconset)
    print("wrote Resources/AppIcon.icns (theme: \(t.name))")

default:
    print("unknown mode")
}
