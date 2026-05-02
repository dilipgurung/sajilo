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
let menuOut = root.appendingPathComponent("BundleResources/MenuIcon.icns")
let paletteOut = root.appendingPathComponent("BundleResources/PaletteIconTemplate.icns")

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

// MARK: - Menu icon: solid-red Nepal flag pennant silhouette as .icns.
// Both the menu bar tray and the Ctrl+Space switcher use this. The switcher's
// TIS-based icon loader historically only reads .icns reliably, so we ship
// the menu icon as a multi-resolution icns rather than PDF.
do {
    func renderFlagPNG(pixelSize: Int) throws -> Data {
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

        let W = CGFloat(pixelSize)
        let H = CGFloat(pixelSize)
        let inset: CGFloat = max(1, W * 0.06)
        let topPad: CGFloat = max(1, H * 0.10)
        let botPad: CGFloat = max(1, H * 0.10)
        let top = H - topPad
        let bot = botPad

        let path = NSBezierPath()
        path.move(to: NSPoint(x: inset, y: bot))
        path.line(to: NSPoint(x: inset, y: top))
        path.line(to: NSPoint(x: W * 0.78, y: bot + (top - bot) * 0.55))
        path.line(to: NSPoint(x: W * 0.50, y: bot + (top - bot) * 0.45))
        path.line(to: NSPoint(x: W - inset, y: bot))
        path.close()

        NSColor(red: 0.86, green: 0.08, blue: 0.24, alpha: 1.0).setFill()
        path.fill()

        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "make_icon", code: 5)
        }
        return png
    }

    let iconsetDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("MenuIcon-\(UUID().uuidString).iconset", isDirectory: true)
    try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: iconsetDir) }

    let renditions: [(name: String, pixels: Int)] = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
    ]
    for r in renditions {
        let png = try renderFlagPNG(pixelSize: r.pixels)
        try png.write(to: iconsetDir.appendingPathComponent(r.name))
    }

    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    proc.arguments = ["-c", "icns", iconsetDir.path, "-o", menuOut.path]
    let stderr = Pipe()
    proc.standardError = stderr
    try proc.run()
    proc.waitUntilExit()
    if proc.terminationStatus != 0 {
        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        FileHandle.standardError.write(Data("iconutil failed: \(err)\n".utf8))
        exit(Int32(proc.terminationStatus))
    }
    let attrs = try FileManager.default.attributesOfItem(atPath: menuOut.path)
    let size = (attrs[.size] as? Int) ?? 0
    print("Wrote \(menuOut.path) (\(size) bytes)")
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

        // No badge — macOS's input-source switcher provides its own circular
        // backdrop. Filename ends in "Template", so AppKit treats the image
        // as a template (alpha-only mask) and tints to match context.
        // Drawn in BLACK so the file is also visible when previewed in
        // Finder/Preview against a white background — the source color is
        // ignored at runtime once template treatment kicks in.
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let fontSize = CGFloat(pixelSize) * 0.85
        let font = NSFont(name: "Kohinoor Devanagari", size: fontSize)
            ?? NSFont(name: "Devanagari MT", size: fontSize)
            ?? NSFont(name: "Devanagari Sangam MN", size: fontSize)
            ?? NSFont.systemFont(ofSize: fontSize, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
            .paragraphStyle: para,
        ]
        let str = NSAttributedString(string: "ने", attributes: attrs)
        let bounds = str.boundingRect(
            with: canvas.size,
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let drawRect = NSRect(
            x: canvas.midX - bounds.width / 2,
            y: canvas.midY - bounds.height / 2 - CGFloat(pixelSize) * 0.05,
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
