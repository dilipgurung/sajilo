#!/usr/bin/env swift
// Generates the menu-bar and palette icons for NepaliIME.
//
//   swift scripts/make_icon.swift
//
// Outputs:
//   BundleResources/MenuIcon.pdf      16x16  Nepal flag silhouette (colored)
//   BundleResources/PaletteIcon.pdf   32x32  "ने" character (template, monochrome)
//
// MenuIcon is the small status-bar glyph; PaletteIcon shows in the Ctrl+Space
// input-source switcher and elsewhere where a square text-style glyph reads
// better than a flag silhouette.

import Foundation
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let menuOut = root.appendingPathComponent("BundleResources/MenuIcon.pdf")
let paletteOut = root.appendingPathComponent("BundleResources/PaletteIcon.icns")

func writePDF(at url: URL, size: NSSize, draw: (NSGraphicsContext, CGContext) -> Void) throws {
    let data = NSMutableData()
    guard let consumer = CGDataConsumer(data: data) else {
        throw NSError(domain: "make_icon", code: 1)
    }
    var mediaBox = CGRect(origin: .zero, size: size)
    guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        throw NSError(domain: "make_icon", code: 2)
    }
    ctx.beginPDFPage(nil)
    let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
    let prev = NSGraphicsContext.current
    NSGraphicsContext.current = nsCtx
    draw(nsCtx, ctx)
    NSGraphicsContext.current = prev
    ctx.endPDFPage()
    ctx.closePDF()
    try data.write(to: url, options: .atomic)
    print("Wrote \(url.path) (\(data.length) bytes)")
}

// MARK: - Menu icon: small colored Nepal flag pennant.
// TISIconIsTemplate=false in Info.plist so the red/blue colors render as drawn.
try writePDF(at: menuOut, size: NSSize(width: 16, height: 16)) { _, _ in
    let W: CGFloat = 16
    let H: CGFloat = 16
    let inset: CGFloat = 1.0
    let topPad: CGFloat = 2.0
    let botPad: CGFloat = 2.0
    let top = H - topPad
    let bot = botPad

    let path = NSBezierPath()
    path.move(to: NSPoint(x: inset, y: bot))
    path.line(to: NSPoint(x: inset, y: top))
    path.line(to: NSPoint(x: W * 0.78, y: bot + (top - bot) * 0.55))   // upper peak
    path.line(to: NSPoint(x: W * 0.50, y: bot + (top - bot) * 0.45))   // notch
    path.line(to: NSPoint(x: W - inset, y: bot))                       // lower peak
    path.close()

    NSColor(red: 0.86, green: 0.08, blue: 0.24, alpha: 1.0).setFill()
    path.fill()

    NSColor(red: 0.0, green: 0.22, blue: 0.58, alpha: 1.0).setStroke()
    path.lineWidth = 1.0
    path.lineJoinStyle = .round
    path.stroke()
}

// MARK: - Palette icon: .icns (multi-resolution) — what the Ctrl+Space
// switcher reliably reads. Each size is rendered natively (not just scaled
// from a single source) so the character stays legible at small sizes.
//
// Note: at 16pt the conjunct "ने" is genuinely cramped — the consonant न
// plus the vowel sign े plus the dot above leave little pixel budget. The
// 32pt rep is what the switcher uses on retina displays.
do {
    func renderPNG(pixelSize: Int) throws -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize, pixelsHigh: pixelSize,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 32
        )!
        rep.size = NSSize(width: pixelSize, height: pixelSize)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        defer { NSGraphicsContext.restoreGraphicsState() }

        let canvas = NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)

        // Solid round badge so it survives macOS's circular masking in the switcher.
        let inset: CGFloat = max(1, CGFloat(pixelSize) * 0.04)
        let badgeRect = canvas.insetBy(dx: inset, dy: inset)
        let badge = NSBezierPath(ovalIn: badgeRect)
        NSColor(red: 0.0, green: 0.22, blue: 0.58, alpha: 1.0).setFill()
        badge.fill()

        // Character. Use the largest Devanagari font that still fits and is
        // legible at this pixel size.
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let fontSize = CGFloat(pixelSize) * 0.72
        let font = NSFont(name: "Kohinoor Devanagari", size: fontSize)
            ?? NSFont(name: "Devanagari MT", size: fontSize)
            ?? NSFont(name: "Devanagari Sangam MN", size: fontSize)
            ?? NSFont.systemFont(ofSize: fontSize, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .paragraphStyle: para,
        ]
        let str = NSAttributedString(string: "ने", attributes: attrs)
        let bounds = str.boundingRect(
            with: canvas.size,
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let drawRect = NSRect(
            x: canvas.midX - bounds.width / 2,
            y: canvas.midY - bounds.height / 2 - CGFloat(pixelSize) * 0.04,
            width: bounds.width,
            height: bounds.height
        )
        str.draw(in: drawRect)

        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "make_icon", code: 4)
        }
        return png
    }

    // Build an .iconset directory with the standard names iconutil expects.
    let iconsetDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("PaletteIcon-\(UUID().uuidString).iconset", isDirectory: true)
    try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: iconsetDir) }

    // Sizes recognised by iconutil. We supply small sizes since this is a UI
    // glyph, not an app icon.
    let renditions: [(name: String, pixels: Int)] = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
    ]
    for r in renditions {
        let png = try renderPNG(pixelSize: r.pixels)
        try png.write(to: iconsetDir.appendingPathComponent(r.name))
    }

    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    proc.arguments = ["-c", "icns", iconsetDir.path, "-o", paletteOut.path]
    let stderr = Pipe()
    proc.standardError = stderr
    try proc.run()
    proc.waitUntilExit()
    if proc.terminationStatus != 0 {
        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        FileHandle.standardError.write(Data("iconutil failed: \(err)\n".utf8))
        exit(Int32(proc.terminationStatus))
    }
    let attrs = try FileManager.default.attributesOfItem(atPath: paletteOut.path)
    let size = (attrs[.size] as? Int) ?? 0
    print("Wrote \(paletteOut.path) (\(size) bytes; reps: \(renditions.map(\.name).joined(separator: ", ")))")
}
