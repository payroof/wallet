import SwiftUI

/// Peer actions in one row when they fit the width, otherwise stacked, so no
/// button is clipped or pushed past the edge on a narrow screen. As in the platform
/// guidelines, form actions sit at the trailing edge with the main action last,
/// while `.leading` is for rows that lead with an explanation.
struct WalletActionRow<Content: View>: View {
  var spacing: CGFloat = 10
  var alignment: HorizontalAlignment = .trailing
  @ViewBuilder let content: () -> Content
  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: spacing) {
        if alignment == .trailing { Spacer(minLength: 0) }
        content()
      }
      VStack(alignment: alignment, spacing: 8) { content() }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
    }
  }
}
