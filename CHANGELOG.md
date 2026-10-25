# Changelog

All notable changes to this project are documented here. The format follows
Keep a Changelog, and the project follows Semantic Versioning.

## [0.1.1] - 2026-10-25

### Added

- The macOS app is a universal build: it runs on Intel Macs as well as Apple Silicon.
- `./build-apple.sh macos-universal` builds that app locally.

## [0.1.0] - 2026-10-25

- First public release of Payroof Wallet, a self-custody EVM wallet for macOS and iOS.
- Encrypted local vault with BIP-39 recovery words, BIP-44 accounts, and local signing.
- Send, receive, portfolio and activity read from the chain, with editable networks and tokens.
- Optional Payroof API connection for payment addresses and integration pairing.
- macOS app distributed through Homebrew (`brew install --cask payroof/tap/wallet`) and GitHub Releases.
- Rust core published on crates.io as `payroof-wallet-core`.
