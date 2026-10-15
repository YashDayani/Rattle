#!/usr/bin/env swift
// Renders Rattle's app icon into build/AppIcon.iconset (run by build.sh, then iconutil makes the .icns).
import Cocoa

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/AppIcon.iconset"
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)


extension CGPath {
    var nsPath: NSBezierPath {
        let p = NSBezierPath()
        applyWithBlock { e in
            let pt = e.pointee.points
            switch e.pointee.type {
            case .moveToPoint: p.move(to: pt[0])
            case .addLineToPoint: p.line(to: pt[0])
            case .addCurveToPoint: p.curve(to: pt[2], controlPoint1: pt[0], controlPoint2: pt[1])
            case .addQuadCurveToPoint: p.curve(to: pt[1], controlPoint1: pt[0], controlPoint2: pt[0])
            case .closeSubpath: p.close()
            @unknown default: break
            }
        }
        return p
    }
}

extension NSBezierPath {
    var cgPath: CGPath {
        let p = CGMutablePath(); var pts = [NSPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            switch element(at: i, associatedPoints: &pts) {
            case .moveTo: p.move(to: pts[0])
            case .lineTo: p.addLine(to: pts[0])
            case .curveTo: p.addCurve(to: pts[2], control1: pts[0], control2: pts[1])
            case .closePath: p.closeSubpath()
            default: break
            }
        }
        return p
    }
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 512
    let body = NSRect(x: 40 * s, y: 40 * s, width: CGFloat(px) - 80 * s, height: CGFloat(px) - 80 * s)
    let radius = 110 * s
    let path = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
    // Soft dark drop shadow, like system icons.
    NSGraphicsContext.saveGraphicsState()
    let drop = NSShadow(); drop.shadowColor = NSColor.black.withAlphaComponent(0.45); drop.shadowBlurRadius = 14 * s; drop.shadowOffset = NSSize(width: 0, height: -6 * s)
    drop.set()
    NSColor.black.setFill(); path.fill()
    NSGraphicsContext.restoreGraphicsState()
    // Dark body with a faint lift at the top.
    NSGradient(starting: NSColor(calibratedRed: 0.17, green: 0.17, blue: 0.17, alpha: 1), ending: NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.07, alpha: 1))!.draw(in: path, angle: -90)
    // Waveform, centred on the icon (total width 4 * 62 + 34 = 282).
    NSGraphicsContext.saveGraphicsState()
    let bars = NSShadow(); bars.shadowColor = NSColor.white.withAlphaComponent(0.45); bars.shadowBlurRadius = 14 * s; bars.shadowOffset = .zero
    bars.set()
    NSColor.white.setFill()
    let heights: [CGFloat] = [90, 190, 290, 190, 90]
    for (i, h) in heights.enumerated() {
        let x = (115 + CGFloat(i) * 62) * s
        NSBezierPath(roundedRect: NSRect(x: x, y: (256 - h / 2) * s, width: 34 * s, height: h * s), xRadius: 17 * s, yRadius: 17 * s).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: URL(fileURLWithPath: "\(outDir)/icon_\(base)x\(base).png"))
    try render(base * 2).write(to: URL(fileURLWithPath: "\(outDir)/icon_\(base)x\(base)@2x.png"))
}
