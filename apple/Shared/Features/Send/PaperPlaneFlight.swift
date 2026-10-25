import SwiftUI

/// A paper plane launched from the bottom of the screen, banking up and away over the
/// roofs with a dashed trail behind it. It fades as it leaves.
struct PaperPlaneFlight: View {
  @State private var progress: CGFloat = 0
  var body: some View {
    GeometryReader { box in
      let size = box.size
      let start = CGPoint(x: size.width * 0.18, y: size.height * 0.86)
      let end = CGPoint(x: size.width * 1.12, y: size.height * 0.04)
      let c1 = CGPoint(x: size.width * 0.55, y: size.height * 0.95)
      let c2 = CGPoint(x: size.width * 0.25, y: size.height * 0.2)
      let curve = Path { p in
        p.move(to: start)
        p.addCurve(to: end, control1: c1, control2: c2)
      }
      ZStack {
        curve.trim(from: max(0, progress - 0.35), to: progress)
          .stroke(
            WalletTheme.accent.opacity(0.6),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 7]))
        RoofIcon(.plane, size: 34, weight: 2)
          .foregroundStyle(WalletTheme.accent)
          .modifier(FlightPosition(progress: progress, start: start, c1: c1, c2: c2, end: end))
      }
      .modifier(FlightFade(progress: progress))
    }
    .onAppear {
      // After the review sheet has gone down.
      withAnimation(.easeIn(duration: 1.5).delay(0.6)) { progress = 1 }
    }
    .accessibilityHidden(true)
  }
}

/// Places a view along a cubic curve at `progress`, turned to its heading.
private struct FlightPosition: ViewModifier, Animatable {
  var progress: CGFloat
  let start: CGPoint
  let c1: CGPoint
  let c2: CGPoint
  let end: CGPoint
  nonisolated var animatableData: CGFloat {
    get { progress }
    set { progress = newValue }
  }
  func body(content: Content) -> some View {
    let t = min(max(progress, 0), 1)
    let point = Self.point(t, start, c1, c2, end)
    let ahead = Self.point(min(t + 0.01, 1), start, c1, c2, end)
    let heading = atan2(ahead.y - point.y, ahead.x - point.x)
    // The glyph's nose points up and to the right (−45°).
    return
      content
      .rotationEffect(.radians(heading + .pi / 4))
      .scaleEffect(1 - 0.35 * t)
      .position(point)
  }
  private static func point(
    _ t: CGFloat, _ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint
  ) -> CGPoint {
    let u = 1 - t
    let x = u * u * u * a.x + 3 * u * u * t * b.x + 3 * u * t * t * c.x + t * t * t * d.x
    let y = u * u * u * a.y + 3 * u * u * t * b.y + 3 * u * t * t * c.y + t * t * t * d.y
    return CGPoint(x: x, y: y)
  }
}

/// Fades the flight in at launch and out as it leaves, frame by frame.
private struct FlightFade: ViewModifier, Animatable {
  var progress: CGFloat
  nonisolated var animatableData: CGFloat {
    get { progress }
    set { progress = newValue }
  }
  func body(content: Content) -> some View {
    content.opacity(
      progress < 0.03
        ? Double(progress / 0.03) : progress < 0.85 ? 1 : Double((1 - progress) / 0.15))
  }
}
