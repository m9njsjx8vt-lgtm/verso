#!/usr/bin/env swift

// Generates a 1024×1024 PNG app icon: gradient squircle with a centered character.
// Usage: swift make_icon.swift <output-png-path> [glyph] [font-name] [size]
//   default: 訳, system heavy, 720pt

import AppKit
import Foundation

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "/tmp/icon_1024.png"
let glyph = CommandLine.arguments.count > 2
    ? CommandLine.arguments[2]
    : "訳"
let fontName = CommandLine.arguments.count > 3
    ? CommandLine.arguments[3]
    : ""
let pointSize: CGFloat = CommandLine.arguments.count > 4
    ? CGFloat(Double(CommandLine.arguments[4]) ?? 720)
    : 720

let glyphFont: NSFont = {
    if !fontName.isEmpty, let f = NSFont(name: fontName, size: pointSize) {
        return f
    }
    return NSFont.systemFont(ofSize: pointSize, weight: .heavy)
}()

let size = NSSize(width: 1024, height: 1024)
let img = NSImage(size: size)
img.lockFocus()

guard let ctx = NSGraphicsContext.current?.cgContext else {
    fatalError("no graphics context")
}

// 1. Squircle background path
let cornerRadius: CGFloat = 224 // ~22% — matches macOS app icon shape
let bgPath = CGPath(
    roundedRect: CGRect(origin: .zero, size: size),
    cornerWidth: cornerRadius,
    cornerHeight: cornerRadius,
    transform: nil
)
ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()

// 2. Diagonal gradient (indigo → violet)
let topColor = CGColor(srgbRed: 0.231, green: 0.357, blue: 0.859, alpha: 1.0)
let bottomColor = CGColor(srgbRed: 0.612, green: 0.212, blue: 0.710, alpha: 1.0)
let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [topColor, bottomColor] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: size.height),
    end: CGPoint(x: size.width, y: 0),
    options: []
)
ctx.restoreGState()

// 3. Subtle inner highlight on top-left
ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()
let highlight = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.15),
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0)
    ] as CFArray,
    locations: [0, 1]
)!
ctx.drawRadialGradient(
    highlight,
    startCenter: CGPoint(x: 250, y: 850),
    startRadius: 0,
    endCenter: CGPoint(x: 250, y: 850),
    endRadius: 800,
    options: []
)
ctx.restoreGState()

// 4. Centered glyph with subtle shadow
let para = NSMutableParagraphStyle()
para.alignment = .center

let shadow = NSShadow()
shadow.shadowColor = NSColor(white: 0, alpha: 0.18)
shadow.shadowOffset = NSSize(width: 0, height: -8)
shadow.shadowBlurRadius = 24

let attrs: [NSAttributedString.Key: Any] = [
    .font: glyphFont,
    .foregroundColor: NSColor.white,
    .paragraphStyle: para,
    .shadow: shadow,
]
let s = NSAttributedString(string: glyph, attributes: attrs)
let tSize = s.size()
let textRect = NSRect(
    x: (size.width - tSize.width) / 2,
    y: (size.height - tSize.height) / 2 - 40, // visually balanced
    width: tSize.width,
    height: tSize.height
)
s.draw(in: textRect)

img.unlockFocus()

// 5. Encode and write PNG
guard
    let tiff = img.tiffRepresentation,
    let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [:])
else {
    fatalError("failed to encode PNG")
}
try png.write(to: URL(fileURLWithPath: outputPath))
print("✓ saved \(outputPath) (1024×1024, glyph: \(glyph))")
