import SwiftUI

/// An icon for the first line of text. It is as tall as one line of the surrounding font
/// and centred in it, so beside wrapped text (set the row's alignment to `.top`) it sits
/// level with the first line rather than hanging from its baseline.
struct WalletLineIcon: View {
  let systemName: String
  var body: some View {
    ZStack {
      Text(verbatim: " ").hidden()
      Image(systemName: systemName)
    }
    .accessibilityHidden(true)
  }
}
