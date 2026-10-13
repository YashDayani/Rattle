#!/usr/bin/env swift
// Renders Rattle's app icon into build/AppIcon.iconset (run by build.sh, then iconutil makes the .icns).
import Cocoa

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/AppIcon.iconset"
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 512
    let inset = 40 * s
    let body = NSRect(x: inset, y: inset, width: CGFloat(px) - 2 * inset, height: CGFloat(px) - 2 * inset)
    NSColor(calibratedRed: 0.11, green: 0.10, blue: 0.09, alpha: 1).setFill()
    NSBezierPath(roundedRect: body, xRadius: 110 * s, yRadius: 110 * s).fill()
    NSColor.white.setFill()
    let heights: [CGFloat] = [90, 190, 290, 190, 90]
    for (i, h) in heights.enumerated() {
        let x = (130 + CGFloat(i) * 62) * s
        NSBezierPath(roundedRect: NSRect(x: x, y: (256 - h / 2) * s, width: 34 * s, height: h * s),
                     xRadius: 17 * s, yRadius: 17 * s).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: URL(fileURLWithPath: "\(outDir)/icon_\(base)x\(base).png"))
    try render(base * 2).write(to: URL(fileURLWithPath: "\(outDir)/icon_\(base)x\(base)@2x.png"))
}
