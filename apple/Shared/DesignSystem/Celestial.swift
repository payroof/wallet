import SwiftUI

/// Tonight's moon, in its real phase: a halo as bright as the moon is full, the dark
/// part faintly visible (earthshine), and on larger moons the grey seas of its face.
struct NightMoon: View {
  var size: CGFloat = 56
  var body: some View {
    let phase = LunarPhase.now()
    let lit = LunarPhase.illumination(phase)
    ZStack {
      Circle().fill(
        RadialGradient(
          colors: [WalletTheme.lamp.opacity(0.1 + 0.22 * lit), .clear], center: .center,
          startRadius: size * 0.3,
          endRadius: size * 1.4)
      )
      .frame(width: size * 2.8, height: size * 2.8)
      // The unlit part is faintly visible (earthshine), so the disc reads at any phase.
      Circle().fill(Color.white.opacity(0.07)).frame(width: size, height: size)
      ZStack {
        Circle().fill(
          RadialGradient(
            colors: [
              Color(red: 1, green: 0.98, blue: 0.9), Color(red: 0.95, green: 0.87, blue: 0.7),
            ],
            center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: size * 0.6))
        if size >= 28 { MoonSeas() }
      }
      .frame(width: size, height: size)
      .mask { MoonPhaseShape(phase: phase) }
      .shadow(color: WalletTheme.lamp.opacity(0.35 * lit), radius: size * 0.12)
    }
    .accessibilityHidden(true)
  }
}

/// The darker seas (maria) on the moon's near side, roughly where they really are.
private struct MoonSeas: View {
  var body: some View {
    Canvas { context, size in
      let seas: [(x: Double, y: Double, r: Double)] = [
        (0.36, 0.3, 0.13), (0.55, 0.26, 0.1), (0.62, 0.45, 0.12), (0.42, 0.52, 0.09),
        (0.3, 0.62, 0.07), (0.58, 0.7, 0.06),
      ]
      context.addFilter(.blur(radius: size.width * 0.025))
      for sea in seas {
        let r = sea.r * size.width
        context.fill(
          Path(
            ellipseIn: CGRect(
              x: sea.x * size.width - r, y: sea.y * size.height - r * 0.85, width: r * 2,
              height: r * 1.7)),
          with: .color(Color(red: 0.62, green: 0.58, blue: 0.52).opacity(0.22)))
      }
    }
    .accessibilityHidden(true)
  }
}

/// The lit part of the moon: the bright limb on one side and the terminator, an
/// ellipse that sweeps across the disc as the month goes on. `phase` 0 is new, 0.25 the
/// first quarter (right half lit), 0.5 full, 0.75 the last quarter.
struct MoonPhaseShape: Shape {
  var phase: Double
  func path(in rect: CGRect) -> Path {
    let r = min(rect.width, rect.height) / 2
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let side: CGFloat = phase.truncatingRemainder(dividingBy: 1) < 0.5 ? 1 : -1
    // +1 at new moon (terminator on the lit limb), −1 at full (on the opposite limb).
    let sweep = CGFloat(cos(2 * .pi * phase))
    let steps = 48
    var path = Path()
    for index in 0...steps {
      let angle = -CGFloat.pi / 2 + .pi * CGFloat(index) / CGFloat(steps)
      let point = CGPoint(x: center.x + side * r * cos(angle), y: center.y + r * sin(angle))
      if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    for index in 0...steps {
      let angle = CGFloat.pi / 2 - .pi * CGFloat(index) / CGFloat(steps)
      path.addLine(
        to: CGPoint(x: center.x + side * r * sweep * cos(angle), y: center.y + r * sin(angle)))
    }
    path.closeSubpath()
    return path
  }
}

/// The sun as it stands at this hour: high and nearly white around noon, low, larger
/// and amber toward morning and evening. Faint rays turn slowly around it.
struct DaySun: View {
  var size: CGFloat = 60
  var animated = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    let height = SolarHeight.now()
    let core = Self.mix((1, 0.66, 0.32), (1, 0.95, 0.78), height)
    let rim = Self.mix((0.96, 0.5, 0.26), (1, 0.84, 0.5), height)
    let corona = Self.mix((1, 0.72, 0.42), (1, 0.93, 0.7), height)
    ZStack {
      Circle().fill(
        RadialGradient(
          colors: [corona.opacity(0.75 - 0.15 * height), corona.opacity(0.18), .clear],
          center: .center, startRadius: size * 0.35, endRadius: size * (1.6 - 0.2 * height))
      )
      .frame(width: size * 3.2, height: size * 3.2)
      if size >= 28 {
        TimelineView(.animation(minimumInterval: 1 / 15, paused: !animated || reduceMotion)) {
          timeline in
          let turn =
            animated && !reduceMotion
            ? timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 180)
              / 180 : 0
          SunRays(color: corona.opacity(0.14 + 0.08 * height))
            .frame(width: size * 2.3, height: size * 2.3)
            .rotationEffect(.degrees(turn * 360))
        }
      }
      Circle().fill(
        RadialGradient(
          colors: [core, rim], center: UnitPoint(x: 0.45, y: 0.4), startRadius: 0,
          endRadius: size * 0.55)
      )
      .frame(width: size, height: size)
      .shadow(color: corona.opacity(0.6), radius: size * 0.15)
    }
    .accessibilityHidden(true)
  }
  private static func mix(
    _ low: (Double, Double, Double), _ high: (Double, Double, Double), _ t: Double
  ) -> Color {
    Color(
      red: low.0 + (high.0 - low.0) * t, green: low.1 + (high.1 - low.1) * t,
      blue: low.2 + (high.2 - low.2) * t)
  }
}

/// Twelve thin, tapering rays around the sun.
private struct SunRays: View {
  let color: Color
  var body: some View {
    Canvas { context, size in
      let center = CGPoint(x: size.width / 2, y: size.height / 2)
      let inner = size.width * 0.28
      let outer = size.width * 0.5
      for index in 0..<12 {
        let angle = Double(index) / 12 * 2 * .pi
        let reach = index.isMultiple(of: 2) ? outer : outer * 0.82
        let spread = 0.07
        var ray = Path()
        ray.move(
          to: CGPoint(
            x: center.x + cos(angle - spread) * inner, y: center.y + sin(angle - spread) * inner))
        ray.addLine(to: CGPoint(x: center.x + cos(angle) * reach, y: center.y + sin(angle) * reach))
        ray.addLine(
          to: CGPoint(
            x: center.x + cos(angle + spread) * inner, y: center.y + sin(angle + spread) * inner))
        ray.closeSubpath()
        context.fill(
          ray,
          with: .radialGradient(
            Gradient(colors: [color, .clear]), center: center, startRadius: inner,
            endRadius: reach))
      }
    }
    .accessibilityHidden(true)
  }
}

/// How high the sun stands, from local clock time: 0 at 6:00 and 18:00 and outside
/// those hours (when a light appearance still shows a low sun), 1 at noon.
enum SolarHeight {
  static func at(_ date: Date, calendar: Calendar = .current) -> Double {
    let parts = calendar.dateComponents([.hour, .minute], from: date)
    let hour = Double(parts.hour ?? 12) + Double(parts.minute ?? 0) / 60
    return max(0, sin((hour - 6) / 12 * .pi))
  }
  static func now() -> Double { at(Date()) }
}

/// The moon's age as a fraction of a synodic month: 0 new, 0.5 full.
enum LunarPhase {
  static func at(_ date: Date) -> Double {
    // A known new moon: 6 January 2000, 18:14 UTC.
    let reference = Date(timeIntervalSince1970: 947_182_440)
    let synodic = 29.530_588_853 * 86_400
    let age = date.timeIntervalSince(reference).truncatingRemainder(dividingBy: synodic)
    return (age < 0 ? age + synodic : age) / synodic
  }
  static func now() -> Double { at(Date()) }
  /// The lit fraction of the disc: 0 at new moon, 1 at full.
  static func illumination(_ phase: Double) -> Double { (1 - cos(2 * .pi * phase)) / 2 }
}
