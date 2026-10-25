import SwiftUI

struct WalletButtonStyle: ButtonStyle {
  var role: WalletButtonRole = .primary
  var expand = true
  func makeBody(configuration: Configuration) -> some View {
    WalletButtonBody(configuration: configuration, role: role, expand: expand)
  }
}

private struct WalletButtonBody: View {
  let configuration: ButtonStyleConfiguration
  let role: WalletButtonRole
  let expand: Bool
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.walletButtonFill) private var fill
  @Environment(\.walletAccent) private var accent
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hovering = false
  private var shape: Capsule { Capsule(style: .continuous) }
  var body: some View {
    let pressed = configuration.isPressed && isEnabled
    configuration.label
      .font(role == .tertiary ? .callout.weight(.medium) : .callout.weight(.semibold))
      .lineLimit(2).multilineTextAlignment(.center)
      .padding(.horizontal, role == .tertiary ? 4 : 18)
      .frame(
        maxWidth: expand ? .infinity : nil, minHeight: WalletMetrics.control,
        maxHeight: fill ? .infinity : nil
      )
      .foregroundStyle(foreground)
      .background {
        if role == .primary {
          // A glazed roof tile: the accent, lit from above, with a darker lower lip.
          shape.fill(accent.accent)
            .overlay(
              shape.fill(
                LinearGradient(
                  stops: [
                    .init(color: .white.opacity(0.22), location: 0),
                    .init(color: .white.opacity(0.0), location: 0.55),
                    .init(color: .black.opacity(0.12), location: 1),
                  ], startPoint: .top, endPoint: .bottom))
            )
            .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            .shadow(
              color: accent.accent.opacity(isEnabled ? (pressed ? 0.18 : 0.38) : 0),
              radius: pressed ? 4 : 10, y: pressed ? 2 : 5)
        } else if role != .tertiary {
          shape.fill(background)
            .shadow(color: .black.opacity(role == .secondary ? 0.05 : 0), radius: 3, y: 2)
        }
      }
      .overlay {
        // Pointer hover: a faint wash, lighter on filled buttons, darker on quiet ones.
        shape.fill(hoverWash.opacity(hovering && isEnabled && !configuration.isPressed ? 1 : 0))
          .allowsHitTesting(false)
      }
      .overlay {
        if role == .secondary || role == .destructive {
          shape.strokeBorder(
            role == .destructive ? WalletTheme.danger.opacity(0.4) : WalletTheme.border)
        }
      }
      .contentShape(shape)
      .onHover { hovering = $0 }
      .scaleEffect(pressed && !reduceMotion ? 0.965 : 1)
      .opacity(isEnabled ? (configuration.isPressed && role == .tertiary ? 0.6 : 1) : 0.45)
      .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.6), value: pressed)
  }
  private var hoverWash: Color {
    switch role {
    case .primary: Color.white.opacity(0.12)
    case .destructive: WalletTheme.danger.opacity(0.06)
    case .secondary, .tertiary: WalletTheme.text.opacity(0.05)
    }
  }
  private var foreground: Color {
    switch role {
    case .primary: accent.onAccent
    case .secondary: WalletTheme.text
    case .tertiary: accent.accent
    case .destructive: WalletTheme.danger
    }
  }
  private var background: Color {
    switch role {
    case .primary: accent.accent
    case .secondary: WalletTheme.surface
    case .tertiary: .clear
    case .destructive: WalletTheme.danger.opacity(0.08)
    }
  }
}
