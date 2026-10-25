import Foundation

// Standalone host-policy test: stub only the native build/runtime capability.
func localDevelopmentEnabled() -> Bool {
  ProcessInfo.processInfo.environment["TEST_NATIVE_LOCAL_CAPABILITY"] == "1"
}
let mode = CommandLine.arguments[1]
if mode == "isolated" {
  precondition(LocalDevelopment.enabled)
  let storage = try VaultStorage()
  try storage.write("settings.json", "{\"localTest\":true}")
  let stored = try storage.readChecked("settings.json")
  precondition(stored == "{\"localTest\":true}")
} else if mode == "reject" {
  do {
    _ = try VaultStorage()
    fatalError("Unsafe storage launch accepted")
  } catch {}
} else if mode == "defaults" {
  precondition(!LocalDevelopment.enabled)
  precondition(!LocalDevelopment.permitsEndpoint(URLComponents(string: "http://127.0.0.1:8080")!))
  precondition(
    !LocalDevelopment.permitsEndpoint(URLComponents(string: "http://192.168.1.20:8080")!))
}
if mode == "isolated" {
  precondition(
    LocalDevelopment.permitsEndpoint(URLComponents(string: "http://192.168.68.50:8080")!))
  precondition(LocalDevelopment.permitsEndpoint(URLComponents(string: "http://10.0.0.5:8545")!))
  precondition(!LocalDevelopment.permitsEndpoint(URLComponents(string: "http://8.8.8.8:8080")!))
  precondition(!LocalDevelopment.permitsEndpoint(URLComponents(string: "http://172.32.0.1")!))
  precondition(!LocalDevelopment.permitsEndpoint(URLComponents(string: "http://192.168.1.256")!))
}
precondition(!LocalDevelopment.permitsEndpoint(URLComponents(string: "http://example.com")!))
precondition(LocalDevelopment.permitsEndpoint(URLComponents(string: "https://api.example")!))
print("Host policy passed: \(mode)")
