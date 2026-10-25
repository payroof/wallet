import SwiftUI

/// Setup progress as a flight of stairs: one step per stage, climbed as it is done.
struct StairsProgress: View {
  let count: Int
  let current: Int
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    HStack(alignment: .bottom, spacing: 4) {
      ForEach(0..<count, id: \.self) { index in
        let done = index <= current
        UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3, style: .continuous)
          .fill(done ? AnyShapeStyle(WalletTheme.accent) : AnyShapeStyle(WalletTheme.border))
          .frame(width: 26, height: 8 + CGFloat(index) * 7)
          .overlay(alignment: .top) {
            if index == current {
              Circle().fill(WalletTheme.lamp).frame(width: 7, height: 7)
                .shadow(color: WalletTheme.lamp, radius: 4)
                .offset(y: -11)
                .transition(.scale.combined(with: .opacity))
            }
          }
      }
    }
    .frame(height: 8 + CGFloat(count - 1) * 7 + 12, alignment: .bottom)
    .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.7), value: current)
  }
}
