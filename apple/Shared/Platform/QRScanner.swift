import AVFoundation
import SwiftUI

/// A full-screen QR scanner: the camera, dimmed outside a clear frame with corner
/// guides, one short prompt, a close button and, where the camera has one, a
/// flashlight. The frame turns red for a code of the wrong kind and green when read.
/// The camera itself is per platform (QRCamera, CameraPreview in ios/ and macos/).
struct QRScanner: View {
  var purpose: QRScanPurpose
  var onCancel: () -> Void
  var onRead: (String) -> Void
  @State private var camera = QRCamera()
  @State private var phase = Phase.looking
  @State private var reset: Task<Void, Never>?
  @Environment(\.openURL) private var openURL
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private enum Phase { case looking, invalid, found }

  var body: some View {
    GeometryReader { geometry in
      let side = min(min(geometry.size.width, geometry.size.height) * 0.68, 300)
      ZStack {
        Color.black
        CameraPreview(session: camera.runner.session, live: camera.live)
          .opacity(camera.live ? 1 : 0)
        if let problem = camera.problem {
          problemView(problem)
        } else {
          dimming(side)
          ViewfinderCorners()
            .stroke(cornerColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
            .frame(width: side, height: side)
            .scaleEffect(phase == .found && !reduceMotion ? 0.94 : 1)
            .accessibilityHidden(true)
            .overlay {
              if !camera.live { ProgressView().controlSize(.large).tint(.white) }
            }
            .overlay(alignment: .bottom) {
              prompt.fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: max(side, 300))
                .alignmentGuide(.bottom) { $0[.top] - 28 }
            }
        }
      }
      .ignoresSafeArea()
      // Controls stay inside the safe area, clear of the status bar and home indicator.
      .overlay {
        VStack {
          HStack {
            Spacer()
            closeButton
          }
          Spacer()
          if camera.torchAvailable, camera.problem == nil { torchButton }
        }
        .padding(16)
      }
    }
    .environment(\.colorScheme, .dark)
    .animation(reduceMotion ? nil : .spring(duration: 0.3), value: phase)
    .animation(.easeOut(duration: 0.25), value: camera.live)
    #if os(macOS)
      .frame(width: 520, height: 560)
    #else
      .presentationBackground(.black)
    #endif
    .onAppear { camera.start() }
    .onDisappear {
      reset?.cancel()
      camera.stop()
    }
    .onChange(of: camera.code) { _, value in
      if let value { handle(value) }
    }
  }

  private func handle(_ value: String) {
    guard phase != .found else { return }
    reset?.cancel()
    guard purpose.accepts(value) else {
      if phase != .invalid {
        WalletHaptics.notify(success: false)
        AccessibilityNotification.Announcement(purpose.invalidMessage).post()
      }
      phase = .invalid
      // Back to looking after a moment. The same wrong code is then reported again.
      reset = Task {
        try? await Task.sleep(for: .seconds(2.5))
        guard !Task.isCancelled else { return }
        phase = .looking
        camera.rescan()
      }
      return
    }
    phase = .found
    camera.stop()
    WalletHaptics.notify(success: true)
    AccessibilityNotification.Announcement("QR code scanned").post()
    // A short beat so the green frame is seen before the scanner closes.
    reset = Task {
      try? await Task.sleep(for: .milliseconds(reduceMotion ? 150 : 450))
      guard !Task.isCancelled else { return }
      onRead(value)
    }
  }

  private var cornerColor: Color {
    switch phase {
    case .looking: .white
    case .invalid: WalletTheme.danger
    case .found: WalletTheme.success
    }
  }
  /// Darkens everything but the frame, so the eye goes straight to it.
  private func dimming(_ side: CGFloat) -> some View {
    Rectangle().fill(.black.opacity(0.55))
      .mask {
        ZStack {
          Rectangle()
          RoundedRectangle(cornerRadius: 24).frame(width: side, height: side)
            .blendMode(.destinationOut)
        }
        .compositingGroup()
      }
      .accessibilityHidden(true)
  }
  private var prompt: some View {
    let (icon, title, detail, tint): (String, String, String, Color) =
      switch phase {
      case .looking: ("qrcode.viewfinder", purpose.title, "Fit the QR code in the frame", .white)
      case .invalid:
        (
          "exclamationmark.triangle.fill", purpose.invalidMessage, "Try another QR code",
          WalletTheme.danger
        )
      case .found: ("checkmark.circle.fill", "Scanned", "One moment…", WalletTheme.success)
      }
    return HStack(spacing: 12) {
      Image(systemName: icon).font(.title3.weight(.semibold)).foregroundStyle(tint)
        .contentTransition(.symbolEffect(.replace))
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.headline).foregroundStyle(.white)
        Text(detail).font(.subheadline).foregroundStyle(.white.opacity(0.75))
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 16).padding(.vertical, 12)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    .accessibilityElement(children: .combine)
  }
  /// The sheets' own Close: the account-colored cross on its shaped (here, dark)
  /// backing, which keeps it clear over any camera image.
  private var closeButton: some View {
    WalletCloseButton(title: "Close camera", action: cancel)
  }
  private var torchButton: some View {
    Button {
      camera.toggleTorch()
    } label: {
      Image(systemName: camera.torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
        .font(.title3).foregroundStyle(camera.torchOn ? .yellow : .white)
        .frame(width: 56, height: 56)
        .background(.ultraThinMaterial, in: Circle())
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Flashlight")
    .accessibilityValue(camera.torchOn ? "On" : "Off")
  }
  private func problemView(_ problem: QRCameraProblem) -> some View {
    VStack(spacing: 14) {
      Image(systemName: problem == .denied ? "video.slash.fill" : "camera.fill")
        .font(.system(size: 40)).foregroundStyle(.white.opacity(0.85))
        .accessibilityHidden(true)
      Text(problem == .denied ? "Camera access is off" : "No camera available")
        .font(.title3.weight(.semibold)).foregroundStyle(.white)
      Text(
        problem == .denied
          ? "Allow camera access in Settings to scan QR codes."
          : "Connect a camera, or paste the text instead."
      )
      .font(.callout).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
      if problem == .denied, let url = QRCamera.settingsURL {
        Button("Open Settings") { openURL(url) }
          .buttonStyle(.borderedProminent).walletTint().padding(.top, 6)
      }
    }
    .padding(32).frame(maxWidth: 360)
  }
  private func cancel() {
    reset?.cancel()
    camera.stop()
    onCancel()
  }
}

/// Four rounded corner guides around the scan area.
struct ViewfinderCorners: Shape {
  var length: CGFloat = 36
  var radius: CGFloat = 24
  func path(in r: CGRect) -> Path {
    var p = Path()
    let corners: [(CGPoint, CGPoint, CGPoint)] = [
      (
        CGPoint(x: r.minX, y: r.minY + length), CGPoint(x: r.minX, y: r.minY),
        CGPoint(x: r.minX + length, y: r.minY)
      ),
      (
        CGPoint(x: r.maxX - length, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
        CGPoint(x: r.maxX, y: r.minY + length)
      ),
      (
        CGPoint(x: r.maxX, y: r.maxY - length), CGPoint(x: r.maxX, y: r.maxY),
        CGPoint(x: r.maxX - length, y: r.maxY)
      ),
      (
        CGPoint(x: r.minX + length, y: r.maxY), CGPoint(x: r.minX, y: r.maxY),
        CGPoint(x: r.minX, y: r.maxY - length)
      ),
    ]
    for (start, corner, end) in corners {
      p.move(to: start)
      p.addArc(tangent1End: corner, tangent2End: end, radius: radius)
      p.addLine(to: end)
    }
    return p
  }
}

enum QRCameraProblem { case denied, unavailable }

/// `@unchecked Sendable` because AVCaptureSession is not Sendable yet is thread safe for
/// start and stop. Configuration is completed on the main actor before the first start. Blocking
/// start/stop calls are serialized on this queue. The session is not mutated after.
final class CaptureRunner: @unchecked Sendable {
  let session = AVCaptureSession()
  private let queue = DispatchQueue(label: "top.payroof.wallet.camera")
  func start(_ started: @escaping @Sendable () -> Void) {
    queue.async {
      self.session.startRunning()
      if self.session.isRunning { started() }
    }
  }
  func stop() { queue.async { self.session.stopRunning() } }
}
