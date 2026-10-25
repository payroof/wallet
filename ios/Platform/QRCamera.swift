import AVFoundation
import SwiftUI
import UIKit

/// The back camera, reading QR codes with AVFoundation's metadata output. Each new
/// payload is published once in `code`, and QRScanner decides whether it is the one it wants.
@MainActor @Observable final class QRCamera {
  private(set) var code: String?
  private(set) var problem: QRCameraProblem?
  /// Frames are on screen.
  private(set) var live = false
  private(set) var torchOn = false
  private(set) var torchAvailable = false
  static let settingsURL = URL(string: UIApplication.openSettingsURLString)
  let runner = CaptureRunner()
  private let reader = MetadataReader()
  private var device: AVCaptureDevice?
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
    setTorch(false)
    runner.stop()
  }
  /// Forget the last code, so the same one is reported again.
  func rescan() { code = nil }
  func toggleTorch() { setTorch(!torchOn) }

  fileprivate func received(_ value: String) {
    guard !stopped, value != code else { return }
    code = value
  }
  private func setTorch(_ on: Bool) {
    guard let device, device.hasTorch, on != torchOn,
      (try? device.lockForConfiguration()) != nil
    else { return }
    device.torchMode = on ? .on : .off
    device.unlockForConfiguration()
    torchOn = on
  }
  private func configure() {
    guard !stopped else { return }
    if configured {
      runner.start { [weak self] in Task { @MainActor in self?.started() } }
      return
    }
    let session = runner.session
    guard
      let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        ?? AVCaptureDevice.default(for: .video),
      let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input)
    else {
      problem = .unavailable
      return
    }
    let output = AVCaptureMetadataOutput()
    guard session.canAddOutput(output) else {
      problem = .unavailable
      return
    }
    session.addInput(input)
    session.addOutput(output)
    output.setMetadataObjectsDelegate(reader, queue: .main)
    output.metadataObjectTypes = [.qr]
    // QR codes are read up close: focus there first.
    if device.isAutoFocusRangeRestrictionSupported, (try? device.lockForConfiguration()) != nil {
      device.autoFocusRangeRestriction = .near
      device.unlockForConfiguration()
    }
    self.device = device
    torchAvailable = device.hasTorch
    configured = true
    runner.start { [weak self] in Task { @MainActor in self?.started() } }
  }
  private func started() {
    if !stopped { live = true }
  }
}

private final class MetadataReader: NSObject, AVCaptureMetadataOutputObjectsDelegate,
  @unchecked Sendable
{
  /// Set on the main actor before frames arrive.
  weak var camera: QRCamera?
  func metadataOutput(
    _ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject],
    from connection: AVCaptureConnection
  ) {
    guard
      let value = objects.lazy.compactMap({
        ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue
      }).first
    else { return }
    let camera = camera
    Task { @MainActor in camera?.received(value) }
  }
}

/// The live camera image, kept upright as the device turns.
struct CameraPreview: UIViewRepresentable {
  let session: AVCaptureSession
  /// Changes when frames start, so rotation is followed once the camera is known.
  var live: Bool
  func makeUIView(context: Context) -> PreviewView {
    let view = PreviewView()
    view.preview?.session = session
    view.preview?.videoGravity = .resizeAspectFill
    return view
  }
  func updateUIView(_ view: PreviewView, context: Context) { view.followRotation() }
}

final class PreviewView: UIView {
  override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
  var preview: AVCaptureVideoPreviewLayer? { layer as? AVCaptureVideoPreviewLayer }
  private var coordinator: AVCaptureDevice.RotationCoordinator?
  private var observation: NSKeyValueObservation?
  func followRotation() {
    guard coordinator == nil, let preview,
      let device = (preview.session?.inputs.first as? AVCaptureDeviceInput)?.device
    else { return }
    let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: preview)
    self.coordinator = coordinator
    observation = coordinator.observe(
      \.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]
    ) { [weak self] coordinator, _ in
      let angle = coordinator.videoRotationAngleForHorizonLevelPreview
      Task { @MainActor in self?.rotate(angle) }
    }
  }
  private func rotate(_ angle: CGFloat) {
    guard let connection = preview?.connection, connection.isVideoRotationAngleSupported(angle)
    else { return }
    connection.videoRotationAngle = angle
  }
}
