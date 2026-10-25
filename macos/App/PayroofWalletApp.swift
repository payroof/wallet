import AppKit
import SwiftUI

@MainActor final class WalletAppDelegate: NSObject, NSApplicationDelegate {
  private weak var model: WalletModel?
  private var pendingURL: URL?
  private var activityMonitor: Any?

  func attach(_ model: WalletModel) {
    self.model = model
    // Input in the app restarts the inactivity timer at once. Input elsewhere on the
    // Mac is read when it fires (see `UserIdle`).
    if activityMonitor == nil {
      activityMonitor = NSEvent.addLocalMonitorForEvents(matching: [
        .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseDragged,
        .scrollWheel,
      ]) { [weak self] event in
        MainActor.assumeIsolated { self?.model?.touch() }
        return event
      }
    }
    if let url = pendingURL {
      pendingURL = nil
      model.receive(url)
    }
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    guard let url = urls.last else { return }
    if let model {
      model.receive(url)
    } else if WalletIncomingLink.resolve(url) != nil {
      pendingURL = url
    }
    application.activate()
    (application.mainWindow ?? application.windows.first { $0.canBecomeMain })?
      .makeKeyAndOrderFront(nil)
  }
}

@main struct PayroofWalletApp: App {
  @NSApplicationDelegateAdaptor(WalletAppDelegate.self) private var delegate
  @State private var model = WalletModel()
  @Environment(\.scenePhase) private var phase

  var body: some Scene {
    // A single Window scene prevents URLs and New Window from opening another vault session.
    Window("Payroof Wallet", id: "wallet") {
      WalletView().environment(model)
        .onAppear { delegate.attach(model) }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
          if let url = activity.webpageURL { model.receive(url) }
        }
        // Switching away or minimizing doesn't lock: the wallet locks after 5 minutes
        // without any input on the Mac. Sleep and screen lock below lock at once.
        .onChange(of: phase) { _, value in
          if value == .active { model.returnedToApp() } else { model.leftApp() }
        }
        .onReceive(
          NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
        ) { _ in model.leftApp() }
        .onReceive(
          NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in model.returnedToApp() }
        .onReceive(
          NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
        ) { _ in model.lock() }
        .onReceive(
          NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.sessionDidResignActiveNotification)
        ) { _ in model.lock() }
    }
    .defaultSize(width: 1000, height: 760)
  }
}
