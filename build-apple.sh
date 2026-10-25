#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
export CARGO_BUILD_JOBS=${CARGO_BUILD_JOBS:-2}
# The core is built for the apps' minimum OS versions (macos/ios project.yml), not the
# build machine's, so the linked app runs on every supported system.
export MACOSX_DEPLOYMENT_TARGET=15.0 IPHONEOS_DEPLOYMENT_TARGET=18.0
# Debug by default. CONFIGURATION=Release builds the optimised app.
configuration=${CONFIGURATION:-Debug}
product=${1:-macos}
features=()
derived_suffix=""
# Unsigned by default. ios-device signs with automatic provisioning so the app can
# be installed on a physical device: DEVELOPMENT_TEAM is required, DEVICE_ID
# (UDID) targets one device and BUNDLE_ID optionally overrides the bundle ID.
# macos-local is its own app (bundle ID top.payroof.wallet.local: own sandbox container
# and Keychain items). With DEVELOPMENT_TEAM it is signed and sandboxed like a release,
# with the Keychain access group device unlock (Touch ID) needs. Without it the app is
# unsigned and device unlock reports itself unavailable.
signing=(CODE_SIGNING_ALLOWED=NO)
if [[ "$product" == macos-local ]]; then
  product=macos
  features=(--features local-development)
  derived_suffix=-local
  signing+=(PRODUCT_BUNDLE_IDENTIFIER=top.payroof.wallet.local)
  if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
    signing=(-allowProvisioningUpdates -allowProvisioningDeviceRegistration CODE_SIGN_STYLE=Automatic "DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM"
      PRODUCT_BUNDLE_IDENTIFIER=top.payroof.wallet.local CODE_SIGN_ENTITLEMENTS=WalletSigned.entitlements)
  fi
fi
# ios-device-local: a signed iPhone app (bundle ID <id>.local, own data and Keychain) whose
# core has local development on: plain HTTP to loopback or a private LAN IPv4 only, preset
# to the Mac's local stack (roofer up) at PAYROOF_LOCAL_HOST (the Mac's Wi-Fi IP). Its Info plist
# (ios/Info-Local.plist) also declares the Bonjour service the app browses once to ask
# for Local Network access before its first request to the Mac.
if [[ "$product" == ios-device-local ]]; then
  : "${DEVELOPMENT_TEAM:?set DEVELOPMENT_TEAM to your Apple development team ID}"
  [[ "${PAYROOF_LOCAL_HOST:-}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] \
    || { echo 'set PAYROOF_LOCAL_HOST to the Mac'"'"'s LAN IPv4 (e.g. 192.168.1.20)' >&2; exit 2; }
  export PAYROOF_LOCAL_HOST
  features=(--features local-development)
  target=aarch64-apple-ios; architecture=arm64; sdk=iphoneos; product=ios; derived_suffix=-device-local
  destination="${DEVICE_ID:+id=$DEVICE_ID}"; destination="${destination:-generic/platform=iOS}"
  signing=(-allowProvisioningUpdates -allowProvisioningDeviceRegistration CODE_SIGN_STYLE=Automatic
    "DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM" "PRODUCT_BUNDLE_IDENTIFIER=${BUNDLE_ID:-top.payroof.wallet}.local"
    "INFOPLIST_KEY_NSLocalNetworkUsageDescription=Connect to the Payroof test stack on your Mac"
    INFOPLIST_FILE=Info-Local.plist)
  local_ios=1
fi
architecture=${architecture:-$(uname -m)}
[[ -n "${local_ios:-}" ]] || case "$product" in
  macos) case "$(uname -m)" in arm64) target=aarch64-apple-darwin ;; x86_64) target=x86_64-apple-darwin ;; *) exit 2 ;; esac; sdk=macosx; destination='generic/platform=macOS' ;;
  ios) target=aarch64-apple-ios; architecture=arm64; sdk=iphoneos; destination='generic/platform=iOS' ;;
  ios-device)
    : "${DEVELOPMENT_TEAM:?set DEVELOPMENT_TEAM to your Apple development team ID}"
    target=aarch64-apple-ios; architecture=arm64; sdk=iphoneos; product=ios; derived_suffix=-device
    destination="${DEVICE_ID:+id=$DEVICE_ID}"; destination="${destination:-generic/platform=iOS}"
    signing=(-allowProvisioningUpdates -allowProvisioningDeviceRegistration CODE_SIGN_STYLE=Automatic
      "DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM")
    if [[ -n "${BUNDLE_ID:-}" ]]; then signing+=("PRODUCT_BUNDLE_IDENTIFIER=$BUNDLE_ID"); fi ;;
  ios-simulator) case "$(uname -m)" in arm64) target=aarch64-apple-ios-sim ;; x86_64) target=x86_64-apple-ios ;; *) exit 2 ;; esac; sdk=iphonesimulator; destination='generic/platform=iOS Simulator'; product=ios ;;
   *) echo 'usage: build-apple.sh [macos|macos-local|ios|ios-device|ios-device-local|ios-simulator]' >&2; exit 2 ;;
esac
# Use rustup's toolchain (rust-toolchain.toml + the target added below), not a cargo/rustc
# earlier on PATH (e.g. Homebrew's rust), which has no standard library for iOS targets.
rustup_bin="$(dirname "$(command -v rustup)")"
export PATH="$rustup_bin:$PATH"
rustup target add "$target"
cargo build --locked -p payroof-wallet-core --lib --release --target "$target" ${features[@]+"${features[@]}"}
mkdir -p "$product/Generated"
cargo run --locked --bin uniffi-bindgen -- generate --library "target/$target/release/libpayroof_wallet_core.a" --language swift --out-dir "$product/Generated"
cp "$product/Generated/payroof_wallet_coreFFI.modulemap" "$product/Generated/module.modulemap"
cp "target/$target/release/libpayroof_wallet_core.a" "$product/Generated/"
(cd "$product" && xcodegen generate)
xcodebuild -project "$product/PayroofWallet.xcodeproj" -scheme PayroofWallet -configuration "$configuration" -sdk "$sdk" -destination "$destination" -derivedDataPath "target/apple-$sdk$derived_suffix" ARCHS="$architecture" ONLY_ACTIVE_ARCH=YES "${signing[@]}" build
