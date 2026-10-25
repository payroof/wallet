import CryptoKit
import Foundation

final class VaultStorage {
  /// Every file the wallet keeps. Any other name is refused.
  static let files: Set = [
    "vault.json", "projects.json", "sources.json", "paths.json", "settings.json", "history.json",
    "values.json",
  ]
  private let directory: URL
  /// The Keychain account of this vault's device unlock. A custom data directory gets
  /// its own, so an isolated wallet can never read or replace the real wallet's item.
  let deviceAccount: String
  init() throws {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let production = base.appendingPathComponent("PayroofWallet", isDirectory: true)
      .resolvingSymlinksInPath().standardizedFileURL
    let environment = ProcessInfo.processInfo.environment
    if environment["PAYROOF_WALLET_LOCAL_DEVELOPMENT"] != nil
      || environment["PAYROOF_WALLET_DATA_DIR"] != nil
    {
      // Fail closed: a malformed local launch must never fall back to the real vault.
      guard LocalDevelopment.enabled, let path = environment["PAYROOF_WALLET_DATA_DIR"],
        path.hasPrefix("/")
      else { throw CocoaError(.fileWriteNoPermission) }
      let isolated = URL(fileURLWithPath: path, isDirectory: true).resolvingSymlinksInPath()
        .standardizedFileURL
      guard isolated.path != production.path, !isolated.path.hasPrefix(production.path + "/"),
        !production.path.hasPrefix(isolated.path + "/")
      else { throw CocoaError(.fileWriteNoPermission) }
      directory = isolated
      deviceAccount =
        "primary-"
        + SHA256.hash(data: Data(isolated.path.utf8)).prefix(8).map {
          String(format: "%02x", $0)
        }.joined()
    } else {
      directory = production
      deviceAccount = "primary"
    }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    var url = directory
    var flags = URLResourceValues()
    flags.isExcludedFromBackup = true
    try url.setResourceValues(flags)
  }
  func readChecked(_ name: String) throws -> String? {
    guard Self.files.contains(name) else { throw CocoaError(.fileReadInvalidFileName) }
    let url = directory.appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try String(contentsOf: url, encoding: .utf8)
  }
  func write(_ name: String, _ value: String) throws {
    guard Self.files.contains(name) else { throw CocoaError(.fileWriteInvalidFileName) }
    let url = directory.appendingPathComponent(name)
    let bytes = Data(value.utf8)
    #if os(iOS)
      try bytes.write(to: url, options: [.atomic, .completeFileProtection])
    #else
      try bytes.write(to: url, options: .atomic)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    #endif
  }
}
