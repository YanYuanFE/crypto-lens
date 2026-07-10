import AppKit

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)

image.lockFocus()
NSColor(calibratedRed: 0.075, green: 0.086, blue: 0.105, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

let lens = NSBezierPath(ovalIn: NSRect(x: 178, y: 222, width: 590, height: 590))
NSColor(calibratedRed: 0.20, green: 0.82, blue: 0.69, alpha: 1).setStroke()
lens.lineWidth = 76
lens.stroke()

let handle = NSBezierPath()
handle.move(to: NSPoint(x: 690, y: 278))
handle.line(to: NSPoint(x: 856, y: 112))
handle.lineCapStyle = .round
handle.lineWidth = 86
NSColor(calibratedRed: 0.20, green: 0.82, blue: 0.69, alpha: 1).setStroke()
handle.stroke()

let chart = NSBezierPath()
chart.move(to: NSPoint(x: 280, y: 410))
chart.line(to: NSPoint(x: 412, y: 530))
chart.line(to: NSPoint(x: 520, y: 452))
chart.line(to: NSPoint(x: 662, y: 630))
chart.lineCapStyle = .round
chart.lineJoinStyle = .round
chart.lineWidth = 54
NSColor(calibratedRed: 1.0, green: 0.43, blue: 0.37, alpha: 1).setStroke()
chart.stroke()

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 577, y: 630))
arrow.line(to: NSPoint(x: 662, y: 630))
arrow.line(to: NSPoint(x: 662, y: 545))
arrow.lineWidth = 54
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.stroke()

image.unlockFocus()

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: 1024,
    pixelsHigh: 1024,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Unable to allocate app icon bitmap")
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
image.draw(in: NSRect(origin: .zero, size: size))
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode app icon")
}
try png.write(to: outputURL)
