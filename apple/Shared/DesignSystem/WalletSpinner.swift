import SwiftUI

/// Activity indicator: a rooftop turbine vent seen from above, its curved vanes turning
/// in the wind. Drawn in the surrounding foreground style, so it contrasts with any
/// surface (filled buttons, sign boards, both themes). With Reduce Motion it turns
/// slowly and steadily instead of spinning. Decorative: the control it sits in carries
/// the label.
struct WalletSpinner: View {
  var size: CGFloat = 14
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    let period = reduceMotion ? 6.0 : 1.1
    // The vanes are drawn once. Only their rotation is animated.
    TurbineVanes(lineWidth: max(1.3, size / 9))
      .keyframeAnimator(initialValue: 0.0, repeating: true) { vanes, angle in
        vanes.rotationEffect(.degrees(angle))
      } keyframes: { _ in
        LinearKeyframe(360, duration: period)
      }
      .frame(width: size, height: size)
      .accessibilityHidden(true)
  }
}

/// Seven curved vanes inside a rim, the hub at the centre.
struct TurbineVanes: View {
  var lineWidth: CGFloat = 1.6
  var vanes = 7
  var body: some View {
    Canvas { context, canvas in
      let radius = min(canvas.width, canvas.height) / 2 - lineWidth / 2
      let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
      var blades = Path()
      for index in 0..<vanes {
        let angle = Double(index) / Double(vanes) * 2 * .pi
        let start = CGPoint(
          x: center.x + cos(angle) * radius * 0.22, y: center.y + sin(angle) * radius * 0.22)
        let end = CGPoint(
          x: center.x + cos(angle + 0.9) * radius, y: center.y + sin(angle + 0.9) * radius)
        let control = CGPoint(
          x: center.x + cos(angle + 0.15) * radius * 0.85,
          y: center.y + sin(angle + 0.15) * radius * 0.85)
        blades.move(to: start)
        blades.addQuadCurve(to: end, control: control)
      }
      let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round)
      context.stroke(blades, with: .foreground, style: style)
      context.stroke(
        Path(
          ellipseIn: CGRect(
            x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
        with: .foreground, style: StrokeStyle(lineWidth: lineWidth * 0.8))
      let hub = radius * 0.2
      context.fill(
        Path(
          ellipseIn: CGRect(x: center.x - hub, y: center.y - hub, width: hub * 2, height: hub * 2)),
        with: .foreground)
    }
  }
}
