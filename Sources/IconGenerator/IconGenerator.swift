import AppKit

@main
struct IconGenerator {
    static func main() throws {
        let outputPath = CommandLine.arguments.dropFirst().first ?? "MediaCompressor.iconset"
        let icnsPath = CommandLine.arguments.dropFirst(2).first
        let outputURL = URL(fileURLWithPath: outputPath)
        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

        let iconSizes: [(String, CGFloat, CGFloat)] = [
            ("icon_16x16.png", 16, 1),
            ("icon_16x16@2x.png", 16, 2),
            ("icon_32x32.png", 32, 1),
            ("icon_32x32@2x.png", 32, 2),
            ("icon_128x128.png", 128, 1),
            ("icon_128x128@2x.png", 128, 2),
            ("icon_256x256.png", 256, 1),
            ("icon_256x256@2x.png", 256, 2),
            ("icon_512x512.png", 512, 1),
            ("icon_512x512@2x.png", 512, 2)
        ]

        for iconSize in iconSizes {
            try renderIcon(named: iconSize.0, pointSize: iconSize.1, scale: iconSize.2, into: outputURL)
        }

        if let icnsPath {
            try writeICNS(from: outputURL, to: URL(fileURLWithPath: icnsPath))
        }
    }

    private static func renderIcon(named name: String, pointSize: CGFloat, scale: CGFloat, into folder: URL) throws {
        let pixels = Int(pointSize * scale)
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
            throw NSError(domain: "IconGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create bitmap for \(name)"])
        }

        bitmap.size = NSSize(width: CGFloat(pixels), height: CGFloat(pixels))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

        let bounds = NSRect(x: 0, y: 0, width: pixels, height: pixels)
        NSColor.clear.setFill()
        bounds.fill()

        let inset = CGFloat(pixels) * 0.04
        let cornerRadius = CGFloat(pixels) * 0.22
        let background = NSBezierPath(roundedRect: bounds.insetBy(dx: inset, dy: inset), xRadius: cornerRadius, yRadius: cornerRadius)
        NSGradient(colors: [NSColor.systemPurple, NSColor.systemPink])?.draw(in: background, angle: 225)

        if let symbol = NSImage(systemSymbolName: "arrow.down.and.line.horizontal.and.arrow.up", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 200, weight: .semibold)
            let configured = symbol.withSymbolConfiguration(config) ?? symbol
            let nativeSize = configured.size
            let targetSide = CGFloat(pixels) * 0.56
            let scale = min(targetSide / nativeSize.width, targetSide / nativeSize.height)
            let drawSize = NSSize(width: nativeSize.width * scale, height: nativeSize.height * scale)
            let symbolRect = NSRect(
                x: (CGFloat(pixels) - drawSize.width) / 2,
                y: (CGFloat(pixels) - drawSize.height) / 2,
                width: drawSize.width,
                height: drawSize.height
            )

            var proposedRect = NSRect(origin: .zero, size: nativeSize)
            let renderWidth = Int(drawSize.width.rounded())
            let renderHeight = Int(drawSize.height.rounded())
            if renderWidth > 0, renderHeight > 0,
               let cgImage = configured.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil),
               let offscreen = CGContext(
                   data: nil,
                   width: renderWidth,
                   height: renderHeight,
                   bitsPerComponent: 8,
                   bytesPerRow: 0,
                   space: CGColorSpaceCreateDeviceRGB(),
                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
               ) {
                let drawRect = CGRect(x: 0, y: 0, width: renderWidth, height: renderHeight)
                offscreen.draw(cgImage, in: drawRect)
                offscreen.setBlendMode(.sourceAtop)
                offscreen.setFillColor(NSColor.white.cgColor)
                offscreen.fill(drawRect)

                if let tintedImage = offscreen.makeImage(), let cgContext = NSGraphicsContext.current?.cgContext {
                    cgContext.draw(tintedImage, in: symbolRect)
                }
            }
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "IconGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not render \(name)"])
        }

        try png.write(to: folder.appendingPathComponent(name))
    }

    private static func writeICNS(from iconset: URL, to destination: URL) throws {
        let entries: [(String, String)] = [
            ("icp4", "icon_16x16.png"),
            ("icp5", "icon_32x32.png"),
            ("icp6", "icon_32x32@2x.png"),
            ("ic07", "icon_128x128.png"),
            ("ic08", "icon_256x256.png"),
            ("ic09", "icon_512x512.png"),
            ("ic10", "icon_512x512@2x.png")
        ]

        var body = Data()
        for entry in entries {
            let png = try Data(contentsOf: iconset.appendingPathComponent(entry.1))
            body.append(entry.0.data(using: .macOSRoman)!)
            body.appendUInt32(UInt32(png.count + 8))
            body.append(png)
        }

        var icns = Data()
        icns.append("icns".data(using: .macOSRoman)!)
        icns.appendUInt32(UInt32(body.count + 8))
        icns.append(body)
        try icns.write(to: destination)
    }
}

private extension Data {
    mutating func appendUInt32(_ value: UInt32) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { bytes in
            append(contentsOf: bytes)
        }
    }
}
