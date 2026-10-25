import SwiftUI

/// Picks one network from a compact row of round marks, each the network's colored
/// initial (the same mark as everywhere else in the app). The chosen one gets an accent
/// ring and a slight lift, and its full name is written beneath the row. Marks wrap
/// onto further lines when the width is short. A network that is turned off stays
/// selectable but is dimmed and says so in its caption.
struct WalletNetworkChooser: View {
  let networks: [WalletNetwork]
  @Binding var selection: ChainID?
  /// Locks the choice (for example while a token's network can't change).
  var locked = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.isEnabled) private var isEnabled

  private var current: WalletNetwork? { networks.first { $0.id == selection } }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      WalletFlowLayout(spacing: 6) {
        ForEach(networks) { network in
          NetworkMark(
            network: network, selected: network.id == selection,
            locked: locked || !isEnabled
          ) {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
              selection = network.id
            }
          }
        }
      }
      caption
    }
    .accessibilityElement(children: .contain)
  }

  /// The chosen network's full name and chain, replaced in place when the choice changes.
  @ViewBuilder private var caption: some View {
    if let current {
      HStack(spacing: 6) {
        Text(current.name).font(.callout.weight(.semibold)).foregroundStyle(WalletTheme.text)
        Text(detail(current)).font(.caption).foregroundStyle(WalletTheme.muted)
      }
      .lineLimit(1)
      .id(current.id)
      .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 3)))
      .accessibilityHidden(true)
      .frame(maxWidth: .infinity, alignment: .leading)
      .clipped()
    }
  }

  private func detail(_ network: WalletNetwork) -> String {
    let chain = "chain \(network.id.number)"
    return network.enabled ? chain : chain + " · off"
  }
}

/// One round, selectable network mark with a hover ring and a 34pt hit target.
private struct NetworkMark: View {
  let network: WalletNetwork
  let selected: Bool
  let locked: Bool
  let action: () -> Void
  @State private var hovering = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Button(action: action) {
      WalletNetworkGlyph(name: network.name, art: network.art, size: 26)
        .opacity(network.enabled ? 1 : 0.5)
        .padding(3)
        .overlay {
          Circle().strokeBorder(ringStyle, lineWidth: selected ? 2 : 1.5)
        }
        .scaleEffect(selected && !reduceMotion ? 1.08 : 1)
        .frame(width: WalletMetrics.tile, height: WalletMetrics.tile)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .disabled(locked)
    .opacity(locked && !selected ? 0.4 : 1)
    #if os(macOS)
      .onHover { hovering = $0 }
    #endif
    .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: hovering)
    .help(network.name)
    .accessibilityLabel(network.enabled ? network.name : "\(network.name), off")
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private var ringStyle: AnyShapeStyle {
    if selected { return AnyShapeStyle(WalletTheme.accent) }
    return AnyShapeStyle(hovering && !locked ? WalletTheme.muted : Color.clear)
  }
}
