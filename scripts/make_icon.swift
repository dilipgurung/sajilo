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
let paletteOut = root.appendingPathComponent("BundleResources/PaletteIcon.pdf")

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

// MARK: - Menu icon: small Nepal-flag pennant silhouette
try writePDF(at: menuOut, size: NSSize(width: 16, height: 16)) { _, _ in
    let W: CGFloat = 16
    let H: CGFloat = 16
    let inset: CGFloat = 1.0
    let topPad: CGFloat = 2.0   // empty space above flag
    let botPad: CGFloat = 2.0   // empty space below flag
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

// MARK: - Palette icon: "ने" character, square, template-friendly
try writePDF(at: paletteOut, size: NSSize(width: 32, height: 32)) { _, _ in
    let canvas = NSRect(x: 0, y: 0, width: 32, height: 32)

    let para = NSMutableParagraphStyle()
    para.alignment = .center

    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
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
        y: canvas.midY - bounds.height / 2 - 1,
        width: bounds.width,
        height: bounds.height
    )
    str.draw(in: drawRect)
}
