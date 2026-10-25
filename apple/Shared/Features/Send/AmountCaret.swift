import SwiftUI

/// The amount's insertion point: a bar in the accent that blinks like the system's
/// (steady with Reduce Motion).
struct AmountCaret: View {
  static let width: CGFloat = 3
  let height: CGFloat
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    let bar = RoundedRectangle(cornerRadius: 1.5).fill(WalletTheme.accent)
      .frame(width: Self.width, height: height)
    if reduceMotion {
      bar
    } else {
      bar.phaseAnimator([1.0, 0.0]) { content, opacity in
        content.opacity(opacity)
      } animation: { _ in
        .easeInOut(duration: 0.5).delay(0.15)
      }
    }
  }
}
