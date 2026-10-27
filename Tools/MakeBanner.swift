// Renders the README banner: dark slab, app icon, wordmark, tagline.
//
// Run with: swift Tools/MakeBanner.swift   (writes docs/banner.png at 2x)

import AppKit
import CoreGraphics

let logical = CGSize(width: 1200, height: 420)
let scale: CGFloat = 2
let px = Int(logical.width * scale)
let py = Int(logical.height * scale)

let resources = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("docs")

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: px,
    pixelsHigh: py,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
ctx.scaleBy(x: scale, y: scale)
ctx.interpolationQuality = .high

let canvas = CGRect(origin: .zero, size: logical)

// Backdrop.
ctx.drawLinearGradient(
    CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color(0x121216).cgColor, color(0x060607).cgColor] as CFArray,
        locations: [0, 1]
    )!,
    start: CGPoint(x: 0, y: logical.height),
    end: CGPoint(x: 0, y: 0),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
)
ctx.drawRadialGradient(
    CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color(0xFFFFFF, alpha: 0.10).cgColor, color(0xFFFFFF, alpha: 0).cgColor] as CFArray,
        locations: [0, 1]
    )!,
    startCenter: CGPoint(x: 250, y: 360),
    startRadius: 0,
    endCenter: CGPoint(x: 250, y: 360),
    endRadius: 620,
    options: [.drawsAfterEndLocation]
)

// App icon.
if let icon = NSImage(contentsOfFile: "Resources/AppIcon-1024.png") {
    let side: CGFloat = 236
    icon.draw(
        in: CGRect(x: 88, y: (logical.height - side) / 2, width: side, height: side),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )
}

// Wordmark.
let title = NSAttributedString(
    string: "Kove",
    attributes: [
        .font: NSFont.systemFont(ofSize: 86, weight: .bold),
        .foregroundColor: color(0xF7F7FA),
        .kern: -1.6
    ]
)
let tagline = NSAttributedString(
    string: "A Dynamic Island for macOS",
    attributes: [
        .font: NSFont.systemFont(ofSize: 25, weight: .regular),
        .foregroundColor: color(0xFFFFFF, alpha: 0.62),
        .kern: 0.2
    ]
)
let sub = NSAttributedString(
    string: "Apple Music playback and Command Code usage, fused to the notch.",
    attributes: [
        .font: NSFont.systemFont(ofSize: 16, weight: .regular),
        .foregroundColor: color(0xFFFFFF, alpha: 0.34)
    ]
)

let textWidth: CGFloat = logical.width - 400 - 88
func height(_ string: NSAttributedString) -> CGFloat {
    string.boundingRect(
        with: CGSize(width: textWidth, height: 400),
        options: [.usesLineFragmentOrigin]
    ).height
}

let titleHeight = height(title)
let taglineHeight = height(tagline)
let subHeight = height(sub)
let gap: CGFloat = 12
let block = titleHeight + gap + taglineHeight + 26 + subHeight
var top = (logical.height + block) / 2

let x: CGFloat = 400
for (string, stringHeight, space) in [
    (title, titleHeight, gap),
    (tagline, taglineHeight, 26),
    (sub, subHeight, 0)
] {
    let rect = CGRect(x: x, y: top - stringHeight, width: textWidth, height: stringHeight)
    string.draw(with: rect, options: [.usesLineFragmentOrigin])
    top -= stringHeight + space
}

ctx.flush()
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("encode") }
let out = resources.appendingPathComponent("banner.png")
try! png.write(to: out)
print("wrote \(out.path) \(px)x\(py)")
