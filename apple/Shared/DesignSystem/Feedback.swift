import SwiftUI

/// Transient feedback for a screen or modal: nothing, an operation in progress, or
/// a message. Every surface hands its status to `walletStatus(_:dismiss:)`. One toast
/// shows the newest surface's status outside all content, at the top right of the
/// window on macOS and at the top of the screen on iOS, so it never crowds a modal.
///
/// The app's feedback rules:
/// - Progress belongs to the control that started it (a busy button title, the PIN
///   indicators). The toast carries progress only when no such control exists.
/// - Operation results (success, information, failure) use the toast. Every message
///   fades on its own (problems stay longer), and also closes when tapped, when it is
///   replaced, or when the user moves to another screen.
/// - Input the user must correct is flagged inline at the field (`WalletField`
///   error), where it stays for as long as the input is invalid.
enum WalletStatus: Hashable {
  case idle
  case progress(String)
  case message(String, WalletTone)
  var text: String? {
    switch self {
    case .idle: nil
    case .progress(let text), .message(let text, _): text
    }
  }
  /// How long a message stays before fading. Problems stay longer so they can be
  /// read. VoiceOver users get extra time. Progress stays until it ends.
  func lifetime(voiceOver: Bool) -> Duration? {
    guard case .message(_, let tone) = self else { return nil }
    let seconds = tone == .success || tone == .neutral ? 4 : 8
    return .seconds(voiceOver ? seconds * 2 + 2 : seconds)
  }
}

/// The toast itself: a pill on frosted glass, its tone carried by a round badge with the
/// icon (a turning vent while something runs), so state never depends on color alone.
/// One continuous shape: the badge sits inside it, nothing is drawn on its edge.
struct WalletToast: View {
  let status: WalletStatus
  /// Nil for progress, which ends on its own.
  let dismiss: (() -> Void)?
  @Environment(\.colorScheme) private var scheme
  var body: some View {
    HStack(alignment: .center, spacing: 10) {
      badge
      Text(status.text ?? "").font(.callout.weight(.medium))
        .foregroundStyle(WalletTheme.text)
        .fixedSize(horizontal: false, vertical: true).lineLimit(4)
        .frame(minHeight: 28)
      if let dismiss {
        Button(action: dismiss) {
          Image(systemName: "xmark").font(.caption2.weight(.bold))
            .foregroundStyle(WalletTheme.muted)
            .frame(width: 24, height: 24)
            .background(WalletTheme.text.opacity(0.06), in: Circle())
            .contentShape(Circle())
        }.buttonStyle(.plain)
          .accessibilityLabel("Dismiss message").help("Dismiss")
      }
    }
    .padding(.leading, 7).padding(.trailing, dismiss == nil ? 16 : 8).padding(.vertical, 7)
    .background {
      shape.fill(.regularMaterial)
        .overlay(shape.fill(tint.opacity(scheme == .dark ? 0.10 : 0.06)))
        .overlay(shape.strokeBorder(tint.opacity(0.24), lineWidth: 1))
        // Light catching the glass along its top edge.
        .overlay(
          shape.strokeBorder(Color.white.opacity(scheme == .dark ? 0.14 : 0.6), lineWidth: 1)
            .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .center))
        )
        // Two soft layers: a close contact shadow and a wide, faint one that fades out
        // well inside the toast's window.
        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.12), radius: 10, y: 6)
    }
    .accessibilityElement(children: .contain)
  }
  /// Capsule while the message fits one line. The radius stays the same as it wraps.
  private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 21, style: .continuous) }
  @ViewBuilder private var badge: some View {
    ZStack {
      Circle().fill(tint)
      switch status {
      case .progress:
        WalletSpinner(size: 16).foregroundStyle(ink)
      case .message(_, let tone):
        Image(systemName: Self.glyph(tone)).font(.caption.weight(.bold))
          .foregroundStyle(ink)
      case .idle:
        EmptyView()
      }
    }
    .frame(width: 28, height: 28)
    .accessibilityHidden(true)
  }
  /// The badge's glyph: white on the deep day tones, near-black on the light night ones.
  private var ink: Color { scheme == .dark ? Color.black.opacity(0.82) : .white }
  private static func glyph(_ tone: WalletTone) -> String {
    switch tone {
    case .neutral, .accent: "info"
    case .success: "checkmark"
    case .warning: "exclamationmark"
    case .danger: "xmark"
    }
  }
  private var tint: AnyShapeStyle {
    if case .message(_, let tone) = status, tone != .neutral { return tone.color }
    return AnyShapeStyle(WalletTheme.accent)
  }
}

/// Every surface that reports status, newest last. The toast shows the newest one
/// that has something to say, so an idle modal lets the screen behind it speak.
@MainActor @Observable final class WalletToasts {
  static let shared = WalletToasts()
  struct Source {
    var status: WalletStatus
    var dismiss: (() -> Void)?
    var modal: Bool
  }
  private var sources: [(id: UUID, source: Source)] = []
  /// Open modals that report status. A new one starts a new context.
  private(set) var modals = 0
  /// The current account's accent, for the toast window, which has no model of its own.
  var accent = WalletAccent.copper
  func set(_ id: UUID, _ source: Source) {
    if let index = sources.firstIndex(where: { $0.id == id }) {
      sources[index].source = source
    } else {
      sources.append((id, source))
      if source.modal { modals += 1 }
    }
  }
  func remove(_ id: UUID) {
    guard let index = sources.firstIndex(where: { $0.id == id }) else { return }
    if sources[index].source.modal { modals = max(0, modals - 1) }
    sources.remove(at: index)
  }
  var current: Source? { sources.last { $0.source.status != .idle }?.source }
}

private struct WalletStatusSource: ViewModifier {
  let status: WalletStatus
  let dismiss: (() -> Void)?
  let modal: Bool
  @State private var id = UUID()
  func body(content: Content) -> some View {
    content
      .onAppear { publish() }
      .onChange(of: status) { _, _ in publish() }
      .onDisappear { WalletToasts.shared.remove(id) }
  }
  private func publish() {
    WalletToasts.shared.set(id, .init(status: status, dismiss: dismiss, modal: modal))
  }
}

extension View {
  /// Reports `status` to the app's single toast while this view is on screen.
  /// `dismiss` clears the source of the message (e.g. the model's feedback).
  func walletStatus(
    _ status: WalletStatus, dismiss: (() -> Void)? = nil, modal: Bool = false
  ) -> some View {
    modifier(WalletStatusSource(status: status, dismiss: dismiss, modal: modal))
  }
}

/// The one toast, drawn in its own window above every screen and modal (see
/// `WalletToastWindow`, which sizes that window to it). `changed` reports whether a
/// toast shows whenever what it shows changes. False once it has faded out.
struct WalletToastHost: View {
  let changed: (Bool) -> Void
  private let toasts = WalletToasts.shared
  @State private var shown: WalletStatus = .idle
  @State private var hovering = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
  private struct Key: Equatable {
    let status: WalletStatus
    let hovering: Bool
  }
  private var status: WalletStatus { toasts.current?.status ?? .idle }
  var body: some View {
    ZStack {
      if shown != .idle {
        WalletToast(status: shown, dismiss: dismissAction)
          .contentShape(Rectangle())
          // Tapping a message anywhere closes it.
          .onTapGesture { if dismissAction != nil { close() } }
          .onHover { hovering = $0 }
          .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
          // Progress that moves on updates in place. A new message replaces the old.
          .id(identity)
      }
    }
    .task(id: Key(status: status, hovering: hovering)) { await present() }
    .task(id: shown) {
      // The window fits each new toast at once and shrinks once it has faded out.
      guard shown == .idle else { return changed(true) }
      try? await Task.sleep(for: .milliseconds(300))
      if !Task.isCancelled { changed(false) }
    }
  }
  private var identity: String {
    if case .message(let text, _) = shown { return text }
    return "progress"
  }
  /// Messages can be dismissed. Progress ends on its own.
  private var dismissAction: (() -> Void)? {
    if case .message = shown { return { close() } }
    return nil
  }
  private func close() {
    let dismiss = toasts.current?.dismiss
    set(.idle)
    dismiss?()
  }
  private func set(_ value: WalletStatus) {
    withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.22)) {
      shown = value
    }
  }
  private func present() async {
    if case .progress = status, shown == .idle {
      // Brief operations finish before their progress would flash on screen.
      try? await Task.sleep(for: .milliseconds(400))
      guard !Task.isCancelled else { return }
    }
    if shown != status {
      let announce = status.text != nil && !(isProgress(shown) && isProgress(status))
      set(status)
      if announce, let text = status.text { AccessibilityNotification.Announcement(text).post() }
    }
    // Messages fade. A pointer resting on the toast holds it.
    guard let lifetime = status.lifetime(voiceOver: voiceOver), !hovering else { return }
    try? await Task.sleep(for: lifetime)
    guard !Task.isCancelled else { return }
    close()
  }
  private func isProgress(_ status: WalletStatus) -> Bool {
    if case .progress = status { true } else { false }
  }
}

struct WalletBadge: View {
  let title: String
  var tone: WalletTone = .success
  var icon: String? = nil
  init(title: String, tone: WalletTone = .success, icon: String? = nil) {
    self.title = title
    self.tone = tone
    self.icon = icon
  }
  var body: some View {
    HStack(spacing: 4) {
      if let icon { Image(systemName: icon).imageScale(.small) }
      Text(title)
    }
    .font(RoofFont.stencil(11, relativeTo: .caption)).tracking(0.6).lineLimit(1)
    .padding(.horizontal, 8).padding(.top, 4).padding(.bottom, 3)
    .foregroundStyle(tone.color)
    .background(tone.color.opacity(0.12), in: Capsule())
    .overlay(Capsule().strokeBorder(tone.color.opacity(0.22), lineWidth: 0.8))
  }
}

/// Inline guidance about the screen's current state (unlike a toast, it stays while the
/// state does). Neutral notes are plain text. The others are notices: a soft card tinted
/// by their role with a round badge, like the toasts. `.accent` is for something the
/// user can put right themselves and wears the current account's color, usually with
/// the fix as its action. The `.warning` and `.danger` tones keep their fixed colors, because their
/// meaning must not change with an account's color. `icon` names the situation itself
/// (an eye for privacy, a clock for waiting) instead of a generic sign.
struct WalletNote: View {
  struct Action {
    var title: String
    var icon: String
    var busy = false
    var run: () -> Void
  }
  let text: String
  var tone: WalletTone = .neutral
  var icon: String? = nil
  var action: Action? = nil
  @Environment(\.colorScheme) private var scheme
  init(_ text: String, tone: WalletTone = .neutral, icon: String? = nil, action: Action? = nil) {
    self.text = text
    self.tone = tone
    self.icon = icon
    self.action = action
  }
  var body: some View {
    if tone == .neutral {
      HStack(alignment: .top, spacing: 8) {
        WalletLineIcon(systemName: icon ?? tone.icon).foregroundStyle(WalletTheme.muted)
        Text(text).foregroundStyle(WalletTheme.muted)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
      }
      .font(.footnote)
      .accessibilityElement(children: .combine)
    } else {
      notice
    }
  }

  private var notice: some View {
    let shape = RoundedRectangle(cornerRadius: WalletMetrics.radius, style: .continuous)
    return VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .center, spacing: 11) {
        Image(systemName: icon ?? Self.glyph(tone)).font(.footnote.weight(.bold))
          .foregroundStyle(scheme == .dark ? Color.black.opacity(0.82) : .white)
          .frame(width: 30, height: 30)
          .background(tint, in: Circle())
          .accessibilityHidden(true)
        Text(text).font(.footnote.weight(.medium)).foregroundStyle(WalletTheme.text)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
        if let action, !actionBelow {
          actionButton(action)
        }
      }
      if let action, actionBelow {
        actionButton(action).frame(maxWidth: .infinity, alignment: .trailing)
      }
    }
    .padding(.vertical, 10).padding(.leading, 10).padding(.trailing, 12)
    .background(shape.fill(tint.opacity(0.09)))
    .background(shape.fill(WalletTheme.surface))
    .overlay(shape.strokeBorder(tint.opacity(0.3), lineWidth: 1))
    .accessibilityElement(children: .contain)
  }
  /// A long message leaves no room beside it: its action moves underneath.
  private var actionBelow: Bool { text.count > 70 }

  private func actionButton(_ action: Action) -> some View {
    Button {
      WalletHaptics.tap()
      action.run()
    } label: {
      HStack(spacing: 5) {
        if action.busy {
          WalletSpinner(size: 13)
        } else {
          Image(systemName: action.icon).font(.caption.weight(.bold))
        }
        Text(action.title).font(.footnote.weight(.semibold))
      }
      .foregroundStyle(scheme == .dark ? Color.black.opacity(0.85) : .white)
      .padding(.horizontal, 12).frame(minHeight: 32)
      .background(tint, in: Capsule())
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .fixedSize()
    .disabled(action.busy)
    .accessibilityLabel(action.title)
  }

  private var tint: AnyShapeStyle {
    tone == .accent ? AnyShapeStyle(WalletTheme.accent) : tone.color
  }
  private static func glyph(_ tone: WalletTone) -> String {
    switch tone {
    case .neutral, .accent: "info"
    case .success: "checkmark"
    case .warning: "exclamationmark"
    case .danger: "xmark"
    }
  }
}
