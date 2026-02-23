#!/usr/bin/env swift
// Generates AppIcon.iconset PNG files for ClaudeUsage.
// Run from the project root: swift Scripts/make-icon.swift

import Foundation
import CoreGraphics
import ImageIO

func makeIcon(size: Int) -> CGImage {
    let s = CGFloat(size)
    guard let ctx = CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("Cannot create CGContext") }

    // Orange rounded-rect background
    let bg = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(),
                     components: [0.72, 0.45, 0.20, 1.0])!
    ctx.setFillColor(bg)
    let r = s * 0.22
    ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                       cornerWidth: r, cornerHeight: r, transform: nil))
    ctx.fillPath()

    // White cat silhouette (y=0 at bottom in CGContext)
    let white = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(),
                        components: [1, 1, 1, 1])!
    ctx.setFillColor(white)
    let cat = CGMutablePath()
    // Left ear
    cat.move(to:    CGPoint(x: s*0.14, y: s*0.72))
    cat.addLine(to: CGPoint(x: s*0.22, y: s*0.93))
    cat.addLine(to: CGPoint(x: s*0.40, y: s*0.72))
    cat.closeSubpath()
    // Right ear
    cat.move(to:    CGPoint(x: s*0.60, y: s*0.72))
    cat.addLine(to: CGPoint(x: s*0.78, y: s*0.93))
    cat.addLine(to: CGPoint(x: s*0.86, y: s*0.72))
    cat.closeSubpath()
    // Head
    cat.addEllipse(in: CGRect(x: s*0.13, y: s*0.10, width: s*0.74, height: s*0.65))
    ctx.addPath(cat)
    ctx.fillPath(using: .winding)

    // Eyes (orange, matching background)
    ctx.setFillColor(bg)
    let ew = s * 0.09, eh = s * 0.12, ey = s * 0.44
    ctx.fillEllipse(in: CGRect(x: s*0.28, y: ey, width: ew, height: eh))
    ctx.fillEllipse(in: CGRect(x: s*0.63, y: ey, width: ew, height: eh))

    return ctx.makeImage()!
}

func scale(_ src: CGImage, to size: Int) -> CGImage {
    guard let ctx = CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("scale: cannot create context") }
    ctx.interpolationQuality = .high
    ctx.draw(src, in: CGRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size)))
    return ctx.makeImage()!
}

func save(_ img: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let dst = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil) else {
        print("ERROR: cannot write \(path)"); return
    }
    CGImageDestinationAddImage(dst, img, nil)
    CGImageDestinationFinalize(dst)
}

let outDir = "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let base = makeIcon(size: 1024)

let specs: [(String, Int)] = [
    ("icon_16x16.png",       16),
    ("icon_16x16@2x.png",    32),
    ("icon_32x32.png",       32),
    ("icon_32x32@2x.png",    64),
    ("icon_128x128.png",    128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png",    256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png",    512),
    ("icon_512x512@2x.png",1024),
]

for (name, px) in specs {
    let img = px == 1024 ? base : scale(base, to: px)
    save(img, to: "\(outDir)/\(name)")
    print("  \(name)")
}
print("✅ AppIcon.iconset ready")
