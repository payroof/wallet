# Payroof Wallet

A self-custody EVM wallet for macOS and iOS. Your keys never leave your device.

<img src="docs/screenshot.png" alt="Payroof Wallet">

[![CI](https://github.com/payroof/wallet/actions/workflows/ci.yml/badge.svg)](https://github.com/payroof/wallet/actions/workflows/ci.yml)
[![crates.io](https://img.shields.io/crates/v/payroof-wallet-core.svg)](https://crates.io/crates/payroof-wallet-core)
[![License: MIT OR Apache-2.0](https://img.shields.io/badge/license-MIT%20OR%20Apache--2.0-blue.svg)](#license)

## Features

- Recovery words, accounts and addresses, all derived and stored on your device.
- Send and receive with exact amounts, a reviewed recipient and fee, and local signing.
- Portfolio, activity and USD totals read straight from the chain. Networks, RPCs and
  tokens are plain, editable settings.
- Encrypted vault with a PIN, optional Face ID / Touch ID and auto-lock.
- Optional [Payroof](https://github.com/payroof/payroof) connection for payment
  addresses and integrations such as [Stor](https://github.com/payroof/stor). The wallet
  never needs it to check balances or sign.

## Install

macOS 15 or later, Apple Silicon, with [Homebrew](https://brew.sh):

```sh
brew install --cask payroof/tap/wallet
```

The app is ad-hoc signed, not notarized. The cask clears the quarantine flag for you.
You can also download the zip of `PayroofWallet.app` from
[GitHub Releases](https://github.com/payroof/wallet/releases).

The Rust core is on [crates.io](https://crates.io/crates/payroof-wallet-core):

```sh
cargo add payroof-wallet-core
```

## Build from source

You need Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen) and the Rust
toolchain pinned in [`rust-toolchain.toml`](rust-toolchain.toml).

```sh
./build-apple.sh macos                        # or ios-simulator
CONFIGURATION=Release ./build-apple.sh macos  # stripped, size-optimised app
cargo test --locked --all-targets             # Rust core tests
```

The app is built under `target/apple-*`. Device builds, signing and local development
are in [docs/apple.md](docs/apple.md).

## Documentation

- [Features](docs/features.md)
- [Apple apps: build variants, signing, development, release](docs/apple.md)
- [Architecture, vault and safety boundaries](docs/architecture.md)
- [Payroof API client contract](docs/api-client.md)
- [Changelog](CHANGELOG.md)

## License

Licensed under either of [Apache License 2.0](LICENSE-APACHE) or
[MIT](LICENSE-MIT), at your option.
