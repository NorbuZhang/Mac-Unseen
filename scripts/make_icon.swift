// SPDX-License-Identifier: MPL-2.0

import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("usage: make_icon.swift input.png output.png\n", stderr)
    exit(2)
}

let pixels = 1024
let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
guard let source = NSImage(contentsOf: inputURL) else {
    fatalError("Unable to load source icon")
}

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixels,
    pixelsHigh: pixels,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Unable to create icon bitmap")
}

NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Unable to create icon graphics context")
}
NSGraphicsContext.current = context
context.imageInterpolation = .high

let bounds = NSRect(x: 0, y: 0, width: pixels, height: pixels)
NSColor.clear.setFill()
bounds.fill()
source.draw(
    in: bounds,
    from: NSRect(origin: .zero, size: source.size),
    operation: .copy,
    fraction: 1
)

NSGraphicsContext.restoreGraphicsState()

// The approved concept has a solid black canvas outside the rounded tile.
// Remove only near-black pixels connected to the image boundary so the
// intentional dark details inside the icon remain untouched.
guard let pixelData = bitmap.bitmapData else {
    fatalError("Unable to access icon pixels")
}
let bytesPerRow = bitmap.bytesPerRow
let samplesPerPixel = bitmap.samplesPerPixel
let pixelCount = pixels * pixels
var visited = Array(repeating: false, count: pixelCount)
var queue: [Int] = []
queue.reserveCapacity(pixelCount / 4)

func isBackground(_ index: Int) -> Bool {
    let x = index % pixels
    let y = index / pixels
    let offset = y * bytesPerRow + x * samplesPerPixel
    return max(pixelData[offset], pixelData[offset + 1], pixelData[offset + 2]) <= 8
}

func enqueue(_ index: Int) {
    guard !visited[index], isBackground(index) else { return }
    visited[index] = true
    queue.append(index)
}

for x in 0..<pixels {
    enqueue(x)
    enqueue((pixels - 1) * pixels + x)
}
for y in 0..<pixels {
    enqueue(y * pixels)
    enqueue(y * pixels + pixels - 1)
}

var cursor = 0
while cursor < queue.count {
    let index = queue[cursor]
    cursor += 1
    let x = index % pixels
    let y = index / pixels
    if x > 0 { enqueue(index - 1) }
    if x + 1 < pixels { enqueue(index + 1) }
    if y > 0 { enqueue(index - pixels) }
    if y + 1 < pixels { enqueue(index + pixels) }
}

for index in queue {
    let x = index % pixels
    let y = index / pixels
    pixelData[y * bytesPerRow + x * samplesPerPixel + 3] = 0
}

guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode icon")
}
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
