#!/usr/bin/env swift
// Crop an icon PNG to the macOS app-icon squircle (rounded rect ~22% corner radius),
// making the corners transparent. Used when the AI generator produced an icon with
// the design baked into the full-bleed square (no alpha channel).
//
// Usage: swift apply_squircle_mask.swift <input.png> <output.png>

import AppKit
import Foundation

guard CommandLine.arguments.count >= 3 else {
    print("usage: swift apply_squircle_mask.swift <input.png> <output.png>")
    exit(1)
}
let inPath = CommandLine.arguments[1]
let outPath = CommandLine.arguments[2]

guard let inImage = NSImage(contentsOfFile: inPath) else {
    print("✗ failed to read \(inPath)")
    exit(1)
}

// Draw at 1024×1024 so the .icns generator sees a clean square.
let size = NSSize(width: 1024, height: 1024)
let outImage = NSImage(size: size)
outImage.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else {
    fatalError("no graphics context")
}

// Fill with transparency first (defensive)
ctx.clear(CGRect(origin: .zero, size: size))

// Squircle path — 22% corner radius matches macOS app icon shape
let cornerRadius: CGFloat = 224
let bgPath = CGPath(
    roundedRect: CGRect(origin: .zero, size: size),
    cornerWidth: cornerRadius,
    cornerHeight: cornerRadius,
    transform: nil
)
ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()

// Draw the source image scaled to fill the canvas
inImage.draw(in: CGRect(origin: .zero, size: size),
             from: .zero,
             operation: .sourceOver,
             fraction: 1.0)
ctx.restoreGState()

outImage.unlockFocus()

guard
    let tiff = outImage.tiffRepresentation,
    let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [:])
else {
    fatalError("failed to encode PNG")
}
try png.write(to: URL(fileURLWithPath: outPath))
print("✓ saved \(outPath) (squircle-masked, 1024×1024 RGBA)")
