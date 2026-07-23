#!/usr/bin/env swift
import AppKit
import Foundation

guard CommandLine.arguments.count >= 3 else {
    fputs("Usage: stamp-icon.swift <App.app> <AppIcon.icns>\n", stderr)
    exit(1)
}

let app = CommandLine.arguments[1]
let icns = CommandLine.arguments[2]
guard let img = NSImage(contentsOf: URL(fileURLWithPath: icns)) else {
    fputs("error: could not load \(icns)\n", stderr)
    exit(1)
}
guard NSWorkspace.shared.setIcon(img, forFile: app, options: []) else {
    fputs("error: NSWorkspace.setIcon failed\n", stderr)
    exit(1)
}
print("Stamped Finder icon onto \(app)")
