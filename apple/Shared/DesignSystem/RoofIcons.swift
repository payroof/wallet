import SwiftUI

/// Payroof's own icon set: things found on a city roof, drawn as single-weight line art
/// on a 24-point grid. Generic actions (copy, share, close, chevrons) keep SF Symbols,
/// which everyone already reads. These carry the app's own places and objects.
enum RoofGlyph: String, CaseIterable, Sendable {
  case house, plane, mailbox, stairs, vent, antenna, dish, key, lock, shield

  /// The main line art, in the 24-point design space (y down).
  fileprivate var base: Path {
    var p = Path()
    switch self {
    case .house:
      p.addLines([pt(3, 11.5), pt(12, 3.5), pt(21, 11.5)])
      p.addLines([pt(5.5, 9.6), pt(5.5, 20.5), pt(18.5, 20.5), pt(18.5, 9.6)])
      p.addLines([pt(15.5, 6.9), pt(15.5, 4), pt(18, 4), pt(18, 9.1)])
      p.addLines([pt(10, 20.5), pt(10, 15), pt(14, 15), pt(14, 20.5)])
    case .plane:
      p.addLines([pt(3, 11.2), pt(21, 3.5), pt(14.6, 20.5), pt(11, 13), pt(3, 11.2)])
      p.addLines([pt(11, 13), pt(21, 3.5)])
    case .mailbox:
      p.move(to: pt(3.5, 15))
      p.addLine(to: pt(3.5, 9.5))
      p.addArc(
        center: pt(7.5, 9.5), radius: 4 * u, startAngle: .degrees(180), endAngle: .degrees(270),
        clockwise: false)
      p.addLine(to: pt(18, 5.5))
      p.addArc(
        center: pt(18, 9.5), radius: 4 * u, startAngle: .degrees(270), endAngle: .degrees(360),
        clockwise: false)
      p.addLine(to: pt(22, 15))
      p.closeSubpath()
      p.move(to: pt(11.5, 15))
      p.addArc(
        center: pt(7.5, 9.5), radius: 4 * u, startAngle: .degrees(0), endAngle: .degrees(-180),
        clockwise: true)
      p.addLines([pt(12.5, 15), pt(12.5, 21)])
      p.addLines([pt(9, 21), pt(16, 21)])
    case .stairs:
      p.addLines([
        pt(3, 20.5), pt(3, 16.5), pt(8, 16.5), pt(8, 12), pt(13, 12), pt(13, 7.5), pt(18, 7.5),
        pt(18, 3.5), pt(21, 3.5), pt(21, 20.5), pt(3, 20.5),
      ])
    case .vent:
      // A turbine ventilator: a ribbed ball (its ribs drawn by `ventRibs`, so they can
      // turn) on a short neck, on its flashing.
      p.addEllipse(in: CGRect(x: 5.5, y: 2.5, width: 13, height: 11.5))
      p.addLines([pt(10, 14), pt(10, 17)])
      p.addLines([pt(14, 14), pt(14, 17)])
      p.addLines([pt(5, 20.5), pt(9, 17), pt(15, 17), pt(19, 20.5), pt(5, 20.5)])
    case .antenna:
      p.addLines([pt(12, 21), pt(12, 6)])
      p.addLines([pt(7, 9.5), pt(17, 9.5)])
      p.addLines([pt(8.5, 13.5), pt(15.5, 13.5)])
      p.addLines([pt(8, 21), pt(12, 16), pt(16, 21)])
    case .dish:
      // A satellite dish on its post, facing up and to the right: the bowl, its rim,
      // the arm out to the feed (`filled`), and two waves of signal beyond it.
      p.move(to: pt(3.5, 8.5))
      p.addQuadCurve(to: pt(15.5, 19.5), control: pt(4, 19.5))
      p.closeSubpath()
      p.addLines([pt(9.5, 14), pt(14.5, 9)])
      p.addLines([pt(8, 17.8), pt(8, 21)])
      p.addLines([pt(4.5, 21), pt(11.5, 21)])
      for radius in [4.0, 7.5] {
        p.move(to: pt(14.5 + radius * cos(-0.44 * .pi), 9 + radius * sin(-0.44 * .pi)))
        p.addArc(
          center: pt(14.5, 9), radius: radius, startAngle: .degrees(-79.2),
          endAngle: .degrees(-10.8), clockwise: false)
      }
    case .key:
      p.addEllipse(in: CGRect(x: 3.5 * u, y: 8 * u, width: 8 * u, height: 8 * u))
      p.addLines([pt(11.5, 12), pt(21, 12)])
      p.addLines([pt(17, 12), pt(17, 15.5)])
      p.addLines([pt(20, 12), pt(20, 14.5)])
    case .lock:
      p.move(to: pt(7.5, 11))
      p.addLine(to: pt(7.5, 8.5))
      p.addArc(
        center: pt(12, 8.5), radius: 4.5 * u, startAngle: .degrees(180), endAngle: .degrees(360),
        clockwise: false)
      p.addLine(to: pt(16.5, 11))
      p.addRoundedRect(
        in: CGRect(x: 5 * u, y: 11 * u, width: 14 * u, height: 9.5 * u),
        cornerSize: CGSize(width: 2 * u, height: 2 * u))
      p.addLines([pt(12, 14.5), pt(12, 17)])
    case .shield:
      p.move(to: pt(12, 3))
      p.addLine(to: pt(19.5, 6))
      p.addLine(to: pt(19.5, 11.5))
      p.addCurve(to: pt(12, 21), control1: pt(19.5, 16), control2: pt(16.3, 19.6))
      p.addCurve(to: pt(4.5, 11.5), control1: pt(7.7, 19.6), control2: pt(4.5, 16))
      p.addLine(to: pt(4.5, 6))
      p.closeSubpath()
      p.addLines([pt(8.5, 13.5), pt(12, 10), pt(15.5, 13.5)])
    }
    return p
  }

  /// Solid parts drawn in the same color: the antenna's light, the dish's feed.
  fileprivate var filled: Path? {
    switch self {
    case .antenna:
      return Path(ellipseIn: CGRect(x: 10.4 * u, y: 2 * u, width: 3.2 * u, height: 3.2 * u))
    case .dish:
      return Path(ellipseIn: CGRect(x: 13 * u, y: 7.5 * u, width: 3 * u, height: 3 * u))
    default:
      return nil
    }
  }

  /// The vent's twisted ribs, `spin` turns round (a sixth of a turn repeats them).
  /// Each is a meridian of the ball, faded as it turns to the back.
  fileprivate static func ventRibs(spin: Double) -> [(path: Path, opacity: Double)] {
    (0..<6).compactMap { index in
      let longitude = 2 * Double.pi * (spin + Double(index) / 6)
      let front = cos(longitude)
      guard front > 0.05 else { return nil }
      var p = Path()
      for step in 0...12 {
        let latitude = Double.pi * (Double(step) / 12 - 0.5)
        // The vanes twist from top to bottom, as a turbine's do.
        let turned = longitude + 0.6 * latitude / (Double.pi / 2)
        let point = pt(12 + 6.5 * cos(latitude) * sin(turned), 8.25 + 5.75 * sin(latitude))
        if step == 0 { p.move(to: point) } else { p.addLine(to: point) }
      }
      return (p, min(1, front * 2.5))
    }
  }

  /// The mailbox's flag, separate so it can be raised.
  fileprivate static let flag: Path = {
    var p = Path()
    p.addLines([pt(18.5, 12), pt(18.5, 1.5), pt(22.5, 1.5), pt(22.5, 4.5), pt(18.5, 4.5)])
    return p
  }()
}

/// The 24-point grid is drawn at unit scale. The view scales it to its size.
private let u: CGFloat = 1
private func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

/// One glyph in the current foreground style. `active` animates the glyphs that have a
/// state of their own: the mailbox raises its flag. Each change of `play` performs the
/// glyph's one move (none under Reduce Motion): the paper plane flies off and comes back
/// round, the house hops, the mailbox takes a letter, the stairs are climbed, the vent's
/// turbine spins, and the rest give a small pop. Decorative: the control around it
/// carries the label.
struct RoofIcon: View {
  let glyph: RoofGlyph
  var size: CGFloat = 22
  var weight: CGFloat = 1.7
  var active = false
  var play = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  init(
    _ glyph: RoofGlyph, size: CGFloat = 22, weight: CGFloat = 1.7, active: Bool = false,
    play: Int = 0
  ) {
    self.glyph = glyph
    self.size = size
    self.weight = weight
    self.active = active
    self.play = play
  }

  var body: some View {
    KeyframeAnimator(initialValue: RoofMotion(), trigger: reduceMotion ? 0 : play) { motion in
      drawing(spin: motion.spin)
        .scaleEffect(x: motion.scaleX, y: motion.scaleY, anchor: glyph.pivot)
        .rotationEffect(.degrees(motion.angle), anchor: glyph.pivot)
        .offset(x: motion.x * size / 24, y: motion.y * size / 24)
        .opacity(motion.opacity)
    } keyframes: { _ in
      RoofMotion.keyframes(for: glyph)
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }

  private func drawing(spin: Double) -> some View {
    ZStack {
      Canvas { context, canvas in
        let scale = canvas.width / 24
        context.scaleBy(x: scale, y: scale)
        let style = StrokeStyle(
          lineWidth: weight, lineCap: .round, lineJoin: .round)
        context.stroke(glyph.base, with: .foreground, style: style)
        if let filled = glyph.filled { context.fill(filled, with: .foreground) }
        if glyph == .vent {
          for rib in RoofGlyph.ventRibs(spin: spin) {
            var faded = context
            faded.opacity = rib.opacity
            faded.stroke(rib.path, with: .foreground, style: style)
          }
        }
      }
      if glyph == .mailbox {
        Canvas { context, canvas in
          let scale = canvas.width / 24
          context.scaleBy(x: scale, y: scale)
          context.stroke(
            RoofGlyph.flag, with: .foreground,
            style: StrokeStyle(lineWidth: weight, lineCap: .round, lineJoin: .round))
        }
        .rotationEffect(.degrees(active ? 0 : -90), anchor: UnitPoint(x: 18.5 / 24, y: 12 / 24))
        .opacity(active ? 1 : 0)
      }
    }
    .frame(width: size, height: size)
  }
}

extension RoofGlyph {
  /// Where a glyph's squash and tilt are anchored: things standing on the roof keep
  /// their feet on it. The plane turns about its middle.
  fileprivate var pivot: UnitPoint {
    switch self {
    case .house, .mailbox, .stairs, .antenna, .dish: .bottom
    default: .center
    }
  }
}

/// One frame of a glyph's move. Offsets are in the 24-point design space.
private struct RoofMotion {
  var x: CGFloat = 0
  var y: CGFloat = 0
  var angle: Double = 0
  var scaleX: CGFloat = 1
  var scaleY: CGFloat = 1
  var opacity: Double = 1
  var spin: Double = 0

  /// Settles without a wobble once the move's energy is spent.
  private static let land = Spring(response: 0.42, dampingRatio: 0.62)
  private static let glide = Spring(response: 0.5, dampingRatio: 0.78)

  @KeyframesBuilder<RoofMotion>
  static func keyframes(for glyph: RoofGlyph) -> some Keyframes<RoofMotion> {
    KeyframeTrack(\.x) {
      switch glyph {
      case .plane:
        // A short draw back, off to the top right, then in again from the bottom
        // left, as if it had flown a loop behind the bar.
        CubicKeyframe(-3, duration: 0.1)
        CubicKeyframe(30, duration: 0.26)
        MoveKeyframe(-24)
        LinearKeyframe(-24, duration: 0.12)
        SpringKeyframe(0, duration: 0.55, spring: glide)
      case .stairs:
        // Two steps up and to the right, then back down.
        CubicKeyframe(2.5, duration: 0.12)
        LinearKeyframe(2.5, duration: 0.05)
        CubicKeyframe(5, duration: 0.12)
        SpringKeyframe(0, duration: 0.4, spring: land)
      default:
        LinearKeyframe(0, duration: 0.01)
      }
    }
    KeyframeTrack(\.y) {
      switch glyph {
      case .plane:
        CubicKeyframe(3, duration: 0.1)
        CubicKeyframe(-26, duration: 0.26)
        MoveKeyframe(16)
        LinearKeyframe(16, duration: 0.12)
        SpringKeyframe(0, duration: 0.55, spring: glide)
      case .house:
        // Crouch, hop, land.
        LinearKeyframe(0, duration: 0.09)
        CubicKeyframe(-7, duration: 0.17)
        CubicKeyframe(0, duration: 0.15)
      case .mailbox:
        // The letter drops in: the box gives a little.
        LinearKeyframe(0, duration: 0.1)
        CubicKeyframe(2.2, duration: 0.08)
        SpringKeyframe(0, duration: 0.4, spring: land)
      case .stairs:
        CubicKeyframe(-3, duration: 0.12)
        LinearKeyframe(-3, duration: 0.05)
        CubicKeyframe(-6, duration: 0.12)
        SpringKeyframe(0, duration: 0.4, spring: land)
      default:
        LinearKeyframe(0, duration: 0.01)
      }
    }
    KeyframeTrack(\.angle) {
      switch glyph {
      case .plane:
        // Nose up on the climb, level again on the way back in.
        CubicKeyframe(6, duration: 0.1)
        CubicKeyframe(-12, duration: 0.26)
        MoveKeyframe(10)
        LinearKeyframe(10, duration: 0.12)
        SpringKeyframe(0, duration: 0.55, spring: glide)
      case .mailbox:
        LinearKeyframe(0, duration: 0.1)
        CubicKeyframe(-6, duration: 0.08)
        CubicKeyframe(4, duration: 0.1)
        SpringKeyframe(0, duration: 0.35, spring: land)
      default:
        LinearKeyframe(0, duration: 0.01)
      }
    }
    KeyframeTrack(\.scaleX) {
      switch glyph {
      case .plane:
        CubicKeyframe(0.92, duration: 0.1)
        CubicKeyframe(0.65, duration: 0.26)
        MoveKeyframe(0.75)
        LinearKeyframe(0.75, duration: 0.12)
        SpringKeyframe(1, duration: 0.55, spring: glide)
      case .house:
        // Squash and stretch, mirrored in scaleY.
        CubicKeyframe(1.12, duration: 0.09)
        CubicKeyframe(0.94, duration: 0.12)
        CubicKeyframe(1, duration: 0.14)
        CubicKeyframe(1.1, duration: 0.06)
        SpringKeyframe(1, duration: 0.35, spring: land)
      case .mailbox, .stairs:
        LinearKeyframe(1, duration: 0.01)
      default:
        CubicKeyframe(1.14, duration: 0.12)
        SpringKeyframe(1, duration: 0.4, spring: land)
      }
    }
    KeyframeTrack(\.scaleY) {
      switch glyph {
      case .plane:
        CubicKeyframe(0.92, duration: 0.1)
        CubicKeyframe(0.65, duration: 0.26)
        MoveKeyframe(0.75)
        LinearKeyframe(0.75, duration: 0.12)
        SpringKeyframe(1, duration: 0.55, spring: glide)
      case .house:
        CubicKeyframe(0.86, duration: 0.09)
        CubicKeyframe(1.08, duration: 0.12)
        CubicKeyframe(1, duration: 0.14)
        CubicKeyframe(0.9, duration: 0.06)
        SpringKeyframe(1, duration: 0.35, spring: land)
      case .mailbox, .stairs:
        LinearKeyframe(1, duration: 0.01)
      default:
        CubicKeyframe(1.14, duration: 0.12)
        SpringKeyframe(1, duration: 0.4, spring: land)
      }
    }
    KeyframeTrack(\.opacity) {
      switch glyph {
      case .plane:
        // Gone while off stage, back as it glides in.
        LinearKeyframe(1, duration: 0.2)
        LinearKeyframe(0, duration: 0.16)
        LinearKeyframe(0, duration: 0.12)
        LinearKeyframe(1, duration: 0.2)
      default:
        LinearKeyframe(1, duration: 0.01)
      }
    }
    KeyframeTrack(\.spin) {
      switch glyph {
      case .vent:
        // Caught by the wind, it turns one and a half times and slows to a stop on
        // the same rib pattern it started from.
        CubicKeyframe(0.25, duration: 0.18)
        CubicKeyframe(1.5, duration: 0.9, endVelocity: 0)
      default:
        LinearKeyframe(0, duration: 0.01)
      }
    }
  }
}

/// A lit moon disc in the night's phase: `phase` 0 is new, 0.5 full. The terminator is
/// the true ellipse (`MoonPhaseShape`), so crescents and gibbous moons both read right.
struct MoonDisc: View {
  var phase: Double
  var body: some View {
    MoonPhaseShape(phase: phase).fill(.foreground)
      .aspectRatio(1, contentMode: .fit)
  }
}
