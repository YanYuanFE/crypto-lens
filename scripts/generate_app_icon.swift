import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: swift scripts/generate_app_icon.swift source.png AppIcon.appiconset\n", stderr)
    exit(64)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    fputs("Unable to read source image: \(sourceURL.path)\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

for dimension in [16, 32, 64, 128, 256, 512, 1024] {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: dimension,
        pixelsHigh: dimension,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Unable to allocate \(dimension)x\(dimension) bitmap")
    }

    bitmap.size = NSSize(width: dimension, height: dimension)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)
    context?.imageInterpolation = .high
    NSGraphicsContext.current = context
    sourceImage.draw(
        in: NSRect(x: 0, y: 0, width: dimension, height: dimension),
        from: NSRect(origin: .zero, size: sourceImage.size),
        operation: .copy,
        fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Unable to encode \(dimension)x\(dimension) icon")
    }
    let outputURL = outputDirectory.appendingPathComponent("icon_\(dimension).png")
    try png.write(to: outputURL, options: .atomic)
}
