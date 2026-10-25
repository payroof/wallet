import SwiftUI

/// A choice shown as its current value and one chevron: a header title, or the token
/// beside the amount.
struct WalletChoiceLabel: View {
  let title: String
  var font: Font = .headline
  /// Set for sign lettering (`RoofFont.sign`) of this size: the title is centred
  /// optically and the chevron is sized to the capitals.
  var signSize: CGFloat? = nil
  var color: Color = WalletTheme.text
  var body: some View {
    HStack(alignment: .center, spacing: 5) {
      if let signSize {
        Text(title).signLettering(signSize, relativeTo: .title)
      } else {
        Text(title).font(font)
      }
      // Sized from the title, so it stays in proportion at any size.
      Image(systemName: "chevron.down")
        .font(signSize.map { .system(size: $0 * 0.45, weight: .bold) } ?? font.bold())
        .imageScale(.small)
        .foregroundStyle(WalletTheme.muted)
    }
    .foregroundStyle(color).lineLimit(1)
    .contentTransition(.interpolate)
    .contentShape(Rectangle())
  }
}
