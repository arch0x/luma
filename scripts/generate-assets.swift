import AppKit
import CoreGraphics

// Resize the checked-in app icon and generate native sample documents.
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = root.appendingPathComponent("dist/AppIcon.iconset")
let iconSource = root.appendingPathComponent("Sources/Luma/Resources/Brand/AppIcon.png")
guard let appIcon = NSImage(contentsOf: iconSource) else {
    throw NSError(domain: "Assets", code: 4, userInfo: [
        NSLocalizedDescriptionKey: "Cannot load app icon: \(iconSource.path)"
    ])
}
let samples = root.appendingPathComponent("Sources/Luma/Resources/Samples")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func bitmap(width: Int, height: Int, draw: () -> Void) throws -> Data {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "Assets", code: 1)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    draw()
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "Assets", code: 2) }
    return data
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = points * scale
        let s = CGFloat(size)
        let png = try bitmap(width: size, height: size) {
            NSGraphicsContext.current?.imageInterpolation = .high
            appIcon.draw(in: NSRect(x: 0, y: 0, width: s, height: s),
                         from: .zero, operation: .copy, fraction: 1)
        }
        try png.write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"))
    }
}

// An ICNS container with PNG representations; avoids an iconutil dependency.
func uint32(_ value: Int) -> Data {
    Data([UInt8((value >> 24) & 255), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)])
}
var iconBody = Data()
for (type, name) in [("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"), ("icp6", "icon_32x32@2x.png"), ("ic07", "icon_128x128.png"), ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"), ("ic10", "icon_512x512@2x.png")] {
    let data = try Data(contentsOf: iconset.appendingPathComponent(name))
    iconBody.append(Data(type.utf8))
    iconBody.append(uint32(data.count + 8))
    iconBody.append(data)
}
var icon = Data("icns".utf8)
icon.append(uint32(iconBody.count + 8))
icon.append(iconBody)
try icon.write(to: root.appendingPathComponent("dist/AppIcon.icns"))

func text(_ string: String, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) {
    NSAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]).draw(at: NSPoint(x: x, y: y))
}

func cover(width: CGFloat, height: CGFloat, subtitle: String) {
    let green = NSColor(calibratedRed: 0.20, green: 0.43, blue: 0.36, alpha: 1)
    NSColor(calibratedRed: 0.96, green: 0.95, blue: 0.92, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    green.withAlphaComponent(0.12).setFill()
    NSBezierPath(ovalIn: NSRect(x: width * 0.55, y: height * 0.3, width: width * 0.5, height: width * 0.5)).fill()
    green.withAlphaComponent(0.28).setFill()
    NSBezierPath(roundedRect: NSRect(x: width * 0.68, y: height * 0.15, width: width * 0.17, height: height * 0.62), xRadius: width * 0.085, yRadius: width * 0.085).fill()
    text("LUMA  /  A LOCAL READING SPACE", x: width * 0.08, y: height * 0.85, size: width * 0.014, color: green, weight: .medium)
    text("Less noise.", x: width * 0.08, y: height * 0.54, size: width * 0.068, color: green, weight: .medium)
    text("More clarity.", x: width * 0.08, y: height * 0.41, size: width * 0.068, color: green, weight: .medium)
    text(subtitle, x: width * 0.08, y: height * 0.16, size: width * 0.018, color: green)
    text("01 — MADE FOR YOUR FILES", x: width * 0.08, y: height * 0.08, size: width * 0.012, color: green.withAlphaComponent(0.6))
}

let pngURL = samples.appendingPathComponent("留白.png")
if !FileManager.default.fileExists(atPath: pngURL.path) {
    try bitmap(width: 1200, height: 800) { cover(width: 1200, height: 800, subtitle: "A little room for the things that matter.") }.write(to: pngURL)
}

let pdfURL = samples.appendingPathComponent("阅读空间.pdf")
if !FileManager.default.fileExists(atPath: pdfURL.path) {
    var page = CGRect(x: 0, y: 0, width: 600, height: 800)
    guard let context = CGContext(pdfURL as CFURL, mediaBox: &page, nil) else { throw NSError(domain: "Assets", code: 3) }
    context.beginPDFPage(nil)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    cover(width: 600, height: 800, subtitle: "A quiet workspace, one file at a time.")
    NSGraphicsContext.restoreGraphicsState()
    context.endPDFPage()
    context.beginPDFPage(nil)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 600, height: 800).fill()
    text("A space to read.", x: 48, y: 680, size: 34, color: .darkGray, weight: .semibold)
    text("Documents, data and code — all in one window.", x: 48, y: 620, size: 16, color: .darkGray)
    text("Try searching for clarity with Command-F.", x: 48, y: 580, size: 16, color: .darkGray)
    text("Luma keeps your original files untouched.", x: 48, y: 540, size: 16, color: .darkGray)
    text("02 / LUMA", x: 48, y: 48, size: 10, color: .gray)
    NSGraphicsContext.restoreGraphicsState()
    context.endPDFPage()
    context.closePDF()
}
