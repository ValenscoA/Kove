// Renders Kove's artwork: the app icon (.icns) and the menu bar template glyph.
//
// The mark is the island itself — a pill fused to the top edge of a dark squircle,
// with the MacBook notch bitten out of it — so the icon says the same thing the app
// does. Run with: swift Tools/MakeIcon.swift   (output goes to Resources/)
//
//   swift Tools/MakeIcon.swift                  → writes the real assets
//   swift Tools/MakeIcon.swift --sheet /tmp/x.png → renders the variants side by side

import AppKit
import CoreGraphics

let renderSize: CGFloat = 1024
let resources = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Resources")

// MARK: - Shapes

/// Apple's icon grid is a superellipse, not a rounded rect; n = 5 matches it
/// closely enough that the icon sits well next to system icons in the Dock.
func squircle(in rect: CGRect, exponent n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2
    let b = rect.height / 2
    let steps = 1440

    for step in 0...steps {
        let t = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let c = cos(t)
        let s = sin(t)
        let x = rect.midX + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = rect.midY + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        if step == 0 {
            path.move(to: CGPoint(x: x, y: y))
        } else {
            path.addLine(to: CGPoint(x: x, y: y))
        }
    }
    path.closeSubpath()
    return path
}

/// A rect whose top edge is straight and whose bottom corners are round — the
/// island's silhouette.
func islandPill(in rect: CGRect, bottomRadius radius: CGFloat) -> CGPath {
    let r = min(radius, min(rect.width / 2, rect.height))
    let path = CGMutablePath()
    path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + r))
    path.addArc(
        tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
        tangent2End: CGPoint(x: rect.maxX - r, y: rect.minY),
        radius: r
    )
    path.addLine(to: CGPoint(x: rect.minX + r, y: rect.minY))
    path.addArc(
        tangent1End: CGPoint(x: rect.minX, y: rect.minY),
        tangent2End: CGPoint(x: rect.minX, y: rect.minY + r),
        radius: r
    )
    path.closeSubpath()
    return path
}

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func gradient(_ stops: [(NSColor, CGFloat)]) -> CGGradient {
    CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: stops.map { $0.0.cgColor } as CFArray,
        locations: stops.map { $0.1 }
    )!
}

// MARK: - Rendering helpers

func makeContext(pixels: Int) -> (NSBitmapImageRep, CGContext) {
    let rep = NSBitmapImageRep(
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
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.interpolationQuality = .high
    return (rep, ctx)
}

func finish(_ rep: NSBitmapImageRep, _ ctx: CGContext, path: String) {
    ctx.flush()
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG encoding failed for \(path)")
    }
    try! data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

/// Scales a finished render down to any size with high-quality resampling.
func scaled(_ source: NSBitmapImageRep, pixels: Int) -> NSBitmapImageRep {
    let (rep, ctx) = makeContext(pixels: pixels)
    if let image = source.cgImage {
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    }
    ctx.flush()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - The mark

struct IconGeometry {
    var pillWidth: CGFloat = 600
    var pillHeight: CGFloat = 240
    var notchWidth: CGFloat = 156
    var notchDepth: CGFloat = 54
    /// Draws the expanded island's content below the pill.
    var showsContent = false
}

/// All geometry is expressed in 1024-point space and scaled by `u`.
func drawIcon(_ ctx: CGContext, size: CGFloat, geometry g: IconGeometry) {
    let u = size / 1024

    let canvas = CGRect(x: 0, y: 0, width: size, height: size)
    let body = canvas.insetBy(dx: 100 * u, dy: 100 * u)
    let bodyPath = squircle(in: body)
    let edge = body.maxY

    let pillPath = islandPill(
        in: CGRect(
            x: (size / 2) - g.pillWidth * u / 2,
            y: edge - g.pillHeight * u,
            width: g.pillWidth * u,
            height: g.pillHeight * u + 16 * u
        ),
        bottomRadius: g.pillHeight * u / 2
    )
    let notchPath = islandPill(
        in: CGRect(
            x: (size / 2) - g.notchWidth * u / 2,
            y: edge - g.notchDepth * u,
            width: g.notchWidth * u,
            height: g.notchDepth * u + 16 * u
        ),
        bottomRadius: g.notchDepth * u / 2
    )

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()

    // Body: near-black with a touch of warmth at the top so it is not a flat slab.
    ctx.drawLinearGradient(
        gradient([(color(0x2B2B33), 0), (color(0x131316), 0.55), (color(0x08080A), 1)]),
        start: CGPoint(x: size / 2, y: edge),
        end: CGPoint(x: size / 2, y: body.minY),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    // Soft light pooling behind the pill, as if the island were lit from above.
    ctx.drawRadialGradient(
        gradient([(color(0xFFFFFF, alpha: 0.16), 0), (color(0xFFFFFF, alpha: 0), 1)]),
        startCenter: CGPoint(x: size / 2, y: edge - 40 * u),
        startRadius: 0,
        endCenter: CGPoint(x: size / 2, y: edge - 40 * u),
        endRadius: 520 * u,
        options: [.drawsAfterEndLocation]
    )

    // The screen's top edge, with the pill hanging off it — the seam is what makes
    // the shape read as a notch on a display rather than an abstract bar.
    ctx.setFillColor(color(0xFFFFFF, alpha: 0.20).cgColor)
    ctx.fill(CGRect(x: body.minX, y: edge - 3 * u, width: body.width, height: 3 * u))

    if g.showsContent {
        drawContent(ctx, size: size, unit: u)
    }

    // Glow, then contact shadow, then the pill itself. Each pass is clipped to the
    // body so the pill reads as fused to the top edge instead of floating over it.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 120 * u, color: color(0xFFFFFF, alpha: 0.22).cgColor)
    ctx.addPath(pillPath)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -22 * u), blur: 70 * u, color: NSColor.black.withAlphaComponent(0.55).cgColor)
    ctx.addPath(pillPath)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(pillPath)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([(color(0xFFFFFF), 0), (color(0xF2F3F6), 0.6), (color(0xDDDEE4), 1)]),
        start: CGPoint(x: size / 2, y: edge + 16 * u),
        end: CGPoint(x: size / 2, y: edge - g.pillHeight * u),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    ctx.restoreGState()

    // The notch: a bite out of the pill's top edge, filled with the body's own dark
    // so it reads as a hole rather than a painted-on rectangle.
    ctx.saveGState()
    ctx.addPath(notchPath)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([(color(0x24242A), 0), (color(0x0C0C0F), 1)]),
        start: CGPoint(x: size / 2, y: edge + 16 * u),
        end: CGPoint(x: size / 2, y: edge - g.notchDepth * u),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    ctx.restoreGState()

    ctx.restoreGState()

    // Rim light, drawn outside the clip so it stays crisp.
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.setStrokeColor(color(0xFFFFFF, alpha: 0.13).cgColor)
    ctx.setLineWidth(2.5 * u)
    ctx.strokePath()
    ctx.restoreGState()
}

/// The expanded island: artwork tile, track lines and transport controls, drawn
/// faintly so the pill stays the hero.
func drawContent(_ ctx: CGContext, size: CGFloat, unit u: CGFloat) {
    let cx = size / 2

    func bar(_ rect: CGRect, radius: CGFloat, alpha: CGFloat) {
        ctx.setFillColor(color(0xFFFFFF, alpha: alpha).cgColor)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.fillPath()
    }

    let panel = CGRect(x: cx - 220 * u, y: 230 * u, width: 440 * u, height: 400 * u)
    let panelPath = CGPath(roundedRect: panel, cornerWidth: 84 * u, cornerHeight: 84 * u, transform: nil)

    ctx.saveGState()
    ctx.addPath(panelPath)
    ctx.setFillColor(color(0xFFFFFF, alpha: 0.055).cgColor)
    ctx.fillPath()
    ctx.addPath(panelPath)
    ctx.setStrokeColor(color(0xFFFFFF, alpha: 0.14).cgColor)
    ctx.setLineWidth(3 * u)
    ctx.strokePath()

    // Artwork tile.
    let art = CGRect(x: cx - 176 * u, y: 470 * u, width: 150 * u, height: 150 * u)
    ctx.setFillColor(color(0xFFFFFF, alpha: 0.14).cgColor)
    ctx.addPath(CGPath(roundedRect: art, cornerWidth: 32 * u, cornerHeight: 32 * u, transform: nil))
    ctx.fillPath()

    // Track title, artist.
    bar(CGRect(x: cx - 6 * u, y: 576 * u, width: 182 * u, height: 22 * u), radius: 11 * u, alpha: 0.62)
    bar(CGRect(x: cx - 6 * u, y: 534 * u, width: 124 * u, height: 16 * u), radius: 8 * u, alpha: 0.26)
    bar(CGRect(x: cx - 6 * u, y: 506 * u, width: 96 * u, height: 12 * u), radius: 6 * u, alpha: 0.16)

    // Progress.
    bar(CGRect(x: cx - 176 * u, y: 424 * u, width: 352 * u, height: 12 * u), radius: 6 * u, alpha: 0.16)
    bar(CGRect(x: cx - 176 * u, y: 424 * u, width: 132 * u, height: 12 * u), radius: 6 * u, alpha: 0.72)

    // Transport: previous / play / next.
    for (offset, diameter, alpha) in [(-84.0, 34.0, 0.22), (0.0, 48.0, 0.80), (84.0, 34.0, 0.22)] {
        let circle = CGRect(
            x: cx + CGFloat(offset) * u - CGFloat(diameter) * u / 2,
            y: 320 * u,
            width: CGFloat(diameter) * u,
            height: CGFloat(diameter) * u
        )
        ctx.setFillColor(color(0xFFFFFF, alpha: CGFloat(alpha)).cgColor)
        ctx.addPath(CGPath(ellipseIn: circle, transform: nil))
        ctx.fillPath()
    }
    ctx.restoreGState()
}

// MARK: - Variant sheet

let variants: [(String, IconGeometry)] = [
    ("A  minimal", IconGeometry(pillWidth: 440, pillHeight: 200, notchWidth: 128, notchDepth: 44)),
    ("B  hero pill", IconGeometry()),
    ("C  with content", IconGeometry(showsContent: true))
]

func renderSheet(to path: String) {
    let tile: CGFloat = 340
    let gap: CGFloat = 40
    let width = Int(tile * CGFloat(variants.count) + gap * CGFloat(variants.count + 1))
    let height = Int(tile + gap * 2 + 44)

    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    ctx.setFillColor(color(0xE8E8EC).cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

    for (index, variant) in variants.enumerated() {
        let (tileRep, tileCtx) = makeContext(pixels: Int(tile))
        drawIcon(tileCtx, size: tile, geometry: variant.1)
        tileCtx.flush()
        NSGraphicsContext.restoreGraphicsState()

        let x = gap + CGFloat(index) * (tile + gap)
        ctx.draw(tileRep.cgImage!, in: CGRect(x: x, y: gap, width: tile, height: tile))

        let label = NSAttributedString(
            string: variant.0,
            attributes: [
                .font: NSFont.systemFont(ofSize: 16, weight: .medium),
                .foregroundColor: color(0x33333A)
            ]
        )
        let line = NSGraphicsContext.current!
        line.cgContext.saveGState()
        line.cgContext.textMatrix = .identity
        label.draw(at: NSPoint(x: x + 4, y: gap + tile + 14))
        line.cgContext.restoreGState()
    }

    // Also show the real size, where icons are usually judged.
    let (smallRep, smallCtx) = makeContext(pixels: 64)
    drawIcon(smallCtx, size: 64, geometry: variants[0].1)
    smallCtx.flush()
    NSGraphicsContext.restoreGraphicsState()
    ctx.draw(smallRep.cgImage!, in: CGRect(x: gap, y: gap + tile + 24, width: 32, height: 32))

    ctx.flush()
    NSGraphicsContext.restoreGraphicsState()

    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

// MARK: - Menu bar template glyph

/// Template images are drawn as a mask: black pixels are opaque, everything else
/// is clear, and macOS tints them for light/dark menu bars.
func templateGlyph(pixels: Int, tint: NSColor = .black) -> NSBitmapImageRep {
    let (rep, ctx) = makeContext(pixels: pixels)
    let scale = CGFloat(pixels) / 36

    let glyph = islandPill(
        in: CGRect(x: 3 * scale, y: 7 * scale, width: 30 * scale, height: 22 * scale),
        bottomRadius: 11 * scale
    )
    let notch = islandPill(
        in: CGRect(x: 18 * scale - 5.5 * scale, y: 29 * scale - 6 * scale, width: 11 * scale, height: 8 * scale),
        bottomRadius: 3 * scale
    )

    ctx.setFillColor(tint.cgColor)
    ctx.addPath(glyph)
    ctx.fillPath()

    ctx.setBlendMode(.clear)
    ctx.addPath(notch)
    ctx.fillPath()
    ctx.setBlendMode(.normal)

    ctx.flush()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - Main

if let flagIndex = CommandLine.arguments.firstIndex(of: "--sheet") {
    let path = CommandLine.arguments.count > flagIndex + 1
        ? CommandLine.arguments[flagIndex + 1]
        : "/tmp/kove-icon-variants.png"
    renderSheet(to: path)
    exit(0)
}

let (icon, ctx) = makeContext(pixels: Int(renderSize))
drawIcon(ctx, size: renderSize, geometry: IconGeometry())
let iconPath = resources.appendingPathComponent("AppIcon-1024.png").path
finish(icon, ctx, path: iconPath)

for (name, px) in [("StatusIcon.png", 18), ("StatusIcon@2x.png", 36), ("StatusIcon@3x.png", 54)] {
    let rep = templateGlyph(pixels: px)
    let url = resources.appendingPathComponent(name)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG encoding failed for \(name)")
    }
    try! data.write(to: url)
    print("wrote \(url.path)")
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Kove.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for (suffix, factor) in [("", 1), ("@2x", 2)] {
        let rep = scaled(icon, pixels: base * factor)
        guard let data = rep.representation(using: .png, properties: [:]) else { continue }
        try! data.write(to: iconset.appendingPathComponent("icon_\(base)x\(base)\(suffix).png"))
    }
}

// Windows: one .ico for the app, one per tray theme (Windows does not tint
// template images, so the glyph has to be drawn in the right colour).
func writeICO(_ sizes: [Int], make: (Int) -> NSBitmapImageRep, to path: String) {
    let images = sizes.map(make)
    let datas = images.compactMap { $0.representation(using: .png, properties: [:]) }

    var out = Data([0, 0, 1, 0])
    let count = UInt16(datas.count)
    out.append(contentsOf: [UInt8(count & 0xFF), UInt8(count >> 8)])

    var offset = 6 + 16 * datas.count
    for (image, data) in zip(images, datas) {
        let width = image.pixelsWide
        let height = image.pixelsHigh
        out.append(UInt8(width >= 256 ? 0 : width))
        out.append(UInt8(height >= 256 ? 0 : height))
        out.append(contentsOf: [0, 0, 1, 0, 32, 0])
        for value in [UInt32(data.count), UInt32(offset)] {
            out.append(contentsOf: [
                UInt8(value & 0xFF),
                UInt8((value >> 8) & 0xFF),
                UInt8((value >> 16) & 0xFF),
                UInt8((value >> 24) & 0xFF)
            ])
        }
        offset += data.count
    }
    for data in datas { out.append(data) }

    try! out.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

writeICO([16, 32, 48, 64, 128, 256], make: { scaled(icon, pixels: $0) },
         to: resources.appendingPathComponent("AppIcon.ico").path)
writeICO([16, 20, 24, 32, 40, 48], make: { templateGlyph(pixels: $0, tint: .black) },
         to: resources.appendingPathComponent("TrayIcon-Black.ico").path)
writeICO([16, 20, 24, 32, 40, 48], make: { templateGlyph(pixels: $0, tint: .white) },
         to: resources.appendingPathComponent("TrayIcon-White.ico").path)

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try! iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "wrote Resources/AppIcon.icns" : "iconutil failed")
