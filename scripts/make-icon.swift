import AppKit

// Render a 1024×1024 app-icon PNG (clock/timer motif on a blue gradient) to argv[1].
let size: CGFloat = 1024

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.png>\n".utf8))
    exit(1)
}
let outPath = CommandLine.arguments[1]

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// Background: rounded-rect vertical gradient.
let margin = size * 0.08
let bgRect = NSRect(x: margin, y: margin, width: size - 2 * margin, height: size - 2 * margin)
let radius = bgRect.width * 0.225
let background = NSBezierPath(roundedRect: bgRect, xRadius: radius, yRadius: radius)
let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.27, green: 0.60, blue: 1.00, alpha: 1),
    NSColor(srgbRed: 0.10, green: 0.32, blue: 0.86, alpha: 1),
])!
gradient.draw(in: background, angle: -90)

let cx = size / 2, cy = size / 2
let r = size * 0.26

// Clock ring.
NSColor.white.setStroke()
let ring = NSBezierPath(ovalIn: NSRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
ring.lineWidth = size * 0.055
ring.stroke()

// Timer button on top.
let button = NSBezierPath(
    roundedRect: NSRect(x: cx - size * 0.035, y: cy + r + size * 0.005, width: size * 0.07, height: size * 0.06),
    xRadius: size * 0.015, yRadius: size * 0.015
)
NSColor.white.setFill()
button.fill()

// Hands.
let hands = NSBezierPath()
hands.lineWidth = size * 0.05
hands.lineCapStyle = .round
hands.move(to: NSPoint(x: cx, y: cy)); hands.line(to: NSPoint(x: cx, y: cy + r * 0.58))
hands.move(to: NSPoint(x: cx, y: cy)); hands.line(to: NSPoint(x: cx + r * 0.40, y: cy + r * 0.16))
NSColor.white.setStroke()
hands.stroke()

// Center dot.
let dotR = size * 0.022
let dot = NSBezierPath(ovalIn: NSRect(x: cx - dotR, y: cy - dotR, width: 2 * dotR, height: 2 * dotR))
NSColor.white.setFill()
dot.fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("failed to render png\n".utf8))
    exit(1)
}
do {
    try png.write(to: URL(fileURLWithPath: outPath))
} catch {
    FileHandle.standardError.write(Data("write failed: \(error)\n".utf8))
    exit(1)
}
