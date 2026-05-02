#!/usr/bin/env swift
// Generates a small PDF of the Nepal flag pennant silhouette for use as the
// IME's menu-bar icon. Run from the repo root:
//   swift scripts/make_icon.swift BundleResources/MenuIcon.pdf
//
// The flag silhouette is a stylised two-triangle pennant, crimson fill with
// a deep-blue border. Not to spec geometry — it's an icon at 16-22pt, not a
// faithful flag rendering.

import Foundation
import AppKit

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: make_icon.swift OUTPUT_PATH\n".utf8))
    exit(1)
}
let outURL = URL(fileURLWithPath: CommandLine.arguments[1])

let size = NSSize(width: 18, height: 22)
let data = NSMutableData()
guard let consumer = CGDataConsumer(data: data) else { exit(1) }
var mediaBox = CGRect(origin: .zero, size: size)
guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { exit(1) }
ctx.beginPDFPage(nil)

let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
NSGraphicsContext.current = nsCtx

let W = size.width
let H = size.height
let inset: CGFloat = 1.0

// Pennant silhouette traced clockwise from bottom-left of the hoist.
let path = NSBezierPath()
path.move(to: NSPoint(x: inset, y: inset))                          // bottom-left
path.line(to: NSPoint(x: inset, y: H - inset))                      // hoist (left edge)
path.line(to: NSPoint(x: W * 0.85, y: H * 0.55))                    // upper peak (right)
path.line(to: NSPoint(x: W * 0.55, y: H * 0.45))                    // notch between pennants
path.line(to: NSPoint(x: W - inset, y: inset))                      // lower peak (right)
path.close()

// Crimson red fill (Nepal flag standard ~#DC143C-ish for legibility)
NSColor(red: 0.86, green: 0.08, blue: 0.24, alpha: 1.0).setFill()
path.fill()

// Deep blue stroke border
NSColor(red: 0.0, green: 0.22, blue: 0.58, alpha: 1.0).setStroke()
path.lineWidth = 1.4
path.lineJoinStyle = .round
path.stroke()

ctx.endPDFPage()
ctx.closePDF()

try data.write(to: outURL, options: .atomic)
print("Wrote \(outURL.path) (\(data.length) bytes)")
