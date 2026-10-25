import SwiftUI

/// Chooses the current account's receive address. One field searches the list and also
/// takes an exact child index ("57") or derivation path ("m/44'/60'/0'/0/57") that
/// isn't there yet. The list is paged so a long one stays compact. Every page is as tall
/// as a full one, so turning pages never resizes the sheet.
struct AddressPickerSheet: View {
  @Environment(WalletModel.self) private var model
  let slot: UInt32
  @Binding var path: String
  let done: () -> Void
  @State private var query = ""
  @State private var page = 0
  private static let pageSize = 8
  private var account: ProjectCard? { model.state.projects.first { $0.slot == slot } }
  private var paths: [String] { account?.orderedPaths ?? [] }
  private var needle: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var listed: [String] {
    guard !needle.isEmpty else { return paths }
    let lower = needle.lowercased()
    return paths.filter {
      WalletText.addressName($0).lowercased().contains(lower) || $0.contains(lower)
        || model.addresses[$0]?.lowercased().contains(lower) == true
    }
  }
  /// More than one page: the pager shows and every page keeps a full page's height.
  private var paged: Bool { listed.count > Self.pageSize }
  private var pages: Int { max(1, (listed.count + Self.pageSize - 1) / Self.pageSize) }
  private var current: Int { min(page, pages - 1) }
  private var visible: ArraySlice<String> {
    let start = current * Self.pageSize
    return listed[start..<min(start + Self.pageSize, listed.count)]
  }
  /// The typed index or absolute path, when valid and not already listed.
  private enum Entry {
    case index(UInt32)
    case path(String)
  }
  private var entry: Entry? {
    if let value = UInt32(needle) {
      let known = paths.contains("m/44'/60'/\(slot)'/0/\(value)")
      return known ? nil : .index(value)
    }
    guard needle.hasPrefix("m/"), needle.count > 2,
      needle.dropFirst(2).split(separator: "/", omittingEmptySubsequences: false).allSatisfy({
        let digits = $0.hasSuffix("'") ? $0.dropLast() : $0
        return !digits.isEmpty && UInt32(digits) != nil
      })
    else { return nil }
    return paths.contains(needle) ? nil : .path(needle)
  }
  /// The address's biggest cached holding, when any has been read.
  private var hints: [String: Hint] {
    Dictionary(
      WalletPortfolio.addresses(model.state, account: account).compactMap { item in
        item.top.map {
          (
            item.path,
            Hint(
              text: ExactAmount.short($0.atomic, decimals: $0.asset.decimals) + " "
                + $0.asset.symbol,
              asset: $0.asset)
          )
        }
      }, uniquingKeysWith: { first, _ in first })
  }

  var body: some View {
    WalletSheet(
      "Receive address", subtitle: account?.label ?? "", icon: "tray.and.arrow.down",
      closeTitle: "Done",
      status: model.feedback?.status ?? .idle,
      dismissStatus: { model.feedback = nil }, close: done
    ) {
      WalletSearchField(prompt: "Search, index or path", text: $query)
        .onSubmit { useEntry() }
      let hints = hints
      VStack(spacing: 2) {
        if let entry {
          WalletOptionRow(
            option: WalletOption(
              value: "entry", title: entryTitle(entry), icon: "plus",
              enabled: model.canRun(.address)),
            selected: false
          ) { useEntry() }
        }
        ForEach(visible, id: \.self) { item in
          WalletOptionRow(option: option(item, hints: hints), selected: item == path) {
            path = item
            done()
          }
        }
        // A short last page keeps a full page's height: the rows' places stay empty.
        if paged {
          ForEach(visible.count..<Self.pageSize, id: \.self) { _ in
            WalletOptionRow(option: Self.placeholder, selected: false) {}
              .hidden().accessibilityHidden(true)
          }
        }
        if listed.isEmpty && entry == nil {
          Text("No matches").font(.callout).foregroundStyle(WalletTheme.muted)
            .frame(maxWidth: .infinity).padding(.vertical, 12)
        }
      }
      if paged { pager }
    }
    .walletModal(width: 480, busy: model.isRunning(.address))
    .onAppear { page = (paths.firstIndex(of: path) ?? 0) / Self.pageSize }
    // Each row shows its address under its name: derive the ones on this page.
    .task(id: Array(visible)) { await model.deriveAddresses(Array(visible)) }
    .onChange(of: query) { _, _ in page = 0 }
  }

  /// A row's address and biggest holding under its name. Until the address is derived
  /// the line still holds its place, so rows never grow as addresses arrive.
  private func option(_ item: String, hints: [String: Hint]) -> WalletOption<String> {
    let address = model.addresses[item].map(WalletText.short) ?? "Deriving…"
    let hint = hints[item]
    return WalletOption(
      value: item, title: WalletText.addressName(item),
      subtitle: ([address] + [hint?.text].compactMap { $0 }).joined(separator: " · "),
      icon: hint == nil ? "circle.dashed" : nil,
      artwork: hint.map { WalletAssetGlyph.image(asset: $0.asset, size: 20) })
  }
  /// An address's biggest holding, as text and as the token it is in.
  private struct Hint {
    let text: String
    let asset: WalletAsset
  }
  /// Stands in for a missing row on the last page: the same height as a real one.
  private static let placeholder = WalletOption(
    value: "", title: "Address", subtitle: "0x0000…0000")

  private func entryTitle(_ entry: Entry) -> String {
    switch entry {
    case .index(let value): "Use index \(value)"
    case .path(let value): "Use path \(value)"
    }
  }

  private var pager: some View {
    HStack(spacing: 12) {
      WalletIconButton(title: "Previous page", icon: "chevron.left") { page = current - 1 }
        .disabled(current == 0)
      let first = current * Self.pageSize + 1
      Text("\(first)–\(first + visible.count - 1) of \(listed.count)")
        .font(.callout).monospacedDigit().foregroundStyle(WalletTheme.muted)
        .frame(maxWidth: .infinity)
      WalletIconButton(title: "Next page", icon: "chevron.right") { page = current + 1 }
        .disabled(current >= pages - 1)
    }
  }

  private func useEntry() {
    guard let entry, model.canRun(.address) else { return }
    switch entry {
    case .index(let value):
      model.run(.address(slot, value)) {
        path = model.state.address?.path ?? path
        done()
      }
    case .path(let value):
      model.run(.exact(value)) {
        path = value
        done()
      }
    }
  }
}
