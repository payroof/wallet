import SwiftUI

struct WalletOption<Value: Hashable>: Identifiable {
  let value: Value
  let title: String
  var subtitle: String? = nil
  var icon: String? = nil
  var badge: String? = nil
  var badgeTone: WalletTone = .neutral
  var enabled = true
  /// A picture shown before the title in option rows (e.g. a network's mark), in
  /// place of `icon`.
  var artwork: Image? = nil
  var id: Value { value }
}

extension View {
  fileprivate func walletSelected(_ selected: Bool) -> some View {
    accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
  }
}

/// A wrapping row layout for chips.
struct WalletFlowLayout: Layout {
  var spacing: CGFloat = 8
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let limit = proposal.width ?? .infinity
    var x: CGFloat = 0
    var y: CGFloat = 0
    var row: CGFloat = 0
    var widest: CGFloat = 0
    for view in subviews {
      var size = view.sizeThatFits(.unspecified)
      size.width = min(size.width, limit)
      if x > 0 && x + size.width > limit {
        y += row + spacing
        x = 0
        row = 0
      }
      x += size.width + spacing
      row = max(row, size.height)
      widest = max(widest, x - spacing)
    }
    return CGSize(width: proposal.width ?? widest, height: y + row)
  }
  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    var x = bounds.minX
    var y = bounds.minY
    var row: CGFloat = 0
    for view in subviews {
      var size = view.sizeThatFits(.unspecified)
      size.width = min(size.width, bounds.width)
      if x > bounds.minX && x + size.width > bounds.maxX {
        y += row + spacing
        x = bounds.minX
        row = 0
      }
      view.place(
        at: CGPoint(x: x, y: y), anchor: .topLeading,
        proposal: ProposedViewSize(width: size.width, height: size.height))
      x += size.width + spacing
      row = max(row, size.height)
    }
  }
}

struct WalletChip<Value: Hashable>: View {
  let option: WalletOption<Value>
  let selected: Bool
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        if selected {
          Image(systemName: "checkmark").font(.caption.weight(.bold))
            .foregroundStyle(WalletTheme.accent)
        } else if let icon = option.icon {
          Image(systemName: icon).font(.caption).foregroundStyle(WalletTheme.muted)
        }
        VStack(alignment: .leading, spacing: 0) {
          Text(option.title).font(.callout.weight(selected ? .semibold : .medium)).lineLimit(1)
          if let subtitle = option.subtitle {
            Text(subtitle).font(.caption2).foregroundStyle(WalletTheme.muted).lineLimit(1)
          }
        }
        if let badge = option.badge {
          WalletBadge(title: badge, tone: option.badgeTone)
        }
      }
      .padding(.horizontal, 14).padding(.vertical, 4)
      .frame(minHeight: WalletMetrics.chip)
      .background(
        selected
          ? AnyShapeStyle(WalletTheme.accent.opacity(0.12)) : AnyShapeStyle(WalletTheme.surface),
        in: Capsule(style: .continuous)
      )
      .overlay(
        Capsule(style: .continuous).strokeBorder(
          selected ? AnyShapeStyle(WalletTheme.accent) : AnyShapeStyle(WalletTheme.border),
          style: StrokeStyle(lineWidth: selected ? 1.5 : 1, dash: option.enabled ? [] : [3, 3]))
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain).disabled(!option.enabled).opacity(option.enabled ? 1 : 0.55)
    .walletSelected(selected)
    .accessibilityLabel(
      [option.title, option.subtitle, option.badge].compactMap { $0 }.joined(separator: ", "))
  }
}

/// A radio-style option row for comparing choices or for long option lists.
struct WalletOptionRow<Value: Hashable>: View {
  let option: WalletOption<Value>
  let selected: Bool
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
          .font(.title3).foregroundStyle(
            selected ? AnyShapeStyle(WalletTheme.accent) : AnyShapeStyle(WalletTheme.border)
          )
          .accessibilityHidden(true)
        if let artwork = option.artwork {
          artwork.accessibilityHidden(true)
        } else if let icon = option.icon {
          Image(systemName: icon).foregroundStyle(WalletTheme.muted).frame(width: 20)
            .accessibilityHidden(true)
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(option.title).font(.body.weight(selected ? .semibold : .regular))
          if let subtitle = option.subtitle {
            Text(subtitle).font(.footnote).foregroundStyle(WalletTheme.muted)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        Spacer(minLength: 8)
        if let badge = option.badge { WalletBadge(title: badge, tone: option.badgeTone) }
      }
      .padding(.horizontal, 12).padding(.vertical, 8).frame(minHeight: WalletMetrics.control + 8)
      .background(
        selected ? AnyShapeStyle(WalletTheme.accent.opacity(0.08)) : AnyShapeStyle(Color.clear),
        in: WalletShape.tile
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(WalletRowButtonStyle()).disabled(!option.enabled)
    .walletSelected(selected)
    .accessibilityLabel(
      [option.title, option.subtitle, option.badge].compactMap { $0 }.joined(separator: ", "))
  }
}

/// A rounded search input with a clear button.
struct WalletSearchField: View {
  let prompt: String
  @Binding var text: String
  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass").foregroundStyle(WalletTheme.muted)
        .accessibilityHidden(true)
      TextField(prompt, text: $text).textFieldStyle(.plain).autocorrectionDisabled()
        #if os(iOS)
          .textInputAutocapitalization(.never)
        #endif
      if !text.isEmpty {
        Button {
          text = ""
        } label: {
          Image(systemName: "xmark.circle.fill").foregroundStyle(WalletTheme.muted)
        }.buttonStyle(.plain).accessibilityLabel("Clear search")
      }
    }
    .padding(.horizontal, 14).frame(minHeight: WalletMetrics.field)
    .background(WalletTheme.surface, in: Capsule(style: .continuous))
    .overlay(Capsule(style: .continuous).strokeBorder(WalletTheme.border))
  }
}

/// Searchable option list presented in a sheet for large option sets.
struct WalletOptionSheet<Value: Hashable>: View {
  let title: String
  var subtitle = ""
  var icon = "list.bullet"
  let options: [WalletOption<Value>]
  @Binding var selection: Value
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @FocusState private var searching: Bool
  /// The natural heights of the header and of the full list (iOS sheet height). The
  /// list's is taken while nothing is searched, so typing never resizes the sheet.
  @State private var headerHeight: CGFloat = 0
  @State private var listHeight: CGFloat = 0
  private var filtered: [WalletOption<Value>] {
    let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
    guard !needle.isEmpty else { return options }
    return options.filter {
      $0.title.lowercased().contains(needle)
        || ($0.subtitle?.lowercased().contains(needle) ?? false)
    }
  }
  private var header: some View {
    VStack(spacing: 0) {
      WalletSheetHeader(title: title, subtitle: subtitle, icon: icon) { dismiss() }
      if options.count > 6 {
        WalletSearchField(prompt: "Search \(options.count) options", text: $query)
          .focused($searching).padding(.horizontal, 20).padding(.bottom, 12)
      }
      Divider()
    }
    .onGeometryChange(for: CGFloat.self) {
      $0.size.height
    } action: {
      headerHeight = $0
    }
  }
  private var listFit: Binding<CGFloat> {
    Binding(get: { listHeight }, set: { if query.isEmpty { listHeight = $0 } })
  }
  var body: some View {
    VStack(spacing: 0) {
      header
      WalletFittedScroll(maxHeight: min(440, WalletModalSize.maxScroll), fitted: listFit) {
        VStack(spacing: 2) {
          ForEach(filtered) { option in
            WalletOptionRow(option: option, selected: option.value == selection) {
              selection = option.value
              dismiss()
            }
          }
          if filtered.isEmpty {
            WalletEmptyState(
              icon: "magnifyingglass", title: "No matches",
              detail: "Nothing matches “\(query)”. Try a symbol, network or address number.")
          }
        }.padding(8)
      }
    }
    .walletFittedDetent(listHeight > 0 ? headerHeight + listHeight : 0)
    // The same sky as every other sheet (`WalletSheet`).
    .walletSheetBackdrop()
    .walletTint().foregroundStyle(WalletTheme.text)
    .walletModal(width: 460)
    .task { searching = options.count > 8 }
  }
}

/// A compact, field-like selector that keeps the current choice visible and
/// opens a searchable list. Suits large collections of addresses or assets.
struct WalletSelector<Value: Hashable>: View {
  let label: String
  let options: [WalletOption<Value>]
  @Binding var selection: Value
  var placeholder = "Choose"
  var icon: String? = nil
  @State private var choosing = false
  var body: some View {
    let current = options.first { $0.value == selection }
    Button {
      choosing = true
    } label: {
      HStack(spacing: 10) {
        if let icon = current?.icon ?? icon {
          Image(systemName: icon).foregroundStyle(WalletTheme.accent).frame(width: 20)
            .accessibilityHidden(true)
        }
        VStack(alignment: .leading, spacing: 1) {
          Text(label.uppercased()).font(.caption2.weight(.semibold)).tracking(0.6)
            .foregroundStyle(WalletTheme.muted)
          HStack(spacing: 6) {
            Text(current?.title ?? placeholder).font(.callout.weight(.semibold)).lineLimit(1)
            if let subtitle = current?.subtitle {
              Text(subtitle).font(.caption).foregroundStyle(WalletTheme.muted).lineLimit(1)
            }
          }
        }
        Spacer(minLength: 4)
        if let badge = current?.badge {
          WalletBadge(title: badge, tone: current?.badgeTone ?? .neutral)
        }
        Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold))
          .foregroundStyle(WalletTheme.muted).accessibilityHidden(true)
      }
      .padding(.horizontal, 12).padding(.vertical, 6)
      .frame(maxWidth: .infinity, minHeight: WalletMetrics.field + 10, alignment: .leading)
      .background(WalletTheme.surface, in: WalletShape.field)
      .overlay(WalletShape.field.strokeBorder(WalletTheme.border))
    }
    .buttonStyle(WalletRowButtonStyle(radius: WalletMetrics.radius))
    .accessibilityLabel(
      "\(label): \([current?.title, current?.subtitle].compactMap { $0 }.joined(separator: ", "))"
    )
    .accessibilityHint("Choose from \(options.count) options")
    .walletSheet(isPresented: $choosing) {
      WalletOptionSheet(
        title: label, icon: icon ?? "list.bullet", options: options, selection: $selection)
    }
    .walletDismissOnLock { choosing = false }
  }
}

/// Button-driven single choice. Short sets are shown inline as chips so every
/// option is visible. Large sets collapse into a button that opens a searchable sheet.
struct WalletChoice<Value: Hashable, Accessory: View>: View {
  let label: String
  let options: [WalletOption<Value>]
  @Binding var selection: Value
  var inlineLimit = 8
  var placeholder = "Choose"
  let accessory: Accessory
  @State private var choosing = false
  init(
    _ label: String, options: [WalletOption<Value>], selection: Binding<Value>,
    inlineLimit: Int = 8, placeholder: String = "Choose",
    @ViewBuilder accessory: () -> Accessory
  ) {
    self.label = label
    self.options = options
    self._selection = selection
    self.inlineLimit = inlineLimit
    self.placeholder = placeholder
    self.accessory = accessory()
  }
  var body: some View {
    if options.count <= inlineLimit {
      WalletFlowLayout(spacing: 8) {
        ForEach(options) { option in
          WalletChip(option: option, selected: option.value == selection) {
            selection = option.value
          }
        }
        accessory
      }
      .accessibilityElement(children: .contain).accessibilityLabel(label)
    } else {
      let current = options.first { $0.value == selection }
      WalletFlowLayout(spacing: 8) {
        Button {
          choosing = true
        } label: {
          HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
              Text(current?.title ?? placeholder).font(.callout.weight(.semibold))
              if let subtitle = current?.subtitle {
                Text(subtitle).font(.caption2).foregroundStyle(WalletTheme.muted)
              }
            }
            if let badge = current?.badge {
              WalletBadge(title: badge, tone: current?.badgeTone ?? .neutral)
            }
            Text("Change · \(options.count)").font(.caption.weight(.semibold))
              .foregroundStyle(WalletTheme.accent)
          }
          .padding(.horizontal, 12).padding(.vertical, 4).frame(minHeight: WalletMetrics.chip)
          .background(
            WalletTheme.accent.opacity(current == nil ? 0 : 0.12), in: Capsule(style: .continuous)
          )
          .overlay(
            Capsule(style: .continuous)
              .strokeBorder(
                current == nil
                  ? AnyShapeStyle(WalletTheme.border) : AnyShapeStyle(WalletTheme.accent),
                lineWidth: 1.5)
          )
          .contentShape(Rectangle())
        }.buttonStyle(.plain)
          .accessibilityLabel(
            "\(label): \(current?.title ?? placeholder). Choose from \(options.count) options")
        accessory
      }
      .walletSheet(isPresented: $choosing) {
        WalletOptionSheet(title: label, options: options, selection: $selection)
      }
      .walletDismissOnLock { choosing = false }
    }
  }
}

extension WalletChoice where Accessory == EmptyView {
  init(
    _ label: String, options: [WalletOption<Value>], selection: Binding<Value>,
    inlineLimit: Int = 8, placeholder: String = "Choose"
  ) {
    self.init(
      label, options: options, selection: selection, inlineLimit: inlineLimit,
      placeholder: placeholder
    ) { EmptyView() }
  }
}
