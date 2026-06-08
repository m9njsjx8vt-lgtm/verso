#!/usr/bin/env swift

import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 || arguments.count == 4 else {
    fputs("Usage: prepare_icon_source.swift <input.png> <output.png> [--remove-border-background]\n", stderr)
    exit(64)
}

let inputURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])
let removeBorderBackground = arguments.dropFirst(3).contains("--remove-border-background")

guard let sourceImage = NSImage(contentsOf: inputURL),
      let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("Could not load image: \(inputURL.path)\n", stderr)
    exit(1)
}

let width = cgImage.width
let height = cgImage.height
guard width > 0, height > 0 else {
    fputs("Image has invalid dimensions: \(inputURL.path)\n", stderr)
    exit(1)
}

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width,
    pixelsHigh: height,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Could not allocate bitmap\n", stderr)
    exit(1)
}

bitmap.size = NSSize(width: width, height: height)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()
NSImage(cgImage: cgImage, size: NSSize(width: width, height: height)).draw(
    in: NSRect(x: 0, y: 0, width: width, height: height),
    from: .zero,
    operation: .sourceOver,
    fraction: 1.0
)
NSGraphicsContext.restoreGraphicsState()

if removeBorderBackground {
    guard let data = bitmap.bitmapData else {
        fputs("Could not access bitmap data\n", stderr)
        exit(1)
    }

    let bytesPerRow = bitmap.bytesPerRow
    let tolerance = 28

    func offset(_ x: Int, _ y: Int) -> Int {
        y * bytesPerRow + x * 4
    }

    func colorAt(_ x: Int, _ y: Int) -> (Int, Int, Int) {
        let i = offset(x, y)
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
    }

    let corners = [
        colorAt(0, 0),
        colorAt(width - 1, 0),
        colorAt(0, height - 1),
        colorAt(width - 1, height - 1)
    ]
    let background = (
        corners.map(\.0).reduce(0, +) / corners.count,
        corners.map(\.1).reduce(0, +) / corners.count,
        corners.map(\.2).reduce(0, +) / corners.count
    )

    func matchesBackground(_ x: Int, _ y: Int) -> Bool {
        let (red, green, blue) = colorAt(x, y)
        return max(abs(red - background.0), abs(green - background.1), abs(blue - background.2)) <= tolerance
    }

    var visited = Array(repeating: false, count: width * height)
    var queue: [(Int, Int)] = []
    queue.reserveCapacity(width * 2 + height * 2)

    for x in 0..<width {
        queue.append((x, 0))
        queue.append((x, height - 1))
    }
    for y in 0..<height {
        queue.append((0, y))
        queue.append((width - 1, y))
    }

    var cursor = 0
    while cursor < queue.count {
        let (x, y) = queue[cursor]
        cursor += 1

        guard x >= 0, x < width, y >= 0, y < height else { continue }
        let index = y * width + x
        guard !visited[index] else { continue }
        visited[index] = true
        guard matchesBackground(x, y) else { continue }

        let i = offset(x, y)
        data[i] = 0
        data[i + 1] = 0
        data[i + 2] = 0
        data[i + 3] = 0

        queue.append((x + 1, y))
        queue.append((x - 1, y))
        queue.append((x, y + 1))
        queue.append((x, y - 1))
    }
}

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not encode PNG\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try pngData.write(to: outputURL, options: [.atomic])
