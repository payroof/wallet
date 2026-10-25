#!/usr/bin/env bash
# Compiles and runs the standalone Swift harnesses against the shared sources.
# Storage-touching checks use a fresh temporary directory, never the real vault.
set -euo pipefail
cd "$(dirname "$0")/.."
shared=apple/Shared
out=target/swift-harnesses
mkdir -p "$out"
data="$(mktemp -d)"; chmod 700 "$data"
trap 'rm -rf "$data"' EXIT

echo "==> host policy"
xcrun swiftc -D DEBUG "$shared/Platform/LocalDevelopment.swift" "$shared/Platform/VaultStorage.swift" \
  tests/local-development/main.swift -o "$out/host-policy"
"$out/host-policy" defaults
PAYROOF_WALLET_LOCAL_DEVELOPMENT=1 TEST_NATIVE_LOCAL_CAPABILITY=1 "$out/host-policy" reject
PAYROOF_WALLET_LOCAL_DEVELOPMENT=1 TEST_NATIVE_LOCAL_CAPABILITY=1 PAYROOF_WALLET_DATA_DIR="$data/host" \
  "$out/host-policy" isolated

echo "==> persisted schema"
xcrun swiftc "$shared"/Model/Domain/*.swift "$shared/Platform/LocalDevelopment.swift" \
  tests/persisted-schema/main.swift -o "$out/persisted-schema"
"$out/persisted-schema"

echo "==> incoming links"
xcrun swiftc "$shared/Model/WalletIncomingLink.swift" "$shared/Platform/LocalDevelopment.swift" \
  tests/incoming-links/main.swift -o "$out/incoming-links"
"$out/incoming-links"

echo "==> native runtime (Rust core with local-development)"
target="$(uname -m | sed 's/arm64/aarch64/')-apple-darwin"
cargo build --locked -p payroof-wallet-core --lib --release --target "$target" \
  --features local-development --target-dir target/harness
cargo run --locked --bin uniffi-bindgen -- generate \
  --library "target/harness/$target/release/libpayroof_wallet_core.a" --language swift \
  --out-dir "$out/bindings" >/dev/null
xcrun swiftc -parse-as-library -D DEBUG -I "$out/bindings" -Xcc -fmodule-map-file="$out/bindings/payroof_wallet_coreFFI.modulemap" \
  -L "target/harness/$target/release" -lpayroof_wallet_core \
  "$shared"/Model/Worker/*.swift "$shared"/Model/WalletSnapshot.swift "$shared"/Model/WalletCommand.swift "$shared"/Model/SendFees.swift \
  "$shared"/Model/Formatting.swift "$shared"/Model/Portfolio.swift "$shared"/Model/Domain/*.swift \
  "$shared"/Platform/LocalDevelopment.swift "$shared"/Platform/VaultStorage.swift "$shared"/Platform/DeviceUnlock.swift \
  "$out/bindings/payroof_wallet_core.swift" tests/native-runtime/main.swift -o "$out/native-runtime"
mkdir -m 700 "$data/runtime"
PAYROOF_WALLET_LOCAL_DEVELOPMENT=1 PAYROOF_WALLET_DATA_DIR="$data/runtime" "$out/native-runtime"
echo "All Swift harnesses passed."
