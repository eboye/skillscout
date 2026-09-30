#!/usr/bin/env swift
// Renders the Skillscout app icon into Skillscout/AppIcon.icon, an Icon Composer bundle.
// Layers are flat 1024pt PNGs: macOS adds the Liquid Glass, and Xcode derives the
// icons for older macOS releases from the same bundle.
// Usage: swift scripts/render-icon.swift

import AppKit
import ImageIO
import UniformTypeIdentifiers

let canvas: CGFloat = 1024
// Three skill cards, one per tool, fanned from the top left.
let cardSize = CGSize(width: 420, height: 290)
let cardRadius: CGFloat = 62
let cardOrigins = [CGPoint(x: 150, y: 168), CGPoint(x: 222, y: 250), CGPoint(x: 294, y: 332)]
let lensCenter = CGPoint(x: 628, y: 596)
let lensRadius: CGFloat = 152
let lensThickness: CGFloat = 48
let handleEnd = CGPoint(x: 858, y: 826)
let handleWidth: CGFloat = 74
let sparkleRadius: CGFloat = 86

let backgroundTop: UInt32 = 0x191C33
let backgroundBottom: UInt32 = 0x30356B
let darkBackgroundTop: UInt32 = 0x0B0C18
let darkBackgroundBottom: UInt32 = 0x1C1F42
let codexColor: UInt32 = 0x34C7C0
let claudeColor: UInt32 = 0xFF9A3D
let cursorColor: UInt32 = 0x8C88FF
let lensColor: UInt32 = 0xFFFFFF
let sparkleColor: UInt32 = 0xFFD54F

func rgb(_ hex: UInt32) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
  (CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255)
}

func cgColor(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
  let color = rgb(hex)
  return CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: alpha)
}

func iconColor(_ hex: UInt32) -> String {
  let color = rgb(hex)
  return "\"extended-srgb:" + [color.red, color.green, color.blue, 1].map { String(format: "%.5f", $0) }.joined(separator: ",") + "\""
}

func layer(_ draw: (CGContext) -> Void) -> CGImage {
  let context = CGContext(
    data: nil,
    width: Int(canvas),
    height: Int(canvas),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )!
  context.translateBy(x: 0, y: canvas)
  context.scaleBy(x: 1, y: -1)
  draw(context)
  return context.makeImage()!
}

func card(_ index: Int, color: UInt32) -> CGImage {
  layer { context in
    context.setFillColor(cgColor(color))
    context.addPath(CGPath(roundedRect: CGRect(origin: cardOrigins[index], size: cardSize), cornerWidth: cardRadius, cornerHeight: cardRadius, transform: nil))
    context.fillPath()
  }
}

// Two lines of "text" on the front card, clear of the lens.
let lines = layer { context in
  context.setFillColor(cgColor(0xFFFFFF))
  let origin = cardOrigins[2]
  for (offset, width) in [(CGFloat(56), CGFloat(170)), (106, 112)] {
    let rect = CGRect(x: origin.x + 46, y: origin.y + offset, width: width, height: 28)
    context.addPath(CGPath(roundedRect: rect, cornerWidth: 14, cornerHeight: 14, transform: nil))
  }
  context.fillPath()
}

let lens = layer { context in
  context.setStrokeColor(cgColor(lensColor))
  context.setLineWidth(lensThickness)
  context.strokeEllipse(in: CGRect(x: lensCenter.x - lensRadius, y: lensCenter.y - lensRadius, width: 2 * lensRadius, height: 2 * lensRadius))

  let rim = lensRadius + lensThickness / 2 - 6
  context.setLineWidth(handleWidth)
  context.setLineCap(.round)
  context.move(to: CGPoint(x: lensCenter.x + rim * cos(.pi / 4), y: lensCenter.y + rim * sin(.pi / 4)))
  context.addLine(to: handleEnd)
  context.strokePath()
}

// A four-point sparkle with curved sides.
let sparkle = layer { context in
  let c = lensCenter
  let r = sparkleRadius
  let pinch = r * 0.16
  context.setFillColor(cgColor(sparkleColor))
  context.move(to: CGPoint(x: c.x, y: c.y - r))
  context.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + pinch, y: c.y - pinch))
  context.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + pinch, y: c.y + pinch))
  context.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - pinch, y: c.y + pinch))
  context.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - pinch, y: c.y - pinch))
  context.fillPath()
}

let manifest = """
{
  "fill-specializations" : [
    { "value" : { "linear-gradient" : [\(iconColor(backgroundTop)), \(iconColor(backgroundBottom))] } },
    { "appearance" : "dark", "value" : { "linear-gradient" : [\(iconColor(darkBackgroundTop)), \(iconColor(darkBackgroundBottom))] } }
  ],
  "groups" : [
    {
      "name" : "Lens",
      "layers" : [
        { "name" : "Sparkle", "image-name" : "sparkle.png", "glass" : true },
        { "name" : "Lens", "image-name" : "lens.png", "glass" : true }
      ],
      "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
      "specular" : true,
      "translucency" : { "enabled" : true, "value" : 0.2 }
    },
    {
      "name" : "Cards",
      "layers" : [
        { "name" : "Lines", "image-name" : "lines.png", "glass" : true, "opacity" : 0.8 },
        { "name" : "Cursor", "image-name" : "cursor.png", "glass" : true },
        { "name" : "Claude", "image-name" : "claude.png", "glass" : true },
        { "name" : "Codex", "image-name" : "codex.png", "glass" : true }
      ],
      "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
      "specular" : true,
      "translucency" : { "enabled" : true, "value" : 0.3 }
    }
  ],
  "supported-platforms" : {
    "squares" : ["macOS"]
  }
}

"""

func write(_ image: CGImage, to url: URL) {
  let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(destination, image, nil)
  CGImageDestinationFinalize(destination)
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let bundle = root.appendingPathComponent("Skillscout/AppIcon.icon")
let assets = bundle.appendingPathComponent("Assets")
try? FileManager.default.removeItem(at: bundle)
try! FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
write(card(0, color: codexColor), to: assets.appendingPathComponent("codex.png"))
write(card(1, color: claudeColor), to: assets.appendingPathComponent("claude.png"))
write(card(2, color: cursorColor), to: assets.appendingPathComponent("cursor.png"))
write(lines, to: assets.appendingPathComponent("lines.png"))
write(lens, to: assets.appendingPathComponent("lens.png"))
write(sparkle, to: assets.appendingPathComponent("sparkle.png"))
try! manifest.write(to: bundle.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
print("Wrote \(bundle.path)")
