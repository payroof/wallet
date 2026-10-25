use payroof_wallet_core::{derivation, recovery};
const WORDS: &str =
    "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
#[test]
fn evm_vectors_and_watch_match() {
    // The account's own addresses: the standard BIP-44 ones every EVM wallet shows.
    for (path, address) in [
        (
            "m/44'/60'/0'/0/0",
            "0x9858effd232b4033e47d90003d41ec34ecaeda94",
        ),
        (
            "m/44'/60'/0'/0/1",
            "0x6fac4d18c912343bf86fa7049364dd4e424ab9c0",
        ),
        (
            "m/44'/60'/1'/0/0",
            "0x78839f6054d7ed13918bae0473ba31b1ca9d7265",
        ),
    ] {
        assert_eq!(derivation::address(WORDS, "", path).unwrap(), address);
    }
    // Payment addresses: the watch root Payroof gets is branch 1, never the account's own.
    for (slot, index, address) in [
        (0, 0, "0x399db6ed32539fbdf44c3e7678b5b428e378f666"),
        (0, 1, "0x26db4d065800bd118928848e69a1cbf956cff1d0"),
        (1, 0, "0xdb447a90f6d37e92801a3d8e8aa30eebd04061d3"),
    ] {
        let root = derivation::watch(WORDS, "", slot).unwrap();
        assert_eq!(root.path, format!("m/44'/60'/{slot}'/1"));
        assert_eq!(
            derivation::derive_evm_address(&root.key, index).unwrap(),
            address
        );
        assert_eq!(
            derivation::address(WORDS, "", &format!("{}/{index}", root.path)).unwrap(),
            address
        );
    }
}
#[test]
fn recovery_vectors() {
    let vectors: serde_json::Value =
        serde_json::from_str(include_str!("vectors/recovery.json")).unwrap();
    for v in vectors.as_array().unwrap() {
        assert_eq!(
            recovery::public(
                v["mnemonic"].as_str().unwrap(),
                "",
                u32::try_from(v["slot"].as_u64().unwrap()).unwrap()
            )
            .unwrap(),
            v["recovery_public_key"].as_str().unwrap()
        );
    }
}
#[test]
fn hidden_slots_are_not_reused() {
    let mut p = payroof_wallet_core::projects::Projects::default();
    let first = p.add("a".into(), None).unwrap();
    p.hide(first);
    assert_eq!(p.add("b".into(), None).unwrap(), first + 1);
}
