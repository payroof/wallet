import Foundation

let id = "pair_" + String(repeating: "a", count: 43)
let pairing = "https://api.example/v1/pairings/" + id
func envelope(_ inner: String) -> URL {
  var wrapper = URLComponents()
  wrapper.scheme = "payroof"
  wrapper.host = "pair"
  wrapper.queryItems = [URLQueryItem(name: "url", value: inner)]
  return wrapper.url!
}
precondition(WalletIncomingLink.resolve(envelope(pairing)) == pairing)
precondition(WalletIncomingLink.resolve(URL(string: pairing)!) == pairing)
for inner in [
  "http://api.example/v1/pairings/" + id,
  "https://user:secret@api.example/v1/pairings/" + id,
  pairing + "#fragment",
  pairing + "?approve=true",
  pairing + "/extra",
  "https://api.example/v1/pairings/pair_short",
  "https://api.example/v1/pairings/%70" + id.dropFirst(),
  "https://api.example/v1/pairings/../pairings/" + id,
  "payroof://pair?url=" + pairing,
  "javascript:alert(1)",
  "https://api.example/" + String(repeating: "x", count: 8192),
] {
  precondition(WalletIncomingLink.resolve(envelope(inner)) == nil, "Accepted invalid inner URL")
}
for raw in [
  "wrong://pair?url=" + pairing,
  "payroof://other?url=" + pairing,
  envelope(pairing).absoluteString + "&approve=true",
  envelope(pairing).absoluteString + "&url=" + pairing,
  envelope(pairing).absoluteString + "#fragment",
  "payroof://user:secret@pair?url=" + pairing,
  "payroof://pair",
] {
  precondition(WalletIncomingLink.resolve(URL(string: raw)!) == nil, "Accepted invalid envelope")
}
print("Incoming pairing envelope checks passed")
var pending = WalletIncomingLink.PendingRequest()
precondition(pending.receive(envelope(pairing)))
precondition(pending.take(unlocked: false, busy: false, reviewing: false) == nil)
precondition(pending.take(unlocked: true, busy: true, reviewing: false) == nil)
precondition(pending.take(unlocked: true, busy: false, reviewing: true) == nil)
precondition(pending.take(unlocked: true, busy: false, reviewing: false) == pairing)
precondition(pending.take(unlocked: true, busy: false, reviewing: false) == nil)
precondition(!pending.receive(URL(string: "payroof://pair")!))
print("In-memory locked/unlocked pairing routing checks passed")
