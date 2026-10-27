// Renders the artwork used by the README and for sharing.
//
//   swift Tools/MakeBanner.swift                    → docs/banner.png (1200 × 420 @2x)
//   swift Tools/MakeBanner.swift --vertical         → docs/banner-vertical.png (1080 × 1920)
//   swift Tools/MakeBanner.swift --vertical out.png → custom path
//
// Everything is drawn with CoreGraphics: gradients, the app icon, the island's own
// screenshot, and centred text laid out from measured heights.

import AppKit
import CoreGraphics

let docsDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("docs")

// MARK: - Helpers

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func makeContext(width: CGFloat, height: CGFloat, scale: CGFloat) -> (NSBitmapImageRep, CGContext) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(width * scale),
        pixelsHigh: Int(height * scale),
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
    return (rep, ctx)
}

/// The README banner ships at 1800 px wide, so the 2x render is resampled before it
/// is written: running this script must reproduce the committed file, not a bigger one.
func downscaled(_ rep: NSBitmapImageRep, toWidth width: Int) -> NSBitmapImageRep {
    let height = Int((Double(rep.pixelsHigh) / Double(rep.pixelsWide) * Double(width)).rounded())
    let (scaled, ctx) = makeContext(width: CGFloat(width), height: CGFloat(height), scale: 1)
    if let image = rep.cgImage {
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    ctx.flush()
    NSGraphicsContext.restoreGraphicsState()
    return scaled
}

func save(_ rep: NSBitmapImageRep, to path: String) {
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("encode") }
    try! png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) \(rep.pixelsWide)x\(rep.pixelsHigh)")
}

/// The shared backdrop: a near-black slab with light pooling in from one corner, so
/// the flat fill does not read as a solid black rectangle.
func drawBackdrop(_ ctx: CGContext, size: CGSize, glow: CGPoint, glowRadius: CGFloat) {
    ctx.drawLinearGradient(
        CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [color(0x121216).cgColor, color(0x060607).cgColor] as CFArray,
            locations: [0, 1]
        )!,
        start: CGPoint(x: 0, y: size.height),
        end: CGPoint(x: 0, y: 0),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    ctx.drawRadialGradient(
        CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [color(0xFFFFFF, alpha: 0.10).cgColor, color(0xFFFFFF, alpha: 0).cgColor] as CFArray,
            locations: [0, 1]
        )!,
        startCenter: glow,
        startRadius: 0,
        endCenter: glow,
        endRadius: glowRadius,
        options: [.drawsAfterEndLocation]
    )
}

func text(_ string: String, size: CGFloat, weight: NSFont.Weight, color ink: NSColor, kern: CGFloat = 0) -> NSAttributedString {
    NSAttributedString(
        string: string,
        attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: ink,
            .kern: kern
        ]
    )
}

func measuredHeight(_ string: NSAttributedString, width: CGFloat) -> CGFloat {
    string.boundingRect(
        with: CGSize(width: width, height: 600),
        options: [.usesLineFragmentOrigin]
    ).height
}

/// Draws centred in a column, anchored by its top edge, and returns its height.
@discardableResult
func drawCentred(
    _ string: NSAttributedString,
    top: CGFloat,
    width: CGFloat,
    canvasHeight: CGFloat,
    centerX: CGFloat
) -> CGFloat {
    let height = measuredHeight(string, width: width)
    let rect = CGRect(
        x: centerX - width / 2,
        y: canvasHeight - top - height,
        width: width,
        height: height
    )
    string.draw(with: rect, options: [.usesLineFragmentOrigin])
    return height
}

func centred(_ string: NSAttributedString) -> NSAttributedString {
    let mutable = NSMutableAttributedString(attributedString: string)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineHeightMultiple = 1
    mutable.addAttribute(
        .paragraphStyle,
        value: paragraph,
        range: NSRange(location: 0, length: mutable.length)
    )
    return mutable
}

/// Straight top edge, quad-curved bottom corners: the island's own silhouette, so a
/// hairline drawn with it lines up with the screenshot's border.
func islandPath(in rect: CGRect, bottomRadius: CGFloat) -> CGPath {
    let r = min(bottomRadius, min(rect.width / 2, rect.height))
    let path = CGMutablePath()
    path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + r))
    path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.minY), control: CGPoint(x: rect.maxX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.minX + r, y: rect.minY))
    path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + r), control: CGPoint(x: rect.minX, y: rect.minY))
    path.closeSubpath()
    return path
}

func load(_ relativePath: String) -> NSImage? {
    NSImage(contentsOfFile: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(relativePath).path)
}

// MARK: - Horizontal banner

let horizontalSize = CGSize(width: 1200, height: 420)

func renderHorizontal(to path: String) {
    let (rep, ctx) = makeContext(width: horizontalSize.width, height: horizontalSize.height, scale: 2)
    drawBackdrop(ctx, size: horizontalSize, glow: CGPoint(x: 250, y: 360), glowRadius: 620)

    if let icon = load("Resources/AppIcon-1024.png") {
        let side: CGFloat = 236
        icon.draw(
            in: CGRect(x: 88, y: (horizontalSize.height - side) / 2, width: side, height: side),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
    }

    let title = text("Kove", size: 86, weight: .bold, color: color(0xF7F7FA), kern: -1.6)
    let tagline = text("A Dynamic Island for macOS", size: 25, weight: .regular, color: color(0xFFFFFF, alpha: 0.62), kern: 0.2)
    let sub = text("Apple Music playback and Command Code usage, fused to the notch.", size: 16, weight: .regular, color: color(0xFFFFFF, alpha: 0.34))

    let textWidth: CGFloat = horizontalSize.width - 400 - 88
    let gap: CGFloat = 12
    let block = measuredHeight(title, width: textWidth)
        + gap
        + measuredHeight(tagline, width: textWidth)
        + 26
        + measuredHeight(sub, width: textWidth)

    var top = (horizontalSize.height + block) / 2
    for (string, space) in [(title, gap), (tagline, 26), (sub, 0)] {
        let height = measuredHeight(string, width: textWidth)
        string.draw(
            with: CGRect(x: 400, y: top - height, width: textWidth, height: height),
            options: [.usesLineFragmentOrigin]
        )
        top -= height + CGFloat(space)
    }

    ctx.flush()
    NSGraphicsContext.restoreGraphicsState()
    save(downscaled(rep, toWidth: 1800), to: path)
}

// MARK: - Vertical banner

let verticalSize = CGSize(width: 1080, height: 1920)

func renderVertical(to path: String) {
    let (rep, ctx) = makeContext(width: verticalSize.width, height: verticalSize.height, scale: 1)
    let centerX = verticalSize.width / 2

    drawBackdrop(
        ctx,
        size: verticalSize,
        glow: CGPoint(x: verticalSize.width * 0.5, y: verticalSize.height * 0.78),
        glowRadius: 900
    )

    // Mark.
    let iconSide: CGFloat = 380
    let iconTop: CGFloat = 168
    if let icon = load("Resources/AppIcon-1024.png") {
        icon.draw(
            in: CGRect(
                x: centerX - iconSide / 2,
                y: verticalSize.height - iconTop - iconSide,
                width: iconSide,
                height: iconSide
            ),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
    }

    // Wordmark and promise, stacked from measured heights.
    var top = iconTop + iconSide + 84

    let title = centred(text("Kove", size: 148, weight: .bold, color: color(0xF7F7FA), kern: -2.6))
    let titleHeight = drawCentred(title, top: top, width: 940, canvasHeight: verticalSize.height, centerX: centerX)
    print("vertical: wordmark \(Int(top))..\(Int(top + titleHeight))")
    top += titleHeight + 26

    let tagline = centred(text("A Dynamic Island for macOS", size: 40, weight: .regular, color: color(0xFFFFFF, alpha: 0.66), kern: 0.4))
    let taglineHeight = drawCentred(tagline, top: top, width: 940, canvasHeight: verticalSize.height, centerX: centerX)
    print("vertical: tagline \(Int(top))..\(Int(top + taglineHeight))")
    top += taglineHeight

    // The product itself. The screenshot is drawn at 880 wide and outlined with the
    // island's own silhouette, because a black panel on a near-black slab needs an edge.
    if let island = load("docs/island-usage.png") {
        let artWidth: CGFloat = 880
        let artHeight = artWidth * (178.0 / 420.0)
        let artTop = top + 116
        let artRect = CGRect(
            x: centerX - artWidth / 2,
            y: verticalSize.height - artTop - artHeight,
            width: artWidth,
            height: artHeight
        )
        island.draw(in: artRect, from: .zero, operation: .sourceOver, fraction: 1)

        ctx.addPath(islandPath(in: artRect, bottomRadius: 26 * artWidth / 420))
        ctx.setStrokeColor(color(0xFFFFFF, alpha: 0.16).cgColor)
        ctx.setLineWidth(1.2)
        ctx.strokePath()
        print("vertical: island art \(Int(artTop))..\(Int(artTop + artHeight))")

        top = artTop + artHeight
    }

    // Claim and where to find it.
    let sub = centred(text("Apple Music and Command Code usage, fused to the notch.", size: 28, weight: .regular, color: color(0xFFFFFF, alpha: 0.42)))
    let subHeight = drawCentred(sub, top: top + 92, width: 900, canvasHeight: verticalSize.height, centerX: centerX)
    print("vertical: caption \(Int(top + 92))..\(Int(top + 92 + subHeight))")

    let sources = centred(text("Apple Music  ·  Spotify  ·  Command Code", size: 24, weight: .medium, color: color(0xFFFFFF, alpha: 0.30), kern: 0.6))
    drawCentred(sources, top: top + 92 + subHeight + 22, width: 900, canvasHeight: verticalSize.height, centerX: centerX)

    let footer = centred(text("github.com/ValenscoA/Kove", size: 22, weight: .regular, color: color(0xFFFFFF, alpha: 0.28), kern: 0.2))
    let footerHeight = measuredHeight(footer, width: 900)
    drawCentred(footer, top: verticalSize.height - 96 - footerHeight, width: 900, canvasHeight: verticalSize.height, centerX: centerX)

    ctx.flush()
    NSGraphicsContext.restoreGraphicsState()
    save(rep, to: path)
}

// MARK: - Main

let arguments = CommandLine.arguments.dropFirst()

if arguments.contains("--vertical") {
    let path = arguments.first { $0.hasSuffix(".png") } ?? docsDirectory.appendingPathComponent("banner-vertical.png").path
    renderVertical(to: path)
} else {
    let path = arguments.first { $0.hasSuffix(".png") } ?? docsDirectory.appendingPathComponent("banner.png").path
    renderHorizontal(to: path)
}
