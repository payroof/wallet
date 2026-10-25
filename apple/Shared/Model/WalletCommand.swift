import Foundation

/// What a command works on. Commands on different operations run side by side, each
/// operation at most once at a time. Only the session (opening, creating or unlocking
/// the wallet, its PIN and device unlock) holds everything else back. So a slow request
/// (checking endpoints, a balance, the Payroof API) never keeps an unrelated action
/// waiting.
enum WalletOperation: Hashable, Sendable {
  case session
  /// Adding an account.
  case account
  /// Changing an account's name or accent color.
  case accent
  /// Deleting an account.
  case removal
  /// Deriving a receive address.
  case address
  /// One network: its endpoints, details, on/off and removal.
  case network(ChainID)
  /// Checking all of one network's endpoints.
  case probe(ChainID)
  /// Adding, editing or removing a token.
  case asset
  /// Showing or hiding one token.
  case visibility(AssetID)
  case providerKey
  /// Planning, confirming and carrying out a send.
  case send
  /// One Payroof API connection, `origin#project`.
  case connection(String)
  /// Reviewing or approving an access request.
  case access
  /// Choosing the Stor server.
  case stor
}

enum WalletCommand: Sendable {
  case load, generate
  case create(String, String)
  case unlock(String)
  case deviceUnlock, disableDeviceUnlock, lock
  case enableDeviceUnlock(DeviceUnlockPolicy)
  case project(String, UInt32?, String)
  /// Rename an account and set its accent color.
  case editAccount(UInt32, String, String)
  /// Delete an account and the local data of it.
  case removeAccount(UInt32)
  case address(UInt32, UInt32?)
  case exact(String)
  /// Add (after verifying chain identity) or replace an endpoint and select it.
  case addEndpoint(chain: ChainID, url: String, replacing: String?)
  case selectEndpoint(ChainID, String)
  case deleteEndpoint(ChainID, String)
  case probeEndpoints(ChainID)
  case setNetwork(ChainID, Bool)
  /// Add or update a network. A new network may also get a native coin entry. `look`
  /// replaces the stored color and logo. Nil keeps them (a new network gets a random preset color and no logo).
  case saveNetwork(
    chain: ChainID, name: String, mode: TransactionMode, explorer: String, currency: String?,
    look: WalletLook? = nil)
  case removeNetwork(ChainID)
  /// Add or update an asset, where `replacing` is the ID of the entry being edited.
  case saveAsset(WalletAsset, replacing: AssetID?)
  case removeAsset(AssetID)
  case assetVisible(AssetID, Bool)
  /// Plan a send: account slot, asset, recipient, amount, endpoint, preferred address.
  case plan(UInt32, AssetID, String, String, String, String?)
  /// The most the account can send of an asset, as Review would plan it: slot, asset,
  /// recipient (may be empty), endpoint, preferred path.
  case sendMaximum(UInt32, AssetID, String, String, String?)
  case confirmPlan(Bool)
  /// Sign and broadcast the plan's step at this index.
  case step(Int)
  /// Connect an account to its project: origin, name for a new project, slot. An account
  /// that already has a project there gets access to it back, whatever its name.
  case connect(String, String, UInt32)
  case sync(String, String, UInt32)
  case pairing(String, String, Bool)
  case dismissAccess
  case pin(String, String)
  /// The recovery words, shown again after the PIN is entered.
  case revealWords(String)
  case grants(String, String)
  case revokeGrant(String, String, String)
  /// Create a credential: origin, project, name, permissions. The token comes back once.
  case createGrant(String, String, String, [String])
  /// Create a store for the project: origin, project, Stor server, subdomain, Google
  /// Sheet, and the store's link to keep with the connection.
  case createStore(String, String, String, String, String, link: String)
  /// The Payments tab's URL and KEY for a store that already exists: origin, project,
  /// the store's subdomain, and its link to keep with the connection when it was given.
  /// The key comes back once.
  case storeKey(String, String, String, link: String?)
  /// Remember the Stor server stores are created on.
  case storServer(String)
  /// Store a provider's API key in the vault, or remove it when nil.
  case providerKey(KeyProvider, String?)
  case disconnect(String, String)
  var operation: WalletOperation {
    switch self {
    case .load, .generate, .create, .unlock, .deviceUnlock, .disableDeviceUnlock, .lock,
      .enableDeviceUnlock, .pin, .revealWords:
      .session
    case .project: .account
    case .editAccount: .accent
    case .removeAccount: .removal
    case .address, .exact: .address
    case .addEndpoint(let chain, _, _), .selectEndpoint(let chain, _),
      .deleteEndpoint(let chain, _), .setNetwork(let chain, _), .removeNetwork(let chain):
      .network(chain)
    case .saveNetwork(let chain, _, _, _, _, _): .network(chain)
    case .probeEndpoints(let chain): .probe(chain)
    case .saveAsset, .removeAsset: .asset
    case .assetVisible(let id, _): .visibility(id)
    case .providerKey: .providerKey
    case .plan, .sendMaximum, .confirmPlan, .step: .send
    case .connect(let origin, let project, _), .sync(let origin, let project, _),
      .grants(let origin, let project), .revokeGrant(let origin, let project, _),
      .createGrant(let origin, let project, _, _),
      .createStore(let origin, let project, _, _, _, _),
      .storeKey(let origin, let project, _, _),
      .disconnect(let origin, let project):
      .connection(origin + "#" + project)
    case .pairing, .dismissAccess: .access
    case .storServer: .stor
    }
  }
  var failureMessage: String {
    switch self {
    case .load:
      return
        "Your wallet could not be read. Check storage access and try again. Your files have not been replaced."
    case .unlock:
      return "Wrong passcode. Try again."
    case .revealWords:
      return "Wrong passcode, or too many tries. Wait a moment and try again."
    case .deviceUnlock:
      return "Device unlock unavailable. Use your PIN."
    case .enableDeviceUnlock:
      return "Device unlock wasn't turned on. Your PIN still works."
    case .create:
      return "Check your recovery words and passcode. Recovery words must be a valid BIP-39 phrase."
    case .plan:
      return
        "Could not prepare this transfer. Check the address, amount and RPC. Nothing was sent."
    case .sendMaximum:
      return "Could not work out the maximum. Check the network and try again."
    case .confirmPlan, .step:
      return
        "Transfer could not be completed or saved. Check Activity and the addresses on-chain before retrying."
    case .connect:
      return
        "Could not connect this account. Check the server and try again."
    case .sync:
      return
        "Could not find new addresses. Check the server. Existing addresses are unchanged."
    case .pairing:
      return
        "Could not review or approve access. Check the link, the project, and request expiry."
    case .createGrant:
      return "Could not create the token. Your access may not include these permissions."
    case .createStore:
      return "Could not create the store. Check the sheet link and try again."
    case .storeKey:
      return "Could not make the store's key. Check the store's address and try again."
    case .grants, .revokeGrant:
      return "Could not update access. Check the server and this device's permissions."
    case .providerKey: return "Check the key: letters, digits, - and _ only."
    case .disconnect:
      return "Could not disconnect. Nothing was changed. Try again."
    case .pin:
      return
        "Could not change the PIN. Check your current passcode and enter at least six characters for the new one."
    case .saveAsset: return "Check the token contract, symbol, and decimal count (0–36)."
    case .saveNetwork: return "Check the chain ID, network name and URLs."
    case .addEndpoint:
      return
        "Couldn't verify this endpoint. Check that it is a reachable HTTPS RPC URL for this network."
    case .probeEndpoints: return "Couldn't check endpoints. Try again."
    case .editAccount:
      return "Couldn't save the account. Use a name of 1 to 100 characters."
    case .removeAccount:
      return "Couldn't delete the account. It may be the last one. Nothing was changed."
    default:
      return
        "This action could not be completed. Check your inputs and wallet lock state, then try again."
    }
  }
}
