import AppKit

public enum IconMaker {
    public static func color(hex: String) -> NSColor {
        var value: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
        return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    static func bitmap(size: Int, draw: (CGFloat) -> Void) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: size, height: size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(CGFloat(size))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    static func writeICNS(to destination: URL, draw: @escaping (CGFloat) -> Void) throws {
        let fm = FileManager.default
        let iconset = fm.temporaryDirectory.appendingPathComponent("clonebox-\(UUID().uuidString).iconset")
        try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: iconset) }
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let rep = bitmap(size: base * scale, draw: draw)
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                try rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
            }
        }
        try sh("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", destination.path])
    }

    /// The original app icon with a coloured badge carrying the profile's first letter.
    public static func writeBadgedIcon(forApp app: URL, letter: String, colorHex: String, to destination: URL) throws {
        let icon = NSWorkspace.shared.icon(forFile: app.path)
        let badgeColor = color(hex: colorHex)
        try writeICNS(to: destination) { size in
            icon.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .sourceOver, fraction: 1)
            let d = size * 0.44
            let rect = NSRect(x: size - d - size * 0.04, y: size * 0.04, width: d, height: d)
            NSColor.white.setFill()
            NSBezierPath(ovalIn: rect).fill()
            badgeColor.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: d * 0.07, dy: d * 0.07)).fill()
            let text = NSAttributedString(string: letter, attributes: [
                .font: NSFont.systemFont(ofSize: d * 0.56, weight: .bold),
                .foregroundColor: NSColor.white,
            ])
            let textSize = text.size()
            text.draw(at: NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2))
        }
    }

    /// CloneBox's own icon: two overlapping rounded squares.
    public static func writeAppIcon(to destination: URL) throws {
        try writeICNS(to: destination) { size in
            let plate = NSBezierPath(roundedRect: NSRect(x: size * 0.1, y: size * 0.1, width: size * 0.8, height: size * 0.8),
                                     xRadius: size * 0.18, yRadius: size * 0.18)
            NSGradient(starting: color(hex: "7C5CFF"), ending: color(hex: "3B2A9E"))!.draw(in: plate, angle: -90)
            let s = size * 0.36
            NSColor.white.withAlphaComponent(0.45).setFill()
            NSBezierPath(roundedRect: NSRect(x: size * 0.24, y: size * 0.40, width: s, height: s), xRadius: s * 0.22, yRadius: s * 0.22).fill()
            NSColor.white.setFill()
            NSBezierPath(roundedRect: NSRect(x: size * 0.40, y: size * 0.24, width: s, height: s), xRadius: s * 0.22, yRadius: s * 0.22).fill()
        }
    }
}
