import Foundation

/// Opening, creating, unlocking and locking the wallet, and its PIN. Key stretching
/// (Argon2) runs in the background, so a lock never waits behind an unlock.
extension WalletWorker {
  /// Reads the stored wallet, if any. An existing vault is never replaced or rewritten
  /// here. Only settings from another version of the app start over from the defaults.
  func load() throws -> Outcome {
    storage = try VaultStorage()
    let accounts = try storage?.readChecked("projects.json")
    let stored = try storage?.readChecked("settings.json")
    guard let vault = try storage?.readChecked("vault.json") else {
      // Settings or accounts without a vault: not a wallet this app wrote.
      if accounts != nil || stored != nil { throw CocoaError(.coderInvalidValue) }
      return Outcome()
    }
    guard let accounts, let stored else { throw CocoaError(.coderInvalidValue) }
    let loaded = try Wallet.load(vaultJson: vault, publicJson: accounts)
    var outcome = Outcome()
    if let current = try? LocalSettingsCodec.decode(Data(stored.utf8)) {
      snapshot.settings = current
      if LocalDevelopment.enabled, let defaults = try? defaults(),
        snapshot.settings.adoptDevelopmentAssets(from: defaults)
      {
        try? storage?.write("settings.json", encode(snapshot.settings))
      }
    } else {
      // Settings hold no secret: written by another version of the app, they start
      // over rather than keep the wallet closed.
      snapshot.settings = LocalSettings(defaults: try defaults())
      try storage?.write("settings.json", encode(snapshot.settings))
      outcome = Outcome(
        notice:
          "Settings from another version were reset: networks, tokens and colors are back to the defaults. Your wallet, accounts and recovery phrase are unchanged.",
        warning: true)
    }
    histories =
      (try? decode(
        [String: StoredHistory].self, try storage?.readChecked("history.json") ?? "{}"))
      ?? [:]
    snapshot.history = histories.values.flatMap(\.entries)
    snapshot.values =
      (try? decode(
        [String: [ValuePoint]].self, try storage?.readChecked("values.json") ?? "{}"))
      ?? [:]
    wallet = loaded
    return outcome
  }

  /// A new wallet from recovery words: unlocked, with one account and its first address.
  func create(words: String, pin: String) async throws -> Outcome {
    guard let storage, wallet == nil, try storage.readChecked("vault.json") == nil else {
      throw CocoaError(.fileWriteNoPermission)
    }
    let created = try await background {
      let created = try Wallet.create(words: words, pin: pin)
      try created.unlock(pin: pin)
      return created
    }
    // Checked again: another create may have finished while this one stretched its key.
    guard wallet == nil else { throw CocoaError(.fileWriteNoPermission) }
    let first = try created.addProject(label: "Main", slot: nil)
    _ = try created.address(slot: first, index: nil)
    wallet = created
    snapshot.settings = LocalSettings(defaults: try defaults())
    snapshot.settings.accents[String(first)] = AccountAccent.random(avoiding: [])
    try save()
    return Outcome()
  }

  func unlock(pin: String) async throws -> Outcome {
    let wallet = try unlockedWallet()
    try await background { try wallet.unlock(pin: pin) }
    return Outcome()
  }

  /// Unlocks with the key kept behind Face ID, Touch ID or the login password.
  func unlockWithDevice() async throws -> Outcome {
    guard let wallet, let storage, snapshot.settings.deviceUnlock != nil else {
      throw CocoaError(.fileWriteNoPermission)
    }
    let key: Data
    do {
      key = try DeviceUnlock.read(
        account: storage.deviceAccount, reason: "Unlock your Payroof wallet")
    } catch let error as DeviceUnlockError {
      if error == .missing {
        // Enrollment changed or the item was removed: stop offering a dead option.
        // The vault is untouched and the PIN keeps working.
        snapshot.settings.deviceUnlock = nil
        try? save()
      }
      throw WalletUserError(error.unlockMessage)
    }
    try await background { try wallet.unlockDevice(key: key) }
    return Outcome()
  }

  func enableDeviceUnlock(_ policy: DeviceUnlockPolicy) throws -> Outcome {
    guard let wallet, let storage else { throw CocoaError(.fileWriteNoPermission) }
    let key = try wallet.deviceKey()
    // Prove the system prompt works and returns the same key before relying on it.
    // A build that isn't signed for this device can't use the Keychain this way.
    do {
      try DeviceUnlock.store(key, account: storage.deviceAccount, policy: policy)
      let stored = try DeviceUnlock.read(
        account: storage.deviceAccount, reason: "Turn on device unlock for Payroof")
      guard stored == key else { throw DeviceUnlockError.failed }
    } catch {
      DeviceUnlock.delete(account: storage.deviceAccount)
      throw WalletUserError(
        (error as? DeviceUnlockError)?.enableMessage
          ?? "Device unlock wasn't turned on. Your PIN still works.")
    }
    snapshot.settings.deviceUnlock = policy
    try save()
    return Outcome(notice: "Device unlock is on. Your PIN still works and is never replaced.")
  }

  func disableDeviceUnlock() throws -> Outcome {
    guard let storage else { throw CocoaError(.fileWriteNoPermission) }
    DeviceUnlock.delete(account: storage.deviceAccount)
    snapshot.settings.deviceUnlock = nil
    try save()
    return Outcome()
  }

  /// Forgets the session key and everything shown only while unlocked.
  func lock() -> Outcome {
    wallet?.lock()
    snapshot.unlocked = false
    snapshot.address = nil
    clearPlan()
    snapshot.access = nil
    snapshot.accessLink = ""
    snapshot.accessProject = ""
    snapshot.grants = []
    snapshot.grantsConnection = ""
    return Outcome()
  }

  func changePIN(old: String, new: String) async throws -> Outcome {
    let wallet = try unlockedWallet()
    guard new.count >= 6 else { throw CocoaError(.coderInvalidValue) }
    try await background { try wallet.changePin(old: old, new: new) }
    try save()
    return Outcome(notice: "Passcode changed. Your recovery words stay the same.")
  }

  /// The recovery words of the open wallet. The core asks for the PIN again.
  func recoveryWords(pin: String) async throws -> String {
    let wallet = try unlockedWallet()
    return try await background { try wallet.recoveryWords(pin: pin) }
  }
}
