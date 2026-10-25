import SwiftUI

/// A row of buildings against the sky, generated from a seed: flat roofs, parapets, a
/// water tower or an antenna here and there, and windows, some lit (more at night).
struct SkylineView: View {
  var seed: UInt64 = 7
  var color: Color = WalletTheme.skylineFar
  /// Tallest building as a fraction of the height.
  var relief: Double = 1
  var windows = true
  /// Lights go on and off now and then, and a television flickers here and there.
  var animated = false
  @Environment(\.colorScheme) private var scheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @LightsOut private var lightsOut

  var body: some View {
    let night = scheme == .dark
    let live = animated && night && windows && !lightsOut && !reduceMotion
    TimelineView(.animation(minimumInterval: 1 / 10, paused: !live)) { timeline in
      let time = live ? timeline.date.timeIntervalSinceReferenceDate : 0
      skyline(night: night, time: time)
    }
    .accessibilityHidden(true)
    .allowsHitTesting(false)
  }

  private func skyline(night: Bool, time: Double) -> some View {
    Canvas { context, size in
      var generator = SeededRandom(seed: seed)
      var building = 0
      var x: CGFloat = -8
      while x < size.width {
        let width = CGFloat(26 + generator.next() * 46)
        let height = size.height * CGFloat(0.35 + generator.next() * 0.65 * relief)
        let rect = CGRect(x: x, y: size.height - height, width: width, height: height)
        context.fill(Path(rect), with: .color(color))
        // Parapet lip.
        context.fill(
          Path(CGRect(x: rect.minX - 1.5, y: rect.minY, width: width + 3, height: 2.5)),
          with: .color(color))
        let prop = generator.next()
        if prop < 0.18 {
          // Water tower on legs.
          let tower = CGRect(x: rect.minX + width * 0.2, y: rect.minY - 16, width: 12, height: 9)
          context.fill(Path(tower), with: .color(color))
          var roof = Path()
          roof.addLines([
            CGPoint(x: tower.minX - 1, y: tower.minY), CGPoint(x: tower.midX, y: tower.minY - 5),
            CGPoint(x: tower.maxX + 1, y: tower.minY),
          ])
          context.fill(roof, with: .color(color))
          context.stroke(
            Path { p in
              p.move(to: CGPoint(x: tower.minX + 2, y: tower.maxY))
              p.addLine(to: CGPoint(x: tower.minX + 1, y: rect.minY))
              p.move(to: CGPoint(x: tower.maxX - 2, y: tower.maxY))
              p.addLine(to: CGPoint(x: tower.maxX - 1, y: rect.minY))
            }, with: .color(color), lineWidth: 1.2)
        } else if prop < 0.32 {
          // Antenna.
          let mastX = rect.minX + width * 0.7
          context.stroke(
            Path { p in
              p.move(to: CGPoint(x: mastX, y: rect.minY))
              p.addLine(to: CGPoint(x: mastX, y: rect.minY - 18))
              p.move(to: CGPoint(x: mastX - 4, y: rect.minY - 12))
              p.addLine(to: CGPoint(x: mastX + 4, y: rect.minY - 12))
            }, with: .color(color), lineWidth: 1.2)
        } else if prop < 0.46 {
          // Gable.
          var gable = Path()
          gable.addLines([
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.midX, y: rect.minY - width * 0.32),
            CGPoint(x: rect.maxX, y: rect.minY),
          ])
          context.fill(gable, with: .color(color))
        }
        if windows {
          Self.drawWindows(
            &context, building: rect, index: building, seed: seed, ground: size.height - 2,
            night: night, lightsOut: lightsOut, time: time)
        }
        building += 1
        // Buildings stand shoulder to shoulder, with now and then an alley between.
        x += width + (generator.next() < 0.25 ? CGFloat(6 + generator.next() * 10) : 0)
      }
    }
  }

  /// A 0..<1 value for one window, the same on every launch, independent of the
  /// building shapes' own random sequence.
  private static func hash(_ values: UInt64...) -> Double {
    var generator = SeededRandom(
      seed: values.reduce(0x51_7C_C1_B7_27_22_0A_95) { ($0 ^ $1) &* 0x100_0000_01B3 })
    return generator.next()
  }

  /// Every window of a building: dark glass (by day catching the sky), and at night a
  /// share of them lit: mostly warm lamps, some cooler, a curtain drawn here and there,
  /// and a television flickering blue. Every few seconds a light somewhere goes on or off.
  private static func drawWindows(
    _ context: inout GraphicsContext, building rect: CGRect, index: Int, seed: UInt64,
    ground: CGFloat, night: Bool, lightsOut: Bool, time: Double
  ) {
    let pitchX: CGFloat = 7.5
    let pitchY: CGFloat = 11
    let columns = max(1, Int((rect.width - 6) / pitchX))
    let rows = max(1, Int((rect.height - 8) / pitchY))
    let inset = (rect.width - CGFloat(columns) * pitchX) / 2
    for row in 0..<rows {
      for column in 0..<columns {
        let window = CGRect(
          x: rect.minX + inset + CGFloat(column) * pitchX + 2,
          y: rect.minY + 7 + CGFloat(row) * pitchY,
          width: 3.5, height: 5)
        guard window.maxY < ground else { continue }
        let id = hash(seed, UInt64(index), UInt64(row), UInt64(column))
        guard night else {
          // Glass reflecting the sky, a few panes catching the sun.
          context.fill(
            Path(window), with: .color(Color.white.opacity(id > 0.93 ? 0.55 : 0.12 + 0.12 * id)))
          continue
        }
        var lit = !lightsOut && id < 0.27
        if time > 0 {
          // Each window has its own clock. Now and then its light switches.
          let period = floor(time / 7 + id * 13)
          if hash(UInt64(id * 1e9), UInt64(period)) < 0.07 { lit.toggle() }
        }
        guard lit else {
          context.fill(Path(window), with: .color(Color.white.opacity(0.035)))
          continue
        }
        let kind = hash(UInt64(id * 1e9), 7)
        var color = ScenePalette.bulb
        var strength = 0.8
        if kind > 0.62 { color = Color(red: 1, green: 0.62, blue: 0.3) }
        if kind > 0.82 { color = Color(red: 0.86, green: 0.92, blue: 1) }
        if kind > 0.94 {
          color = Color(red: 0.5, green: 0.68, blue: 1)
          strength = time > 0 ? 0.45 + 0.4 * abs(sin(time * 6 + id * 50) * sin(time * 2.3)) : 0.7
        }
        context.fill(
          Path(window.insetBy(dx: -1.4, dy: -1.4)), with: .color(color.opacity(0.16 * strength)))
        let curtain = hash(UInt64(id * 1e9), 3) < 0.2
        let pane =
          curtain
          ? CGRect(x: window.minX, y: window.midY, width: window.width, height: window.height / 2)
          : window
        context.fill(Path(pane), with: .color(color.opacity(strength)))
      }
    }
  }
}

/// A tiny, fast, deterministic generator (SplitMix64) for scenery that looks the same
/// on every launch. Never used for anything secret.
struct SeededRandom {
  private var state: UInt64
  init(seed: UInt64) { state = seed }
  mutating func next() -> Double {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    z ^= z >> 31
    return Double(z >> 11) / Double(1 << 53)
  }
}
