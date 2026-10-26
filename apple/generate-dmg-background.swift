// Payroof.dmg window background generator.
// Run from wallet/:  xcrun swift apple/generate-dmg-background.swift
//
// Draws the install diagram shown when the disk image opens: Payroof.app on the left, an
// arrow, and the Applications folder on the right, with a one-line instruction. Finder draws
// the two icons on top of this picture at the positions in apple/dmg-settings.py, so the
// layout constants below must match it (window 660x400 points, icons centred at x=165 and
// x=495, y=185 from the top).
// Writes assets/dmg/background.png (1x), background@2x.png and docs/install.png, a
// README preview with icon placeholders. Generates asset files only.
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let width: CGFloat = 660
let height: CGFloat = 400
let iconY: CGFloat = 185
let leftX: CGFloat = 165
let rightX: CGFloat = 495
let space = CGColorSpaceCreateDeviceRGB()
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
  CGColor(colorSpace: space, components: [r, g, b, a])!
}
let ink = rgb(0.10, 0.13, 0.24)
let muted = rgb(0.38, 0.42, 0.52)
let amber = rgb(0.96, 0.62, 0.11)

func text(
  _ ctx: CGContext, _ string: String, size: CGFloat, weight: CGFloat, color: CGColor,
  at x: CGFloat = width / 2, y: CGFloat
) {
  let traits = [kCTFontWeightTrait: weight] as CFDictionary
  let descriptor = CTFontDescriptorCreateWithAttributes(
    [kCTFontFamilyNameAttribute: "SF Pro Display", kCTFontTraitsAttribute: traits] as CFDictionary)
  let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
  let attributed = NSAttributedString(
    string: string,
    attributes: [
      NSAttributedString.Key(kCTFontAttributeName as String): font,
      NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
    ])
  let line = CTLineCreateWithAttributedString(attributed)
  let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
  ctx.textPosition = CGPoint(x: x - bounds.width / 2 - bounds.minX, y: height - y)
  CTLineDraw(line, ctx)
}

func draw(_ ctx: CGContext, placeholders: Bool) {
  // Soft vertical gradient, light enough for Finder's black icon labels.
  let gradient = CGGradient(
    colorsSpace: space, colors: [rgb(0.97, 0.97, 0.99), rgb(0.91, 0.93, 0.97)] as CFArray,
    locations: [0, 1])!
  ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: .zero, options: [])

  text(ctx, "Install Payroof", size: 26, weight: 0.4, color: ink, y: 62)
  text(
    ctx, "Drag the Payroof icon onto the Applications folder", size: 14, weight: 0, color: muted,
    y: 88)

  // Arrow between the icons (Finder icons are 128 pt wide).
  let y = height - iconY
  let start = leftX + 92
  let end = rightX - 92
  ctx.setStrokeColor(amber)
  ctx.setLineWidth(6)
  ctx.setLineCap(.round)
  ctx.setLineDash(phase: 0, lengths: [1, 14])
  ctx.move(to: CGPoint(x: start, y: y))
  ctx.addLine(to: CGPoint(x: end - 22, y: y))
  ctx.strokePath()
  ctx.setLineDash(phase: 0, lengths: [])
  ctx.setFillColor(amber)
  ctx.move(to: CGPoint(x: end, y: y))
  ctx.addLine(to: CGPoint(x: end - 26, y: y + 16))
  ctx.addLine(to: CGPoint(x: end - 26, y: y - 16))
  ctx.closePath()
  ctx.fillPath()

  text(
    ctx, "Then open Payroof from Applications or Launchpad.", size: 12, weight: 0, color: muted,
    y: 330)
  text(
    ctx, "First launch: System Settings → Privacy & Security → Open Anyway.", size: 12, weight: 0,
    color: muted, y: 350)

  guard placeholders else { return }
  // README preview only: the real app icon and a plain folder stand in for what Finder draws.
  let iconURL = URL(fileURLWithPath: "macos/App/Assets.xcassets/AppIcon.appiconset/icon-128-2.png")
  if let source = CGImageSourceCreateWithURL(iconURL as CFURL, nil),
    let icon = CGImageSourceCreateImageAtIndex(source, 0, nil)
  {
    ctx.draw(icon, in: CGRect(x: leftX - 64, y: y - 64, width: 128, height: 128))
  }
  let folder = CGRect(x: rightX - 54, y: y - 44, width: 108, height: 84)
  ctx.setFillColor(rgb(0.30, 0.60, 0.95))
  ctx.addPath(
    CGPath(
      roundedRect: CGRect(x: folder.minX, y: folder.maxY - 10, width: 44, height: 20),
      cornerWidth: 6, cornerHeight: 6, transform: nil))
  ctx.fillPath()
  ctx.setFillColor(rgb(0.40, 0.70, 1.0))
  ctx.addPath(CGPath(roundedRect: folder, cornerWidth: 10, cornerHeight: 10, transform: nil))
  ctx.fillPath()
  text(ctx, "A", size: 40, weight: 0.3, color: rgb(1, 1, 1, 0.9), at: rightX, y: iconY + 14)
  text(ctx, "Payroof", size: 13, weight: 0, color: ink, at: leftX, y: iconY + 84)
  text(ctx, "Applications", size: 13, weight: 0, color: ink, at: rightX, y: iconY + 84)
}

func write(_ path: String, scale: CGFloat, placeholders: Bool) {
  let ctx = CGContext(
    data: nil, width: Int(width * scale), height: Int(height * scale), bitsPerComponent: 8,
    bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  ctx.scaleBy(x: scale, y: scale)
  draw(ctx, placeholders: placeholders)
  let url = URL(fileURLWithPath: path)
  try? FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
  let destination = CGImageDestinationCreateWithURL(
    url as CFURL, UTType.png.identifier as CFString, 1, nil)!
  // 72 dpi at 1x and 144 dpi at 2x so Finder and tiffutil treat the pair as one HiDPI image.
  CGImageDestinationAddImage(
    destination, ctx.makeImage()!,
    [kCGImagePropertyDPIWidth: 72 * scale, kCGImagePropertyDPIHeight: 72 * scale] as CFDictionary)
  precondition(CGImageDestinationFinalize(destination), "could not write \(path)")
  print("wrote \(path)")
}

write("assets/dmg/background.png", scale: 1, placeholders: false)
write("assets/dmg/background@2x.png", scale: 2, placeholders: false)
write("docs/install.png", scale: 2, placeholders: true)
