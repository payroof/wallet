import AVFoundation
import SwiftUI
import Vision

/// The Mac's camera (built in, external or an iPhone via Continuity Camera), looking for
/// a QR code with Vision a few times a second. Each new payload is published once in
/// `code`, and QRScanner decides whether it is the one it wants.
@MainActor @Observable final class QRCamera {
  private(set) var code: String?
  private(set) var problem: QRCameraProblem?
  /// Frames are on screen.
  private(set) var live = false
  /// Macs have no flashlight.
  let torchOn = false
  let torchAvailable = false
  static let settingsURL = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
  let runner = CaptureRunner()
  private let reader = FrameReader()
  private var configured = false
  private var stopped = false

  func start() {
    stopped = false
    reader.camera = self
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: configure()
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { allowed in
        Task { @MainActor in
          if allowed { self.configure() } else { self.problem = .denied }
        }
      }
    default: problem = .denied
    }
  }
  func stop() {
    stopped = true
    runner.stop()
  }
  /// Forget the last code, so the same one is reported again.
  func rescan() { code = nil }
  func toggleTorch() {}

  fileprivate func received(_ value: String) {
    guard !stopped, value != code else { return }
    code = value
  }
  private func configure() {
    guard !stopped else { return }
    if configured {
      runner.start { [weak self] in Task { @MainActor in self?.started() } }
      return
    }
    let session = runner.session
    guard let device = AVCaptureDevice.default(for: .video),
      let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input)
    else {
      problem = .unavailable
      return
    }
    let output = AVCaptureVideoDataOutput()
    output.alwaysDiscardsLateVideoFrames = true
    guard session.canAddOutput(output) else {
      problem = .unavailable
      return
    }
    session.addInput(input)
    session.addOutput(output)
    output.setSampleBufferDelegate(reader, queue: reader.queue)
    configured = true
    runner.start { [weak self] in Task { @MainActor in self?.started() } }
  }
  private func started() {
    if !stopped { live = true }
  }
}

/// Looks for a QR code in a few frames a second, on its own serial queue.
private final class FrameReader: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate,
  @unchecked Sendable
{
  let queue = DispatchQueue(label: "top.payroof.wallet.qr")
  /// Set on the main actor before frames arrive.
  weak var camera: QRCamera?
  private var last = Date.distantPast
  func captureOutput(
    _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    let now = Date()
    guard now.timeIntervalSince(last) >= 0.2 else { return }
    last = now
    let request = VNDetectBarcodesRequest()
    request.symbologies = [.qr]
    try? VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up).perform([request])
    guard let value = request.results?.lazy.compactMap(\.payloadStringValue).first else { return }
    let camera = camera
    Task { @MainActor in camera?.received(value) }
  }
}

/// The live camera image.
struct CameraPreview: NSViewRepresentable {
  let session: AVCaptureSession
  var live: Bool
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    let layer = AVCaptureVideoPreviewLayer(session: session)
    layer.videoGravity = .resizeAspectFill
    view.layer = layer
    view.wantsLayer = true
    return view
  }
  func updateNSView(_ view: NSView, context: Context) {}
}
