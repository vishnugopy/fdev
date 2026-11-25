import AppKit

/// The fdev mark: a bold rounded "f" followed by a text cursor — "fdev, typing code".
/// One drawing routine feeds the app icon, the header logo and the menu bar icon.
enum LogoArtwork {
    static let ink = NSColor(srgbRed: 0.07, green: 0.075, blue: 0.09, alpha: 1)
    static let accent = NSColor(srgbRed: 0.31, green: 0.55, blue: 1.0, alpha: 1)

    /// "f" glyph outline (rounded, black weight) at a reference size.
    private static let fPath: CGPath? = {
        let base = NSFont.systemFont(ofSize: 100, weight: .black)
        let font = NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: 100) ?? base
        var ch: UniChar = 0x66
        var glyph: CGGlyph = 0
        CTFontGetGlyphsForCharacters(font as CTFont, &ch, &glyph, 1)
        return CTFontCreatePathForGlyph(font as CTFont, glyph, nil)
    }()

    /// Draws the f + cursor centered in `rect`, with the glyph `height` tall.
    static func drawMark(in ctx: CGContext, rect: CGRect, height: CGFloat, f: CGColor, caret: CGColor) {
        guard let path = fPath else { return }
        let b = path.boundingBoxOfPath
        let k = height / b.height
        let fw = b.width * k
        let caretW = height * 0.14
        let gap = height * 0.08
        let caretH = height * 0.80
        let x0 = (rect.midX - (fw + gap + caretW) / 2).rounded()
        let y0 = (rect.midY - height / 2).rounded()

        var t = CGAffineTransform(translationX: x0, y: y0).scaledBy(x: k, y: k).translatedBy(x: -b.minX, y: -b.minY)
        if let moved = path.copy(using: &t) {
            ctx.addPath(moved); ctx.setFillColor(f); ctx.fillPath()
        }
        let r = CGRect(x: x0 + fw + gap, y: y0, width: caretW, height: caretH)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: caretW * 0.3, cornerHeight: caretW * 0.3, transform: nil))
        ctx.setFillColor(caret); ctx.fillPath()
    }

    /// Solid ink tile with a hairline rim and the mark.
    static func drawTile(in ctx: CGContext, rect: CGRect, radius: CGFloat) {
        let tile = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.addPath(tile); ctx.setFillColor(ink.cgColor); ctx.fillPath()
        // Rim keeps the tile visible on dark menus and Docks.
        let lw = max(1, rect.width / 200)
        let inset = rect.insetBy(dx: lw / 2, dy: lw / 2)
        ctx.addPath(CGPath(roundedRect: inset, cornerWidth: radius - lw / 2, cornerHeight: radius - lw / 2, transform: nil))
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.14).cgColor); ctx.setLineWidth(lw); ctx.strokePath()
        drawMark(in: ctx, rect: rect, height: rect.height * 0.46, f: NSColor.white.cgColor, caret: accent.cgColor)
    }

    /// Logo for the header.
    static func tileImage(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            drawTile(in: ctx, rect: r, radius: r.width * 0.26)
            return true
        }
    }

    /// Monochrome template for the menu bar (macOS tints it for light/dark/highlight).
    static let menuBarImage: NSImage = {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { r in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            drawMark(in: ctx, rect: r, height: 14, f: NSColor.black.cgColor, caret: NSColor.black.cgColor)
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "fdev"
        return img
    }()

    /// 1024×1024 app icon on the macOS icon grid (824pt body, ~185pt radius) with real elevation.
    static func renderAppIcon(to url: URL) throws {
        let S = 1024
        guard let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        let body = CGRect(x: 100, y: 100, width: 824, height: 824)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.28).cgColor)
        ctx.addPath(CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil))
        ctx.setFillColor(ink.cgColor); ctx.fillPath()
        ctx.restoreGState()
        drawTile(in: ctx, rect: body, radius: 185)
        guard let cg = ctx.makeImage(),
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return }
        try png.write(to: url)
    }
}
