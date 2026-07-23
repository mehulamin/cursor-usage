#!/usr/bin/env swift
import AppKit
import Foundation

/// Build a complete AppIcon.icns from AppIcon-1024.png.
/// We embed PNG streams directly — `iconutil` on recent macOS often drops ic10/1024
/// and @2x slots, which makes Finder show the generic app icon.

guard CommandLine.arguments.count >= 3 else {
    fputs("Usage: make-icns.swift <AppIcon-1024.png> <AppIcon.icns>\n", stderr)
    exit(1)
}

let srcURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let src = NSImage(contentsOf: srcURL) else {
    fputs("error: could not load \(srcURL.path)\n", stderr)
    exit(1)
}

func rgbaPNG(_ size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
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
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()
    src.draw(
        in: NSRect(x: 0, y: 0, width: size, height: size),
        from: NSRect(origin: .zero, size: src.size),
        operation: .sourceOver,
        fraction: 1.0,
        respectFlipped: false,
        hints: [.interpolation: NSImageInterpolation.high]
    )
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("png encode failed for \(size)")
    }
    return data
}

// OSType → pixel size (includes retina slots Finder expects)
let icons: [(String, Int)] = [
    ("ic04", 16),
    ("ic05", 32),
    ("ic07", 128),
    ("ic08", 256),
    ("ic09", 512),
    ("ic10", 1024),
    ("ic11", 32),
    ("ic12", 64),
    ("ic13", 256),
    ("ic14", 512),
]

var body = Data()
for (type, px) in icons {
    let png = rgbaPNG(px)
    var chunk = Data(type.utf8)
    var len = UInt32(png.count + 8).bigEndian
    chunk.append(Data(bytes: &len, count: 4))
    chunk.append(png)
    body.append(chunk)
}

var file = Data("icns".utf8)
var total = UInt32(body.count + 8).bigEndian
file.append(Data(bytes: &total, count: 4))
file.append(body)
try file.write(to: outURL)
print("Wrote \(outURL.path) (\(file.count) bytes)")
