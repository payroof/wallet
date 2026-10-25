import SwiftUI

/// A panel whose top edge is a shallow gable — the Payroof roofline.
struct PitchedPanelShape: Shape {
  var pitch: CGFloat = 12
  var radius: CGFloat = WalletMetrics.radiusLarge
  func path(in rect: CGRect) -> Path {
    let eave = rect.minY + min(pitch, rect.height / 3)
    let corner = min(radius, rect.width / 4, (rect.maxY - eave) / 2)
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: eave + corner))
    path.addArc(
      tangent1End: CGPoint(x: rect.minX, y: eave), tangent2End: CGPoint(x: rect.midX, y: rect.minY),
      radius: corner)
    path.addArc(
      tangent1End: CGPoint(x: rect.midX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: eave),
      radius: corner * 2)
    path.addArc(
      tangent1End: CGPoint(x: rect.maxX, y: eave), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY),
      radius: corner)
    path.addArc(
      tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
      tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: corner)
    path.addArc(
      tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: eave),
      radius: corner)
    path.closeSubpath()
    return path
  }
}

/// An open roof chevron used for the brand mark and section markings.
struct RoofChevron: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    return path
  }
}

/// The Payroof mark in its 1024-point design space (y down): a rooftop sign. "PAY" in heavy
/// condensed block letters fills a framed panel, its only lettering. The panel
/// stands on steel posts with an X brace on the roof edge. Same geometry as
/// apple/generate-icons.swift, which draws the app icon from it.
enum PayroofArt {
  /// Letter pieces: P has a hole (even-odd), A and Y are unions of like-wound pieces.
  /// Natural size 676 x 300, centred on `center`.
  static func letters(scale s: CGFloat, center: CGPoint) -> (p: Path, ay: Path) {
    let width: CGFloat = 190 + 36 + 220 + 10 + 220
    let origin = CGPoint(x: center.x - width * s / 2, y: center.y - 150 * s)
    func poly(_ path: inout Path, _ points: [(CGFloat, CGFloat)], dx: CGFloat) {
      path.addLines(
        points.map { CGPoint(x: origin.x + (dx + $0.0) * s, y: origin.y + $0.1 * s) })
      path.closeSubpath()
    }
    var p = Path()
    poly(
      &p, [(0, 0), (135, 0), (190, 55), (190, 125), (135, 180), (60, 180), (60, 300), (0, 300)],
      dx: 0)
    poly(&p, [(60, 58), (118, 58), (130, 70), (130, 110), (118, 122), (60, 122)], dx: 0)
    var ay = Path()
    poly(&ay, [(0, 300), (78, 0), (142, 0), (64, 300)], dx: 226)
    poly(&ay, [(78, 0), (142, 0), (220, 300), (156, 300)], dx: 226)
    poly(&ay, [(70, 205), (150, 205), (150, 250), (70, 250)], dx: 226)
    poly(
      &ay,
      [
        (0, 0), (70, 0), (110, 100), (150, 0), (220, 0), (142, 165), (142, 300), (78, 300),
        (78, 165),
      ], dx: 456)
    return (p, ay)
  }

  /// Marquee bulb centres round the frame.
  static let bulbs: [CGPoint] = {
    var points: [CGPoint] = []
    for k in 0..<13 {
      let x = 182 + CGFloat(k) * 55
      points.append(CGPoint(x: x, y: 133))
      points.append(CGPoint(x: x, y: 667))
    }
    for k in 0..<8 {
      let y = 190 + CGFloat(k) * 60
      points.append(CGPoint(x: 109, y: y))
      points.append(CGPoint(x: 915, y: y))
    }
    for (x, y) in [(121.6, 145.6), (902.4, 145.6), (121.6, 654.4), (902.4, 654.4)] {
      points.append(CGPoint(x: x, y: y))
    }
    return points
  }()

  static let stars: [(CGFloat, CGFloat, CGFloat)] = [
    (60, 70, 6), (190, 60, 4), (330, 40, 5), (700, 50, 4), (830, 80, 6), (960, 40, 4),
    (40, 330, 4), (985, 300, 5), (35, 560, 3), (990, 520, 4),
  ]
}

/// Colors of the mark for one color scheme. Day is a pale sky, a limestone face and ink-navy
/// letters with an amber edge. Night is an indigo sky with lit amber letters and bulbs.
struct PayroofPalette {
  var skyTop: Color
  var skyBottom: Color
  var face: Color
  var frame: Color
  var bulb: Color
  var bulbCore: Color
  var letterTop: Color
  var letterBottom: Color
  var edge: Color?
  var post: Color
  var roof: Color
  var roofEdge: Color
  var glow: Color?

  static let light = PayroofPalette(
    skyTop: Color(red: 0.55, green: 0.74, blue: 0.92),
    skyBottom: Color(red: 0.99, green: 0.87, blue: 0.74),
    face: Color(red: 0.98, green: 0.95, blue: 0.88),
    frame: Color(red: 0.137, green: 0.165, blue: 0.239),
    bulb: Color(red: 0.96, green: 0.66, blue: 0.20),
    bulbCore: Color(red: 1, green: 0.93, blue: 0.75),
    letterTop: Color(red: 0.17, green: 0.21, blue: 0.31),
    letterBottom: Color(red: 0.09, green: 0.11, blue: 0.18),
    edge: Color(red: 0.96, green: 0.66, blue: 0.20),
    post: Color(red: 0.36, green: 0.39, blue: 0.47),
    roof: Color(red: 0.137, green: 0.165, blue: 0.239),
    roofEdge: Color(red: 0.47, green: 0.50, blue: 0.59), glow: nil)
  static let dark = PayroofPalette(
    skyTop: Color(red: 0.020, green: 0.031, blue: 0.090),
    skyBottom: Color(red: 0.165, green: 0.149, blue: 0.302),
    face: Color(red: 0.063, green: 0.082, blue: 0.150),
    frame: Color(red: 0.231, green: 0.267, blue: 0.369),
    bulb: Color(red: 1, green: 0.80, blue: 0.45), bulbCore: Color(red: 1, green: 0.95, blue: 0.80),
    letterTop: Color(red: 1, green: 0.95, blue: 0.80),
    letterBottom: Color(red: 1, green: 0.78, blue: 0.38), edge: nil,
    post: Color(red: 0.30, green: 0.33, blue: 0.45),
    roof: Color(red: 0.043, green: 0.055, blue: 0.118),
    roofEdge: Color(red: 0.20, green: 0.23, blue: 0.33),
    glow: Color(red: 1, green: 0.72, blue: 0.30))
}

/// The Payroof mark: the app icon in miniature, in the day or night version of the current
/// color scheme. Below 80 points the frame and bulbs are dropped so PAY stays dominant.
struct PayroofMark: View {
  var size: CGFloat = 40
  @Environment(\.colorScheme) private var scheme
  var body: some View {
    let shape = RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
    let palette = scheme == .dark ? PayroofPalette.dark : PayroofPalette.light
    let small = size < 80
    Canvas { context, canvas in
      let k = canvas.width / 1024
      context.scaleBy(x: k, y: k)
      Self.draw(&context, palette: palette, small: small, unit: k)
    }
    .frame(width: size, height: size)
    .clipShape(shape)
    .overlay(
      shape.strokeBorder(Color.white.opacity(0.12), lineWidth: max(0.5, size * 0.015))
    )
    .accessibilityHidden(true)
  }

  private static func glowed(
    _ context: inout GraphicsContext, color: Color?, radius: CGFloat,
    _ draw: (inout GraphicsContext) -> Void
  ) {
    context.drawLayer { layer in
      if let color { layer.addFilter(.shadow(color: color, radius: radius, x: 0, y: 0)) }
      draw(&layer)
    }
  }

  private static func draw(
    _ context: inout GraphicsContext, palette p: PayroofPalette, small: Bool, unit: CGFloat
  ) {
    let all = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    context.fill(
      Path(all),
      with: .linearGradient(
        Gradient(colors: [p.skyTop, p.skyBottom]), startPoint: .zero,
        endPoint: CGPoint(x: 0, y: 1024)))
    if p.glow == nil {
      context.fill(
        Path(all),
        with: .radialGradient(
          Gradient(colors: [Color(red: 1, green: 0.98, blue: 0.88).opacity(0.85), .clear]),
          center: CGPoint(x: 880, y: 70), startRadius: 0, endRadius: 420))
    } else if !small {
      for (x, y, r) in PayroofArt.stars {
        context.fill(
          Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
          with: .color(.white.opacity(0.8)))
      }
    }

    // Roof edge and posts.
    let roofY: CGFloat = 850
    let panelBottom: CGFloat = small ? 690 : 680
    let postWidth: CGFloat = small ? 60 : 32
    let postLeft: CGFloat = small ? 190 : 240
    let postRight = 1024 - postLeft - postWidth
    let postHeight = roofY - panelBottom + 14
    for x in [postLeft, postRight] {
      context.fill(
        Path(CGRect(x: x, y: panelBottom - 10, width: postWidth, height: postHeight)),
        with: .color(p.post))
    }
    if !small {
      let l = postLeft + postWidth / 2
      let r = postRight + postWidth / 2
      var brace = Path()
      for (a, b) in [
        (CGPoint(x: l, y: panelBottom + 20), CGPoint(x: r, y: roofY - 14)),
        (CGPoint(x: r, y: panelBottom + 20), CGPoint(x: l, y: roofY - 14)),
        (CGPoint(x: l, y: 765), CGPoint(x: r, y: 765)),
      ] {
        brace.move(to: a)
        brace.addLine(to: b)
      }
      context.stroke(brace, with: .color(p.post), lineWidth: 14)
      for x in [postLeft, postRight] {
        context.fill(
          Path(CGRect(x: x - 22, y: roofY - 18, width: postWidth + 44, height: 18)),
          with: .color(p.post))
      }
    }
    context.fill(
      Path(CGRect(x: 0, y: roofY, width: 1024, height: 1024 - roofY)), with: .color(p.roof))
    context.fill(Path(CGRect(x: 0, y: roofY, width: 1024, height: 20)), with: .color(p.roofEdge))

    // Panel.
    let outer =
      small
      ? CGRect(x: 56, y: 150, width: 912, height: 540)
      : CGRect(x: 96, y: 120, width: 832, height: 560)
    let inset: CGFloat = small ? 20 : 26
    let face = outer.insetBy(dx: inset, dy: inset)
    let outerPath = Path(roundedRect: outer, cornerRadius: 58, style: .continuous)
    let facePath = Path(roundedRect: face, cornerRadius: 58 - inset, style: .continuous)
    glowed(&context, color: p.glow?.opacity(0.22) ?? .black.opacity(0.28), radius: 24) {
      $0.fill(outerPath, with: .color(p.frame))
    }
    context.fill(facePath, with: .color(p.face))

    // Letters.
    let scale: CGFloat = small ? 1.24 : 1.12
    let center = CGPoint(x: 512, y: face.midY)
    let letters = PayroofArt.letters(scale: scale, center: center)
    let top = center.y - 150 * scale
    let ink = GraphicsContext.Shading.linearGradient(
      Gradient(colors: [p.letterTop, p.letterBottom]), startPoint: CGPoint(x: 0, y: top),
      endPoint: CGPoint(x: 0, y: top + 300 * scale))
    let eo = FillStyle(eoFill: true)
    if let edge = p.edge {
      let dx: CGFloat = small ? 12 : 9
      let dy: CGFloat = small ? 14 : 11
      let shift = CGAffineTransform(translationX: dx, y: dy)
      context.fill(letters.p.applying(shift), with: .color(edge), style: eo)
      context.fill(letters.ay.applying(shift), with: .color(edge))
    }
    if let glow = p.glow {
      glowed(&context, color: glow.opacity(0.85), radius: 90) {
        $0.fill(letters.p, with: .color(p.letterBottom), style: eo)
        $0.fill(letters.ay, with: .color(p.letterBottom))
      }
    }
    context.fill(letters.p, with: ink, style: eo)
    context.fill(letters.ay, with: ink)

    if !small {
      glowed(&context, color: p.glow?.opacity(0.9), radius: 18) { layer in
        for b in PayroofArt.bulbs {
          layer.fill(
            Path(ellipseIn: CGRect(x: b.x - 9, y: b.y - 9, width: 18, height: 18)),
            with: .color(p.bulb))
        }
      }
      for b in PayroofArt.bulbs {
        context.fill(
          Path(ellipseIn: CGRect(x: b.x - 4.5, y: b.y - 4.5, width: 9, height: 9)),
          with: .color(p.bulbCore))
      }
    }
  }
}

/// "Payroof" as one word, for toolbars and titles: "Pay" in ink and "roof" in the accent,
/// set in the rounded system face the amounts use, bold and slightly tight. The mark
/// beside it already carries the sign's PAY, so the word stays plain and legible at any
/// size and in every language's text settings.
struct PayroofWordmark: View {
  var size: CGFloat = 20
  var body: some View {
    let pay = Text("Pay").foregroundStyle(WalletTheme.text)
    let roof = Text("roof").foregroundStyle(WalletTheme.accent)
    Text("\(pay)\(roof)")
      .font(.system(size: size * 1.2, weight: .bold, design: .rounded))
      .tracking(-size * 0.02)
      .lineLimit(1)
      .fixedSize()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Payroof")
  }
}
