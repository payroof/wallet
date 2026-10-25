// Payroof Wallet app icon generator.
// Run from wallet/:  xcrun swift apple/generate-icons.swift
// Previews:          xcrun swift apple/generate-icons.swift --preview <dir>
//
// Design (matches PayroofMark in apple/Shared/DesignSystem/Brand.swift): a rooftop sign.
// A framed sign panel stands on steel posts with an X brace on a roof edge. "PAY" fills the
// panel in heavy condensed block letters, the only lettering on the sign. Marquee bulbs run
// round the frame.
//   Light: pale day sky, limestone face, ink-navy letters with an amber edge.
//   Dark:  night indigo sky, glowing amber letters and bulbs, soft halo.
//   Tinted: grayscale on black, which the system tints.
// At 64 px and below the frame and bulbs are dropped so PAY stays dominant.
//
// iOS:   1024x1024 full-bleed opaque squares the system masks: light, dark and tinted, as
//        iOS 18 expects (AppIcon appearances).
// macOS: one icon, as the asset catalog does not switch with appearance on macOS 15. It uses
//        the night version, whose lit letters keep a strong silhouette on any Dock or
//        Finder background. Artwork sits in an 824x824 continuous-style rounded rect
//        (radius 185) centered in the 1024 canvas (100px margins) with a soft drop shadow.
// Writes PNGs plus Contents.json for both AppIcon.appiconset folders (filenames:
// icon-<size>-<scale>.png). Generates asset files only. Does not launch an app, simulator
// or UI renderer.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let space = CGColorSpaceCreateDeviceRGB()
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
  CGColor(colorSpace: space, components: [r, g, b, a])!
}
func gray(_ v: CGFloat, _ a: CGFloat = 1) -> CGColor { rgb(v, v, v, a) }

enum Variant: String { case standard, dark, tinted }

struct Palette {
  var skyTop: CGColor
  var skyBottom: CGColor
  var face: CGColor
  var frame: CGColor
  var bulb: CGColor
  var bulbCore: CGColor
  var letterTop: CGColor
  var letterBottom: CGColor
  /// The amber edge behind the letters (day only).
  var edge: CGColor?
  var post: CGColor
  var roof: CGColor
  var roofEdge: CGColor
  /// Halo colour of lit parts (night only).
  var glow: CGColor?
  var stars: Bool
  var sun: Bool

  static let light = Palette(
    skyTop: rgb(0.55, 0.74, 0.92), skyBottom: rgb(0.99, 0.87, 0.74),
    face: rgb(0.98, 0.95, 0.88), frame: rgb(0.137, 0.165, 0.239),
    bulb: rgb(0.96, 0.66, 0.20), bulbCore: rgb(1, 0.93, 0.75),
    letterTop: rgb(0.17, 0.21, 0.31), letterBottom: rgb(0.09, 0.11, 0.18),
    edge: rgb(0.96, 0.66, 0.20), post: rgb(0.36, 0.39, 0.47),
    roof: rgb(0.137, 0.165, 0.239), roofEdge: rgb(0.47, 0.50, 0.59),
    glow: nil, stars: false, sun: true)
  static let dark = Palette(
    skyTop: rgb(0.020, 0.031, 0.090), skyBottom: rgb(0.165, 0.149, 0.302),
    face: rgb(0.063, 0.082, 0.150), frame: rgb(0.231, 0.267, 0.369),
    bulb: rgb(1, 0.80, 0.45), bulbCore: rgb(1, 0.95, 0.80),
    letterTop: rgb(1, 0.95, 0.80), letterBottom: rgb(1, 0.78, 0.38),
    edge: nil, post: rgb(0.30, 0.33, 0.45),
    roof: rgb(0.043, 0.055, 0.118), roofEdge: rgb(0.20, 0.23, 0.33),
    glow: rgb(1, 0.72, 0.30), stars: true, sun: false)
  static let tinted = Palette(
    skyTop: gray(0), skyBottom: gray(0),
    face: gray(0.13), frame: gray(0.42),
    bulb: gray(0.85), bulbCore: gray(1),
    letterTop: gray(1), letterBottom: gray(0.88),
    edge: nil, post: gray(0.38),
    roof: gray(0.22), roofEdge: gray(0.45),
    glow: nil, stars: false, sun: false)
}

// MARK: Geometry (1024 design space, y down)

func polygon(
  _ points: [(CGFloat, CGFloat)], _ path: CGMutablePath, scale: CGFloat, at origin: CGPoint
) {
  let mapped = points.map { CGPoint(x: origin.x + $0.0 * scale, y: origin.y + $0.1 * scale) }
  path.addLines(between: mapped)
  path.closeSubpath()
}

/// "PAY" in heavy condensed block letters. P has a hole (even-odd), A and Y are unions of
/// like-wound pieces (non-zero). Natural size 676 x 300.
func letterPaths(scale s: CGFloat, centeredAt center: CGPoint) -> (p: CGPath, ay: CGPath) {
  let width: CGFloat = 190 + 36 + 220 + 10 + 220
  let origin = CGPoint(x: center.x - width * s / 2, y: center.y - 150 * s)
  func at(_ dx: CGFloat) -> CGPoint { CGPoint(x: origin.x + dx * s, y: origin.y) }
  let p = CGMutablePath()
  polygon(
    [(0, 0), (135, 0), (190, 55), (190, 125), (135, 180), (60, 180), (60, 300), (0, 300)], p,
    scale: s, at: at(0))
  polygon(
    [(60, 58), (118, 58), (130, 70), (130, 110), (118, 122), (60, 122)], p, scale: s, at: at(0))
  let ay = CGMutablePath()
  let ax: CGFloat = 190 + 36
  polygon([(0, 300), (78, 0), (142, 0), (64, 300)], ay, scale: s, at: at(ax))
  polygon([(78, 0), (142, 0), (220, 300), (156, 300)], ay, scale: s, at: at(ax))
  polygon([(70, 205), (150, 205), (150, 250), (70, 250)], ay, scale: s, at: at(ax))
  let yx = ax + 220 + 10
  polygon(
    [
      (0, 0), (70, 0), (110, 100), (150, 0), (220, 0), (142, 165), (142, 300), (78, 300),
      (78, 165),
    ], ay, scale: s, at: at(yx))
  return (p, ay)
}

// MARK: Art

/// Art in a 1024x1024 design space, origin bottom-left. `unit` is device pixels per design
/// unit, used for shadow blur (which CoreGraphics does not scale with the CTM).
func drawArt(_ c: CGContext, pixels: Int, unit: CGFloat, palette p: Palette) {
  let small = pixels <= 64
  c.saveGState()
  c.translateBy(x: 0, y: 1024)
  c.scaleBy(x: 1, y: -1)  // now y down, as in Brand.swift
  c.setLineCap(.round)
  c.setLineJoin(.round)

  // Sky.
  let sky = CGGradient(
    colorsSpace: space, colors: [p.skyTop, p.skyBottom] as CFArray, locations: [0, 1])!
  c.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: 1024), options: [])
  if p.sun {
    let sun = CGGradient(
      colorsSpace: space, colors: [rgb(1, 0.98, 0.88, 0.85), rgb(1, 0.98, 0.88, 0)] as CFArray,
      locations: [0, 1])!
    c.drawRadialGradient(
      sun, startCenter: CGPoint(x: 880, y: 70), startRadius: 0,
      endCenter: CGPoint(x: 880, y: 70), endRadius: 420, options: [])
  }
  if p.stars && !small {
    c.setFillColor(rgb(1, 1, 1, 0.8))
    for (x, y, r) in [
      (60.0, 70.0, 6.0), (190, 60, 4), (330, 40, 5), (700, 50, 4), (830, 80, 6), (960, 40, 4),
      (40, 330, 4), (985, 300, 5), (35, 560, 3), (990, 520, 4),
    ] {
      c.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }
  }

  // Roof edge and posts.
  let roofY: CGFloat = 850
  let panelBottom: CGFloat = small ? 690 : 680
  let postWidth: CGFloat = small ? 60 : 32
  let postLeft: CGFloat = small ? 190 : 240
  let postRight: CGFloat = 1024 - postLeft - postWidth
  c.setFillColor(p.post)
  c.fill(
    CGRect(x: postLeft, y: panelBottom - 10, width: postWidth, height: roofY - panelBottom + 14))
  c.fill(
    CGRect(x: postRight, y: panelBottom - 10, width: postWidth, height: roofY - panelBottom + 14))
  if !small {
    c.setStrokeColor(p.post)
    c.setLineWidth(14)
    c.setLineCap(.butt)
    let l = postLeft + postWidth / 2
    let r = postRight + postWidth / 2
    c.strokeLineSegments(
      between: [
        CGPoint(x: l, y: panelBottom + 20), CGPoint(x: r, y: roofY - 14),
        CGPoint(x: r, y: panelBottom + 20), CGPoint(x: l, y: roofY - 14),
        CGPoint(x: l, y: 765), CGPoint(x: r, y: 765),
      ])
    c.setLineCap(.round)
    c.setFillColor(p.post)
    c.fill(CGRect(x: postLeft - 22, y: roofY - 18, width: postWidth + 44, height: 18))
    c.fill(CGRect(x: postRight - 22, y: roofY - 18, width: postWidth + 44, height: 18))
  }
  c.setFillColor(p.roof)
  c.fill(CGRect(x: 0, y: roofY, width: 1024, height: 1024 - roofY))
  c.setFillColor(p.roofEdge)
  c.fill(CGRect(x: 0, y: roofY, width: 1024, height: 20))

  // Panel.
  let outer =
    small
    ? CGRect(x: 56, y: 150, width: 912, height: 540)
    : CGRect(x: 96, y: 120, width: 832, height: 560)
  let inset: CGFloat = small ? 20 : 26
  let face = outer.insetBy(dx: inset, dy: inset)
  let outerPath = CGPath(roundedRect: outer, cornerWidth: 58, cornerHeight: 58, transform: nil)
  let facePath = CGPath(
    roundedRect: face, cornerWidth: 58 - inset, cornerHeight: 58 - inset, transform: nil)
  c.saveGState()
  if let glow = p.glow {
    c.setShadow(offset: .zero, blur: 50 * unit, color: glow.copy(alpha: 0.22)!)
  } else {
    c.setShadow(offset: CGSize(width: 0, height: -14 * unit), blur: 24 * unit, color: gray(0, 0.28))
  }
  c.setFillColor(p.frame)
  c.addPath(outerPath)
  c.fillPath()
  c.restoreGState()
  c.setFillColor(p.face)
  c.addPath(facePath)
  c.fillPath()
  // Letters.
  let scale: CGFloat = small ? 1.24 : 1.12
  let center = CGPoint(x: 512, y: face.midY)
  let letters = letterPaths(scale: scale, centeredAt: center)
  func fillLetters(_ paths: [(CGPath, Bool)], dx: CGFloat = 0, dy: CGFloat = 0) {
    for (path, evenOdd) in paths {
      var t = CGAffineTransform(translationX: dx, y: dy)
      c.addPath(path.copy(using: &t)!)
      c.fillPath(using: evenOdd ? .evenOdd : .winding)
    }
  }
  let all: [(CGPath, Bool)] = [(letters.p, true), (letters.ay, false)]
  if let edge = p.edge {
    c.setFillColor(edge)
    fillLetters(all, dx: small ? 12 : 9, dy: small ? 14 : 11)
  }
  if let glow = p.glow {
    c.saveGState()
    c.setShadow(offset: .zero, blur: 90 * unit, color: glow.copy(alpha: 0.85)!)
    c.setFillColor(p.letterBottom)
    fillLetters(all)
    c.restoreGState()
  }
  // Letter body, with a vertical gradient.
  let ink = CGGradient(
    colorsSpace: space, colors: [p.letterTop, p.letterBottom] as CFArray, locations: [0, 1])!
  let top = center.y - 150 * scale
  for (path, evenOdd) in all {
    c.saveGState()
    c.addPath(path)
    c.clip(using: evenOdd ? .evenOdd : .winding)
    c.drawLinearGradient(
      ink, start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: top + 300 * scale), options: [])
    c.restoreGState()
  }

  if !small {
    // Marquee bulbs on the frame.
    var bulbs: [CGPoint] = []
    for k in 0..<13 {
      let x = 182 + CGFloat(k) * 55
      bulbs.append(CGPoint(x: x, y: 133))
      bulbs.append(CGPoint(x: x, y: 667))
    }
    for k in 0..<8 {
      let y = 190 + CGFloat(k) * 60
      bulbs.append(CGPoint(x: 109, y: y))
      bulbs.append(CGPoint(x: 915, y: y))
    }
    for (x, y) in [(121.6, 145.6), (902.4, 145.6), (121.6, 654.4), (902.4, 654.4)] {
      bulbs.append(CGPoint(x: x, y: y))
    }
    c.saveGState()
    if let glow = p.glow {
      c.setShadow(offset: .zero, blur: 18 * unit, color: glow.copy(alpha: 0.9)!)
    }
    c.setFillColor(p.bulb)
    for b in bulbs { c.fillEllipse(in: CGRect(x: b.x - 9, y: b.y - 9, width: 18, height: 18)) }
    c.restoreGState()
    c.setFillColor(p.bulbCore)
    for b in bulbs { c.fillEllipse(in: CGRect(x: b.x - 4.5, y: b.y - 4.5, width: 9, height: 9)) }
  }
  c.restoreGState()
}

func makeImage(size: Int, mac: Bool, variant: Variant) -> CGImage {
  let alpha = mac
  let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8,
    bytesPerRow: size * 4, space: space,
    bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue)!
  context.interpolationQuality = .high
  let palette: Palette =
    switch variant {
    case .standard: .light
    case .dark: .dark
    case .tinted: .tinted
    }
  let full = CGFloat(size) / 1024
  context.scaleBy(x: full, y: full)
  if mac {
    let rect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)
    context.saveGState()
    context.setShadow(
      offset: CGSize(width: 0, height: -12 * full), blur: 28 * full, color: rgb(0, 0, 0, 0.35))
    context.setFillColor(palette.skyTop)
    context.addPath(shape)
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(shape)
    context.clip()
    context.translateBy(x: 100, y: 100)
    context.scaleBy(x: 824.0 / 1024, y: 824.0 / 1024)
    // Pixel size of the artwork itself, for small-size simplification.
    drawArt(
      context, pixels: Int((CGFloat(size) * 824.0 / 1024).rounded()), unit: full * 824.0 / 1024,
      palette: palette)
    context.restoreGState()
  } else {
    drawArt(context, pixels: size, unit: full, palette: palette)
  }
  return context.makeImage()!
}

func drawIcon(size: Int, mac: Bool, variant: Variant = .standard, to url: URL) throws {
  let destination = CGImageDestinationCreateWithURL(
    url as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(destination, makeImage(size: size, mac: mac, variant: variant), nil)
  guard CGImageDestinationFinalize(destination) else {
    throw NSError(domain: "IconGeneration", code: 1)
  }
}

let arguments = CommandLine.arguments
if let flag = arguments.firstIndex(of: "--preview"), flag + 1 < arguments.count {
  let folder = URL(fileURLWithPath: arguments[flag + 1])
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  for variant in [Variant.standard, .dark, .tinted] {
    for size in [1024, 128, 64, 32, 16] {
      for mac in [false, true] where !(mac && variant == .tinted) {
        let name = "\(mac ? "mac" : "ios")-\(variant.rawValue)-\(size).png"
        try drawIcon(
          size: size, mac: mac, variant: variant, to: folder.appendingPathComponent(name))
      }
    }
  }
  exit(0)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
for (path, mac) in [("ios/App/Assets.xcassets", false), ("macos/App/Assets.xcassets", true)] {
  let assets = root.appendingPathComponent(path)
  let folder = assets.appendingPathComponent("AppIcon.appiconset")
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  let sizes = mac ? [16, 32, 128, 256, 512] : [1024]
  var images: [[String: Any]] = []
  for size in sizes {
    for scale in (mac ? [1, 2] : [1]) {
      let filename = "icon-\(size)-\(scale).png"
      try drawIcon(
        size: size * scale, mac: mac, variant: mac ? .dark : .standard,
        to: folder.appendingPathComponent(filename))
      var entry: [String: Any] = [
        "idiom": mac ? "mac" : "universal", "size": "\(size)x\(size)", "filename": filename,
      ]
      if mac { entry["scale"] = "\(scale)x" } else { entry["platform"] = "ios" }
      images.append(entry)
    }
  }
  if !mac {
    for variant in [Variant.dark, .tinted] {
      let filename = "icon-1024-\(variant.rawValue).png"
      try drawIcon(
        size: 1024, mac: false, variant: variant, to: folder.appendingPathComponent(filename))
      images.append([
        "idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": filename,
        "appearances": [["appearance": "luminosity", "value": variant.rawValue]],
      ])
    }
  }
  let info: [String: Any] = ["info": ["author": "xcode", "version": 1]]
  try JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]).write(
    to: assets.appendingPathComponent("Contents.json"))
  try JSONSerialization.data(
    withJSONObject: ["images": images, "info": info["info"]!],
    options: [.prettyPrinted, .sortedKeys]
  ).write(to: folder.appendingPathComponent("Contents.json"))
}
