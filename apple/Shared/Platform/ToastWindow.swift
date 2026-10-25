import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

/// The toast's own window, above the wallet's content and every modal: in the right of
/// the wallet window's header on macOS, at the top of the screen on iOS.
///
/// The toast lays itself out at its own width, independent of the window, pinned to
/// the window's top right (macOS) or top centre (iOS), and reports the size it took.
/// The window follows that size, so it never cuts the toast short and never covers
/// more than the toast. Even while it catches up, the toast stays in its corner.
@MainActor final class WalletToastWindow {
  static let shared = WalletToastWindow()
  /// The widest a toast grows before its text wraps.
  static let width: CGFloat = 360
  /// Room around the toast for its shadow to fade out completely.
  static let margin: CGFloat = 28
  /// The toast's distance from the window's (macOS) or screen's (iOS) edges.
  static let inset: CGFloat = 12
  /// A toast is on screen (or fading out).
  private var visible = false
  /// The toast's laid-out size, shadow room included.
  private var size: CGSize = .zero
  /// What the toast's layout is offered: the widest toast, never wider than the window.
  private var offered: CGFloat = width + margin * 2

  private func root() -> WalletToastRoot {
    WalletToastRoot(
      width: offered,
      changed: { [weak self] in self?.changed($0) },
      resized: { [weak self] in self?.resized($0) })
  }
  private func changed(_ showing: Bool) {
    #if os(macOS)
      if showing && !visible { raise() }
    #endif
    visible = showing
    place()
  }
  private func resized(_ value: CGSize) {
    guard value != size else { return }
    size = value
    place()
  }

  #if os(macOS)
    private var panel: NSPanel?
    private var host: NSHostingView<WalletToastRoot>?
    private weak var parent: NSWindow?
    private var observers: [NSObjectProtocol] = []

    /// Follows the wallet window: attached as a child, it moves with it.
    func attach(to window: NSWindow) {
      guard parent !== window else { return }
      detach()
      parent = window
      let panel = ToastPanel(
        contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
      panel.isOpaque = false
      panel.backgroundColor = .clear
      panel.hasShadow = false
      panel.hidesOnDeactivate = true
      panel.isReleasedWhenClosed = false
      panel.ignoresMouseEvents = true
      panel.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
      let host = NSHostingView(rootView: root())
      // The window's size is set here, from the toast. The content never constrains it.
      host.sizingOptions = []
      host.autoresizingMask = [.width, .height]
      panel.contentView = host
      self.panel = panel
      self.host = host
      let center = NotificationCenter.default
      for name in [
        NSWindow.didResizeNotification, NSWindow.didEnterFullScreenNotification,
        NSWindow.didExitFullScreenNotification,
      ] {
        observers.append(
          center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.place() }
          })
      }
      observers.append(
        center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) {
          [weak self] _ in MainActor.assumeIsolated { self?.detach() }
        })
      place()
    }
    private func detach() {
      observers.forEach(NotificationCenter.default.removeObserver)
      observers = []
      if let panel {
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
      }
      panel = nil
      host = nil
      parent = nil
      visible = false
      size = .zero
    }
    /// Re-attached on top, so it is above any sheet opened since.
    private func raise() {
      guard let panel, let parent else { return }
      parent.removeChildWindow(panel)
      parent.addChildWindow(panel, ordered: .above)
      panel.level = .floating
    }
    /// In the window's header (title bar and toolbar): vertically centred in it, at its
    /// right edge, above the header's own buttons while it shows. A message taller than
    /// the header hangs from the header's top instead.
    private func place() {
      guard let panel, let host, let parent else { return }
      let window = parent.frame
      let content = parent.convertToScreen(parent.contentLayoutRect)
      let header = max(0, window.maxY - content.maxY)
      let margin = Self.margin
      let right = window.maxX - Self.inset
      // Never wider than the header leaves, clear of the window controls on the left.
      let widest = max(120, min(Self.width, right - window.minX - 80))
      if widest + margin * 2 != offered {
        offered = widest + margin * 2
        host.rootView = root()
      }
      let shown = visible && size.width > margin * 2
      let frame = shown ? size : CGSize(width: 1, height: 1)
      let toast = frame.height - margin * 2
      let middle =
        toast + 8 <= header ? window.maxY - header / 2 : window.maxY - 6 - toast / 2
      panel.setFrame(
        NSRect(
          x: right + margin - frame.width, y: middle - frame.height / 2,
          width: frame.width, height: frame.height),
        display: true)
      panel.ignoresMouseEvents = !shown
    }
  #else
    private var window: ToastUIWindow?
    private var host: UIHostingController<WalletToastRoot>?

    func attach(to scene: UIWindowScene) {
      guard window?.windowScene !== scene else { return }
      let window = ToastUIWindow(windowScene: scene)
      window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 1)
      window.backgroundColor = .clear
      let host = UIHostingController(rootView: root())
      host.view.backgroundColor = .clear
      host.sizingOptions = []
      window.rootViewController = host
      window.isHidden = false
      self.window = window
      self.host = host
      place()
    }
    private func place() {
      guard let window, let host, let scene = window.windowScene else { return }
      let bounds = scene.screen.bounds
      let margin = Self.margin
      let width = min(Self.width, bounds.width - Self.inset * 2) + margin * 2
      if width != offered {
        offered = width
        host.rootView = root()
      }
      let top = scene.windows.first { $0.isKeyWindow }?.safeAreaInsets.top ?? 0
      let shown = visible && size.width > margin * 2
      let frame = shown ? size : CGSize(width: 1, height: 1)
      window.frame = CGRect(
        x: (bounds.width - frame.width) / 2, y: top + 4 - margin,
        width: frame.width, height: frame.height)
      window.toast =
        shown ? CGRect(origin: .zero, size: frame).insetBy(dx: margin, dy: margin) : .zero
    }
  #endif
}

/// The toast window's content: the shared host in the app's appearance and accent, with
/// room for its shadow. It is laid out at `width`, whatever the window's size, pinned to
/// the window's top right (macOS) or top centre (iOS), and reports the size it takes.
struct WalletToastRoot: View {
  let width: CGFloat
  let changed: (Bool) -> Void
  let resized: (CGSize) -> Void
  @AppStorage(WalletStorageKey.appearance.rawValue) private var appearance = WalletAppearance.system
    .rawValue
  private let toasts = WalletToasts.shared
  #if os(macOS)
    private let edge = Alignment.topTrailing
  #else
    private let edge = Alignment.top
  #endif
  var body: some View {
    // The clear base is exactly the window's size. The toast overlays its corner.
    Color.clear.overlay(alignment: edge) {
      WalletToastHost(changed: changed)
        .padding(WalletToastWindow.margin)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGSize.self) {
          $0.size
        } action: {
          resized($0)
        }
        // Offered the same width whatever the window's size, so its text never wraps
        // into nothing while the window catches up.
        .frame(width: width, alignment: Alignment(horizontal: edge.horizontal, vertical: .top))
    }
    .environment(\.walletAccent, toasts.accent)
    .tint(toasts.accent.accent)
    .preferredColorScheme(WalletAppearance(rawValue: appearance)?.scheme ?? nil)
  }
}

#if os(macOS)
  private final class ToastPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
  }

  /// Hands the window it is placed in to the toast window.
  struct WalletToastAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { AnchorView() }
    func updateNSView(_ view: NSView, context: Context) {}
    private final class AnchorView: NSView {
      override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { WalletToastWindow.shared.attach(to: window) }
      }
    }
  }
#else
  /// Touches outside the toast fall through to the app below.
  private final class ToastUIWindow: UIWindow {
    var toast: CGRect = .zero
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
      toast.contains(point) ? super.hitTest(point, with: event) : nil
    }
  }

  /// Hands the scene it is placed in to the toast window.
  struct WalletToastAnchor: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { AnchorView() }
    func updateUIView(_ view: UIView, context: Context) {}
    private final class AnchorView: UIView {
      override func didMoveToWindow() {
        super.didMoveToWindow()
        if let scene = window?.windowScene { WalletToastWindow.shared.attach(to: scene) }
      }
    }
  }
#endif
