#!/usr/bin/env swift
import AppKit
import Foundation

/// Draw AppIcon-1024.png — Apple-style squircle with Cursor’s pointer mark
/// plus ascending usage bars (mint) so the companion app reads as “Cursor usage”.

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
let cg = ctx.cgContext
cg.setShouldAntialias(true)
cg.interpolationQuality = .high

let bounds = NSRect(x: 0, y: 0, width: size, height: size)

// Transparent canvas
NSColor.clear.setFill()
bounds.fill()

// Squircle clip
let squircle = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)
squircle.addClip()

// Background: charcoal (Cursor-adjacent dark)
let bg = NSGradient(colors: [
    NSColor(calibratedRed: 0.14, green: 0.14, blue: 0.15, alpha: 1), // #242426
    NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.09, alpha: 1), // #141416
])!
bg.draw(in: bounds, angle: 270)

// Soft inner highlight along the top edge
let highlight = NSGradient(colors: [
    NSColor(calibratedWhite: 1, alpha: 0.10),
    NSColor(calibratedWhite: 1, alpha: 0.0),
])!
highlight.draw(in: NSRect(x: 0, y: size * 0.72, width: size, height: size * 0.28), angle: 270)

// ── Cursor pointer (official mark geometry, viewBox 28×28) ──────────────────
// Tip points upper-right; two facets with soft white gradients like the brand SVG.
func cursorOutlinePath() -> NSBezierPath {
    // Outer silhouette from theme-seti cursor.svg mask path (y-up AppKit coords
    // via transform later). SVG y grows down; we keep SVG coords and flip in CTM.
    let p = NSBezierPath()
    p.move(to: NSPoint(x: 22.8416, y: 1.387))
    p.curve(
        to: NSPoint(x: 24.1295, y: 2.13055),
        controlPoint1: NSPoint(x: 23.4132, y: 1.0062),
        controlPoint2: NSPoint(x: 24.1735, y: 1.44515)
    )
    p.line(to: NSPoint(x: 22.6326, y: 25.4656))
    p.curve(
        to: NSPoint(x: 21.5162, y: 25.8022),
        controlPoint1: NSPoint(x: 22.5957, y: 26.0405),
        controlPoint2: NSPoint(x: 21.8646, y: 26.2609)
    )
    p.line(to: NSPoint(x: 15.0114, y: 17.2395))
    p.curve(
        to: NSPoint(x: 14.316, y: 16.838),
        controlPoint1: NSPoint(x: 14.8429, y: 17.0177),
        controlPoint2: NSPoint(x: 14.5923, y: 16.873)
    )
    p.line(to: NSPoint(x: 3.6481, y: 15.486))
    p.curve(
        to: NSPoint(x: 3.38136, y: 14.3509),
        controlPoint1: NSPoint(x: 3.07656, y: 15.4136),
        controlPoint2: NSPoint(x: 2.9019, y: 14.6703)
    )
    p.close()
    return p
}

func leftFacetPath() -> NSBezierPath {
    let p = NSBezierPath()
    p.move(to: NSPoint(x: 1.79102, y: 15.2782))
    p.line(to: NSPoint(x: 24.2386, y: 0.457031))
    p.line(to: NSPoint(x: 14.6808, y: 17.0116))
    p.close()
    return p
}

func rightFacetPath() -> NSBezierPath {
    let p = NSBezierPath()
    p.move(to: NSPoint(x: 22.6278, y: 27.3078))
    p.line(to: NSPoint(x: 24.2394, y: 0.457031))
    p.line(to: NSPoint(x: 14.6816, y: 17.0116))
    p.close()
    return p
}

// Layout: pointer on the left-center; usage bars on the right.
let vbH: CGFloat = 28
let cursorScale = size * 0.48 / vbH
let cursorDrawH = vbH * cursorScale
// Optical placement — slightly left of center so bars balance the right side
let cursorOriginX = size * 0.14
let cursorOriginY = (size - cursorDrawH) * 0.42

cg.saveGState()
// SVG → AppKit: scale, then flip Y within the viewBox
cg.translateBy(x: cursorOriginX, y: cursorOriginY + cursorDrawH)
cg.scaleBy(x: cursorScale, y: -cursorScale)

let outline = cursorOutlinePath()
cg.saveGState()
cg.addPath(outline.cgPath)
cg.clip()

// Left facet: white → translucent white
let left = leftFacetPath()
cg.saveGState()
cg.addPath(left.cgPath)
cg.clip()
let leftGrad = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor(calibratedWhite: 1, alpha: 1).cgColor,
        NSColor(calibratedWhite: 1, alpha: 0.45).cgColor,
    ] as CFArray,
    locations: [0, 1]
)!
cg.drawLinearGradient(
    leftGrad,
    start: CGPoint(x: 13, y: 0.46),
    end: CGPoint(x: 13, y: 17.01),
    options: []
)
cg.restoreGState()

// Right facet: translucent → white
let right = rightFacetPath()
cg.saveGState()
cg.addPath(right.cgPath)
cg.clip()
let rightGrad = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor(calibratedWhite: 1, alpha: 0.40).cgColor,
        NSColor(calibratedWhite: 1, alpha: 1).cgColor,
    ] as CFArray,
    locations: [0, 1]
)!
cg.drawLinearGradient(
    rightGrad,
    start: CGPoint(x: 19.5, y: 0.46),
    end: CGPoint(x: 19.5, y: 27.3),
    options: []
)
cg.restoreGState()

cg.restoreGState() // outline clip
cg.restoreGState() // SVG transform

// ── Ascending usage bars (mint) — right side, usage identity ────────────────
let barWidth = size * 0.075
let gap = size * 0.045
let heights: [CGFloat] = [0.22, 0.36, 0.52]
let barColors: [NSColor] = [
    NSColor(calibratedRed: 0.20, green: 0.83, blue: 0.60, alpha: 1),
    NSColor(calibratedRed: 0.16, green: 0.78, blue: 0.55, alpha: 1),
    NSColor(calibratedRed: 0.06, green: 0.73, blue: 0.51, alpha: 1),
]

let barsBottom = size * 0.22
let barsStartX = size * 0.58

for (i, hFrac) in heights.enumerated() {
    let h = size * hFrac
    let x = barsStartX + CGFloat(i) * (barWidth + gap)
    let barRect = NSRect(x: x, y: barsBottom, width: barWidth, height: h)
    let radius = barWidth / 2
    let path = NSBezierPath(roundedRect: barRect, xRadius: radius, yRadius: radius)
    let light = barColors[i].blended(withFraction: 0.25, of: .white) ?? barColors[i]
    let g = NSGradient(colors: [light, barColors[i]])!
    g.draw(in: path, angle: 270)
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fputs("error: png encode failed\n", stderr)
    exit(1)
}
try png.write(to: outURL)
print("Wrote \(outURL.path) (\(png.count) bytes)")
