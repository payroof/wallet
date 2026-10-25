# Architecture

Both Apple hosts compile `apple/Shared/` directly: one implementation of the domain
models, exact decimal arithmetic, the worker, presentation state, design system and
screens. Host folders (`ios/`, `macos/`) contain only entry points, assets, the
iOS camera scanner and tests. One primary type per file. The file is named after it.

```
Shared/
  App/            Root view and navigation (WalletView, WalletSection)
  Model/          WalletModel (MainActor state, running operations, locking, idle
                  timeout), commands and their operations, snapshot, feedback,
                  formatting, portfolio grouping, incoming links
    Worker/       WalletWorker, the Rust/RPC/persistence boundary: one file per
                  domain (session, accounts and API, networks, assets, send, refresh)
    Domain/       Codable records: networks, assets, transfers, accounts, Payroof API,
                  persisted settings (one strict schema), ExactAmount
  Platform/       VaultStorage, LocalDevelopment, DeviceUnlock, PublicClipboard,
                  UserIdle, the toast window
  DesignSystem/   Theme and accent palette, layout, buttons, fields, PIN entry,
                  feedback (toast), modal sheets, selection, content rows, brand
  Features/       One folder per feature: Onboarding, Unlock, Home, Activity, Send,
                  Receive, Addresses, Access, Accounts, Settings (one view per page;
                  sidebar destinations on macOS, the Settings tab on iOS)
```

The accent follows the current account through the environment (`\.walletAccent`, set
once at the root from the model, and in the toast window from `WalletToasts`). Theme
accent shades are styles resolved from it at draw time, so switching accounts recolors
views in place and never rebuilds the window. A command that creates an account reports
its slot, and the model selects it in the same update as the snapshot that holds it.

Views never sign or perform blocking work. The worker does. Each command declares the
operation it works on (`WalletOperation`): commands on different operations run side by
side, one operation at most once at a time, and only the session (opening, unlocking,
the PIN) holds everything back. Views disable and show progress for their own
operation only, so a slow request never blocks an unrelated action. Inside the worker,
every call that waits (network, Argon2) runs off the actor. Code after an `await`
looks state up again by identity, each command returns its own message, and snapshots
carry a revision so a late result never replaces newer state. Receipt queries keep
the reviewed RPC even if settings change. Unreadable or corrupt wallets never turn
into a fresh-wallet onboarding flow. Swift sources follow `swift-format` with the
repository's `.swift-format` (`swift-format lint --strict -r apple macos/Tests macos/App ios/App tests`).

The Rust derivation, encrypted vault, signing, origin pinning, chain checks, and
API permissions remain the security authority. Display values never use floating
point. New wallets use a guided six-digit PIN. Settings can change it to any passcode
of six or more characters. Recovery words never have a
clipboard action. Public addresses, contract identities, hashes, and origins do.

The iOS camera scanner has explicit address and pairing purposes. Send accepts
only a plain, nonzero EVM address and fills the recipient field. Scanning never
prepares or sends a transfer. Pairing accepts only permitted transport URLs,
leaving strict pairing parsing and explicit approval to Rust and the review flow.
iOS does not enable local HTTP development mode. Both scanner sheets offer cancel,
invalid-code feedback, and purpose-specific camera-permission instructions.

Settings use synthesized Codable with required current fields and a checked
schema version. Settings of any other version are replaced by the defaults (with a
warning), while the vault and accounts are only ever read as they are. On iOS the files
use complete data protection: a launch while the device is locked waits for the unlock
instead of failing. Network requests release the core's lock and run off the worker
actor, so user commands never queue behind a slow endpoint. The core's `default_configuration`
seeds networks, endpoints, tokens and the API origin once, at wallet creation.
Token price oracles (`price: {url, field}`) are ordinary asset settings. Fetched USD prices are cached per asset and only feed the Home total.
Balances are cached per address so Wallet can show where each amount is held. Transfers require their source, RPC and historical asset snapshot.
`tests/swift-harnesses.sh` compiles and runs the standalone Swift checks (host
policy, persisted schema, incoming links, native runtime) in a temporary directory.

Provider keys (Alchemy, Infura, Ankr, Etherscan) live only in the vault's secrets. Swift
learns which providers have a key. Each adds virtual `provider:<name>` endpoints that
Rust resolves to real URLs right before a request, so URLs and keys never reach Swift
or error text. Built-in keys (`PRESETS` in `providers.rs`) cover Alchemy on Ethereum and
Polygon, Infura on Ethereum, Polygon, Base and Arbitrum, and Ankr on those plus BNB Smart
Chain. Each is used only on the chains it serves and only until the user saves their
own key for that provider. Activity is found per network from the account's derived addresses and
the wallet's own assets with a persisted cursor: Etherscan V2 (key), Alchemy (key), then
an RPC log scan, each falling back on error. Native transfers are only scanned by block on loopback development nodes.
Swift stores history per network and account and merges it with locally signed sends.

The Rust core is the security authority for everything above: `src/` holds
derivation (`derivation`, `watch_root`), the vault (`vault`, `secret`), RPC reads
(`balance`, `price`), provider key resolution (`providers`), local activity (`history`, keyed `indexer` sources), the send plan (`plan` for funding
sources and gas sponsor, `capability`, `eip712` and `abi` for what a token supports and its typed
signatures, `send` for gathering the facts and running confirmed steps, and `spending` for transaction
signing), the Payroof API client
(`api`, `pairing`, `path_source`, `recovery`), the Stor client (`stor`) and the UniFFI surface (`ffi`). Each
blocking FFI call runs its network work on its own single-threaded runtime on the
calling background thread, after reading what it needs under the wallet's lock and
releasing it, so calls proceed in parallel and the lock is never held across a request.

Not supported: chains other than EVM, automatic pairing approval, and Universal Links without signed
Associated Domains.

## Send plan

`plan_send` takes the current account's paths from Rust's own project list (never from
the host) and returns a reviewable plan or a structured problem. The plan funds the
amount from the account's addresses (a preferred path first, else one address that covers
it, else the largest balances) and gives every leg a gas method in order of preference:
the source pays (`transfer`), a sponsor submits an EIP-3009 `transferWithAuthorization`,
an EIP-2612 `permit` + `transferFrom`, or a sponsor `top_up` of the exact fee followed by
the source's `transfer`. The sponsor is the account address with the most native coin
that covers every fee it fronts. A token's EIP-712 domain and standards are proven with
`eth_call` only (separator must match on chain). Anything unproven falls back to a
top-up. Nothing is signed before `confirm_plan(true)`. `execute_step` then signs one
step at a time in order, checks the chain id, requires successful receipts of its
dependencies, estimates the real signed call against the reviewed gas ceiling before
broadcast, and sequences nonces per sender. The plan lasts 15 minutes (120 s to start).

## Repository layout

| Path | Contents |
|---|---|
| `src/` | Rust core (`payroof-wallet-core`): derivation, vault, RPC, signing, API client. Exposed to Swift with UniFFI |
| `apple/Shared/` | The SwiftUI app shared by both platforms |
| `macos/`, `ios/` | XcodeGen projects, entry points, assets, macOS unit tests |
| `assets/defaults.json` | Networks, RPCs, tokens and price sources a new wallet starts with |
| `tests/` | Rust integration tests and standalone Swift harnesses |

## Vault

```text
PIN → Argon2id → key-encryption key (KEK)
                          ↓ wraps
                 random data-encryption key (DEK)
                          ↓ XChaCha20-Poly1305
                 mnemonic + credentials ciphertext
```

Changing PIN rewraps the same DEK. Biometrics are optional OS-protected convenience
unlock. Temporary Rust secrets are zeroized. Native host string allocations and
real-device behavior require separate manual review. Never log words, seed, PIN,
DEK, private keys, or Access Tokens.

## Safety boundaries

- Mnemonics, private keys and API credentials stay in the encrypted vault.
- Pairing accepts canonical HTTPS `/v1/pairings/pair_…` URLs only. Credentials,
  fragments, queries, encoded/normalized paths and extra segments are rejected.
- Review the exact API origin, Project, permissions and expiry before allowing.
  Requester names are unverified labels, not merchant identity proofs.
- API path feeds are public-address discovery, not balance or spending authority.
  Imported paths must match the locally derived watch root.
- Atomic amounts and signing inputs remain exact. Display/USD estimates never
  drive transaction amounts. RPC network identity is checked before use.

