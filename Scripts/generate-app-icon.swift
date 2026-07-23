#!/usr/bin/env swift
import AppKit
import Foundation

/// Draw AppIcon-1024.png — Apple-style squircle + ascending usage bars.
/// Canvas is 1024×1024 with transparent corners (continuous corner radius).

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: generate-app-icon.swift <AppIcon-1024.png>\n", stderr)
    exit(1)
}

let outURL = URL(fileURLWithPath: CommandLine.arguments[1])
let sizePx = 1024
let size = CGFloat(sizePx)
let cornerRadius = size * 0.2237 // Apple continuous-corner proportion

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: sizePx,
    pixelsHigh: sizePx,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
rep.size = NSSize(width: size, height: size)

NSGraphicsContext.saveGraphicsState()
guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
    fputs("error: could not create graphics context\n", stderr)
    exit(1)
}
NSGraphicsContext.current = ctx
ctx.cgContext.setShouldAntialias(true)
ctx.cgContext.interpolationQuality = .high

let bounds = NSRect(x: 0, y: 0, width: size, height: size)

// Transparent canvas
NSColor.clear.setFill()
bounds.fill()

// Squircle clip
let squircle = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)
squircle.addClip()

// Background: charcoal with subtle top→bottom darkening
let bg = NSGradient(colors: [
    NSColor(calibratedRed: 0.14, green: 0.14, blue: 0.15, alpha: 1), // #242426
    NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.09, alpha: 1), // #141416
])!
bg.draw(in: bounds, angle: 270)

// Soft inner highlight along the top edge (Apple depth cue)
let highlight = NSGradient(colors: [
    NSColor(calibratedWhite: 1, alpha: 0.10),
    NSColor(calibratedWhite: 1, alpha: 0.0),
])!
highlight.draw(in: NSRect(x: 0, y: size * 0.72, width: size, height: size * 0.28), angle: 270)

// Three ascending usage bars (left → right), optically centered
let barWidth = size * 0.125
let gap = size * 0.085
let heights: [CGFloat] = [0.32, 0.52, 0.72] // fraction of canvas height
let barColors: [NSColor] = [
    NSColor(calibratedRed: 0.20, green: 0.83, blue: 0.60, alpha: 1), // mint
    NSColor(calibratedRed: 0.16, green: 0.78, blue: 0.55, alpha: 1),
    NSColor(calibratedRed: 0.06, green: 0.73, blue: 0.51, alpha: 1), // emerald
]

let maxH = size * (heights.max() ?? 0.72)
// Optical center slightly above geometric midpoint
let marginBottom = (size - maxH) * 0.48

let totalBarsWidth = barWidth * 3 + gap * 2
let startX = (size - totalBarsWidth) / 2

for (i, hFrac) in heights.enumerated() {
    let h = size * hFrac
    let x = startX + CGFloat(i) * (barWidth + gap)
    let y = marginBottom
    let barRect = NSRect(x: x, y: y, width: barWidth, height: h)
    let radius = barWidth / 2 // pill / stadium top+bottom
    let path = NSBezierPath(roundedRect: barRect, xRadius: radius, yRadius: radius)

    // Vertical gradient on each bar (lighter at top)
    let light = barColors[i].blended(withFraction: 0.25, of: .white) ?? barColors[i]
    let dark = barColors[i]
    let g = NSGradient(colors: [light, dark])!
    g.draw(in: path, angle: 270)
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fputs("error: png encode failed\n", stderr)
    exit(1)
}
try png.write(to: outURL)
print("Wrote \(outURL.path) (\(png.count) bytes)")
