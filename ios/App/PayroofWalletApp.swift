import SwiftUI

@main struct PayroofWalletApp: App {
  @State private var model = WalletModel()
  @Environment(\.scenePhase) private var phase
  var body: some Scene {
    WindowGroup {
      WalletView().environment(model)
        .onOpenURL { model.receive($0) }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
          if let url = activity.webpageURL { model.receive(url) }
        }
        // Any touch or typing is activity. Leaving the app doesn't lock. The 5-minute
        // inactivity limit applies on return. Device lock (below) still locks at once.
        .background(ActivityTracker { model.touch() })
        .background(KeyboardDismissal())
        .onChange(of: phase) { _, value in
          if value == .active { model.returnedToApp() } else { model.leftApp() }
        }
        // The app switcher's snapshot never shows the unlocked wallet.
        .overlay {
          if phase != .active && model.session.unlocked {
            ZStack {
              SkyBackdrop(animated: false, fadesIntoCanvas: false).ignoresSafeArea()
              PayroofMark(size: 72)
            }
            .accessibilityHidden(true)
          }
        }
        .onReceive(
          NotificationCenter.default.publisher(
            for: UIApplication.protectedDataWillBecomeUnavailableNotification)
        ) { _ in model.lock() }
        .onReceive(
          NotificationCenter.default.publisher(
            for: UIApplication.protectedDataDidBecomeAvailableNotification)
        ) { _ in model.dataBecameAvailable() }
    }
  }
}
