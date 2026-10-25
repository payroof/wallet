import SwiftUI

struct WalletView: View {
  @Environment(WalletModel.self) private var model
  @AppStorage(WalletStorageKey.appearance.rawValue) private var appearance = WalletAppearance.system
    .rawValue
  #if os(iOS)
    @AppStorage(WalletStorageKey.settingsPanel.rawValue) private var settingsPanel = ""
  #endif
  @State private var section: WalletSection = .home
  @State private var addingAccount = false
  @State private var editingAccount: UInt32?
  @State private var connectingProject = false
  private let toasts = WalletToasts.shared
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private var accent: WalletAccent { model.accent(for: model.account) }
  var body: some View {
    Group {
      switch model.loadState {
      case .loading:
        ZStack {
          SkyBackdrop(fadesIntoCanvas: false).ignoresSafeArea()
          VStack(spacing: 22) {
            PayroofMark(size: 84)
              .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
            PayroofWordmark(size: 22)
            WalletSpinner(size: 24).foregroundStyle(WalletTheme.accent)
          }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Opening your wallet securely")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      case .failed:
        WalletCentered(width: 420) {
          WalletEmptyState(
            icon: "lock.shield", title: "Your wallet is safe on disk",
            detail:
              "We couldn't open it. Check storage access, then retry. We will not overwrite or replace an existing vault."
          ) {
            WalletAction(title: "Try again", icon: "arrow.clockwise") { model.load() }
              .frame(maxWidth: 240)
          }
        }.walletPageStatus(section)
      case .ready:
        if !model.session.exists {
          // Setup hosts its own feedback: it adds step-specific messages.
          WalletWelcome()
        } else {
          ZStack {
            // Locking removes the unlocked screens, and with them the window's
            // toolbar, in the same update that shows the unlock screen, so the window
            // changes once. Only when a sheet or alert is open do they stay a moment,
            // hidden and inert, so it closes normally first (`closingSession`).
            if model.session.unlocked || model.closingSession {
              let unlocked = model.session.unlocked
              navigation
                .environment(\.walletLocked, !unlocked)
                .opacity(unlocked ? 1 : 0)
                .allowsHitTesting(unlocked)
                .disabled(!unlocked)
                .accessibilityHidden(!unlocked)
            }
            if !model.session.unlocked {
              // Unlocking rolls the screen up like a shutter, revealing the roof. Locking
              // brings it down at once.
              WalletUnlock().walletPageStatus(section)
                .transition(.asymmetric(insertion: .identity, removal: .move(edge: .top)))
                .zIndex(1)
            }
          }
          .animation(
            model.session.unlocked && !reduceMotion ? .easeInOut(duration: 0.55) : nil,
            value: model.session.unlocked)
        }
      }
    }
    // Presented here, inside the accent below, so every sheet wears the current
    // account's color.
    .walletSheet(isPresented: $addingAccount) {
      CreateAccountView(accent: WalletAccent.random(avoiding: model.session.accents.values))
    }
    .walletSheet(
      isPresented: Binding(
        get: { editingAccount != nil }, set: { if !$0 { editingAccount = nil } })
    ) {
      if let editingAccount { EditAccountSheet(slot: editingAccount) }
    }
    .walletSheet(isPresented: $connectingProject) {
      ConnectProjectSheet { connectingProject = false }
    }
    .walletSheet(
      isPresented: Binding(
        get: { model.session.reviewingPlan && model.session.unlocked },
        set: { shown in
          if !shown && model.state.plan != nil && model.canRun(.send) {
            model.run(.confirmPlan(false))
          }
        })
    ) { TransferConfirmationView() }
    .walletSheet(
      isPresented: Binding(
        get: { model.session.reviewingAccess && model.session.unlocked },
        set: { shown in
          if !shown && model.state.access != nil && model.canRun(.access) {
            model.run(.dismissAccess)
          }
        })
    ) { AccessConfirmationView() }
    // The current account's accent reaches every view through the environment. A new
    // one recolors in place and rebuilds nothing.
    .environment(\.walletAccent, accent)
    .onChange(of: accent, initial: true) { _, value in toasts.accent = value }
    .tint(accent.accent).foregroundStyle(WalletTheme.text).background(WalletTheme.canvas)
    // Pages swap in place on both platforms, with no transition: the sky, the window's
    // title bar and the scroll edge under it stay exactly as they are, as they do
    // between the configuration pages (one view whose panel changes). A crossfade here
    // faded each page's scroll edge and toolbar out and in over the static sky, so the
    // sky seemed to flicker between Send and Receive.
    .preferredColorScheme(WalletAppearance(rawValue: appearance)?.scheme ?? nil)
    // Every screen, not only the unlocked pages: welcome, setup, unlock and loading
    // keep the window's title bar transparent over their sky, hovered or not.
    .walletFixedHeader()
    // The app's one toast lives in its own window above this one and its modals.
    .background(WalletToastAnchor())
    #if os(iOS)
      .onAppear {
        // Settings always opens on its main page. Subpages are not remembered.
        if section != .settings { settingsPanel = "" }
      }
      .onChange(of: section) { old, _ in
        if old == .settings { settingsPanel = "" }
      }
      .onChange(of: settingsPanel) { _, _ in model.feedback = nil }
    #endif
    // Leaving a screen ends its messages.
    .onChange(of: section) { _, _ in model.feedback = nil }
    .onChange(of: toasts.modals) { old, new in
      // A modal opening is a new context: earlier page messages don't follow it.
      if new > old { model.feedback = nil }
    }
    .onChange(of: model.session.unlocked) { _, value in
      if !value {
        addingAccount = false
        editingAccount = nil
        connectingProject = false
      }
    }
    .onChange(of: model.account) { _, _ in
      model.state.address = nil
      model.touch()
    }
    #if os(macOS)
      .frame(minWidth: 560, minHeight: 480)
    #endif
  }
  @ViewBuilder private var navigation: some View {
    #if os(macOS)
      NavigationSplitView {
        WalletSidebar(section: $section, appearance: $appearance, lock: model.lock)
          .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
      } detail: {
        destination(section).walletPageStatus(section)
          // The sky is painted here once. Pages swap over it without repainting it.
          .environment(\.walletBackdropProvided, true)
          .background { WalletBackdrop() }
          .walletFixedHeader()
          // Wallet, Activity and the configuration pages are named in the header.
          // Send and Receive keep the header to their controls.
          .navigationTitle(section.rawValue)
          .toolbar(removing: section == .send || section == .receive ? .title : nil)
      }
    #else
      // The system tab bar is hidden. The roof bar floats over the content instead, and
      // every tab keeps room for it at the bottom of its scroll.
      TabView(selection: $section) {
        ForEach(WalletSection.tabs) { item in
          NavigationStack {
            destination(item)
              .walletPageStatus(item)
              .navigationBarTitleDisplayMode(.inline)
              // Content stops at the keyboard's top edge. The canvas continues under
              // it, so the keyboard's rounded corners show the app's color, not white.
              .background { WalletBackdrop() }
              .environment(\.walletBackdropProvided, true)
              .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: RoofBar.height + 12).allowsHitTesting(false)
              }
              .toolbar(.hidden, for: .tabBar)
          }
          .tag(item)
        }
      }
      .overlay(alignment: .bottom) {
        RoofBar(selection: $section, tabs: WalletSection.tabs)
          .padding(.bottom, 4)
          .ignoresSafeArea(.keyboard)
      }
    #endif
  }
  /// A configuration page: a sidebar destination on macOS, a Settings subpage on iOS.
  private func open(_ panel: SettingsPanel) {
    #if os(macOS)
      section = WalletSection.configuration.first { $0.panel == panel } ?? .home
    #else
      settingsPanel = panel.rawValue
      section = .settings
    #endif
  }
  /// A card corner: an account without a project connects in place. A connected one
  /// opens its project page.
  private func openProject(_ slot: UInt32) {
    if model.state.settings.connections.contains(where: { $0.slot == slot }) {
      open(.project)
    } else {
      model.feedback = nil
      connectingProject = true
    }
  }
  /// The building site's tap: a new account at once, with a random name ("Moonlit
  /// Raccoon") and a color no account uses yet. Edit renames it. Its balances are read
  /// right away (an existing slot may already hold funds).
  private func createAccount() {
    guard model.canRun(.account) else { return }
    let name = AccountNames.random(avoiding: model.state.projects.map(\.label))
    let accent = WalletAccent.random(avoiding: model.state.settings.accents.values)
    model.run(.project(name, nil, accent.rawValue)) { model.refresh() }
  }
  /// Jump straight to network configuration from contextual "needs RPC" prompts.
  private func openNetworks() { open(.networks) }
  @ViewBuilder private func destination(_ item: WalletSection) -> some View {
    switch item {
    case .home:
      WalletHome(
        navigate: { section = $0 }, openNetworks: openNetworks,
        editAccount: { editingAccount = $0 }, createAccount: createAccount,
        createCustomAccount: { addingAccount = true },
        openProject: openProject)
    case .send: WalletSend(openNetworks: openNetworks)
    case .receive: WalletReceive()
    case .activity: WalletActivity()
    case .settings:
      #if os(iOS)
        WalletSettings()
      #else
        EmptyView()
      #endif
    case .security, .networks, .project:
      if let panel = item.panel { SettingsPage(panel: panel) }
    }
  }
}

/// Account editing, looked up when the sheet shows, so the frame that presents it
/// doesn't depend on the accounts' details.
private struct EditAccountSheet: View {
  @Environment(WalletModel.self) private var model
  let slot: UInt32
  var body: some View {
    if let account = model.state.projects.first(where: { $0.slot == slot }) {
      EditAccountView(account: account, accent: model.accent(for: slot))
    }
  }
}

/// Reports the model's feedback for the page on screen. Otherwise, away from Home (whose
/// balance line shows it), what a running refresh is reading. A modifier of its own, so
/// each refresh step redraws only it, not the page.
private struct WalletPageStatus: ViewModifier {
  @Environment(WalletModel.self) private var model
  let section: WalletSection
  func body(content: Content) -> some View {
    content.walletStatus(status) { model.feedback = nil }
  }
  private var status: WalletStatus {
    if let feedback = model.feedback { return feedback.status }
    if model.awaitingLocalNetwork { return .progress("Waiting for Local Network access…") }
    // Only the account on screen reports its progress.
    if section != .home, model.refreshingCurrent, let step = model.refreshStep {
      return .progress(step.text)
    }
    return .idle
  }
}

extension View {
  fileprivate func walletPageStatus(_ section: WalletSection) -> some View {
    modifier(WalletPageStatus(section: section))
  }
}
