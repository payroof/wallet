import SwiftUI

/// The six-digit PIN pad. Above it, six arched windows in a facade light up one by one
/// as the digits go in. The keys stand against a faint brick wall. A wrong PIN shakes
/// the facade and the lights go out. While the wallet opens, the windows light in a
/// wave. Used to choose and to enter the PIN.
struct PINEntry: View {
  /// An icon key for the empty place left of 0.
  struct Accessory {
    var icon: String
    var label: String
    var action: () -> Void
  }
  @Binding var code: String
  /// Outlines the windows in the error color. The message is shown as a toast.
  var error = false
  /// While set, the windows play a wave instead of showing digits. The text is
  /// what VoiceOver reads. The row keeps its height, so the keypad never moves.
  var progress: String? = nil
  var accessory: Accessory? = nil
  var onComplete: (String) -> Void = { _ in }
  #if os(macOS)
    private static let keyWidth: CGFloat = 76
    private static let keyHeight: CGFloat = 52
    private static let spacing: CGFloat = 14
    private static let rowSpacing: CGFloat = 12
  #else
    // Comfortable thumb targets that still fit a 375-point-wide phone with room to spare.
    private static let keyWidth: CGFloat = 92
    private static let keyHeight: CGFloat = 66
    private static let spacing: CGFloat = 18
    private static let rowSpacing: CGFloat = 15
  #endif
  @FocusState private var focused: Bool
  @State private var shakes = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    VStack(spacing: 26) {
      ZStack {
        if let progress {
          working
            .transition(.opacity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(progress)
        } else {
          facade
            .transition(.opacity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(code.count) of 6 PIN digits entered")
            #if os(macOS)
              .overlay {
                SecureField("Six-digit PIN", text: $code).textFieldStyle(.plain)
                .foregroundStyle(.clear)
                .tint(.clear).opacity(0.02).focused($focused)
              }
            #endif
        }
      }
      .frame(height: 44)
      .animation(.easeOut(duration: 0.15), value: progress)
      LazyVGrid(
        columns: Array(
          repeating: GridItem(.fixed(Self.keyWidth), spacing: Self.spacing), count: 3),
        spacing: Self.rowSpacing
      ) {
        ForEach(1...9, id: \.self) { digit in key(String(digit)) }
        if let accessory {
          iconKey(accessory.icon, label: accessory.label, action: accessory.action)
        } else {
          Color.clear.frame(height: Self.keyHeight).accessibilityHidden(true)
        }
        key("0")
        iconKey("delete.left", label: "Delete last PIN digit") {
          if !code.isEmpty { code.removeLast() }
        }
      }
      .frame(width: Self.keyWidth * 3 + Self.spacing * 2)
      .padding(12)
      .background {
        BrickWall(brick: CGSize(width: 44, height: 18))
          .opacity(0.5)
          .mask(
            RadialGradient(
              colors: [.black, .clear], center: .center, startRadius: 40, endRadius: 210)
          )
          .accessibilityHidden(true)
      }
    }.frame(maxWidth: .infinity)
      .onChange(of: code) { old, value in
        let digits = String(value.filter { $0.isASCII && $0.isNumber }.prefix(6))
        if value != digits {
          code = digits
          return
        }
        if digits.count == 6 && old.count != 6 { onComplete(digits) }
      }
      .onChange(of: error) { _, now in if now { shakes += 1 } }
      .task { focused = true }
      .onChange(of: progress) { _, value in
        // Focus returns to the hidden field when the windows come back.
        if value == nil { focused = true }
      }
  }

  /// One window per digit. A wrong PIN shakes the row (not with Reduce Motion).
  private var facade: some View {
    let amplitude: CGFloat = reduceMotion ? 0 : 1
    return HStack(spacing: 12) {
      ForEach(0..<6, id: \.self) { position in
        PINWindow(lit: position < code.count, error: error)
      }
    }
    .keyframeAnimator(initialValue: CGFloat(0), trigger: shakes) { content, x in
      content.offset(x: x)
    } keyframes: { _ in
      KeyframeTrack {
        SpringKeyframe(-12 * amplitude, duration: 0.07)
        SpringKeyframe(10 * amplitude, duration: 0.07)
        SpringKeyframe(-7 * amplitude, duration: 0.07)
        SpringKeyframe(4 * amplitude, duration: 0.07)
        SpringKeyframe(0, duration: 0.1)
      }
    }
  }

  /// The windows light up one after another, left to right, in a continuous wave.
  /// With Reduce Motion they glow together.
  private var working: some View {
    TimelineView(.animation) { context in
      let time = context.date.timeIntervalSinceReferenceDate
      HStack(spacing: 12) {
        ForEach(0..<6, id: \.self) { position in
          let wave = Self.wave(time: time, position: position, calm: reduceMotion)
          PINWindow(lit: true, error: false, glow: 0.25 + 0.75 * wave)
        }
      }
    }
  }
  /// 0...1 for each window, a sixth of the period behind its left neighbour.
  private static func wave(time: TimeInterval, position: Int, calm: Bool) -> Double {
    let delay = calm ? 0 : Double(position) * 0.12
    return (sin((time - delay) * 2 * .pi / 1.2) + 1) / 2
  }
  private func key(_ digit: String) -> some View {
    Button {
      guard code.count < 6 else { return }
      WalletHaptics.tap()
      code += digit
    } label: {
      // DIN's figures sit high in their line: lowered so they centre on the key.
      Text(digit).font(RoofFont.sign(34, relativeTo: .title))
        .offset(y: SignMetrics.centering(34))
        .frame(maxWidth: .infinity, minHeight: Self.keyHeight)
        .contentShape(Rectangle())
    }
    .buttonStyle(PINKeyStyle())
    .accessibilityLabel(digit)
  }
  private func iconKey(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
    Button {
      WalletHaptics.tap()
      action()
    } label: {
      Image(systemName: icon).font(.title3)
        .frame(maxWidth: .infinity, minHeight: Self.keyHeight).contentShape(Rectangle())
    }.buttonStyle(.plain).foregroundStyle(WalletTheme.muted)
      .accessibilityLabel(label).help(label)
  }
}

/// A key: a raised block lit from above. Pressed, it sinks and glows in the accent.
private struct PINKeyStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    PINKeyBody(configuration: configuration)
  }
}

private struct PINKeyBody: View {
  let configuration: ButtonStyleConfiguration
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.isEnabled) private var isEnabled
  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
    let pressed = configuration.isPressed
    configuration.label
      .foregroundStyle(WalletTheme.text)
      .background {
        shape.fill(WalletTheme.surface)
          .overlay(shape.fill(WalletTheme.accent.opacity(pressed ? 0.22 : 0)))
          .overlay(
            shape.strokeBorder(
              LinearGradient(
                colors: [Color.white.opacity(0.35), WalletTheme.border.opacity(0.9)],
                startPoint: .top, endPoint: .bottom), lineWidth: 1)
          )
          .shadow(
            color: .black.opacity(pressed ? 0.04 : 0.10), radius: pressed ? 1 : 4,
            y: pressed ? 1 : 3)
      }
      .scaleEffect(pressed && !reduceMotion ? 0.94 : 1)
      .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.55), value: pressed)
      .opacity(isEnabled ? 1 : 0.5)
  }
}

/// One arched window of the PIN facade: dark glass when empty, warm lamplight when a
/// digit is in. `glow` scales the light (the unlocking wave).
struct PINWindow: View {
  var lit: Bool
  var error: Bool
  var glow: Double = 1
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    let shape = ArchedWindow()
    ZStack {
      shape.fill(WalletTheme.text.opacity(0.06))
      shape.fill(
        LinearGradient(
          colors: [Color(red: 1, green: 0.88, blue: 0.58), WalletTheme.lamp],
          startPoint: .top, endPoint: .bottom)
      )
      .opacity(lit ? glow : 0)
      WindowMullions()
        .stroke(
          lit ? Color.black.opacity(0.25) : WalletTheme.muted.opacity(0.35), lineWidth: 1.2)
      shape.stroke(
        error ? WalletTheme.danger : (lit ? WalletTheme.lamp : WalletTheme.muted.opacity(0.55)),
        lineWidth: 1.6)
    }
    .frame(width: 24, height: 34)
    .shadow(color: WalletTheme.lamp.opacity(lit ? 0.55 * glow : 0), radius: 9)
    // The sill under the window.
    .overlay(alignment: .bottom) {
      // Hangs 5 points below the window's bottom edge.
      Capsule().fill(WalletTheme.muted.opacity(0.45)).frame(width: 30, height: 2.5)
        .alignmentGuide(.bottom) { $0[.bottom] - 5 }
    }
    .scaleEffect(lit && !reduceMotion ? 1.0 : 0.96)
    .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.55), value: lit)
  }
}

/// A window with a round-arched head.
struct ArchedWindow: Shape {
  func path(in rect: CGRect) -> Path {
    let radius = rect.width / 2
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
    path.addArc(
      center: CGPoint(x: rect.midX, y: rect.minY + radius), radius: radius,
      startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    path.closeSubpath()
    return path
  }
}

/// The window's cross bars.
private struct WindowMullions: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.midX, y: rect.minY + 3))
    path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
    path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.55))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.55))
    return path
  }
}

/// Running-bond brickwork: courses of bricks, every other course offset by half a brick,
/// drawn as mortar lines.
struct BrickWall: View {
  var brick = CGSize(width: 48, height: 20)
  var color: Color = WalletTheme.mortar
  var lineWidth: CGFloat = 1
  var body: some View {
    Canvas { context, size in
      var mortar = Path()
      var y: CGFloat = 0
      var course = 0
      while y < size.height {
        mortar.move(to: CGPoint(x: 0, y: y))
        mortar.addLine(to: CGPoint(x: size.width, y: y))
        var x: CGFloat = course.isMultiple(of: 2) ? 0 : -brick.width / 2
        while x < size.width {
          mortar.move(to: CGPoint(x: x, y: y))
          mortar.addLine(to: CGPoint(x: x, y: min(y + brick.height, size.height)))
          x += brick.width
        }
        y += brick.height
        course += 1
      }
      context.stroke(mortar, with: .color(color), lineWidth: lineWidth)
    }
    .allowsHitTesting(false)
  }
}
