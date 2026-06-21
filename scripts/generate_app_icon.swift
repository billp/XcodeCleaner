#!/usr/bin/env swift
//
// scripts/generate_app_icon.swift
//
// Renders the XcodeCleaner app icon (sparkles SF Symbol on a graphite squircle)
// to XcodeCleaner/Assets.xcassets/AppIcon.appiconset/icon_1024.png.
//
// Re-run any time the icon design needs tweaking:
//   swift scripts/generate_app_icon.swift
//
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let cornerRadius = size * 0.2237  // macOS squircle corner radius

// Resolve the repo root from the script's own location.
let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let repoRoot = scriptDir.deletingLastPathComponent()
let icnsURL = repoRoot
    .appendingPathComponent("XcodeCleaner/Support/AppIcon.icns")

// Create a bitmap context.
guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let ctx = CGContext(
        data: nil,
        width: Int(size),
        height: Int(size),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ) else {
    FileHandle.standardError.write("Failed to create bitmap context\n".data(using: .utf8)!)
    exit(1)
}

// Draw the squircle background: a rounded rect filled with a vertical gradient.
let squircleRect = CGRect(x: 0, y: 0, width: size, height: size)
let squirclePath = CGPath(roundedRect: squircleRect,
                          cornerWidth: cornerRadius,
                          cornerHeight: cornerRadius,
                          transform: nil)
ctx.addPath(squirclePath)
ctx.clip()

let gradientColors = [
    CGColor(red: 0.227, green: 0.227, blue: 0.235, alpha: 1.0),  // #3A3A3C top
    CGColor(red: 0.110, green: 0.110, blue: 0.118, alpha: 1.0),  // #1C1C1E bottom
] as CFArray
guard let gradient = CGGradient(colorsSpace: colorSpace,
                                colors: gradientColors,
                                locations: [0.0, 1.0]) else {
    FileHandle.standardError.write("Failed to create gradient\n".data(using: .utf8)!)
    exit(1)
}
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: 0, y: size),
                       end: CGPoint(x: 0, y: 0),
                       options: [])

// Draw the SF Symbol "sparkles" centered, in gold (#FFD60A), at ~62% of the squircle.
let symbolSize = size * 0.62

// NSImage(systemSymbolName:) gives us the SF Symbol; we configure its size and tint.
guard let baseSymbol = NSImage(systemSymbolName: "sparkles",
                               accessibilityDescription: "Sparkles") else {
    FileHandle.standardError.write("Failed to load 'sparkles' SF Symbol\n".data(using: .utf8)!)
    exit(1)
}

let symbolConfig = NSImage.SymbolConfiguration(pointSize: symbolSize * 0.7,
                                                weight: .regular)
let symbolImage = baseSymbol.withSymbolConfiguration(symbolConfig)!
let tinted = NSImage(size: symbolImage.size)
tinted.lockFocus()
symbolImage.draw(in: NSRect(origin: .zero, size: symbolImage.size))
NSColor(red: 1.0, green: 0.839, blue: 0.039, alpha: 1.0).setFill()  // #FFD60A
NSRect(origin: .zero, size: symbolImage.size).fill(using: .sourceAtop)
tinted.unlockFocus()

// Draw the tinted symbol centered in the squircle.
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
tinted.draw(in: NSRect(
    x: (size - symbolImage.size.width) / 2,
    y: (size - symbolImage.size.height) / 2,
    width: symbolImage.size.width,
    height: symbolImage.size.height
), from: .zero, operation: .sourceOver, fraction: 1.0)
NSGraphicsContext.current = nil

// Extract the CGImage and write to PNG.
guard let cgImage = ctx.makeImage() else {
    FileHandle.standardError.write("Failed to make image from context\n".data(using: .utf8)!)
    exit(1)
}
let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("Failed to encode PNG\n".data(using: .utf8)!)
    exit(1)
}

// Write the 1024×1024 PNG to a temp .iconset folder, then generate all
// required sizes and convert to .icns via `iconutil`.
let iconsetDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconsetDir)
try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let sizes: [(Int, String)] = [
    (16, "16x16"), (32, "16x16@2x"),
    (32, "32x32"), (64, "32x32@2x"),
    (128, "128x128"), (256, "128x128@2x"),
    (256, "256x256"), (512, "256x256@2x"),
    (512, "512x512"), (1024, "512x512@2x"),
]
for (px, name) in sizes {
    let resized = NSImage(size: NSSize(width: px, height: px))
    resized.lockFocus()
    NSImage(cgImage: cgImage, size: NSSize(width: px, height: px))
        .draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    resized.unlockFocus()
    if let tiff = resized.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try png.write(to: iconsetDir.appendingPathComponent("icon_\(name).png"))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsURL.path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconsetDir)

if iconutil.terminationStatus == 0 {
    print("✓ Wrote .icns to \(icnsURL.path)")
} else {
    FileHandle.standardError.write("iconutil failed with status \(iconutil.terminationStatus)\n".data(using: .utf8)!)
    exit(1)
}
