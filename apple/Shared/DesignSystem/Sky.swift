import SwiftUI

/// The sky over the roof. By day (light appearance) a pale sky warming to the horizon,
/// the sun as it stands at this hour and clouds like smoke drifting by in two layers. By
/// night (dark) deep indigo, twinkling stars, now and then a shooting star, the moon in
/// tonight's real phase and a few long, moonlit drifts that dim the stars behind them.
/// With Lights out the stars and shooting stars are gone and the moon and clouds stay.
/// Drawn in one Canvas. With Reduce Motion (or `animated: false`) it holds still.
struct SkyBackdrop: View {
  var animated = true
  /// Draws the sun or moon. Off where a screen puts its own focal point there.
  var celestial = true
  /// Where the sun or moon sits, as a fraction of the size.
  var celestialAnchor = UnitPoint(x: 0.84, y: 0.22)
  /// The sky fades into the canvas over its last part, so content below continues it.
  var fadesIntoCanvas = true
  /// How dense the clouds are, 1 being a page's sky. Sheets thin them out, so the text
  /// laid over them stays the clearest thing there.
  var clouds: Double = 1
  @Environment(\.colorScheme) private var scheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @LightsOut private var lightsOut

  var body: some View {
    let night = scheme == .dark
    let moving = animated && !reduceMotion
    let stars = night && !lightsOut
    ZStack {
      LinearGradient(
        colors: [WalletTheme.skyTop, WalletTheme.skyBottom], startPoint: .top, endPoint: .bottom)
      if fadesIntoCanvas {
        LinearGradient(
          stops: [
            .init(color: .clear, location: 0.55),
            .init(color: WalletTheme.canvas, location: 1),
          ], startPoint: .top, endPoint: .bottom)
      }
      TimelineView(.animation(minimumInterval: 1 / 30, paused: !moving)) { timeline in
        let time = moving ? timeline.date.timeIntervalSinceReferenceDate : 0
        Canvas { context, size in
          if stars {
            Self.drawStars(&context, size: size, time: time)
            if moving { Self.drawShootingStar(&context, size: size, time: time) }
          }
          if clouds > 0 {
            Self.drawClouds(&context, size: size, time: time, night: night, density: clouds)
          }
        }
      }
      if celestial {
        GeometryReader { box in
          let size = night ? min(64, box.size.width * 0.15) : min(70, box.size.width * 0.17)
          // The whole glow stays inside the sky (and below the Mac's title bar), so it
          // fades out on its own instead of being cut by an edge.
          let glow = size * (night ? 1.4 : 1.5)
          Group {
            if night {
              NightMoon(size: size)
            } else {
              DaySun(size: size, animated: moving)
            }
          }
          .position(
            x: min(
              max(box.size.width * celestialAnchor.x, glow), box.size.width - glow * 0.6),
            y: max(box.size.height * celestialAnchor.y, glow + Self.headerClearance))
        }
      }
    }
    .accessibilityHidden(true)
    .allowsHitTesting(false)
  }

  /// The Mac's title bar sits over the top of the window's content.
  static var headerClearance: CGFloat {
    #if os(macOS)
      28
    #else
      0
    #endif
  }

  // MARK: Night

  /// Deterministic stars: the same sky on every launch, denser near the zenith.
  private static let stars: [(x: Double, y: Double, r: Double, phase: Double, speed: Double)] = {
    var generator = SeededRandom(seed: 0x5EED_0F_5AF)
    return (0..<90).map { _ in
      let y = pow(generator.next(), 1.6)
      return (
        generator.next(), y * 0.85, 0.35 + generator.next() * 1.1, generator.next() * 6.28,
        0.6 + generator.next() * 1.8
      )
    }
  }()

  private static func drawStars(_ context: inout GraphicsContext, size: CGSize, time: Double) {
    for star in stars {
      let twinkle = time == 0 ? 0.8 : 0.55 + 0.45 * sin(time * star.speed + star.phase)
      let fade = 1 - star.y * 0.9
      let rect = CGRect(
        x: star.x * size.width - star.r, y: star.y * size.height - star.r, width: star.r * 2,
        height: star.r * 2)
      context.fill(
        Path(ellipseIn: rect), with: .color(Color.white.opacity(max(0, twinkle * fade))))
      if star.r > 1.25 {
        // The brightest few get a soft cross of light.
        let glow = Color(red: 1, green: 0.93, blue: 0.8).opacity(0.35 * twinkle * fade)
        var cross = Path()
        cross.move(to: CGPoint(x: rect.midX - star.r * 3, y: rect.midY))
        cross.addLine(to: CGPoint(x: rect.midX + star.r * 3, y: rect.midY))
        cross.move(to: CGPoint(x: rect.midX, y: rect.midY - star.r * 3))
        cross.addLine(to: CGPoint(x: rect.midX, y: rect.midY + star.r * 3))
        context.stroke(cross, with: .color(glow), lineWidth: 0.6)
      }
    }
  }

  /// Every eleven seconds a star falls for under a second, somewhere different each time.
  private static func drawShootingStar(_ context: inout GraphicsContext, size: CGSize, time: Double)
  {
    let period = 11.0
    let cycle = floor(time / period)
    let t = (time - cycle * period) / 0.9
    guard t >= 0, t <= 1 else { return }
    var generator = SeededRandom(seed: UInt64(cycle) &* 2_654_435_761 &+ 7)
    let start = CGPoint(
      x: size.width * (0.15 + 0.6 * generator.next()), y: size.height * 0.08 * generator.next())
    let travel = CGVector(dx: size.width * 0.35, dy: size.height * 0.22)
    let head = CGPoint(x: start.x + travel.dx * t, y: start.y + travel.dy * t)
    let tail = CGPoint(x: head.x - travel.dx * 0.28, y: head.y - travel.dy * 0.28)
    let alpha = sin(t * .pi)
    context.stroke(
      Path { p in
        p.move(to: tail)
        p.addLine(to: head)
      },
      with: .linearGradient(
        Gradient(colors: [.clear, Color.white.opacity(0.9 * alpha)]), startPoint: tail,
        endPoint: head),
      style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
  }

  // MARK: Clouds

  /// A cloud's place and character. Far ones are smaller, fainter and slower, near ones
  /// larger and quicker, so the sky has depth. `flatness` stretches a cloud into a long,
  /// low drift (the night's clouds).
  private struct Cloud {
    let y: Double
    let scale: Double
    let speed: Double
    let offset: Double
    let seed: UInt64
    let near: Bool
    var flatness: Double = 1
  }
  private static let dayClouds: [Cloud] = [
    Cloud(y: 0.12, scale: 0.6, speed: 2.0, offset: 0.78, seed: 11, near: false),
    Cloud(y: 0.32, scale: 0.5, speed: 1.6, offset: 0.30, seed: 12, near: false),
    Cloud(y: 0.46, scale: 0.65, speed: 2.4, offset: 0.55, seed: 13, near: false),
    Cloud(y: 0.20, scale: 1.1, speed: 4.6, offset: 0.06, seed: 14, near: true),
    Cloud(y: 0.38, scale: 0.9, speed: 3.8, offset: 0.60, seed: 15, near: true),
  ]
  private static let nightClouds: [Cloud] = [
    Cloud(y: 0.24, scale: 1.4, speed: 2.0, offset: 0.18, seed: 21, near: true, flatness: 0.5),
    Cloud(y: 0.42, scale: 1.0, speed: 1.3, offset: 0.68, seed: 22, near: false, flatness: 0.45),
    Cloud(y: 0.13, scale: 0.8, speed: 1.0, offset: 0.46, seed: 23, near: false, flatness: 0.4),
  ]

  /// One wisp of a cloud: where it sits in the cloud (a fraction of its width) and how
  /// big and dense it is.
  private struct Wisp {
    let x: Double
    let y: Double
    let radius: Double
    let density: Double
  }

  /// A cloud as smoke: a loose cluster of wisps, densest and highest in the middle,
  /// thinning toward the ends. Each cloud's cluster comes from its seed, so it keeps its
  /// shape as it drifts and on every launch.
  private static func wisps(_ cloud: Cloud) -> [Wisp] {
    var generator = SeededRandom(seed: cloud.seed)
    let count = 7 + Int(generator.next() * 4)
    return (0..<count).map { index in
      let t = (Double(index) + generator.next()) / Double(count)
      let heap = sin(t * .pi)
      return Wisp(
        x: t, y: -0.12 * heap * cloud.flatness + (generator.next() - 0.5) * 0.08,
        radius: 0.16 + 0.16 * heap + 0.06 * generator.next(),
        density: 0.45 + 0.55 * heap)
    }
  }

  /// Each cloud is drawn as soft radial puffs that fade to nothing at their edges, all
  /// blurred together, so no outline or base line ever shows: it thins out into the sky
  /// like smoke. By day it is white with a faintly cooler underside. By night it is a
  /// pale, moonlit grey at low density that dims the stars behind it.
  private static func drawClouds(
    _ context: inout GraphicsContext, size: CGSize, time: Double, night: Bool, density: Double
  ) {
    for cloud in night ? nightClouds : dayClouds {
      let width = 170 * cloud.scale
      let span = size.width + width * 2
      let x =
        (cloud.offset * span + time * cloud.speed).truncatingRemainder(dividingBy: span) - width
      let origin = CGPoint(x: x, y: cloud.y * size.height)
      let strength = (night ? 0.5 : 0.85) * (cloud.near ? 1 : 0.6) * density
      let top: Color =
        night ? Color(red: 0.72, green: 0.75, blue: 0.88) : Color.white
      let bottom: Color =
        night
        ? Color(red: 0.42, green: 0.45, blue: 0.62) : Color(red: 0.86, green: 0.89, blue: 0.96)
      context.drawLayer { layer in
        layer.addFilter(.blur(radius: width * (cloud.near ? 0.06 : 0.09)))
        for wisp in wisps(cloud) {
          let r = width * wisp.radius
          let center = CGPoint(
            x: origin.x + width * wisp.x, y: origin.y + width * wisp.y)
          let ellipse = CGRect(
            x: center.x - r, y: center.y - r * cloud.flatness, width: r * 2,
            height: r * 2 * cloud.flatness)
          let alpha = strength * wisp.density
          // Lighter where the light falls (the crown), cooler underneath.
          var puff = layer
          puff.fill(
            Path(ellipseIn: ellipse),
            with: .radialGradient(
              Gradient(stops: [
                .init(color: top.opacity(alpha), location: 0),
                .init(color: bottom.opacity(alpha * 0.55), location: 0.6),
                .init(color: bottom.opacity(0), location: 1),
              ]),
              center: CGPoint(x: center.x, y: center.y - r * 0.25 * cloud.flatness),
              startRadius: 0, endRadius: r))
        }
      }
    }
  }
}

/// The scenery's lights. Lights out is a calmer night: the stars and shooting stars
/// leave the sky (on every page and in every sheet), the city's windows stay dark and
/// the signs' bulbs are off. The moon and the clouds stay. A sign's bulbs still run
/// while its account refreshes: that is a status, not decoration.
@propertyWrapper
struct LightsOut: DynamicProperty {
  @AppStorage(WalletStorageKey.lightsOut.rawValue) private var stored = false
  var wrappedValue: Bool {
    get { stored }
    nonmutating set { stored = newValue }
  }
  var projectedValue: Binding<Bool> { $stored }
}

/// The ambient backdrop of every page: a band of sky at the top that fades into the
/// canvas, with a far skyline on its horizon. Static, so it costs nothing while scrolling.
struct WalletBackdrop: View {
  var skyHeight: CGFloat = 260
  /// Cloud density (see `SkyBackdrop.clouds`).
  var clouds: Double = 1
  var body: some View {
    ZStack(alignment: .top) {
      WalletTheme.canvas
      ZStack(alignment: .bottom) {
        SkyBackdrop(animated: false, celestial: false, fadesIntoCanvas: true, clouds: clouds)
        // Windows off: on a faded skyline they would float.
        SkylineView(
          seed: 21, color: WalletTheme.skylineFar.opacity(0.35), relief: 0.8, windows: false
        )
        .frame(height: skyHeight * 0.32)
        .mask(
          LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
        )
      }
      .frame(height: skyHeight)
    }
    .ignoresSafeArea()
    .accessibilityHidden(true)
  }
}
