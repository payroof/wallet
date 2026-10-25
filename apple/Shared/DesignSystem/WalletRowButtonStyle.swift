import SwiftUI

/// Full-row button feedback: hover on macOS, pressed tint on both platforms.
struct WalletRowButtonStyle: ButtonStyle {
  var radius: CGFloat = WalletMetrics.radiusSmall
  func makeBody(configuration: Configuration) -> some View {
    WalletRowBody(configuration: configuration, radius: radius)
  }
}

private struct WalletRowBody: View {
  let configuration: ButtonStyleConfiguration
  let radius: CGFloat
  @State private var hovering = false
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    configuration.label
      .background(
        WalletTheme.text.opacity(
          configuration.isPressed ? 0.07 : (hovering && isEnabled ? 0.04 : 0)),
        in: RoundedRectangle(cornerRadius: radius, style: .continuous)
      )
      .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
      .onHover { hovering = $0 }
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
      .animation(
        reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.7),
        value: configuration.isPressed
      )
      .opacity(isEnabled ? 1 : 0.5)
  }
}
