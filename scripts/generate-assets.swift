import AppKit
import CoreGraphics
import ImageIO

// Fit the checked-in icon's blue tile to the canvas and generate sample documents.
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let refreshSamples = CommandLine.arguments.contains("--refresh-samples")
let refreshPDF = refreshSamples || CommandLine.arguments.contains("--refresh-pdf")
let iconset = root.appendingPathComponent("dist/AppIcon.iconset")
let iconSource = root.appendingPathComponent("Sources/Luma/Resources/Brand/AppIcon.png")
guard let iconImageSource = CGImageSourceCreateWithURL(iconSource as CFURL, nil),
      let sourceImage = CGImageSourceCreateImageAtIndex(iconImageSource, 0, nil) else {
    throw NSError(domain: "Assets", code: 4, userInfo: [
        NSLocalizedDescriptionKey: "Cannot load app icon: \(iconSource.path)"
    ])
}

// The master includes transparent exterior padding and faint edge artifacts.
// Use the opaque tile bounds, then crop a centered square at a uniform scale.
// Rounded transparent corners remain; no empty border surrounds the blue tile.
func fullBleedIcon(_ image: CGImage) throws -> CGImage {
    let width = image.width, height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    try pixels.withUnsafeMutableBytes { bytes in
        guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw NSError(domain: "Assets", code: 8)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    var left = width, top = height, right = 0, bottom = 0
    for y in 0..<height {
        for x in 0..<width where pixels[(y * width + x) * 4 + 3] >= 250 {
            left = min(left, x); top = min(top, y)
            right = max(right, x + 1); bottom = max(bottom, y + 1)
        }
    }
    let side = min(right - left, bottom - top)
    guard side > 0 else { throw NSError(domain: "Assets", code: 9) }
    let crop = CGRect(x: left + (right - left - side) / 2,
                      y: top + (bottom - top - side) / 2,
                      width: side, height: side)
    guard let cropped = image.cropping(to: crop) else { throw NSError(domain: "Assets", code: 10) }
    return cropped
}
let iconImage = try fullBleedIcon(sourceImage)
let appIcon = NSImage(cgImage: iconImage, size: NSSize(width: iconImage.width, height: iconImage.height))
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
    let blue = NSColor(srgbRed: 58 / 255, green: 96 / 255, blue: 149 / 255, alpha: 1)
    NSColor(srgbRed: 252 / 255, green: 252 / 255, blue: 250 / 255, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    blue.withAlphaComponent(0.10).setFill()
    NSBezierPath(ovalIn: NSRect(x: width * 0.55, y: height * 0.3, width: width * 0.5, height: width * 0.5)).fill()
    blue.withAlphaComponent(0.24).setFill()
    NSBezierPath(roundedRect: NSRect(x: width * 0.68, y: height * 0.15, width: width * 0.17, height: height * 0.62), xRadius: width * 0.085, yRadius: width * 0.085).fill()
    text("LUMA  /  A LOCAL READING SPACE", x: width * 0.08, y: height * 0.85, size: width * 0.014, color: blue, weight: .medium)
    text("Less noise.", x: width * 0.08, y: height * 0.54, size: width * 0.068, color: blue, weight: .medium)
    text("More clarity.", x: width * 0.08, y: height * 0.41, size: width * 0.068, color: blue, weight: .medium)
    text(subtitle, x: width * 0.08, y: height * 0.16, size: width * 0.018, color: blue)
    text("01 / MADE FOR YOUR FILES", x: width * 0.08, y: height * 0.08, size: width * 0.012, color: blue.withAlphaComponent(0.75))
}

let pngURL = samples.appendingPathComponent("留白.png")
if refreshSamples || !FileManager.default.fileExists(atPath: pngURL.path) {
    try bitmap(width: 1200, height: 800) { cover(width: 1200, height: 800, subtitle: "A little room for the things that matter.") }.write(to: pngURL)
}

let pdfURL = samples.appendingPathComponent("阅读空间.pdf")
if refreshPDF || !FileManager.default.fileExists(atPath: pdfURL.path) {
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
    let blue = NSColor(srgbRed: 58 / 255, green: 96 / 255, blue: 149 / 255, alpha: 1)
    let ink = NSColor(srgbRed: 26 / 255, green: 32 / 255, blue: 43 / 255, alpha: 1)
    NSColor(srgbRed: 252 / 255, green: 252 / 255, blue: 250 / 255, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: 600, height: 800).fill()
    text("A space to read.", x: 48, y: 680, size: 34, color: blue, weight: .semibold)
    text("Documents, data and code - all in one window.", x: 48, y: 620, size: 16, color: ink)
    text("Try searching for clarity with Command-F.", x: 48, y: 580, size: 16, color: ink)
    text("Keep your place. Return to the same paragraph.", x: 48, y: 540, size: 16, color: ink)
    text("READ", x: 48, y: 438, size: 12, color: blue, weight: .semibold)
    text("Markdown, PDF, SVG and images.", x: 48, y: 404, size: 19, color: ink)
    text("EXPLORE", x: 48, y: 330, size: 12, color: blue, weight: .semibold)
    text("JSON, JSONC, JSON Lines, CSV and TSV.", x: 48, y: 296, size: 19, color: ink)
    text("EDIT", x: 48, y: 222, size: 12, color: blue, weight: .semibold)
    text("Preview your draft, then save when ready.", x: 48, y: 188, size: 19, color: ink)
    text("02 / LUMA / BLUE EDITION 2026.11.2", x: 48, y: 48, size: 10, color: blue)
    NSGraphicsContext.restoreGraphicsState()
    context.endPDFPage()
    context.closePDF()
}

let imageExamples = samples.appendingPathComponent("图片格式", isDirectory: true)
try FileManager.default.createDirectory(at: imageExamples, withIntermediateDirectories: true)
let preview = try bitmap(width: 800, height: 534) {
    cover(width: 800, height: 534, subtitle: "A little room for the things that matter.")
}
guard let source = CGImageSourceCreateWithData(preview as CFData, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw NSError(domain: "Assets", code: 5) }
for (ext, type) in [("jpg", "public.jpeg"), ("gif", "com.compuserve.gif"), ("heic", "public.heic"),
                    ("tiff", "public.tiff"), ("bmp", "com.microsoft.bmp")] {
    let url = imageExamples.appendingPathComponent("阅读封面." + ext)
    guard refreshSamples || !FileManager.default.fileExists(atPath: url.path) else { continue }
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil) else {
        throw NSError(domain: "Assets", code: 6, userInfo: [NSLocalizedDescriptionKey: "Cannot encode \(ext)"])
    }
    CGImageDestinationAddImage(destination, image, [
        kCGImageDestinationLossyCompressionQuality: 0.9,
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 5]
    ] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "Assets", code: 7) }
}
let sampleIcon = imageExamples.appendingPathComponent("澄览图标.icns")
if (try? Data(contentsOf: sampleIcon)) != icon {
    try icon.write(to: sampleIcon)
}
