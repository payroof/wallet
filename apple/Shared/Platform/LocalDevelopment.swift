import Foundation

enum LocalDevelopment {
  static var enabled: Bool {
    #if os(macOS) && DEBUG
      return ProcessInfo.processInfo.environment["PAYROOF_WALLET_LOCAL_DEVELOPMENT"] == "1"
        && localDevelopmentEnabled()
    #elseif os(iOS) && DEBUG
      // Only the separate ios-device-local app links a core built with local development.
      return localDevelopmentEnabled()
    #else
      return false
    #endif
  }
  static func permitsEndpoint(_ value: URLComponents) -> Bool {
    value.scheme == "https"
      || (enabled && value.scheme == "http"
        && (["localhost", "127.0.0.1", "[::1]", "::1"].contains(value.host ?? "")
          || isPrivateIPv4(value.host ?? "")))
  }
  /// RFC 1918 LAN address (e.g. the Mac's Wi-Fi IP used by roofer). Dotted-quad only.
  static func isPrivateIPv4(_ host: String) -> Bool {
    let parts = host.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 4 else { return false }
    var octets: [Int] = []
    for part in parts {
      guard (1...3).contains(part.count), part.allSatisfy({ $0.isASCII && $0.isNumber }),
        let value = Int(part), value <= 255
      else { return false }
      octets.append(value)
    }
    return octets[0] == 10
      || (octets[0] == 172 && (16...31).contains(octets[1]))
      || (octets[0] == 192 && octets[1] == 168)
  }
  static func origin(_ raw: String) -> String? {
    guard let url = URLComponents(string: raw), permitsEndpoint(url), let host = url.host,
      url.user == nil, url.password == nil
    else { return nil }
    let defaultPort = url.scheme == "https" ? 443 : 80
    return "\(url.scheme!)://\(host.lowercased())"
      + (url.port == nil || url.port == defaultPort ? "" : ":\(url.port!)")
  }
}
