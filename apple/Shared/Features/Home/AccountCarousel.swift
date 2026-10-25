import SwiftUI

/// The accounts as buildings along a skyline, each with its rooftop sign, then a building
/// site with a crane for a new account, in a paging row with lit windows below.
/// Swiping (or on macOS the chevrons and ←/→) moves between them.
///
/// One source of truth: `model.account`. The row's scroll position is separate, transient
/// state (a `ScrollPosition`) that is created pointing at the current account, so the
/// first frame already shows it, every time the row is created. While the row moves only
/// it and its dots change. The account (and with it the app's accent and the page below)
/// is committed once the row has come to rest on a card.
struct AccountCarousel: View {
  @Environment(WalletModel.self) private var model
  /// Opens Send or Receive for the account, which becomes current first.
  let navigate: (WalletSection) -> Void
  let edit: (UInt32) -> Void
  /// A new account at once, with a random name.
  let create: () -> Void
  /// A new account with a chosen name, color and slot.
  let createCustom: () -> Void
  /// The card corner's project action for an account.
  let project: (UInt32) -> Void
  /// Where the row is scrolled to. Created on the current account (see `init`).
  @State private var position: ScrollPosition
  @State private var hovering = false
  /// The account whose deletion is being confirmed.
  @State private var deleting: ProjectCard?
  /// The account whose project disconnection is being confirmed.
  @State private var disconnecting: ProjectCard?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  enum Card: Hashable {
    case account(UInt32)
    case add
  }

  private static let spacing: CGFloat = 14
  /// Room above the signs for their glow and neon.
  private static let inset: CGFloat = 14
  #if os(macOS)
    /// Desktop cards keep a card's size. The neighbours show beside it.
    private static let width: CGFloat = 420
    private static let peek: CGFloat = 0
  #else
    private static let width = CGFloat.infinity
    /// How much of each neighbour shows at the sides.
    private static let peek: CGFloat = 28
  #endif

  init(
    account: UInt32, navigate: @escaping (WalletSection) -> Void,
    edit: @escaping (UInt32) -> Void, create: @escaping () -> Void,
    createCustom: @escaping () -> Void,
    project: @escaping (UInt32) -> Void
  ) {
    _position = State(initialValue: ScrollPosition(id: Card.account(account), anchor: .center))
    self.navigate = navigate
    self.edit = edit
    self.create = create
    self.createCustom = createCustom
    self.project = project
  }

  private var cards: [Card] { model.state.projects.map { .account($0.slot) } + [.add] }
  /// The card the row shows or is moving to. The current account until the row reports one.
  private var shown: Card { position.viewID(type: Card.self) ?? .account(model.account) }
  private var index: Int { cards.firstIndex(of: shown) ?? 0 }

  var body: some View {
    VStack(spacing: 0) {
      row
      Parapet().frame(height: 24)
        .overlay { dots }
    }
    // The current account changed elsewhere (created, removed, a card's menu): the row
    // shows it.
    .onChange(of: model.account) { _, slot in
      if shown != .account(slot) { position.scrollTo(id: Card.account(slot), anchor: .center) }
    }
    .confirmationDialog(
      "Delete \(deleting?.label ?? "account")?",
      isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
      titleVisibility: .visible, presenting: deleting
    ) { account in
      Button("Delete account", role: .destructive) { model.run(.removeAccount(account.slot)) }
      Button("Cancel", role: .cancel) {}
    } message: { account in
      Text("Funds stay on-chain. Add slot \(account.slot) later to restore it.")
    }
    .confirmationDialog(
      "Disconnect \(disconnecting.flatMap { connection($0.slot)?.project } ?? "project")?",
      isPresented: Binding(
        get: { disconnecting != nil }, set: { if !$0 { disconnecting = nil } }),
      titleVisibility: .visible, presenting: disconnecting
    ) { account in
      Button("Disconnect") { disconnect(account.slot) }
      Button("Cancel", role: .cancel) {}
    } message: { _ in
      Text(
        "This device forgets its access. The project and your addresses stay. Connect again anytime."
      )
    }
    .walletDismissOnLock {
      deleting = nil
      disconnecting = nil
    }
  }

  /// The row is as tall as a card as wide as the row less the neighbours' peek
  /// (`CardRowLayout`). Each card fills the scroller less its content margins. Sizes come
  /// from the layout pass itself, so the first frame is final.
  private var row: some View {
    CardRowLayout(peek: Self.peek, inset: Self.inset, maxWidth: Self.width) { scroller }
      #if os(macOS)
        // Centred on the signs, not on the whole buildings below them.
        .overlay { chevrons.offset(y: (Self.inset - AccountCard.base) / 2) }
        .onHover { hovering = $0 }
      #endif
  }

  private var scroller: some View {
    ScrollView(.horizontal) {
      HStack(spacing: Self.spacing) {
        ForEach(cards, id: \.self) { card in
          face(card)
            // As wide as the scroller less its margins. The row's height (CardRowLayout)
            // is exactly this width's building.
            .frame(maxHeight: .infinity)
            .containerRelativeFrame(.horizontal)
            // The centred card stands out: full size, colour and a soft glow. Its
            // neighbours are smaller, dimmer and paler. Cheap and driven by the scroll.
            .scrollTransition(.interactive, axis: .horizontal) {
              [calm = reduceMotion] content, phase in
              Self.emphasis(content, phase: phase, calm: calm)
            }
        }
      }
      .scrollTargetLayout()
    }
    .contentMargins(.horizontal, Self.peek, for: .scrollContent)
    .contentMargins(.top, Self.inset, for: .scrollContent)
    .scrollIndicators(.hidden)
    .scrollClipDisabled()
    .scrollTargetBehavior(.viewAligned)
    .scrollPosition($position, anchor: .center)
    // SwiftUI applies neither a ScrollPosition's initial ID nor a scroll requested
    // before the row has its real width (on launch and unlock it is laid out at zero
    // first). The row is placed on the current account each time its width or its
    // cards change, so it always opens on the account that was selected last.
    .onGeometryChange(for: CGFloat.self) {
      $0.size.width
    } action: { width in
      if width > 0 { placeOnCurrent() }
    }
    .onChange(of: cards) { _, _ in placeOnCurrent() }
    // Only a scroll that moved commits. Settling after layout or after a programmatic
    // placement never changes the current account.
    .onScrollPhaseChange { old, new in if new == .idle && old != .idle { commit() } }
  }

  @ViewBuilder private func face(_ card: Card) -> some View {
    switch card {
    case .account(let slot):
      if let account = model.state.projects.first(where: { $0.slot == slot }) {
        AccountCard(
          account: account, select: { go(card) }, edit: { edit(slot) },
          project: { project(slot) }
        )
        // Redrawn when its account changes, not on every frame of the row's scroll.
        .equatable()
        .contextMenu { menu(account) }
      }
    case .add:
      Button {
        WalletHaptics.tap()
        create()
      } label: {
        BuildingSite(building: model.isRunning(.account))
      }
      .buttonStyle(.plain).disabled(model.busy || model.isRunning(.account))
      .accessibilityLabel("New account")
      .accessibilityHint("Creates an account with a random name. Rename it in Edit")
      .contextMenu {
        Button("New account", systemImage: "plus", action: create)
        Button("Choose name, color and slot…", systemImage: "slider.horizontal.3") {
          createCustom()
        }
      }
      .accessibilityActions {
        Button("Choose name, color and slot", action: createCustom)
      }
    }
  }

  /// What a card offers on a long press (right click on the Mac): the account's own
  /// actions (Send, Receive, Connect or Disconnect, Edit), the destructive one last.
  @ViewBuilder private func menu(_ account: ProjectCard) -> some View {
    Button("Send", systemImage: "arrow.up.right") { open(.send, on: account.slot) }
    Button("Receive", systemImage: "arrow.down.left") { open(.receive, on: account.slot) }
    if let connection = connection(account.slot) {
      Button("Disconnect", systemImage: "minus.circle") { disconnecting = account }
        .disabled(!model.canRun(.connection(connection.id)))
    } else {
      Button("Connect", systemImage: "link") { openProject(on: account.slot) }
    }
    Button("Edit", systemImage: "slider.horizontal.3") { edit(account.slot) }
    Divider()
    Button("Delete", systemImage: "trash", role: .destructive) { deleting = account }
      .disabled(model.state.projects.count < 2 || !model.canRun(.removal))
  }
  /// The account becomes current at once (the row follows), then the screen opens on it.
  private func open(_ section: WalletSection, on slot: UInt32) {
    makeCurrent(slot)
    navigate(section)
  }
  /// Connect (or the project settings) acts on the current account, so the account
  /// becomes current first.
  private func openProject(on slot: UInt32) {
    makeCurrent(slot)
    project(slot)
  }
  private func connection(_ slot: UInt32) -> PathConnection? {
    model.state.settings.connections.first { $0.slot == slot }
  }
  /// Forgets this device's access to the account's project.
  private func disconnect(_ slot: UInt32) {
    if let connection = connection(slot) {
      model.run(.disconnect(connection.origin, connection.project))
    }
  }
  private func makeCurrent(_ slot: UInt32) {
    guard slot != model.account else { return }
    var quiet = Transaction()
    quiet.disablesAnimations = true
    withTransaction(quiet) { model.account = slot }
  }

  // MARK: Position

  /// The row rests on a card: an account card becomes the current account, at once and
  /// without animating the page below. The "+" card leaves the current account as it is.
  private func commit() {
    guard case .account(let slot) = shown, slot != model.account else { return }
    var quiet = Transaction()
    quiet.disablesAnimations = true
    withTransaction(quiet) { model.account = slot }
  }
  /// Shows the current account without animating or committing anything.
  private func placeOnCurrent() {
    guard cards.contains(.account(model.account)) else { return }
    var quiet = Transaction()
    quiet.disablesAnimations = true
    withTransaction(quiet) { position.scrollTo(id: Card.account(model.account), anchor: .center) }
  }
  /// Moves to a card (a dot, a chevron, a key, a tap on a neighbour). The row commits it
  /// when it comes to rest. Without animation it is at rest at once.
  private func go(_ card: Card) {
    guard card != shown else { return }
    if reduceMotion {
      position.scrollTo(id: card, anchor: .center)
      commit()
    } else {
      withAnimation(.smooth(duration: 0.35)) {
        position.scrollTo(id: card, anchor: .center)
      }
    }
  }
  private nonisolated static func emphasis(
    _ content: EmptyVisualEffect, phase: ScrollTransitionPhase, calm: Bool
  ) -> some VisualEffect {
    let away = min(abs(phase.value), 1)
    // Neighbours stand further back: smaller (from the roof up), dimmer, paler.
    let scale: Double = calm ? 1 : 1 - 0.14 * away
    return
      content
      .scaleEffect(scale, anchor: .bottom)
      .opacity(1 - 0.45 * away)
      .saturation(1 - 0.6 * away)
  }
  private func step(_ delta: Int) {
    let target = min(max(index + delta, 0), cards.count - 1)
    if target != index { go(cards[target]) }
  }

  /// A row of small windows set in the parapet, one per building. The current one is lit.
  private var dots: some View {
    HStack(spacing: 2) {
      ForEach(cards, id: \.self) { card in
        let selected = card == shown
        Button {
          go(card)
        } label: {
          Group {
            if case .account(let slot) = card {
              RoundedRectangle(cornerRadius: 1.5)
                .fill(
                  selected
                    ? AnyShapeStyle(WalletTheme.lamp) : AnyShapeStyle(Color.black.opacity(0.35))
                )
                .overlay(
                  RoundedRectangle(cornerRadius: 1.5).strokeBorder(
                    selected ? model.accent(for: slot).sunrise : Color.white.opacity(0.25),
                    lineWidth: 1)
                )
                .shadow(color: selected ? WalletTheme.lamp.opacity(0.9) : .clear, radius: 4)
                .frame(width: 7, height: 10)
            } else {
              Image(systemName: "plus").font(.system(size: 8, weight: .heavy))
                .foregroundStyle(selected ? WalletTheme.lamp : Color.white.opacity(0.6))
            }
          }
          .frame(width: 18, height: 22)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityHidden(true)
      }
    }
    .padding(.top, 5)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: shown)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Accounts")
    .accessibilityValue("Account \(index + 1) of \(cards.count)")
    .accessibilityIdentifier("account.dots")
    .accessibilityAdjustableAction { direction in
      step(direction == .increment ? 1 : -1)
    }
  }

  #if os(macOS)
    /// Pointer: chevrons at the sides while the row is hovered. They stay in the
    /// layout (and their ←/→ keys work) when hidden.
    private var chevrons: some View {
      HStack {
        chevron("chevron.left", label: "Previous account", key: .leftArrow, delta: -1)
        Spacer()
        chevron("chevron.right", label: "Next account", key: .rightArrow, delta: 1)
      }
      .padding(.horizontal, 6)
    }
    private func chevron(_ icon: String, label: String, key: KeyEquivalent, delta: Int)
      -> some View
    {
      let enabled = (0..<cards.count).contains(index + delta)
      return Button {
        step(delta)
      } label: {
        Image(systemName: icon).font(.body.weight(.semibold))
          .frame(width: 32, height: 32)
          .background(.regularMaterial, in: Circle())
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .keyboardShortcut(key, modifiers: [])
      .disabled(!enabled)
      .opacity(hovering && enabled ? 1 : 0)
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: hovering)
      .help(label).accessibilityLabel(label)
    }
  #endif
}

/// Sizes the row from the width it is offered, in one layout pass: as wide as offered
/// (at most `maxWidth`), as tall as a building of that width less the neighbours' peek,
/// plus room above. Its one subview, the scroller, gets exactly that size.
private struct CardRowLayout: Layout {
  let peek: CGFloat
  let inset: CGFloat
  let maxWidth: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = min(proposal.width ?? 360, maxWidth)
    return CGSize(width: width, height: AccountCard.height(max(width - 2 * peek, 0)) + inset)
  }
  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    for subview in subviews {
      subview.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
  }
}
