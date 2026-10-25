import Foundation

let settings = LocalSettings()
let data = try JSONEncoder().encode(settings)
let decoded = try JSONDecoder().decode(LocalSettings.self, from: data)
precondition(
  decoded.version == LocalSettings.schema && decoded.connections.isEmpty && decoded.networks.isEmpty
)
let complete = try JSONSerialization.jsonObject(with: data) as! [String: Any]
for key in complete.keys {
  var malformed = complete
  malformed.removeValue(forKey: key)
  let bytes = try JSONSerialization.data(withJSONObject: malformed)
  precondition(
    (try? JSONDecoder().decode(LocalSettings.self, from: bytes)) == nil, "Accepted missing \(key)")
  malformed[key] = NSNull()
  let nullBytes = try JSONSerialization.data(withJSONObject: malformed)
  precondition(
    (try? JSONDecoder().decode(LocalSettings.self, from: nullBytes)) == nil, "Accepted null \(key)")
}
precondition((try? JSONDecoder().decode(LocalSettings.self, from: Data("{}".utf8))) == nil)
precondition((try? JSONDecoder().decode(LocalTransfer.self, from: Data("{}".utf8))) == nil)
// Settings decode strictly: the current schema version with every key present.
let defaults = WalletDefaults(
  networks: [
    WalletNetwork(
      id: "eip155:1", name: "Ethereum", transactionMode: .eip1559,
      endpoints: [RPCEndpoint(name: "Public", url: "https://public.example")],
      endpoint: "https://public.example", enabled: true, color: "ocean")
  ], assets: [], apiOrigin: "https://api.example",
  storOrigin: "https://stor.example")
// Sorted keys: the edits below find fields by their neighbours, which needs a stable order.
let sortedEncoder = JSONEncoder()
sortedEncoder.outputFormatting = .sortedKeys
let stored = try sortedEncoder.encode(LocalSettings(defaults: defaults))
let seeded = try LocalSettingsCodec.decode(stored)
precondition(seeded.version == LocalSettings.schema)
precondition(seeded.networks.first?.endpoint == "https://public.example")
precondition(seeded.networks.first?.color == "ocean" && seeded.networks.first?.logo == nil)
// Settings of any other version are rejected, so the load path resets them.
for version in [1, LocalSettings.schema - 1, LocalSettings.schema + 1] {
  precondition(
    (try? LocalSettingsCodec.decode(Data(#"{"version":\#(version)}"#.utf8))) == nil,
    "Accepted version \(version)")
}
// The merged device unlock policy and the store links round-trip.
var linked = LocalSettings(defaults: defaults)
linked.deviceUnlock = .biometrics
linked.storeLinks = ["connection": ["https://sheet.example/1"]]
let relinked = try LocalSettingsCodec.decode(JSONEncoder().encode(linked))
precondition(relinked.deviceUnlock == .biometrics)
precondition(
  relinked.storeLinks == linked.storeLinks && relinked.storServer == "https://stor.example")
// A network or token without a color is not the current schema.
let colorless = String(decoding: stored, as: UTF8.self).replacingOccurrences(
  of: #""color":"ocean","#, with: "")
precondition(colorless != String(decoding: stored, as: UTF8.self))
precondition((try? LocalSettingsCodec.decode(Data(colorless.utf8))) == nil)
precondition((try? JSONDecoder().decode(WalletNetwork.self, from: Data("{}".utf8))) == nil)
print("Canonical persisted-schema checks passed")
