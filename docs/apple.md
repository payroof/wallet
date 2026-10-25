# Apple apps

Run from the repository root (Xcode, XcodeGen and the pinned Rust toolchain are required):

```sh
./build-apple.sh macos
./build-apple.sh ios-simulator
```

The script builds the Rust static library with `--locked`, generates UniFFI
Swift bindings and an Xcode project, then compiles the unsigned host.
Artifacts are under `target/apple-<sdk>`. `CONFIGURATION=Release` builds the stripped,
size-optimised app. The Rust core targets the apps' minimum OS versions (macOS 15, iOS 18).
Use `ios` for the device SDK. Device installation requires Apple signing and provisioning:
`DEVELOPMENT_TEAM=<team> DEVICE_ID=<udid> ./build-apple.sh ios-device` makes a signed build,
and `roofer ios [--device NAME]` (a separate Payroof dev tool) builds, installs and launches it on a paired iPhone.
`PAYROOF_LOCAL_HOST=<Mac LAN IPv4> DEVELOPMENT_TEAM=<team> ./build-apple.sh ios-device-local`
(or `roofer ios --local`) makes a separate test app (bundle ID `<id>.local`, own data and
Keychain) with the `local-development` core: plain HTTP to loopback or a private LAN IPv4, and
new wallets preset to Anvil (`:8545`), Payroof (`:8080`) and Stor (`:8081`) at that host.
`roofer up --ios` starts that stack on the Mac's Wi-Fi address and installs the test app in
one step. iOS asks for Local Network access on the first connection to the Mac and fails
that connection while asking, so the test app asks first: once unlocked it browses for its
own Bonjour service (`_payroof-lan._tcp`, declared in `ios/Info-Local.plist`), and network
work waits until iOS has an answer (`LocalNetworkPermission`). Regular iOS builds stay HTTPS-only.
macOS and simulator builds select the host architecture.

## Isolated localhost manual workflow (macOS only)

Never use real recovery words or real funds here. The existing production vault
at `~/Library/Application Support/PayroofWallet` is not used or modified.
Device unlock works in local mode with its own Keychain item, named after the data
directory, so the production item is never read, written or deleted. It needs a
signed build: `DEVELOPMENT_TEAM=<team ID> ./build-apple.sh macos-local` signs
automatically as `top.payroof.wallet.local`, sandboxed, with the Keychain access group
from `macos/WalletSigned.entitlements` (its data directory must then be inside its own
container). The Mac must be registered with the team once (its Provisioning UDID under
Certificates, Identifiers & Profiles → Devices). Without the team the build is unsigned:
it has no application identifier, the data protection Keychain refuses it
(`errSecMissingEntitlement`), so Security offers PIN only and says why. PIN
creation/import remains manual.

From the workspace's `wallet` directory:

```sh
./build-apple.sh macos-local
mkdir -p ../.local/manual/wallet
chmod 700 ../.local/manual/wallet
open -n -F \
  --env PAYROOF_WALLET_LOCAL_DEVELOPMENT=1 \
  --env PAYROOF_WALLET_DATA_DIR="$(cd .. && pwd)/.local/manual/wallet" \
  "$PWD/target/apple-macosx-local/Build/Products/Debug/PayroofWallet.app"
```

Quit this instance before reopening it. Do not concurrently open two instances
against the same directory. Local app artifacts have their own DerivedData path.
If macOS starts the app without a window, choose **File → New Window**.
`macos-local` explicitly enables the default-off Rust `local-development` feature
even though the static library is compiled with `--release`. Swift additionally
requires `DEBUG`, runtime opt-in, and an absolute isolated data directory. Missing,
invalid, or production-overlapping paths fail closed rather than opening the real
vault. Normal `macos`/iOS builds omit the feature. Normal launches use the unchanged
production path and HTTPS-only behavior. Local mode permits HTTP only to
`localhost`, `127.0.0.1`, `[::1]`, or a private LAN IPv4 (10/8, 172.16/12, 192.168/16). HTTPS origin pins, recovery signatures,
pairing permissions, redirect restrictions, and RPC chain checks are unchanged.

Manual UI steps (Anvil and a Payroof server must already be running. Creating a store also needs Stor):

1. Choose a new test-only PIN and
    generate/write down or import a **TEST** mnemonic. New wallets use a guided
    six-digit PIN setup, a 24-word paper backup, and checks of words 3, 9, and 18.
    No mnemonic/PIN is prefilled. A longer or alphanumeric passcode (set in
    Security → Change passcode) unlocks with the keyboard key left of 0 on the PIN pad.
2. Local mode adds the **Anvil** network (chain ID 31337, `http://127.0.0.1:8545`) with
   its test **ETH** and the **TEST**, **USDC** and **DAI** tokens `roofer` deploys on a fresh
   chain (at their fixed addresses; a local wallet created earlier gets them on its next
   launch), off like any test network: turn it on in **Networks & tokens**. Every
   other network and token stays as configured. RPC chain identity is checked, so no other chain
   can stand in for Anvil.
3. On the **Project** page, with the local account selected (initially Main,
   slot 0), choose **Connect**, keep the server `http://127.0.0.1:8080` and enter a
   fresh project name (for example `manual`). Connecting registers the project and
   verifies its watch root. When the same test mnemonic and slot already own a
   project there, Connect recovers access to it instead, under its own name.
4. Request a pairing from the Payroof server (`POST /v1/pairings`, see its
   [HTTP reference](https://github.com/payroof/payroof/blob/main/docs/http-api.md)).
   Paste the returned `http://127.0.0.1:8080/v1/pairings/…` link into **Pair** in
   Project. Click **Review**, inspect origin, selected Project,
   permissions, and expiry, then explicitly approve. No automatic grant.
5. Once the Payroof server has payment addresses for the project (for example from a
   store created with **+** under **Stores** on the Project page, with Stor at
   `http://127.0.0.1:8081`), open **Wallet**: each balance refresh
   (**Refresh** at the top right of Home or Activity) first adds the connected Project's new
   payment addresses. **Activity** lists incoming transfers found on
   the chain (Anvil is scanned block by block). **Find new addresses** (the arrow in
   the Project header) does the address step on demand. The local Project
   must match the account slot used for registration.
6. In **Receive**, show a selected public address (or add a new address). Fund
    that address using the local Anvil funding workflow. **Wallet → Refresh**
   queries Anvil for the selected Project. Discovery itself does not fund it.
7. In **Send**, pick the source address and **TEST ETH · Anvil** in the two pills at
   the top, enter amount and recipient, review maximum fees, then explicitly
   **Confirm & sign locally**. Its receipt is followed. Activity → Refresh reads incoming transfers.
   ERC-20s are added in **Networks & tokens → Add token** from their contract, or with the
   **+** beside a network's power button, which opens Add token on that network. Add token
   picks the network from a row of round, colored network marks. The selected one's full
   name is written under the row.

The wallet auto-locks after 5 minutes without activity (1 minute to 1 hour in
**Security → Auto-lock**) and at once when the device sleeps or locks. On macOS any input on the Mac counts, so working in another app or a
terminal keeps it unlocked. On iOS touches in the app count and time in the background
counts as idle. It never locks while an operation is running.
On iOS the app-switcher snapshot is covered. Activity lists incoming and outgoing transfers of this account's addresses and the
wallet's own assets, found on the device, together with transfers signed here.
Both open the same detail: amount, value at today's price and status first, then From → To
(the wallet's own addresses by name), network, account and the transaction. Raw values sit
under Technical details, the exact amount among them. Activity's filter (top left) opens a
sheet: networks as chips, direction, and one address from a searchable list that stays fast
with thousands of addresses. Settings → **Lights out** (also in the Mac's sidebar) takes the
stars and shooting stars out of the night sky, on every page and in every sheet, and keeps
the scenery's window lights and sign bulbs dark. The moon and clouds stay.
Every sheet wears the same backdrop (`WalletSheetBackdrop`): a band of sky fading into the
canvas. By day the sun stands as the local hour puts it (high and white at noon, low and
amber toward evening) among soft, layered cumulus. By night the moon shows its real phase
with a true terminator and a halo as bright as it is full, and long clouds lit on the
moon's side hide the stars behind them.
Amounts are rounded for display (`ExactAmount.rounded`): two decimals from 1 000, four from
1, four significant digits below 1, so a fee reads `0.00009187 ETH`. Balances and amounts
available round down, fee limits round up. Exact values stay in Technical details, on
hover and in what is copied.
After **Confirm & sign locally** the paper plane flies and Send shows the transfer's
status: sent and waiting for a block, confirmed, or failed on-chain, updated as receipts
arrive, with Details and Explorer. A transfer that can't be sent keeps the review open
and says which step stopped.
The local-mode RPC label explicitly allows loopback HTTP, without an ATS exception.

Focused host-policy tests use Xcode's compiler (not a separately installed Swift):
`xcrun swiftc -D DEBUG apple/Shared/Platform/LocalDevelopment.swift apple/Shared/Platform/VaultStorage.swift tests/local-development/main.swift -o target/local-host-policy`.
The standalone harness stubs native capability, never opens production storage,
and supports `defaults`, `reject`, and `isolated` test cases.

## Appearance and layout

The design takes the name literally: the wallet is a city roof. Light appearance is day
(sky, sun, clouds), dark is night (stars, shooting stars, the moon in its real phase,
lit windows). Home is a skyline of the accounts as buildings, each with a marquee
rooftop sign carrying its total and an antenna for its project connection ("On air"
when connected). The iOS tab bar is drawn by the app (`RoofBar`). Its tabs carry the
accessibility identifiers `tab.<name>`. Lettering uses faces built into both systems:
DIN Condensed (sign numerals), DIN Alternate (stencilled labels) and Futura (titles).
Body text stays the system font. Every animation is skipped or stilled with Reduce
Motion. Scenery code lives in `apple/Shared/DesignSystem` (`Sky.swift`, `Signage.swift`,
`RoofIcons.swift`, `Typography.swift`).

Shared components live one type per file in the same folder. Copying is always
`WalletCopyButton` (icon) or `WalletCopyAction` (labeled), with `WalletCopySource`
choosing the public clipboard or the self-clearing one for secrets. Icons in a rounded
tile are `WalletIconTile` (sizes in `WalletMetrics`). An icon beside wrapped text uses
`WalletLineIcon`. Rows centre icons and text, and sign lettering uses `signLettering(_:)`.

### App icon and brand mark

The icon is a rooftop sign: a framed panel on steel posts with an X brace, "PAY" in heavy
condensed block letters on its face, a lower band reading "roof.top" and marquee bulbs
round the frame. Day is a pale sky, a limestone face and ink-navy letters with an amber
edge. Night is an indigo sky with glowing amber letters and bulbs. At 64 px and below the
frame, bulbs and band are dropped so PAY stays dominant.

`xcrun swift apple/generate-icons.swift` (run from the repository root) writes the PNGs
and `Contents.json` for both `AppIcon.appiconset` folders. `--preview <dir>` writes day,
night and tinted previews at 1024, 128, 64, 32 and 16 px instead. iOS gets the day icon
plus night and tinted (grayscale) variants through the asset catalog's appearances. macOS
15 does not switch the catalog icon with the appearance, so macOS ships the night one,
whose lit letters hold up on any Dock background. In the app, `PayroofMark`
(`Brand.swift`) draws the same sign in vector form and follows the color scheme. Its
geometry is duplicated from the generator, so change both together.

On macOS the sidebar ends with the appearance (System, Light or Dark, with System by default) and
one row of icons, their names as tooltips: **Security**, **Networks & tokens**, **Project**
and **Lock** (⇧⌘L). On iOS the same pages, the appearance, **Lock** and a **Haptic
feedback** switch (on by default) are in the **Settings** tab, and **Lock** is also at the top
left of the Wallet screen, opposite Refresh. The haptic switch is for the light tap felt on action buttons, PIN keys, Lock and Refresh. Status colors
never change. The preferences contain no wallet data. Shared cards, fields, icon actions and tappable information
popovers are used by both Apple hosts. Temporary feedback uses one toast in its own window
above every screen and modal (in the right of the window's header on macOS. Top of the screen on iOS),
so a long message never crowds a modal: it fades on its own (errors stay longer), and
closes when tapped or when you move to another screen. An action's progress shows in its own button or the PIN indicators. Input
that needs correcting is flagged at its field. Short pages center inside the safe viewport.
Tall pages scroll from the top. PIN geometry is compact and six digits auto-advance. Essential
amounts, errors, recovery warnings and signing/access reviews remain visible.
The Project page (the Payroof API connection. The UI never says "API") shows the
account's one project as a header row: status, host, **Find new addresses** and
**Disconnect** icons. An account has a single project: its addresses are numbered from
the same watch root on every server, so a second project would hand out the same
addresses. Connect refuses while another project is connected. Access is one list of the
project's credentials, pairings and created tokens alike, with permission chips and a
confirmed Revoke. **New token** creates a credential with a subset of this device's
permissions. The token is shown once, copied with the 60-second clipboard, and never
stored. **Pair** takes a pasted or scanned link into the unchanged permission review.
A folded **Details** section lists the server, address count, fingerprint and watch
root, each copyable. **Stores** (while the project is connected) lists the stores created
on this device as links. A project can back any number of stores: each has its own key,
webhook and random order references, so payments never cross stores (the Payroof server
allows 10 webhooks per project, which bounds it). **+** opens **New store**: the Stor
server (ours preset, any other typed in. Remembered. Folded away) answers with the account
to share a Google Sheet with (copyable) and where stores live. Then the store's address
(the project name for the first store), the sheet's link, and **Create**. The core creates
a key limited to `references`, `paths` and `webhooks` ("Stor <address>", listed under
Access), solves Stor's proof of work and sends one request. If Stor refuses, the key is
revoked and the reason shown in the sheet.
Home keeps one layout in every state: `$--.--` until a total is known, and one line
below it that reads Updating…, Updated … ago or Not updated yet.

### Network and token colors and logos

Every network and token has a color and an optional SVG logo, so they can be told apart at
a glance. Wherever one is shown (Home holdings, Send, Activity, address picker, the
Networks & tokens list, review and status screens) it appears as a round mark: the logo
on the color, or the first letters when there is no logo.

- Where the defaults are declared. Only in `assets/defaults.json`. Each default network
  and token states `color` (`#RRGGBB`) and `logo` (the path of an SVG under
  `assets/icons`, for example `"logo": "eip155:1/slip44:60/icon.svg"`). Nothing is
  inferred from an ID. The local Anvil chain, which only development builds add, is
  declared under `development` in the same file. `build.rs` reads those paths and
  embeds exactly the files they name, so the file is the one list and a missing or
  unsafe path fails the build. The core's `default_configuration()` returns the logo as
  SVG text. The Rust tests check that every default has a valid color and an existing
  SVG, and that `assets/icons` holds no file that the JSON does not name.
- Where it lives afterwards. `color` is required and `logo` is optional on each network
  and token in `settings.json` (`WalletNetwork` and `WalletAsset`). A new wallet copies
  both from the defaults, so settings are self-contained and drawing never reads the app
  bundle or the core. A missing logo means no logo, nothing else. The settings schema
  is 2. Settings of any other version, or with an invalid color or logo, are reset to the
  defaults by the normal load path, with a notice.
- Color format. The same value an account's accent takes: a preset name from
  `AccountAccent.names` or `#RRGGBB`. A mark resolves it through `WalletAccent` and draws
  the disc in the accent's card shade, because logos and lettering are white and that
  shade keeps white readable in light and dark appearance. The brand colors in the
  defaults are `#RRGGBB`, so they are derived shades like any custom accent.
- New entries. A new network or token gets a random preset that no other entry of its
  kind uses yet (`WalletAccent.random(avoiding:)`, the accounts' own logic). Edit it in
  the network or token sheet (`WalletLookEditor`) with `WalletColorPicker`, the one color
  picker the accounts use too, and paste, import or remove an SVG logo.
- Icon standard. A 32 by 32 `viewBox`, one white (`#fff`) glyph with no background,
  because the app draws it on the entry's color. A file is used only when `assets/defaults.json` names it. Keep the shapes as plain paths. Brand
  marks follow the official proportions, simplified.
- Accepted SVG subset (`SVGLogo`). Filled vector shapes only: `svg`, `g`, `path` (all
  commands, including arcs), `circle`, `ellipse`, `rect` (with `rx` and `ry`) and
  `polygon`, with `translate`, `scale` and `matrix` transforms, `fill`,
  `fill-rule`, `opacity`, `viewBox`, `width` and `height`. Scripts, images, `use`,
  `foreignObject`, text, styles, gradients, event handlers and any `href` are refused, as
  is anything over 16 KB or past the element, depth and step limits. Parsing never traps
  on malformed input.

## Unlock and locking

PIN is the default protection. Optional device unlock (Security → Unlock with: PIN only, biometrics, or
biometrics or system passcode. Choosing applies at once) stores
the vault data key in the Keychain behind `.biometryCurrentSet` (biometrics only) or
`.userPresence` (biometrics or the system passcode/login password, entered only in
system UI). Enabling reads the item back through the system prompt and is rolled back
if that fails. A reset item (e.g. biometric change) turns the option off. The PIN
always keeps working. On macOS the item lives in the data protection keychain, which
requires a signed build.
Core operations, vault storage, Argon2 and RPC run on the wallet worker actor.
Lock hides sensitive views immediately and queues the core lock after in-flight
synchronous operations. RPC timeouts bound network operations.
An already-running core operation cannot be cancelled.

## Receive and send

Home shows each account as a building with its rooftop sign in a carousel (swipe, or on Mac chevrons and the arrow keys. The trailing building site adds an account at once, with a random two-word name such as "Moonlit Raccoon" and an unused color, renamed in Edit. Its long-press or right-click menu opens the sheet for a chosen name, color and slot). Each account has its own accent color, and the app's accent follows the current account.
Home groups assets by account. A new wallet starts from `assets/defaults.json`:
reviewed keyless HTTPS RPCs (chain IDs checked when used), default tokens with USD
price sources, and a block explorer per network. Networks & tokens
shows each network with its tokens (the first four, then **Show all**. A search appears
past twelve tokens). A network lets users select an endpoint, add/edit/remove custom
ones (chain-verified before saving) and turn it off. The selected endpoint is used
first. The network's other endpoints are fallbacks for balances, receipts and quotes
when it doesn't answer. A transfer is signed and tracked through the endpoint shown in
its review. Cached values include their timestamps.
Send converts decimal strings to exact atomic units and presents recipient,
network, amount and maximum fees for explicit confirmation before local signing.
Outgoing activity checks receipts. Failed or unavailable RPC requests never
mark a pending transfer successful. Incoming transfers are found locally per network from
the account's addresses and the wallet's own assets, using the first source that
answers: Etherscan V2 or Alchemy (with a key), then an RPC log scan of recent blocks for tokens. Anvil
and other loopback development nodes also get a native block scan. Nothing comes from
the Payroof API.

Networks & tokens → **Provider keys** has a secure field for Alchemy, Infura, Ankr and
Etherscan. Keys stay in the encrypted vault. A saved key adds selectable, read-only
`provider:<name>` endpoints to each supported network. A key is saved only after the
provider accepts it: Alchemy, Infura and Ankr must answer `eth_chainId` `0x1` through
their Ethereum mainnet URL, Etherscan must answer a V2 `eth_blockNumber` call without
an error status. The row shows progress, then a check or a cross. Errors never contain
the key. Providers with a built-in key show "Built-in" and an outlined check. Their
endpoints are listed as "Built-in key" on the networks that key serves, and a saved key
of the user's replaces it everywhere.

Balances and activity are read only when asked: Refresh at the top right of Home (or pull
down on iOS) for the selected account, Refresh on Activity for the current account. Nothing refreshes on unlock or
on a timer. The one exception follows a send: its receipt is checked every 10 seconds while
pending (up to 10 minutes), then that network alone is read once, quietly. A refresh runs
as short worker calls (an endpoint check, one per asset balance, one per account's
activity), so an action started meanwhile waits for one call at most. While it runs, the
line under the Home total (elsewhere, the toast) says what is read and from where, e.g.
`3/7 · Polygon · Activity via PublicNode` or `Base USDC · Balance via PublicNode`.
Activity names its first source: Etherscan or Alchemy with a key,
else the RPC. A network that could not be read keeps its last values and is listed as
"not updated" under the total. An explicit refresh also names it in one short notice.

Home shows one USD total. Tapping it lists holdings with amounts and values.
Each token may carry a price oracle (Networks & tokens → token: Price URL,
Price field).
The URL must be HTTPS and return JSON. The field is a dot path to a USD number or
numeric string, e.g. CoinGecko `ethereum.usd` or DIA `Price`. Defaults share one
CoinGecko request. Tokens without an oracle are left out of the total. Prices are
best effort, cached with their date, never used for signing, and fetched without
redirects, cookies or wallet data.

Each network may carry a block explorer URL (e.g. `https://etherscan.io`. Defaults are
filled in, editable under Network details). Activity details link `<explorer>/tx/<hash>`.
In Holdings, **Send** (or an address row) opens Send on that asset.
Incoming details show the sender, transaction and explorer link.
Send clears amount and recipient after a submitted transfer, and refuses to quote a
transfer whose address can't cover the maximum network fee in the network's coin
(plus the amount when sending the coin itself), saying how much it holds.
The asset list in Send shows what the selected address holds, and separately what the
account's other addresses hold.

Receive exposes public-address QR/text and exact-path controls. Address pickers list
seven addresses around the selected one. Search reaches the rest.
Custom tokens require an independently verified contract and decimal count.
Symbols do not establish asset identity. Optional API Path Sources discover
addresses and persist each imported page before its cursor. Blockchain RPCs
provide actual balances.

Pairing presents the requester's name with the exact origin it came from (the origin,
not the self-chosen name, identifies it), permissions, expiry and the API Project
(chosen automatically when only one is connected) before explicit approval. A link
for an API with no connected project opens no review. A toast points to the Project page instead.
The Project page can disconnect a project (this device forgets its credential,
the project stays on the API). If the API stops accepting this device's credential,
for example after revoking its own token, the app says so and offers Reconnect
(recovery) or Disconnect. A failed Connect offers recovery for existing projects.

Paste/QR pairing does not depend on Apple signing. URL-opening handlers are supplied, but **Universal Link delivery is not claimed**: production requires correctly signed Associated Domains entitlements and an independently served Apple app-site-association document. No placeholder domain association/signing entitlement is added to unsigned builds.

The iOS UI tests (`ios/UITests`) open a test wallet. `AccountSelectionUITests` adds
accounts, selects one and checks it stays the current, centred building across tabs and a
relaunch. `ScreensUITests` turns a sign over, opens its menu and the Edit sheet, steps
through Send, and attaches a screenshot of each screen to the result bundle (export them
with `xcrun xcresulttool export attachments`). Run it on a simulator after
`./build-apple.sh ios-simulator`: `xcodebuild -project ios/PayroofWallet.xcodeproj -scheme
PayroofWallet -sdk iphonesimulator -destination 'platform=iOS Simulator,name=<device>' test`.

macOS amount-conversion XCTest source lives in `macos/Tests`. The Xcode project includes a `PayroofWalletTests` target. Manually verify Keychain/biometrics, storage failures, background locking, camera behavior and transaction broadcasts on your target devices before distributing the application.

## Development checks

```sh
cargo fmt --check
cargo clippy --locked --all-targets -- -D warnings
cargo test --locked --all-targets
swift-format lint --strict -r apple macos/Tests macos/App ios/App tests
bash tests/swift-harnesses.sh
xcodebuild -project macos/PayroofWallet.xcodeproj -scheme PayroofWallet \
  -destination 'platform=macOS' CODE_SIGN_IDENTITY=- test   # after build-apple.sh macos
```

The app icon is generated: `xcrun swift apple/generate-icons.swift` writes the
macOS sizes and the iOS default, dark and tinted variants.

## Release

Versions follow [SemVer](https://semver.org). The app's `MARKETING_VERSION` (in
`macos/project.yml` and `ios/project.yml`) matches `Cargo.toml`, and changes are
listed in [CHANGELOG.md](CHANGELOG.md). A `vX.Y.Z` tag runs
[`release.yml`](.github/workflows/release.yml): checks → crates.io
[`payroof-wallet-core`](https://crates.io/crates/payroof-wallet-core) → a GitHub
release. Signing, notarisation and App Store submission need your Apple team and
are not automated.

## Release

Versions follow [SemVer](https://semver.org). The app's `MARKETING_VERSION` (in
`macos/project.yml` and `ios/project.yml`) matches `Cargo.toml`, and changes are listed in
[CHANGELOG.md](../CHANGELOG.md). A `vX.Y.Z` tag runs the release workflow: checks, then
[`payroof-wallet-core`](https://crates.io/crates/payroof-wallet-core) on crates.io, then a
GitHub release with the macOS app zip. The macOS app is ad-hoc signed, not notarized; the
Homebrew cask clears the quarantine flag on install. Notarisation and App Store submission
need your Apple team and are not automated.
