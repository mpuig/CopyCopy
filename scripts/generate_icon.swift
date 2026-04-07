#!/usr/bin/env swift
import Cocoa

let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))

image.lockFocus()

let context = NSGraphicsContext.current!.cgContext

// Background: rounded rectangle with gradient
let rect = CGRect(x: 0, y: 0, width: size, height: size)
let cornerRadius: CGFloat = CGFloat(size) * 0.22
let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

// Gradient from deep blue to indigo
let colorSpace = CGColorSpaceCreateDeviceRGB()
let colors = [
    CGColor(red: 0.25, green: 0.35, blue: 0.95, alpha: 1.0),
    CGColor(red: 0.45, green: 0.25, blue: 0.85, alpha: 1.0),
] as CFArray
let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0])!

context.saveGState()
context.addPath(path)
context.clip()
context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(size)), end: CGPoint(x: CGFloat(size), y: 0), options: [])
context.restoreGState()

// Draw "CC" text
let fontSize: CGFloat = CGFloat(size) * 0.46
let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
let attributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white,
]
let text = "CC" as NSString
let textSize = text.size(withAttributes: attributes)
let textX = (CGFloat(size) - textSize.width) / 2.0
let textY = (CGFloat(size) - textSize.height) / 2.0
text.draw(at: NSPoint(x: textX, y: textY), withAttributes: attributes)

image.unlockFocus()

// Save as PNG
guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    print("Failed to create PNG")
    exit(1)
}

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let outputPath = "\(outputDir)/icon_1024x1024.png"
try! pngData.write(to: URL(fileURLWithPath: outputPath))
print("Created \(outputPath)")
