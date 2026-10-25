import SwiftUI

/// Center short screens in the safe viewport. Tall content scrolls from the top.
/// No offsets or fixed screen heights: PIN panels remain reachable in small windows.
struct WalletCentered<Content: View>: View {
  var width: CGFloat = 440
  /// Draws the page's sky behind the content. Off where the screen paints its own.
  var backdrop = true
  let content: Content
  init(width: CGFloat = 440, backdrop: Bool = true, @ViewBuilder content: () -> Content) {
    self.width = width
    self.backdrop = backdrop
    self.content = content()
  }
  var body: some View {
    ScrollView {
      content.padding(20).frame(maxWidth: width)
        .frame(maxWidth: .infinity)
    }
    .defaultScrollAnchor(.center, for: .alignment)
    .scrollDismissesKeyboard(.interactively)
    .walletSceneryEdge()
    .background { if backdrop { Color.clear.walletPageBackground() } }
  }
}

/// A scrolling page with an optional title and one-line purpose.
struct WalletPage<Content: View, Actions: View>: View {
  let title: String
  let subtitle: String
  var maxWidth: CGFloat = 760
  /// At least one screen tall, so vertically flexible content (an empty state)
  /// centres in the space below the title.
  var fillsHeight = false
  let content: Content
  let actions: Actions
  @State private var viewport: CGFloat = 0
  init(
    _ title: String, subtitle: String, maxWidth: CGFloat = 760, fillsHeight: Bool = false,
    @ViewBuilder content: () -> Content, @ViewBuilder actions: () -> Actions
  ) {
    self.title = title
    self.subtitle = subtitle
    self.maxWidth = maxWidth
    self.fillsHeight = fillsHeight
    self.content = content()
    self.actions = actions()
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        // A page without a title shows only its actions, at the trailing edge.
        if !title.isEmpty || Actions.self != EmptyView.self {
          HStack(spacing: 12) {
            if !title.isEmpty {
              VStack(alignment: .leading, spacing: 4) {
                Text(title).font(RoofFont.title).accessibilityAddTraits(.isHeader)
                if !subtitle.isEmpty {
                  Text(subtitle).font(.subheadline).foregroundStyle(WalletTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                }
              }
            }
            Spacer(minLength: 8)
            actions
          }
        }
        content
      }
      .padding(.horizontal, WalletMetrics.page).padding(.vertical, 20)
      .frame(minHeight: fillsHeight ? viewport : nil, alignment: .top)
      .frame(maxWidth: maxWidth, alignment: .leading)
      // The column is centered so wide windows stay balanced instead of left-heavy.
      .frame(maxWidth: .infinity, alignment: .center)
    }
    .onGeometryChange(for: CGFloat.self) {
      $0.size.height
    } action: {
      viewport = $0
    }
    .scrollDismissesKeyboard(.interactively).walletPageBackground()
  }
}

extension WalletPage where Actions == EmptyView {
  init(
    _ title: String, subtitle: String, maxWidth: CGFloat = 760, fillsHeight: Bool = false,
    @ViewBuilder content: () -> Content
  ) {
    self.init(
      title, subtitle: subtitle, maxWidth: maxWidth, fillsHeight: fillsHeight, content: content
    ) { EmptyView() }
  }
}

struct WalletCard<Content: View>: View {
  var padding: CGFloat = 16
  let content: Content
  init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
    self.padding = padding
    self.content = content()
  }
  var body: some View {
    let shape = RoundedRectangle(cornerRadius: WalletMetrics.radius, style: .continuous)
    content.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
      .background {
        // A slate tile: the surface, a hairline catching the light along its top edge,
        // and a soft shadow so it sits on the wall rather than in it.
        shape.fill(WalletTheme.surface)
          .overlay(
            shape.strokeBorder(
              LinearGradient(
                colors: [Color.white.opacity(0.10), .clear], startPoint: .top, endPoint: .center),
              lineWidth: 1)
          )
          .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
      }
      .overlay(shape.strokeBorder(WalletTheme.border.opacity(0.8), lineWidth: 1))
  }
}

/// Section title with a small copper roof marking, like signage painted on a roof.
struct WalletSectionHeader<Trailing: View>: View {
  let title: String
  var detail: String = ""
  let trailing: Trailing
  init(_ title: String, detail: String = "", @ViewBuilder trailing: () -> Trailing) {
    self.title = title
    self.detail = detail
    self.trailing = trailing()
  }
  var body: some View {
    HStack(alignment: .center, spacing: 8) {
      RoofChevron()
        .stroke(
          WalletTheme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        )
        .frame(width: 12, height: 6).accessibilityHidden(true)
      Text(title).roofStencil(13, tracking: 1.6).lineLimit(1).layoutPriority(1)
        .accessibilityAddTraits(.isHeader)
      if !detail.isEmpty {
        Text(detail).font(.subheadline).foregroundStyle(WalletTheme.muted).lineLimit(1)
          .truncationMode(.middle)
      }
      Spacer(minLength: 8)
      trailing
    }.frame(minHeight: 28)
  }
}

extension WalletSectionHeader where Trailing == EmptyView {
  init(_ title: String, detail: String = "") {
    self.init(title, detail: detail) { EmptyView() }
  }
}

/// A small uppercase label for grouped content inside a card.
struct WalletEyebrow: View {
  let text: String
  var color: Color = WalletTheme.muted
  init(_ text: String, color: Color = WalletTheme.muted) {
    self.text = text
    self.color = color
  }
  var body: some View {
    Text(text.uppercased()).font(RoofFont.eyebrow).tracking(1.4).foregroundStyle(color)
      .accessibilityAddTraits(.isHeader)
  }
}

extension View {
  /// The window's header looks the same whether or not the pointer is over it: macOS 26
  /// and later otherwise reveal the toolbar's background and separator on hover.
  /// Content that scrolls beneath it fades under the system's soft edge.
  @ViewBuilder func walletFixedHeader() -> some View {
    #if os(macOS)
      toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    #else
      self
    #endif
  }

  /// A centred screen over full-bleed scenery (welcome, setup, unlock) has nothing that
  /// scrolls under the window's title bar, so the system's top scroll edge (a blurred,
  /// tinted band ending in a line) would only cut the sky in two. It is turned off, so
  /// the sky runs unbroken up to the window's top edge.
  @ViewBuilder func walletSceneryEdge() -> some View {
    if #available(macOS 26, iOS 26, *) {
      scrollEdgeEffectHidden(true, for: .top)
    } else {
      self
    }
  }
}
