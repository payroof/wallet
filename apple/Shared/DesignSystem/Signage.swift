import SwiftUI

/// A rooftop sign board. By day it is a painted panel in the account's colors with its
/// bulbs off. By night the panel goes dark, a neon tube in the account's color runs
/// round its edge and the bulbs are lit. While `chasing`, the bulbs run round the board
/// like a theatre marquee (the account is being read).
struct SignBoard<Content: View>: View {
  let accent: WalletAccent
  var chasing = false
  var radius: CGFloat = 20
  var bulbs = true
  @ViewBuilder let content: Content
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    let night = scheme == .dark
    let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
    content
      .background {
        ZStack {
          if night {
            shape.fill(
              LinearGradient(
                colors: [
                  Color(red: 0.035, green: 0.043, blue: 0.08), accent.cardDeep.opacity(0.9),
                ], startPoint: .top, endPoint: .bottom))
          } else {
            shape.fill(
              LinearGradient(
                colors: [accent.cardDeep, accent.cardBright], startPoint: .topLeading,
                endPoint: .bottomTrailing))
            // Sunlight raking across the paint.
            shape.fill(
              RadialGradient(
                colors: [Color.white.opacity(0.10), .clear], center: UnitPoint(x: 0.15, y: 0),
                startRadius: 0, endRadius: 260))
          }
          if bulbs {
            MarqueeBulbs(night: night, chasing: chasing, inset: 9, cornerRadius: radius)
          }
        }
        .compositingGroup()
        .shadow(color: .black.opacity(night ? 0.5 : 0.22), radius: 12, y: 7)
      }
      .overlay {
        if night {
          // The neon tube, glowing in the account's color.
          shape.inset(by: 2).stroke(accent.sunrise, lineWidth: 1.6)
            .shadow(color: accent.cardBright, radius: 6)
            .shadow(color: accent.cardBright.opacity(0.6), radius: 14)
        } else {
          shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
        }
      }
  }
}

/// Bulbs set round the inside edge of a board. Lit at night. While chasing, a bright
/// run moves round them.
struct MarqueeBulbs: View {
  var night: Bool
  var chasing: Bool
  var inset: CGFloat = 9
  var spacing: CGFloat = 15
  /// The board's corner radius. The bulbs follow it round the corners.
  var cornerRadius: CGFloat = 20
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @LightsOut private var lightsOut

  var body: some View {
    let glowing = night && !lightsOut
    TimelineView(.animation(minimumInterval: 1 / 12, paused: !chasing || reduceMotion)) {
      context in
      let step = chasing ? Int(context.date.timeIntervalSinceReferenceDate * 10) : 0
      Canvas { graphics, size in
        let points = Self.points(
          in: size, inset: inset, cornerRadius: cornerRadius, spacing: spacing)
        for (index, point) in points.enumerated() {
          let hot = chasing && (index + step) % 4 == 0
          let radius: CGFloat = hot ? 2.3 : 1.7
          let rect = CGRect(
            x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
          if glowing || hot {
            graphics.fill(
              Path(ellipseIn: rect.insetBy(dx: -3, dy: -3)),
              with: .color(ScenePalette.bulb.opacity(hot ? 0.45 : 0.18)))
            graphics.fill(
              Path(ellipseIn: rect),
              with: .color(ScenePalette.bulbCore.opacity(hot ? 1 : 0.85)))
          } else {
            // Unlit glass: catching the daylight, or barely there at night.
            graphics.fill(
              Path(ellipseIn: rect), with: .color(Color.white.opacity(night ? 0.12 : 0.32)))
          }
        }
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  /// Evenly spaced points (by distance along the outline) round the board's own
  /// rounded outline, inset from its edge: along the straight runs and round each
  /// corner's arc, clockwise from the top left.
  static func points(in size: CGSize, inset: CGFloat, cornerRadius: CGFloat, spacing: CGFloat)
    -> [CGPoint]
  {
    let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
    guard rect.width > 0, rect.height > 0 else { return [] }
    // The bulbs' line runs parallel to the edge, so its corners are the board's less
    // the inset (continuous corners read a little rounder: allow for it).
    let r = min(max(cornerRadius * 1.1 - inset, 0), rect.width / 2, rect.height / 2)
    let across = rect.width - 2 * r
    let down = rect.height - 2 * r
    let arc = CGFloat.pi / 2 * r
    let length = 2 * across + 2 * down + 4 * arc
    let count = max(4, Int((length / spacing).rounded()))
    let step = length / CGFloat(count)
    // Corner centres, clockwise from top right, and the angle each arc starts at.
    let corners: [(CGPoint, CGFloat)] = [
      (CGPoint(x: rect.maxX - r, y: rect.minY + r), -.pi / 2),
      (CGPoint(x: rect.maxX - r, y: rect.maxY - r), 0),
      (CGPoint(x: rect.minX + r, y: rect.maxY - r), .pi / 2),
      (CGPoint(x: rect.minX + r, y: rect.minY + r), .pi),
    ]
    // Straight runs, clockwise from the top: start point and direction.
    let runs: [(CGPoint, CGVector, CGFloat)] = [
      (CGPoint(x: rect.minX + r, y: rect.minY), CGVector(dx: 1, dy: 0), across),
      (CGPoint(x: rect.maxX, y: rect.minY + r), CGVector(dx: 0, dy: 1), down),
      (CGPoint(x: rect.maxX - r, y: rect.maxY), CGVector(dx: -1, dy: 0), across),
      (CGPoint(x: rect.minX, y: rect.maxY - r), CGVector(dx: 0, dy: -1), down),
    ]
    var points: [CGPoint] = []
    for index in 0..<count {
      var d = CGFloat(index) * step + step / 2
      for side in 0..<4 {
        let (start, direction, run) = runs[side]
        if d <= run {
          points.append(CGPoint(x: start.x + direction.dx * d, y: start.y + direction.dy * d))
          break
        }
        d -= run
        if d <= arc {
          let (center, angle) = corners[side]
          let a = angle + (r > 0 ? d / r : 0)
          points.append(CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r))
          break
        }
        d -= arc
      }
    }
    return points
  }
}

/// Lattice steel legs that hold a sign above the roof: pairs of rails braced in a
/// zigzag, standing on the parapet.
struct SignLegs: View {
  var count = 3
  var color: Color = WalletTheme.roofEdge
  var body: some View {
    Canvas { context, size in
      let rail: CGFloat = 9
      var path = Path()
      for index in 0..<count {
        let center = size.width * (CGFloat(index) + 0.5) / CGFloat(count)
        let left = center - rail / 2
        let right = center + rail / 2
        path.move(to: CGPoint(x: left, y: 0))
        path.addLine(to: CGPoint(x: left, y: size.height))
        path.move(to: CGPoint(x: right, y: 0))
        path.addLine(to: CGPoint(x: right, y: size.height))
        var y: CGFloat = 0
        var toRight = true
        path.move(to: CGPoint(x: left, y: 0))
        while y < size.height {
          y = min(y + 8, size.height)
          path.addLine(to: CGPoint(x: toRight ? right : left, y: y))
          toRight.toggle()
        }
      }
      context.stroke(path, with: .color(color), lineWidth: 1.4)
    }
    .accessibilityHidden(true)
    .allowsHitTesting(false)
  }
}

/// The parapet that runs along the roof's edge: a coping stone on top of brick courses.
struct Parapet: View {
  var body: some View {
    VStack(spacing: 0) {
      Rectangle().fill(WalletTheme.roofEdge).frame(height: 5)
        .overlay(alignment: .top) {
          Rectangle().fill(Color.white.opacity(0.18)).frame(height: 1)
        }
      ZStack {
        LinearGradient(
          colors: [WalletTheme.brick, WalletTheme.brickDeep], startPoint: .top, endPoint: .bottom)
        BrickWall(brick: CGSize(width: 34, height: 11), color: Color.black.opacity(0.22))
      }
    }
    .accessibilityHidden(true)
  }
}
