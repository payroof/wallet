import Foundation

// Headless tests of the actual actor + native core. No window, screenshot,
// simulator, production storage, or network/API project is used.
struct MissingValue: Error {}
func unwrapped<T>(_ value: T?) throws -> T {
  guard let value else { throw MissingValue() }
  return value
}
@main struct RuntimeTests {
  static func main() async throws {
    guard LocalDevelopment.enabled,
      ProcessInfo.processInfo.environment["PAYROOF_WALLET_DATA_DIR"] != nil
    else { fatalError("Run with an isolated local-test directory") }
    let max = ExactAmount.maximum
    let exactMaximum = try ExactAmount.atomic(max, decimals: 0)
    precondition(exactMaximum == max)
    precondition(ExactAmount.display("1000000000000000001", decimals: 18) == "1.000000000000000001")
    for value in ["0", "-1", "1e18", "١", max + "0"] {
      var rejected = false
      do { _ = try ExactAmount.atomic(value, decimals: 0) } catch { rejected = true }
      precondition(rejected)
    }
    let worker = WalletWorker()
    let loaded = try await worker.perform(.load)
    precondition(!loaded.snapshot.exists)
    let words = Array(repeating: "abandon", count: 23).joined(separator: " ") + " art"
    let created = try await worker.perform(.create(words, "864200"))
    precondition(created.snapshot.unlocked && created.snapshot.projects.count == 1)
    precondition(AccountAccent.names.contains(created.snapshot.settings.accents["0"] ?? ""))
    let buyer = try await worker.perform(.project("Buyer", nil, "ocean"))
    precondition(buyer.snapshot.projects.count == 2 && buyer.snapshot.projects[1].slot == 1)
    precondition(buyer.snapshot.settings.accents["1"] == "ocean")
    precondition(AccountAccent.isValid("#1A2b3C") && !AccountAccent.isValid("#12345"))
    precondition(!AccountAccent.isValid("1A2B3C") && !AccountAccent.isValid("#GGGGGG"))
    precondition(!AccountAccent.isValid("#1A2B3C ") && !AccountAccent.isValid("Ocean"))
    // A new wallet starts from the core's defaults, stored as ordinary settings.
    precondition(created.snapshot.settings.version == LocalSettings.schema)
    precondition(created.snapshot.network("eip155:31337")?.endpoint == "http://127.0.0.1:8545")
    precondition(created.snapshot.settings.apiOrigin == "http://127.0.0.1:8080")
    // Selecting an existing endpoint needs no network access. Adding one must pass
    // a live chain check, so an unreachable one is rejected and not saved.
    let endpoint = try await worker.perform(
      .selectEndpoint("eip155:31337", "http://127.0.0.1:8545"))
    precondition(endpoint.snapshot.endpoint(for: "eip155:31337") == "http://127.0.0.1:8545")
    var unverifiedRejected = false
    do {
      _ = try await worker.perform(
        .addEndpoint(chain: "eip155:31337", url: "http://127.0.0.1:9", replacing: nil))
    } catch { unverifiedRejected = true }
    precondition(unverifiedRejected)
    let off = try await worker.perform(.setNetwork("eip155:31337", false))
    precondition(off.snapshot.endpoint(for: "eip155:31337") == nil)
    let on = try await worker.perform(.setNetwork("eip155:31337", true))
    precondition(on.snapshot.endpoint(for: "eip155:31337") == "http://127.0.0.1:8545")
    // A refresh is planned without touching a network: every network in use, in the
    // user's order, then prices. Limited to some networks, only those.
    let plan = await worker.refreshPlan(slots: [0], chains: nil)
    precondition(plan.chains == on.snapshot.networks.map(\.id).filter(Set(plan.chains).contains))
    precondition(plan.chains.contains("eip155:31337") && plan.connections.isEmpty)
    precondition(plan.prices && !plan.transfers && plan.steps == plan.chains.count + 1)
    let anvil = await worker.refreshPlan(slots: [0], chains: ["eip155:31337"])
    precondition(anvil.chains == ["eip155:31337"] && !anvil.prices && anvil.steps == 1)
    // Built-in keys count where they serve: Alchemy on Ethereum, none on Optimism.
    precondition(
      historySources(chain: "eip155:1", keys: ["etherscan"])
        == ["Etherscan", "Alchemy", "RPC"])
    precondition(historySources(chain: "eip155:10", keys: []) == ["RPC"])
    precondition(presetProviders(chain: "eip155:137") == ["alchemy", "infura", "ankr"])
    // An unlocked wallet lists the built-in providers' endpoints on the networks they serve.
    let polygon = on.snapshot.endpoints(for: "eip155:137").filter(\.isProvider).map(\.url)
    precondition(polygon == ["provider:alchemy", "provider:infura", "provider:ankr"])
    precondition(on.snapshot.presetProviders == ["alchemy", "infura", "ankr"])
    // Default entries are edited and removed exactly like user-added ones.
    let ethereum: ChainID = "eip155:1"
    let defaultURL = try! unwrapped(on.snapshot.network(ethereum)?.endpoints.first?.url)
    let removedEndpoint = try await worker.perform(.deleteEndpoint(ethereum, defaultURL))
    precondition(
      !removedEndpoint.snapshot.endpoints(for: ethereum).contains { $0.url == defaultURL })
    precondition(removedEndpoint.snapshot.endpoint(for: ethereum) != defaultURL)
    let usdc = try! unwrapped(
      removedEndpoint.snapshot.assets.first { $0.chain == ethereum && $0.symbol == "USDC" })
    var renamed = usdc
    renamed.symbol = "USDC-E"
    let edited = try await worker.perform(.saveAsset(renamed, replacing: usdc.id))
    precondition(edited.snapshot.assets.first { $0.id == usdc.id }?.symbol == "USDC-E")
    let removedAsset = try await worker.perform(.removeAsset(usdc.id))
    precondition(!removedAsset.snapshot.assets.contains { $0.id == usdc.id })
    let custom = try await worker.perform(
      .saveNetwork(
        chain: "eip155:10", name: "Optimism", mode: .eip1559,
        explorer: "https://optimistic.etherscan.io", currency: "ETH"))
    precondition(custom.snapshot.network("eip155:10")?.endpoints.isEmpty == true)
    precondition(
      Explorer.transaction("0xab", custom.snapshot.network("eip155:10"))?.absoluteString
        == "https://optimistic.etherscan.io/tx/0xab")
    precondition(custom.snapshot.nativeAsset("eip155:10")?.symbol == "ETH")
    let removedNetwork = try await worker.perform(.removeNetwork("eip155:56"))
    precondition(removedNetwork.snapshot.network("eip155:56") == nil)
    precondition(!removedNetwork.snapshot.assets.contains { $0.chain == "eip155:56" })
    // A provider key adds a virtual endpoint to the networks it serves. The key lives
    // only in the encrypted vault: settings and the snapshot never hold it.
    let secret = "k3y-SECRET_0123"
    let keyed = try await worker.perform(.providerKey(.alchemy, secret))
    precondition(keyed.snapshot.providers == ["alchemy"])
    precondition(
      keyed.snapshot.endpoints(for: ethereum).contains { $0.url == "provider:alchemy" })
    precondition(keyed.snapshot.endpoints(for: "eip155:31337").allSatisfy { !$0.isProvider })
    let chosen = try await worker.perform(.selectEndpoint(ethereum, "provider:alchemy"))
    precondition(chosen.snapshot.endpoint(for: ethereum) == "provider:alchemy")
    precondition(chosen.snapshot.endpointName("provider:alchemy", chain: ethereum) == "Alchemy")
    let directory = URL(
      fileURLWithPath: try unwrapped(ProcessInfo.processInfo.environment["PAYROOF_WALLET_DATA_DIR"])
    )
    for name in ["settings.json", "vault.json", "projects.json"] {
      let text = try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
      precondition(!text.contains(secret), "\(name) holds the provider key")
    }
    var badKeyRejected = false
    do { _ = try await worker.perform(.providerKey(.infura, "not a key")) } catch {
      badKeyRejected = true
    }
    precondition(badKeyRejected)
    let unkeyed = try await worker.perform(.providerKey(.alchemy, nil))
    precondition(unkeyed.snapshot.providers.isEmpty)
    precondition(unkeyed.snapshot.endpoint(for: ethereum) != "provider:alchemy")
    var replacementRejected = false
    do { _ = try await worker.perform(.create(words, "864200")) } catch {
      replacementRejected = true
    }
    precondition(replacementRejected)
    _ = try await worker.perform(.pin("864200", "864201"))
    _ = try await worker.perform(.lock)
    var oldRejected = false
    do { _ = try await worker.perform(.unlock("864200")) } catch { oldRejected = true }
    precondition(oldRejected)
    _ = try await worker.perform(.unlock("864201"))
    let reopened = WalletWorker()
    let snapshot = try await reopened.perform(.load)
    precondition(
      snapshot.snapshot.exists && !snapshot.snapshot.unlocked
        && snapshot.snapshot.projects.count == 2)
    // Edits persist, and removed defaults stay removed after a reload.
    precondition(snapshot.snapshot.network("eip155:56") == nil)
    precondition(!snapshot.snapshot.assets.contains { $0.id == usdc.id })
    precondition(!snapshot.snapshot.endpoints(for: ethereum).contains { $0.url == defaultURL })
    precondition(snapshot.snapshot.network("eip155:10")?.name == "Optimism")
    precondition(
      ProjectCard(slot: 0, label: "Order", paths: ["m/0/10", "m/0/2"]).orderedPaths == [
        "m/0/2", "m/0/10",
      ])
    // The account's own addresses come first, then its payment addresses (branch 1).
    precondition(
      ProjectCard(slot: 0, label: "Order", paths: ["m/1/0", "m/0/10", "m/1/3", "m/0/2"])
        .orderedPaths == ["m/0/2", "m/0/10", "m/1/0", "m/1/3"])
    // Receive opens on the newest own address. Payment addresses only when there's none.
    precondition(
      ProjectCard(slot: 0, label: "Latest", paths: ["m/0/2", "m/1/9", "m/0/10", "m/0/0"])
        .latestPath == "m/0/10")
    precondition(
      ProjectCard(slot: 0, label: "Latest", paths: ["m/1/3", "m/1/12"]).latestPath == "m/1/12")
    precondition(ProjectCard(slot: 0, label: "Latest", paths: []).latestPath == nil)
    precondition(WalletText.addressName("m/44'/60'/0'/0/7") == "Address 7")
    precondition(WalletText.addressName("m/44'/60'/0'/1/7") == "Payment 7")
    let storage = try VaultStorage()
    let originalSettings = try storage.readChecked("settings.json")!
    defer { try? storage.write("settings.json", originalSettings) }
    var unsupported = snapshot.snapshot.settings
    unsupported.version = 4
    // Settings from another version start over from the defaults. The vault and
    // accounts are read as they are and never rewritten.
    let vaultBefore = try storage.readChecked("vault.json")
    for stale in [String(decoding: try JSONEncoder().encode(unsupported), as: UTF8.self), "{}"] {
      try storage.write("settings.json", stale)
      let loaded = try await WalletWorker().perform(.load)
      let reset = loaded.snapshot
      precondition(reset.exists && reset.projects.count == 2 && loaded.warning)
      precondition(
        reset.network("eip155:56") != nil && reset.settings.version == LocalSettings.schema)
      let vaultAfter = try storage.readChecked("vault.json")
      precondition(vaultAfter == vaultBefore)
      let rewritten = try unwrapped(storage.readChecked("settings.json"))
      let decoded = try LocalSettingsCodec.decode(Data(rewritten.utf8))
      precondition(decoded.version == LocalSettings.schema)
    }
    print(
      "PASS: native actor creation, editable configuration, account isolation, exact amounts, PIN change, lock, reload, overwrite refusal and settings reset"
    )
  }
}
