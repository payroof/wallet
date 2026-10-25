import SwiftUI

/// The page after the last account: a building site. The outline of a sign still to be
/// put up, scaffolding where its legs will stand, a tower crane with a load of bricks
/// swaying on its hook, a pallet, a cone, and hazard tape along the roof's edge.
struct BuildingSite: View {
  /// An account is being created: the sign says so and the crane works faster.
  var building = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    GeometryReader { box in
      VStack(spacing: 0) {
        let shape = RoundedRectangle(cornerRadius: AccountCard.radius, style: .continuous)
        VStack(spacing: 10) {
          if building {
            WalletSpinner(size: 28)
          } else {
            Image(systemName: "plus").font(.title.weight(.semibold))
          }
          Text(building ? "Building…" : "New account").roofStencil(14, tracking: 2)
        }
        .animation(.easeInOut(duration: 0.2), value: building)
        .foregroundStyle(WalletTheme.text.opacity(0.75))
        .frame(maxWidth: .infinity)
        .frame(height: AccountCard.signHeight(box.size.width))
        .background(WalletTheme.surface.opacity(0.35), in: shape)
        .overlay(
          shape.strokeBorder(
            WalletTheme.text.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
        )
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
          let time =
            reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate * (building ? 4 : 1)
          Canvas { graphics, size in
            Self.draw(&graphics, size: size, time: time, silhouette: WalletTheme.steel)
          }
        }
        .frame(height: AccountCard.base)
      }
    }
    .contentShape(Rectangle())
  }

  private static func draw(
    _ g: inout GraphicsContext, size: CGSize, time: Double, silhouette: Color
  ) {
    let w = size.width
    let h = size.height
    let ground = h - 5
    // Scaffolding where the sign's legs will go: poles, two plank levels, braces.
    var scaffold = Path()
    let left = w * 0.24
    let right = w * 0.76
    for index in 0...4 {
      let x = left + (right - left) * CGFloat(index) / 4
      scaffold.move(to: CGPoint(x: x, y: 0))
      scaffold.addLine(to: CGPoint(x: x, y: ground))
    }
    for y in [h * 0.3, h * 0.66] {
      scaffold.move(to: CGPoint(x: left - 4, y: y))
      scaffold.addLine(to: CGPoint(x: right + 4, y: y))
    }
    for index in 0..<4 {
      let x0 = left + (right - left) * CGFloat(index) / 4
      let x1 = left + (right - left) * CGFloat(index + 1) / 4
      scaffold.move(to: CGPoint(x: x0, y: index.isMultiple(of: 2) ? h * 0.3 : h * 0.66))
      scaffold.addLine(to: CGPoint(x: x1, y: index.isMultiple(of: 2) ? h * 0.66 : h * 0.3))
    }
    g.stroke(scaffold, with: .color(silhouette.opacity(0.75)), lineWidth: 1.3)
    // Planks on the levels.
    for y in [h * 0.3, h * 0.66] {
      g.fill(
        Path(CGRect(x: left - 4, y: y - 3, width: right - left + 8, height: 3)),
        with: .color(silhouette))
    }
    // The tower crane: a lattice mast, its jib over the site, a counterweight behind.
    let mast = w * 0.07
    // Inside the canvas, which clips: the jib just under the sign.
    let top: CGFloat = 12
    var crane = Path()
    crane.move(to: CGPoint(x: mast - 4, y: ground))
    crane.addLine(to: CGPoint(x: mast - 4, y: top))
    crane.move(to: CGPoint(x: mast + 4, y: ground))
    crane.addLine(to: CGPoint(x: mast + 4, y: top))
    var y = ground
    var toRight = true
    crane.move(to: CGPoint(x: mast - 4, y: y))
    while y > top {
      y = max(y - 7, top)
      crane.addLine(to: CGPoint(x: toRight ? mast + 4 : mast - 4, y: y))
      toRight.toggle()
    }
    let jibEnd = w * 0.42
    crane.move(to: CGPoint(x: mast - 14, y: top))
    crane.addLine(to: CGPoint(x: jibEnd, y: top))
    crane.move(to: CGPoint(x: mast, y: top - 10))
    crane.addLine(to: CGPoint(x: jibEnd, y: top))
    crane.move(to: CGPoint(x: mast, y: top - 10))
    crane.addLine(to: CGPoint(x: mast - 14, y: top))
    g.stroke(crane, with: .color(silhouette), lineWidth: 1.4)
    g.fill(Path(CGRect(x: mast - 16, y: top, width: 9, height: 6)), with: .color(silhouette))
    // The hook and its load of bricks, swaying.
    let sway = sin(time * 1.3) * 0.08
    let pivot = CGPoint(x: jibEnd - 8, y: top)
    let cable: CGFloat = 24
    let hook = CGPoint(x: pivot.x + sin(sway) * cable, y: pivot.y + cos(sway) * cable)
    g.stroke(
      Path { p in
        p.move(to: pivot)
        p.addLine(to: hook)
      }, with: .color(silhouette), lineWidth: 1)
    var load = g
    load.translateBy(x: hook.x, y: hook.y)
    load.rotate(by: .radians(-sway))
    for row in 0..<2 {
      for column in 0..<(3 - row) {
        load.fill(
          Path(
            roundedRect: CGRect(
              x: -12 + CGFloat(column) * 8 + CGFloat(row) * 4, y: 7 - CGFloat(row) * 5, width: 7,
              height: 4), cornerRadius: 0.8),
          with: .color(ScenePalette.brick))
      }
    }
    // A pallet of bricks and a cone on the right.
    let pallet = CGRect(x: w * 0.8, y: ground - 4, width: 34, height: 4)
    g.fill(Path(pallet), with: .color(silhouette))
    for row in 0..<3 {
      for column in 0..<(4 - row) {
        g.fill(
          Path(
            roundedRect: CGRect(
              x: pallet.minX + 1 + CGFloat(column) * 8 + CGFloat(row) * 4,
              y: pallet.minY - 5 - CGFloat(row) * 5, width: 7, height: 4), cornerRadius: 0.8),
          with: .color(ScenePalette.brick))
      }
    }
    let coneX = w * 0.95
    var traffic = Path()
    traffic.addLines([
      CGPoint(x: coneX - 6, y: ground), CGPoint(x: coneX - 1.5, y: ground - 16),
      CGPoint(x: coneX + 1.5, y: ground - 16), CGPoint(x: coneX + 6, y: ground),
    ])
    traffic.closeSubpath()
    g.fill(traffic, with: .color(ScenePalette.cone))
    g.fill(
      Path(CGRect(x: coneX - 3.6, y: ground - 9, width: 7.2, height: 2.5)), with: .color(.white))
    // Hazard tape along the edge of the roof.
    var stripes = g
    stripes.clip(to: Path(CGRect(x: 0, y: ground, width: w, height: 5)))
    stripes.fill(
      Path(CGRect(x: 0, y: ground, width: w, height: 5)), with: .color(ScenePalette.hazard))
    var x: CGFloat = -10
    while x < w {
      stripes.fill(
        Path { p in
          p.addLines([
            CGPoint(x: x, y: ground + 5), CGPoint(x: x + 5, y: ground),
            CGPoint(x: x + 10, y: ground),
            CGPoint(x: x + 5, y: ground + 5),
          ])
          p.closeSubpath()
        }, with: .color(ScenePalette.hazardStripe))
      x += 10
    }
  }
}
