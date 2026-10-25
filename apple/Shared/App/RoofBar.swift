import SwiftUI

/// The iOS tab bar, as a strip of slate roofing floating above the content. Each tab is
/// one of the roof's things: the house (Wallet), a paper plane (Send), the mailbox
/// (Receive), the fire stairs (Activity) and the turbine vent (Settings). A small
/// gable cap hops to the selected tab, which lights up and does its one move: smoke from
/// the chimney, the plane flying off and looping back, the mailbox raising its flag for a letter, the
/// stairs being climbed, the vent's turbine spinning (`RoofIcon`'s moves).
struct RoofBar: View {
  @Binding var selection: WalletSection
  let tabs: [WalletSection]
  @Namespace private var cap
  /// Where the cap stands. It follows `selection` with its own spring, so only the bar
  /// animates: the screens swap at once, over a sky that never moves.
  @State private var capped: WalletSection?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorScheme) private var scheme
  static let height: CGFloat = 64
  private var night: Bool { scheme == .dark }
  /// The lit tab: lamplight at night, the account's accent by day.
  private var lit: AnyShapeStyle {
    night ? AnyShapeStyle(WalletTheme.lamp) : AnyShapeStyle(WalletTheme.accent)
  }
  private var idle: Color {
    night ? WalletTheme.onRoof.opacity(0.62) : WalletTheme.muted
  }

  var body: some View {
    HStack(spacing: 0) {
      ForEach(tabs) { tab in
        item(tab)
      }
    }
    .padding(.horizontal, 6)
    .frame(height: Self.height)
    .background {
      let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
      shape.fill(WalletTheme.barFill)
        .overlay(
          // Courses of brick from edge to edge, the top course included.
          BarCourses().stroke(WalletTheme.barJoints, lineWidth: 1).clipShape(shape)
        )
        .overlay(
          shape.strokeBorder(
            LinearGradient(
              colors: night
                ? [Color.white.opacity(0.22), Color.white.opacity(0.04)]
                : [Color.white.opacity(0.9), Color(red: 0.62, green: 0.5, blue: 0.4).opacity(0.3)],
              startPoint: .top, endPoint: .bottom), lineWidth: 1)
        )
        .shadow(color: .black.opacity(night ? 0.28 : 0.13), radius: 18, y: 8)
    }
    .padding(.horizontal, 14)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Tab bar")
    .onChange(of: selection, initial: true) { _, now in
      let hop: Animation? =
        reduceMotion || capped == nil ? nil : .spring(response: 0.38, dampingFraction: 0.72)
      withAnimation(hop) { capped = now }
    }
  }

  private func item(_ tab: WalletSection) -> some View {
    let selected = tab == (capped ?? selection)
    return Button {
      guard tab != selection else { return }
      WalletHaptics.tap()
      // The screen changes in place, like the system's tab bar: no transaction reaches
      // the tabs, their sky or their scroll positions.
      var instant = Transaction()
      instant.disablesAnimations = true
      withTransaction(instant) { selection = tab }
    } label: {
      VStack(spacing: 4) {
        ZStack {
          if selected {
            // The cap: a little gable roof over the lit tab.
            RoofChevron()
              .stroke(
                night ? AnyShapeStyle(WalletTheme.sunrise) : AnyShapeStyle(WalletTheme.accent),
                style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
              )
              .frame(width: 30, height: 8)
              .offset(y: -21)
              .matchedGeometryEffect(id: "cap", in: cap)
            Circle().fill(
              night
                ? AnyShapeStyle(WalletTheme.lamp.opacity(0.16))
                : AnyShapeStyle(WalletTheme.accent.opacity(0.12))
            )
            .frame(width: 40, height: 40)
            .blur(radius: 6)
            .matchedGeometryEffect(id: "glow", in: cap)
          }
          TabGlyph(tab: tab, selected: selected)
        }
        .frame(height: 28)
        Text(tab.rawValue).roofStencil(9.5, tracking: 1)
          .lineLimit(1).minimumScaleFactor(0.7)
      }
      .foregroundStyle(selected ? lit : AnyShapeStyle(idle))
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(tab.rawValue)
    .accessibilityIdentifier("tab.\(tab.rawValue)")
    .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
  }
}

/// A tab's icon with its one move, played when the tab is selected.
private struct TabGlyph: View {
  let tab: WalletSection
  let selected: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var plays = 0

  var body: some View {
    RoofIcon(tab.glyph, size: 24, weight: selected ? 1.9 : 1.6, active: selected, play: plays)
      .overlay(alignment: .topTrailing) {
        if tab == .home && selected && !reduceMotion { ChimneySmoke().offset(x: -1, y: -11) }
      }
      .animation(
        reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.6), value: selected
      )
      .onChange(of: selected) { _, now in if now && !reduceMotion { plays += 1 } }
  }
}

/// Three puffs rising from the house's chimney and fading, on a loop.
private struct ChimneySmoke: View {
  @Environment(\.colorScheme) private var scheme
  /// Pale smoke against slate at night, grey against sandstone by day.
  private var smoke: Color { scheme == .dark ? .white : Color(red: 0.45, green: 0.45, blue: 0.5) }
  var body: some View {
    TimelineView(.animation(minimumInterval: 1 / 30)) { context in
      let time = context.date.timeIntervalSinceReferenceDate
      Canvas { graphics, size in
        for index in 0..<3 {
          let t = (time / 2.4 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
          let radius = 1.6 + 2.6 * t
          let center = CGPoint(
            x: size.width / 2 + sin(t * 5 + Double(index)) * 2.5, y: size.height - t * size.height)
          graphics.fill(
            Path(
              ellipseIn: CGRect(
                x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .color(smoke.opacity(0.5 * (1 - t))))
        }
      }
    }
    .frame(width: 12, height: 16)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

/// Brick courses across the bar in running bond, from the very top edge down: every
/// course has its joints, every other one offset by half a brick.
private struct BarCourses: Shape {
  func path(in rect: CGRect) -> Path {
    let course: CGFloat = 11
    let brick: CGFloat = 34
    var path = Path()
    var y = rect.minY
    var index = 0
    while y < rect.maxY {
      if index > 0 {
        path.move(to: CGPoint(x: rect.minX, y: y))
        path.addLine(to: CGPoint(x: rect.maxX, y: y))
      }
      var x = rect.minX + (index.isMultiple(of: 2) ? brick / 2 : 0)
      while x < rect.maxX {
        path.move(to: CGPoint(x: x, y: y))
        path.addLine(to: CGPoint(x: x, y: min(y + course, rect.maxY)))
        x += brick
      }
      y += course
      index += 1
    }
    return path
  }
}
