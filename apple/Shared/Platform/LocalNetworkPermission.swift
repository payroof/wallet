import Foundation

#if os(iOS)
  import Network
  import UIKit
#endif

/// iOS asks for "Local Network" access the first time an app reaches a device on the
/// LAN, and that first request fails at once instead of waiting for the answer. The
/// local test app (the Payroof stack on the Mac's Wi-Fi address) therefore asks first:
/// it advertises and browses for a private Bonjour service, which raises the same
/// prompt, and learns the answer when it sees its own advertisement (allowed) or the
/// system refuses the browse (denied). Network work waits for that answer, so the
/// request the user is waiting on runs once access is granted. Elsewhere (macOS, regular
/// iOS builds, which never use the LAN) everything returns at once.
@MainActor enum LocalNetworkPermission {
  /// The service type, also declared in the local app's Info plist (`NSBonjourServices`).
  static let service = "_payroof-lan._tcp"
  private static var answered = false
  private static var asking: Task<Void, Never>?
  /// Whether some work may have to wait for the answer (local test app, not answered yet).
  static var pending: Bool {
    #if os(iOS)
      LocalDevelopment.enabled && !answered
    #else
      false
    #endif
  }

  /// Starts asking without waiting (on unlock), so the prompt comes up at a calm moment.
  static func prepare() {
    #if os(iOS)
      guard LocalDevelopment.enabled, !answered, asking == nil else { return }
      asking = Task {
        _ = await Probe.run()
        answered = true
      }
    #endif
  }

  /// Returns once iOS has answered (granted or not). Immediately when not needed.
  static func ready() async {
    #if os(iOS)
      guard LocalDevelopment.enabled, !answered else { return }
      prepare()
      await asking?.value
    #endif
  }
}

#if os(iOS)
  /// One look on the LAN: a listener advertising the service and a browser looking for it.
  @MainActor private final class Probe {
    private let listener: NWListener?
    private let browser: NWBrowser
    private var continuation: CheckedContinuation<Bool, Never>?
    /// The probe that is running. Kept alive until it has its answer.
    private static var current: Probe?

    private init() {
      let parameters = NWParameters.tcp
      parameters.includePeerToPeer = false
      listener = try? NWListener(using: parameters)
      listener?.service = NWListener.Service(
        name: "payroof-\(UUID().uuidString.prefix(8))", type: LocalNetworkPermission.service)
      browser = NWBrowser(
        for: .bonjour(type: LocalNetworkPermission.service, domain: nil), using: parameters)
    }

    /// True when access is granted, false otherwise. While the system prompt is on
    /// screen the app is inactive, and the probe waits for it (up to two minutes). A
    /// refusal reported meanwhile is only provisional. With the app active and no
    /// answer after a few seconds (no network at all, say), it gives up, and the
    /// network work goes ahead and reports its own error.
    static func run() async -> Bool {
      await withCheckedContinuation { continuation in
        let probe = Probe()
        current = probe
        probe.continuation = continuation
        probe.start()
      }
    }

    /// The browse was refused at least once.
    private var refused = false

    private func start() {
      listener?.newConnectionHandler = { connection in connection.cancel() }
      listener?.stateUpdateHandler = { _ in }
      browser.browseResultsChangedHandler = { [weak self] results, _ in
        MainActor.assumeIsolated {
          if !results.isEmpty { self?.finish(true) }
        }
      }
      browser.stateUpdateHandler = { [weak self] state in
        MainActor.assumeIsolated {
          // -65570 is kDNSServiceErr_PolicyDenied: not allowed (or not yet).
          if case .waiting(let error) = state, case .dns(let code) = error, code == -65570 {
            self?.refused = true
          } else if case .failed = state {
            self?.finish(false)
          }
        }
      }
      listener?.start(queue: .main)
      browser.start(queue: .main)
      Task { [weak self] in
        var calm: Double = 0
        for _ in 0..<240 {
          try? await Task.sleep(for: .milliseconds(500))
          guard let self, self.continuation != nil else { return }
          // The prompt (or anything else over the app) keeps it inactive: keep waiting.
          if UIApplication.shared.applicationState != .active {
            calm = 0
            continue
          }
          calm += 0.5
          // Back in the app after a refusal, or long enough with nothing at all.
          if (self.refused && calm >= 1.5) || calm >= 6 { return self.finish(false) }
        }
        self?.finish(false)
      }
    }

    private func finish(_ granted: Bool) {
      guard let continuation else { return }
      self.continuation = nil
      browser.cancel()
      listener?.cancel()
      continuation.resume(returning: granted)
      Probe.current = nil
    }
  }
#endif
