import SwiftUI

/// Provider API keys, one secure field each. A key goes straight to the core, which
/// asks the provider to accept it before it is kept in the encrypted vault. This view
/// only ever learns that a provider has one.
struct ProviderKeys: View {
  @Environment(WalletModel.self) private var model
  @State private var expanded = false
  @State private var drafts: [KeyProvider: String] = [:]
  @State private var verifying: KeyProvider?
  @State private var rejected: KeyProvider?
  private var saved: Int { model.state.providers.count }
  private var builtIn: Int { model.state.presetProviders.subtracting(model.state.providers).count }
  private var summary: String {
    switch (saved, builtIn) {
    case (0, 0): "None"
    case (0, _): "\(builtIn) built-in"
    case (_, 0): "\(saved) saved"
    default: "\(saved) saved · \(builtIn) built-in"
    }
  }
  var body: some View {
    WalletCard(padding: 6) {
      WalletDisclosure(
        "Provider keys", detail: summary, expanded: $expanded
      ) {
        VStack(spacing: 10) {
          ForEach(KeyProvider.allCases) { provider in row(provider) }
        }.padding(.bottom, 10)
      }
      .padding(.horizontal, 10)
    }
    .walletDismissOnLock { drafts = [:] }
  }
  private func draft(_ provider: KeyProvider) -> String {
    (drafts[provider] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
  }
  /// The core's rule: 1–128 letters, digits, `-` or `_`.
  private func valid(_ key: String) -> Bool {
    (1...128).contains(key.count)
      && key.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
  }
  private func row(_ provider: KeyProvider) -> some View {
    let has = model.state.providers.contains(provider.id)
    let preset = !has && model.state.presetProviders.contains(provider.id)
    let text = draft(provider)
    let invalid = !text.isEmpty && !valid(text)
    return HStack(spacing: 10) {
      glyph(provider, saved: has, preset: preset).frame(width: 22).accessibilityHidden(true)
      Text(provider.title).font(.callout.weight(.medium)).frame(width: 74, alignment: .leading)
      // A built-in key works until the user saves their own, which replaces it.
      SecureField(has ? "••••••••" : preset ? "Built-in" : "Key", text: binding(provider))
        .textFieldStyle(.plain).autocorrectionDisabled()
        .padding(.horizontal, 12).frame(minHeight: WalletMetrics.field)
        .background(
          WalletTheme.surface, in: WalletShape.field
        )
        .overlay(
          WalletShape.field
            .strokeBorder(invalid ? WalletTheme.danger : WalletTheme.border)
        )
        .onSubmit { save(provider) }
        .accessibilityLabel(
          "\(provider.title) key, \(has ? "saved" : preset ? "built-in" : "not set")"
        )
        .help(preset ? "A built-in key is used. Save your own to replace it." : "")
      if !text.isEmpty {
        WalletIconButton(
          title: "Verify and save \(provider.title) key", icon: "checkmark"
        ) {
          save(provider)
        }.disabled(!model.canRun(.providerKey) || verifying != nil || invalid)
      } else if has {
        WalletIconButton(title: "Remove \(provider.title) key", icon: "trash") {
          model.run(.providerKey(provider, nil))
        }.disabled(!model.canRun(.providerKey))
      }
    }
  }
  @ViewBuilder private func glyph(_ provider: KeyProvider, saved: Bool, preset: Bool)
    -> some View
  {
    if verifying == provider {
      ProgressView().controlSize(.small)
    } else if rejected == provider {
      Image(systemName: "xmark.circle.fill").foregroundStyle(WalletTheme.danger)
    } else if saved {
      Image(systemName: "checkmark.circle.fill").foregroundStyle(WalletTheme.success)
    } else if preset {
      Image(systemName: "checkmark.circle").foregroundStyle(WalletTheme.success)
    } else {
      Image(systemName: "key").foregroundStyle(WalletTheme.muted)
    }
  }
  private func binding(_ provider: KeyProvider) -> Binding<String> {
    Binding(
      get: { drafts[provider] ?? "" },
      set: {
        drafts[provider] = $0
        if rejected == provider { rejected = nil }
      })
  }
  private func save(_ provider: KeyProvider) {
    let key = draft(provider)
    guard model.canRun(.providerKey), verifying == nil, valid(key) else { return }
    verifying = provider
    rejected = nil
    Task {
      let accepted = await model.accepts(provider, key: key)
      verifying = nil
      if accepted {
        model.run(.providerKey(provider, key)) { drafts[provider] = nil }
      } else {
        rejected = provider
        model.feedback = WalletFeedback(
          message: "\(provider.title) did not accept this key.", isError: true)
      }
    }
  }
}
