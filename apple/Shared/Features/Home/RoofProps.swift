import SwiftUI

/// What stands on an account's roof, beside the sign's legs, chosen from the account's
/// slot so each account keeps its own roof: a water tower, twin chimneys, a turbine vent,
/// a satellite dish with solar panels, a roof garden, or a flag in the account's color.
/// Some roofs have a resident on the parapet (a cat whose eyes shine at night, or a pair
/// of pigeons). The right side is always the antenna, the account's project connection.
struct RoofProps: View {
  let slot: UInt32
  let accent: WalletAccent
  let connected: Bool
  let refreshing: Bool
  let current: Bool
  let project: () -> Void
  @Environment(\.colorScheme) private var scheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(alignment: .bottom, spacing: 0) {
      left.padding(.leading, 8)
      Spacer(minLength: 0)
      antenna.padding(.trailing, 4)
    }
    .foregroundStyle(WalletTheme.silhouette)
  }

  @ViewBuilder private var left: some View {
    switch slot % 6 {
    case 0:
      HStack(alignment: .bottom, spacing: 6) {
        WaterTower().frame(width: 40, height: 52)
        chimney(height: 22)
      }
    case 1:
      HStack(alignment: .bottom, spacing: 5) {
        chimney(height: 30)
        chimney(height: 22)
      }
    case 2:
      HStack(alignment: .bottom, spacing: 8) {
        TurbineVentProp(turning: refreshing && !reduceMotion).frame(width: 26, height: 34)
        chimney(height: 26)
      }
    case 3:
      HStack(alignment: .bottom, spacing: 6) {
        SatelliteDish().frame(width: 30, height: 34)
        SolarPanel(night: scheme == .dark).frame(width: 30, height: 20)
      }
    case 4:
      HStack(alignment: .bottom, spacing: 6) {
        RoofGarden(night: scheme == .dark).frame(width: 44, height: 34)
        chimney(height: 24)
      }
    default:
      HStack(alignment: .bottom, spacing: 8) {
        Flagpole(color: accent.cardBright, still: reduceMotion).frame(width: 30, height: 54)
        chimney(height: 20)
      }
    }
  }

  /// A brick chimney. It smokes while the account is being read.
  private func chimney(height: CGFloat) -> some View {
    VStack(spacing: 0) {
      Rectangle().frame(width: 18, height: 4)
      Rectangle().frame(width: 14, height: height)
    }
    .overlay(alignment: .top) {
      if refreshing && !reduceMotion {
        RisingSmoke().frame(width: 24, height: 40).offset(y: -40)
      }
    }
  }

  /// The mast with its warning light: blinking red "on air" when connected, dark
  /// otherwise. It is the project's button.
  private var antenna: some View {
    Button {
      WalletHaptics.tap()
      project()
    } label: {
      ZStack(alignment: .top) {
        AntennaMast().frame(width: 22, height: 56)
        WarningLight(on: connected).offset(y: -5)
      }
      .padding(.horizontal, 11)
      .frame(minWidth: 44, minHeight: 56, alignment: .bottom)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .allowsHitTesting(current)
    .help(connected ? "Project" : "Connect a project")
  }
}

/// The aircraft warning light on the antenna: a slow red blink with a halo when on.
private struct WarningLight: View {
  let on: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    TimelineView(.animation(minimumInterval: 1 / 20, paused: !on || reduceMotion)) { context in
      let pulse =
        on
        ? (reduceMotion
          ? 1 : 0.35 + 0.65 * max(0, sin(context.date.timeIntervalSinceReferenceDate * 3.2)))
        : 0
      ZStack {
        Circle().fill(Color.red.opacity(0.35 * pulse)).frame(width: 18, height: 18).blur(radius: 3)
        Circle().fill(
          on ? Color(red: 1, green: 0.25 + 0.2 * pulse, blue: 0.2) : Color.gray.opacity(0.5)
        )
        .frame(width: 6, height: 6)
      }
    }
    .frame(width: 18, height: 18)
    .accessibilityHidden(true)
  }
}

/// A lattice mast with two cross arms.
private struct AntennaMast: View {
  var body: some View {
    Canvas { context, size in
      var path = Path()
      let x = size.width / 2
      path.move(to: CGPoint(x: x, y: 2))
      path.addLine(to: CGPoint(x: x, y: size.height))
      path.move(to: CGPoint(x: x - 9, y: size.height * 0.28))
      path.addLine(to: CGPoint(x: x + 9, y: size.height * 0.28))
      path.move(to: CGPoint(x: x - 6, y: size.height * 0.46))
      path.addLine(to: CGPoint(x: x + 6, y: size.height * 0.46))
      path.move(to: CGPoint(x: x - 8, y: size.height))
      path.addLine(to: CGPoint(x: x, y: size.height * 0.66))
      path.addLine(to: CGPoint(x: x + 8, y: size.height))
      context.stroke(path, with: .foreground, lineWidth: 1.8)
    }
  }
}

/// A wooden water tower on legs, with a conical cap.
private struct WaterTower: View {
  var body: some View {
    Canvas { context, size in
      let w = size.width
      let h = size.height
      let tank = CGRect(x: w * 0.12, y: h * 0.18, width: w * 0.76, height: h * 0.42)
      var cap = Path()
      cap.addLines([
        CGPoint(x: tank.minX - 2, y: tank.minY), CGPoint(x: w / 2, y: 0),
        CGPoint(x: tank.maxX + 2, y: tank.minY),
      ])
      cap.closeSubpath()
      context.fill(cap, with: .foreground)
      context.fill(Path(roundedRect: tank, cornerRadius: 2), with: .foreground)
      var legs = Path()
      legs.move(to: CGPoint(x: tank.minX + 3, y: tank.maxY))
      legs.addLine(to: CGPoint(x: tank.minX, y: h))
      legs.move(to: CGPoint(x: tank.maxX - 3, y: tank.maxY))
      legs.addLine(to: CGPoint(x: tank.maxX, y: h))
      legs.move(to: CGPoint(x: w / 2, y: tank.maxY))
      legs.addLine(to: CGPoint(x: w / 2, y: h))
      legs.move(to: CGPoint(x: tank.minX + 2, y: tank.maxY + 4))
      legs.addLine(to: CGPoint(x: tank.maxX - 2, y: h - 2))
      legs.move(to: CGPoint(x: tank.maxX - 2, y: tank.maxY + 4))
      legs.addLine(to: CGPoint(x: tank.minX + 2, y: h - 2))
      context.stroke(legs, with: .foreground, lineWidth: 1.6)
      // Hoops round the tank, catching a little light.
      var hoops = Path()
      for f in [0.3, 0.65] {
        hoops.move(to: CGPoint(x: tank.minX, y: tank.minY + tank.height * f))
        hoops.addLine(to: CGPoint(x: tank.maxX, y: tank.minY + tank.height * f))
      }
      context.stroke(hoops, with: .color(.white.opacity(0.12)), lineWidth: 1)
    }
  }
}

/// A turbine vent seen from the side: a ribbed dome on a neck. While turning, its ribs
/// slide round.
private struct TurbineVentProp: View {
  let turning: Bool
  var body: some View {
    TimelineView(.animation(minimumInterval: 1 / 30, paused: !turning)) { context in
      let shift = turning ? context.date.timeIntervalSinceReferenceDate * 1.6 : 0
      Canvas { graphics, size in
        let w = size.width
        let h = size.height
        let dome = CGRect(x: 0, y: 0, width: w, height: h * 0.62)
        graphics.fill(Path(ellipseIn: dome), with: .foreground)
        graphics.fill(
          Path(CGRect(x: w * 0.3, y: dome.midY, width: w * 0.4, height: h - dome.midY)),
          with: .foreground)
        // Ribs: curves whose positions slide with the turn.
        var ribs = Path()
        for index in 0..<5 {
          let phase = (Double(index) / 5 + shift).truncatingRemainder(dividingBy: 1)
          let x = dome.minX + dome.width * (0.5 - 0.5 * cos(phase * .pi))
          ribs.move(to: CGPoint(x: dome.midX, y: dome.minY + 1))
          ribs.addQuadCurve(
            to: CGPoint(x: x, y: dome.maxY - 2), control: CGPoint(x: x + 3, y: dome.midY - 4))
        }
        graphics.stroke(ribs, with: .color(.white.opacity(0.16)), lineWidth: 1)
      }
    }
  }
}

/// Puffs of smoke rising and spreading from a chimney.
private struct RisingSmoke: View {
  var body: some View {
    TimelineView(.animation(minimumInterval: 1 / 30)) { context in
      let time = context.date.timeIntervalSinceReferenceDate
      Canvas { graphics, size in
        for index in 0..<5 {
          let t = (time / 2.6 + Double(index) / 5).truncatingRemainder(dividingBy: 1)
          let radius = 2.5 + 6 * t
          let center = CGPoint(
            x: size.width / 2 + sin(t * 4 + Double(index)) * 4 + t * 6,
            y: size.height - t * size.height)
          graphics.fill(
            Path(
              ellipseIn: CGRect(
                x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .color(Color.gray.opacity(0.45 * (1 - t))))
        }
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

/// A satellite dish on a short post, turned up to the sky.
private struct SatelliteDish: View {
  var body: some View {
    Canvas { context, size in
      let w = size.width
      let h = size.height
      var dish = Path()
      dish.move(to: CGPoint(x: w * 0.08, y: h * 0.18))
      dish.addQuadCurve(
        to: CGPoint(x: w * 0.86, y: h * 0.62), control: CGPoint(x: w * 0.12, y: h * 0.78))
      dish.closeSubpath()
      context.fill(dish, with: .foreground)
      var arm = Path()
      arm.move(to: CGPoint(x: w * 0.45, y: h * 0.42))
      arm.addLine(to: CGPoint(x: w * 0.78, y: h * 0.12))
      context.stroke(arm, with: .foreground, lineWidth: 1.4)
      context.fill(
        Path(ellipseIn: CGRect(x: w * 0.74, y: h * 0.06, width: 4, height: 4)), with: .foreground)
      context.fill(
        Path(CGRect(x: w * 0.42, y: h * 0.6, width: 3, height: h * 0.4)), with: .foreground)
      context.fill(
        Path(CGRect(x: w * 0.28, y: h - 3, width: w * 0.32, height: 3)), with: .foreground)
    }
  }
}

/// A tilted solar panel on its frame. Its cells catch the sky.
private struct SolarPanel: View {
  let night: Bool
  var body: some View {
    Canvas { context, size in
      let w = size.width
      let h = size.height
      var panel = Path()
      panel.addLines([
        CGPoint(x: 0, y: h * 0.7), CGPoint(x: w * 0.22, y: 0), CGPoint(x: w, y: 0),
        CGPoint(x: w * 0.78, y: h * 0.7),
      ])
      panel.closeSubpath()
      context.fill(panel, with: .foreground)
      var cells = Path()
      for f in [0.33, 0.66] {
        cells.move(to: CGPoint(x: w * 0.22 * (1 - f) + w * f * 0.78, y: 0))
        cells.addLine(to: CGPoint(x: w * f * 0.78, y: h * 0.7))
      }
      cells.move(to: CGPoint(x: w * 0.11, y: h * 0.35))
      cells.addLine(to: CGPoint(x: w * 0.89, y: h * 0.35))
      context.stroke(
        cells,
        with: .color(
          night ? Color(red: 0.4, green: 0.5, blue: 0.9).opacity(0.5) : .white.opacity(0.35)),
        lineWidth: 0.8)
      var legs = Path()
      legs.move(to: CGPoint(x: w * 0.2, y: h * 0.7))
      legs.addLine(to: CGPoint(x: w * 0.2, y: h))
      legs.move(to: CGPoint(x: w * 0.8, y: h * 0.3))
      legs.addLine(to: CGPoint(x: w * 0.8, y: h))
      context.stroke(legs, with: .foreground, lineWidth: 1.4)
    }
  }
}

/// A planter box with two small trees. By night a string of lights runs between them.
private struct RoofGarden: View {
  let night: Bool
  @LightsOut private var lightsOut
  var body: some View {
    Canvas { context, size in
      let w = size.width
      let h = size.height
      context.fill(Path(CGRect(x: 0, y: h - 9, width: w, height: 9)), with: .foreground)
      for (x, r) in [(w * 0.27, w * 0.2), (w * 0.72, w * 0.16)] {
        context.fill(
          Path(CGRect(x: x - 1, y: h - 9 - r * 1.1, width: 2, height: r * 1.1)), with: .foreground)
        context.fill(
          Path(ellipseIn: CGRect(x: x - r, y: h - 9 - r * 2.7, width: r * 2, height: r * 2)),
          with: .foreground)
      }
      if night && !lightsOut {
        for index in 0..<5 {
          let t = CGFloat(index) / 4
          let x = w * (0.27 + 0.45 * t)
          let y = h * 0.42 + sin(t * .pi) * 5
          context.fill(
            Path(ellipseIn: CGRect(x: x - 1.3, y: y - 1.3, width: 2.6, height: 2.6)),
            with: .color(ScenePalette.fairyLight))
        }
      }
    }
  }
}

/// A flagpole flying the account's color. The flag ripples in the wind.
private struct Flagpole: View {
  let color: Color
  let still: Bool
  var body: some View {
    TimelineView(.animation(minimumInterval: 1 / 24, paused: still)) { context in
      let time = still ? 0 : context.date.timeIntervalSinceReferenceDate
      Canvas { graphics, size in
        let h = size.height
        graphics.fill(Path(CGRect(x: 2, y: 0, width: 2, height: h)), with: .foreground)
        graphics.fill(
          Path(ellipseIn: CGRect(x: 0.5, y: -2, width: 5, height: 5)), with: .foreground)
        var flag = Path()
        let length = size.width - 5
        flag.move(to: CGPoint(x: 4, y: 3))
        for step in 0...10 {
          let t = CGFloat(step) / 10
          flag.addLine(
            to: CGPoint(x: 4 + length * t, y: 3 + sin(time * 5 + Double(t) * 5) * 1.6 * t))
        }
        for step in (0...10).reversed() {
          let t = CGFloat(step) / 10
          flag.addLine(
            to: CGPoint(x: 4 + length * t, y: 17 + sin(time * 5 + Double(t) * 5) * 1.6 * t))
        }
        flag.closeSubpath()
        graphics.fill(flag, with: .color(color))
      }
    }
  }
}
