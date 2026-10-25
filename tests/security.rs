use payroof_wallet_core::{
    api, mnemonic, pairing,
    path_source::{self, Imported},
    projects::Projects,
    spending::{EvmSigner, WalletSigner},
    state::UnlockSession,
    vault::Vault,
};
const WORDS: &str =
    "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

#[test]
fn credentials_pin_normalized_origins_and_reject_retargeting() {
    let pin = api::Api::pin("https://EXAMPLE.com:443/", false).unwrap();
    assert!(api::Api::new("https://example.com", "prf_test".into(), pin, false).is_ok());
    assert!(api::Api::new("https://other.example", "prf_test".into(), pin, false).is_err());
    for origin in [
        "https://user@example.com",
        "https://example.com/path",
        "https://example.com/?x=1",
        "https://example.com/#x",
        "http://example.com",
        "https://example.com/..",
        "https://example.com/%2e%2e",
    ] {
        assert!(api::origin(origin, false).is_err());
    }
}
#[test]
fn development_allows_only_http_on_explicit_loopback() {
    for url in [
        "http://localhost",
        "http://127.0.0.1:8545",
        "http://[::1]:8545",
    ] {
        assert!(api::origin(url, true).is_ok());
        assert!(payroof_wallet_core::networks::validate_rpc(url, true).is_ok());
        assert!(api::origin(url, false).is_err());
    }
    for url in [
        "ftp://localhost",
        "http://example.com",
        "http://localhost.example",
        "https://user@example.com",
    ] {
        assert!(api::origin(url, true).is_err());
        assert!(payroof_wallet_core::networks::validate_rpc(url, true).is_err());
    }
}
#[test]
fn rejected_feed_page_cannot_import_partial_paths_or_advance_cursor() {
    let mut imported = Imported::default();
    let root = "m/44'/60'/0'/0";
    imported
        .apply(
            root,
            "confirmed",
            &format!("{root}/0\n"),
            "first".into(),
            WORDS,
            "",
        )
        .unwrap();
    let before = serde_json::to_string(&imported).unwrap();
    assert!(
        imported
            .apply(
                root,
                "confirmed",
                &format!("{root}/1\nm/44'/60'/1'/0/0"),
                "bad".into(),
                WORDS,
                ""
            )
            .is_err()
    );
    assert_eq!(serde_json::to_string(&imported).unwrap(), before);
    imported
        .apply(root, "all", &format!("{root}/1"), "all".into(), WORDS, "")
        .unwrap();
    assert_eq!(imported.confirmed_cursor.as_deref(), Some("first"));
    assert_eq!(imported.all_cursor.as_deref(), Some("all"));
}
#[test]
fn slot_tombstones_survive_serialization_and_exact_addresses_are_idempotent() {
    let mut projects = Projects::default();
    projects.add("first".into(), Some(7)).unwrap();
    let path = projects.add_address(7, Some(77)).unwrap();
    assert_eq!(projects.add_address(7, Some(77)).unwrap(), path);
    projects.hide(7);
    let mut restored: Projects =
        serde_json::from_str(&serde_json::to_string(&projects).unwrap()).unwrap();
    // The tombstone survives: automatic choice skips it, an exact slot restores it.
    assert_ne!(restored.add("auto".into(), None).unwrap(), 7);
    assert_eq!(restored.add("replacement".into(), Some(7)).unwrap(), 7);
    assert!(restored.add("overflow".into(), Some(1 << 31)).is_err());
}
#[test]
fn vault_rejects_tampered_ciphertexts_purpose_and_version() {
    let original = Vault::create("test-wallet".into(), "123456", b"private payload").unwrap();
    let key = original.unlock("123456").unwrap();
    let serialized = serde_json::to_string(&original).unwrap();
    let mut changed: Vault = serde_json::from_str(&serialized).unwrap();
    changed.secrets = original.wrapped_key.clone();
    assert!(changed.read(&key).is_err());
    changed = serde_json::from_str(&serialized).unwrap();
    changed.version = 2;
    assert!(changed.unlock("123456").is_err());
    changed = serde_json::from_str(&serialized).unwrap();
    let replacement = if changed.wrapped_key.starts_with('A') {
        "B"
    } else {
        "A"
    };
    changed.wrapped_key.replace_range(0..1, replacement);
    assert!(changed.unlock("123456").is_err());
}

#[test]
fn generated_mnemonics_have_24_words_and_normalize_case_and_whitespace() {
    let first = mnemonic::generate().unwrap();
    let second = mnemonic::generate().unwrap();
    assert_eq!(first.split_whitespace().count(), 24);
    assert_eq!(second.split_whitespace().count(), 24);
    assert_ne!(*first, *second);
    let input = format!("\t {} \n", first.to_uppercase().replace(' ', "\t\n  "));
    assert_eq!(*mnemonic::normalize(&input).unwrap(), *first);
    assert_eq!(
        *mnemonic::seed(&input, "passphrase").unwrap(),
        *mnemonic::seed(&first, "passphrase").unwrap()
    );
    assert_ne!(
        *mnemonic::seed(&first, "").unwrap(),
        *mnemonic::seed(&first, "passphrase").unwrap()
    );
    assert_eq!(*mnemonic::normalize(WORDS).unwrap(), WORDS);
    for invalid in [
        "abandon ".repeat(24),
        "abandon ".repeat(13),
        "not a mnemonic".into(),
    ] {
        assert!(mnemonic::normalize(&invalid).is_err());
    }
}

#[test]
fn exact_slots_and_indexes_obey_nonhardened_boundaries_without_mutating_on_error() {
    let mut projects = Projects::default();
    assert_eq!(
        projects.add("last".into(), Some((1 << 31) - 1)).unwrap(),
        (1 << 31) - 1
    );
    assert_eq!(projects.add("exact".into(), Some(7)).unwrap(), 7);
    assert_eq!(projects.add("automatic".into(), None).unwrap(), 0);
    assert_eq!(
        projects.add_address(7, Some(77)).unwrap(),
        "m/44'/60'/7'/0/77"
    );
    assert_eq!(projects.add_address(7, None).unwrap(), "m/44'/60'/7'/0/0");
    assert_eq!(projects.add_address(7, None).unwrap(), "m/44'/60'/7'/0/1");
    assert_eq!(
        projects.add_address(7, Some((1 << 31) - 1)).unwrap(),
        "m/44'/60'/7'/0/2147483647"
    );
    let before = serde_json::to_string(&projects).unwrap();
    for slot in [7, 1 << 31, u32::MAX] {
        assert!(projects.add("invalid".into(), Some(slot)).is_err());
    }
    for index in [1 << 31, u32::MAX] {
        assert!(projects.add_address(7, Some(index)).is_err());
    }
    assert!(projects.add_address(123, Some(0)).is_err());
    assert_eq!(serde_json::to_string(&projects).unwrap(), before);
    projects.hide(0);
    assert_eq!(projects.add("next".into(), None).unwrap(), 1);
}

#[test]
fn imported_paths_are_exact_canonical_children_only() {
    let root = "m/44'/60'/7'/0";
    for index in [0, 77, (1 << 31) - 1] {
        assert_eq!(
            path_source::validate_child(root, &format!("{root}/{index}")).unwrap(),
            index
        );
    }
    for path in [
        root.to_owned(),
        "m/44'/60'/8'/0/0".into(),
        "m/44'/60'/7'/1/0".into(),
        format!("{root}/00"),
        format!("{root}/+1"),
        format!("{root}/-1"),
        format!("{root}/1'"),
        format!("{root}/1/0"),
        format!("{root}/2147483648"),
        format!("{root}/4294967296"),
        format!("{root}/1 "),
        format!(" {root}/1"),
    ] {
        assert!(
            path_source::validate_child(root, &path).is_err(),
            "accepted {path}"
        );
    }
}

#[test]
fn feed_processing_is_idempotent_and_commits_only_complete_valid_pages() {
    let root = "m/44'/60'/0'/0";
    let mut imported = Imported::default();
    imported
        .apply(
            root,
            "confirmed",
            &format!("{root}/0\r\n{root}/0\n"),
            "c1".into(),
            WORDS,
            "",
        )
        .unwrap();
    assert_eq!(imported.addresses.len(), 1);
    assert_eq!(
        imported.addresses[&format!("{root}/0")],
        "0x9858effd232b4033e47d90003d41ec34ecaeda94"
    );
    imported
        .apply(root, "all", &format!("{root}/1"), "a1".into(), WORDS, "")
        .unwrap();
    let before = serde_json::to_string(&imported).unwrap();
    for (scope, page, words) in [
        ("all", format!("{root}/2\n{root}/00"), WORDS),
        ("confirmed", format!("{root}/2\n\n{root}/3"), WORDS),
        ("unknown", format!("{root}/2"), WORDS),
        ("all", "x".repeat(128_001), WORDS),
        ("all", format!("{root}/2"), "invalid mnemonic"),
    ] {
        assert!(
            imported
                .apply(root, scope, &page, "bad".into(), words, "")
                .is_err()
        );
        assert_eq!(serde_json::to_string(&imported).unwrap(), before);
    }
    imported
        .apply(root, "confirmed", "", "c2".into(), WORDS, "")
        .unwrap();
    assert_eq!(imported.addresses.len(), 2);
    assert_eq!(imported.confirmed_cursor.as_deref(), Some("c2"));
    assert_eq!(imported.all_cursor.as_deref(), Some("a1"));
}

#[test]
fn pin_change_rewraps_same_dek_and_preserves_encrypted_payload() {
    let mut vault = Vault::create("rewrap".into(), "123456", WORDS.as_bytes()).unwrap();
    let key = vault.unlock("123456").unwrap();
    let ciphertext = vault.secrets.clone();
    let wrapped = vault.wrapped_key.clone();
    let salt = vault.kdf.salt;
    let before = serde_json::to_string(&vault).unwrap();
    assert!(!before.contains(WORDS));
    assert!(vault.change_pin("000000", "654321").is_err());
    assert_eq!(serde_json::to_string(&vault).unwrap(), before);
    assert!(vault.change_pin("123456", "short").is_err());
    assert_eq!(serde_json::to_string(&vault).unwrap(), before);
    vault.change_pin("123456", "654321").unwrap();
    assert_eq!(vault.secrets, ciphertext);
    assert_ne!(vault.wrapped_key, wrapped);
    assert_ne!(vault.kdf.salt, salt);
    assert!(vault.unlock("123456").is_err());
    assert_eq!(*vault.unlock("654321").unwrap(), *key);
    assert_eq!(&*vault.read(&key).unwrap(), WORDS.as_bytes());
}

#[test]
fn wrong_pin_locks_and_third_failure_delays_even_correct_pin() {
    let vault = Vault::create("delay".into(), "123456", b"payload").unwrap();
    let mut session = UnlockSession::default();
    assert!(session.key().is_err());
    for _ in 0..2 {
        assert_eq!(
            session.unlock(&vault, "000000").unwrap_err().to_string(),
            "unlock failed"
        );
        assert!(session.key().is_err());
    }
    // A successful attempt before the threshold resets the failure counter.
    session.unlock(&vault, "123456").unwrap();
    session.lock();
    for _ in 0..3 {
        assert_eq!(
            session.unlock(&vault, "000000").unwrap_err().to_string(),
            "unlock failed"
        );
    }
    assert_eq!(
        session.unlock(&vault, "123456").unwrap_err().to_string(),
        "unlock delayed"
    );
    assert!(session.key().is_err());
}

#[test]
fn device_unlock_authenticates_key_and_corrupted_payload_fails_closed() {
    let mut vault = Vault::create("device".into(), "123456", b"payload").unwrap();
    let key = vault.unlock("123456").unwrap();
    let mut session = UnlockSession::default();
    let mut wrong = *key;
    wrong[0] ^= 1;
    assert!(session.device_unlock(&vault, wrong).is_err());
    assert!(session.key().is_err());
    session.device_unlock(&vault, *key).unwrap();
    assert_eq!(&*vault.read(session.key().unwrap()).unwrap(), b"payload");
    session.lock();
    assert!(session.key().is_err());
    let ciphertext = vault.secrets.clone();
    let replacement = if vault.secrets.starts_with('A') {
        "B"
    } else {
        "A"
    };
    vault.secrets.replace_range(0..1, replacement);
    assert!(vault.read(&key).is_err());
    assert!(session.device_unlock(&vault, *key).is_err());
    assert!(session.key().is_err());
    vault.secrets = ciphertext;
    session.device_unlock(&vault, *key).unwrap();
    session.lock();
    vault.secrets = "not a ciphertext".into();
    assert!(vault.read(&key).is_err());
    assert!(session.device_unlock(&vault, *key).is_err());
    assert!(session.key().is_err());
}

#[test]
fn vault_rejects_unsafe_kdf_profiles_and_wallet_identity_substitution() {
    let original = Vault::create("identity".into(), "123456", b"payload").unwrap();
    let key = original.unlock("123456").unwrap();
    let serialized = serde_json::to_string(&original).unwrap();
    let mut changed: Vault = serde_json::from_str(&serialized).unwrap();
    changed.wallet_id = "other".into();
    assert!(changed.unlock("123456").is_err());
    assert!(changed.read(&key).is_err());
    for (memory, iterations, parallelism) in [
        (0, 3, 1),
        (u32::MAX, 3, 1),
        (65536, 0, 1),
        (65536, 11, 1),
        (65536, 3, 0),
        (65536, 3, 5),
    ] {
        let mut changed: Vault = serde_json::from_str(&serialized).unwrap();
        changed.kdf.memory_kib = memory;
        changed.kdf.iterations = iterations;
        changed.kdf.parallelism = parallelism;
        assert!(changed.unlock("123456").is_err());
    }
    changed = serde_json::from_str(&serialized).unwrap();
    changed.kdf.algorithm = "argon2i".into();
    assert!(changed.unlock("123456").is_err());
}

#[test]
fn pairing_origin_is_canonical_and_credentials_cannot_change_scheme_host_or_port() {
    let id = format!("pair_{}", "a".repeat(43));
    let (origin, parsed) =
        pairing::parse(&format!("https://EXAMPLE.com:443/v1/pairings/{id}")).unwrap();
    assert_eq!(origin, "https://example.com");
    assert_eq!(parsed, id);
    let pin = api::Api::pin(&origin, false).unwrap();
    for other in [
        "https://example.com:8443",
        "https://sub.example.com",
        "http://example.com",
    ] {
        assert!(api::Api::new(other, "synthetic-token".into(), pin, true).is_err());
    }
    for raw in [
        format!("http://example.com/pair/{id}"),
        format!("http://example.com/v1/pairings/{id}"),
        format!("https://example.com/v1/pairings/{id}?x=1"),
        format!("https://example.com/v1/pairings/{id}/"),
        format!("https://example.com/v1/pairings/../pairings/{id}"),
        format!("https://example.com/v1/pairings/%70{}", &id[1..]),
        format!("https://user:pass@example.com/pair/{id}"),
        format!("https://example.com/pair/{id}?x=1"),
        format!("https://example.com/pair/{id}#x"),
        format!("https://example.com/pair/{id}/"),
        format!("https://example.com/pair/../pair/{id}"),
        format!("https://example.com/pair/%70{}", &id[1..]),
        format!(" https://example.com/pair/{id}"),
        "https://example.com/pair/pair_short".into(),
    ] {
        assert!(pairing::parse(&raw).is_err());
    }
}

#[test]
fn local_signer_matches_published_eip155_signature_vector() {
    // Public example scalar and digest from EIP-155, never a live wallet key.
    let signer = EvmSigner::from_private_key([0x46; 32]).unwrap();
    assert_eq!(signer.family(), "eip155");
    assert_eq!(
        signer.address(),
        "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f"
    );
    let digest: [u8; 32] =
        hex::decode("daf5a779ae972f972197303d7b574746c7ef83eadac0f2791ad23db92e4c8e53")
            .unwrap()
            .try_into()
            .unwrap();
    let (signature, parity) = signer.sign_recoverable(&digest).unwrap();
    assert_eq!(
        hex::encode(signature),
        "28ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa63627667cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83"
    );
    assert_eq!(parity, 0);
    assert!(EvmSigner::from_private_key([0; 32]).is_err());
    assert!(EvmSigner::from_private_key([0xff; 32]).is_err());
}

// Scripted loopback HTTP peer. Captures only public request targets/JSON.
// authorization headers and raw requests are neither retained nor logged.
type CapturedRequests = Vec<(String, serde_json::Value)>;

fn http_fixture(
    responses: Vec<(String, String)>,
) -> (String, std::thread::JoinHandle<CapturedRequests>) {
    use std::io::{Read, Write};
    use std::time::{Duration, Instant};
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let endpoint = format!("http://{}", listener.local_addr().unwrap());
    listener.set_nonblocking(true).unwrap();
    let worker = std::thread::spawn(move || {
        let mut requests = Vec::new();
        for (headers, body) in responses {
            let deadline = Instant::now() + Duration::from_secs(10);
            let mut stream = loop {
                match listener.accept() {
                    Ok((stream, _)) => break stream,
                    Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                        assert!(
                            Instant::now() < deadline,
                            "expected HTTP request did not arrive"
                        );
                        std::thread::sleep(Duration::from_millis(5));
                    }
                    Err(error) => panic!("fixture accept failed: {error}"),
                }
            };
            // Accepted sockets can inherit nonblocking mode on macOS. Reads
            // below intentionally block with a bounded timeout.
            stream.set_nonblocking(false).unwrap();
            stream
                .set_read_timeout(Some(Duration::from_secs(5)))
                .unwrap();
            let mut bytes = Vec::new();
            let (header_end, length) = loop {
                let mut chunk = [0u8; 4096];
                let count = stream.read(&mut chunk).unwrap();
                assert!(count > 0, "incomplete request");
                bytes.extend_from_slice(&chunk[..count]);
                assert!(bytes.len() < 256_000);
                if let Some(end) = bytes.windows(4).position(|w| w == b"\r\n\r\n") {
                    let header = std::str::from_utf8(&bytes[..end]).unwrap();
                    let length = header
                        .lines()
                        .find_map(|line| {
                            let (name, value) = line.split_once(':')?;
                            name.eq_ignore_ascii_case("content-length")
                                .then(|| value.trim().parse::<usize>().unwrap())
                        })
                        .unwrap_or(0);
                    break (end + 4, length);
                }
            };
            while bytes.len() < header_end + length {
                let mut chunk = [0u8; 4096];
                let count = stream.read(&mut chunk).unwrap();
                assert!(count > 0, "incomplete body");
                bytes.extend_from_slice(&chunk[..count]);
            }
            let target = std::str::from_utf8(&bytes[..header_end])
                .unwrap()
                .lines()
                .next()
                .unwrap()
                .split_whitespace()
                .nth(1)
                .unwrap()
                .to_owned();
            let json = if length == 0 {
                serde_json::Value::Null
            } else {
                serde_json::from_slice(&bytes[header_end..header_end + length]).unwrap()
            };
            requests.push((target, json));
            write!(
                stream,
                "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n{}\r\n{}",
                body.len(),
                headers,
                body
            )
            .unwrap();
        }
        requests
    });
    (endpoint, worker)
}

#[tokio::test]
async fn api_feed_cursors_are_encoded_and_failed_import_does_not_commit_sync_state() {
    let root = "m/44'/60'/0'/0";
    let headers = "payroof-next-cursor: next-page\r\npayroof-has-more: true\r\n".to_owned();
    let (endpoint, worker) = http_fixture(vec![
        (headers.clone(), format!("{root}/0\n")),
        (headers, format!("{root}/1\nm/44'/60'/1'/0/0\n")),
    ]);
    let client = api::Api::new(
        &endpoint,
        "synthetic-token".into(),
        api::Api::pin(&endpoint, true).unwrap(),
        true,
    )
    .unwrap();
    let mut imported = Imported::default();
    let (page, cursor, more) = client
        .paths("test-project", "confirmed", Some("old+/=&"))
        .await
        .unwrap();
    assert!(more);
    imported
        .apply(root, "confirmed", &page, cursor, WORDS, "")
        .unwrap();
    let before = serde_json::to_string(&imported).unwrap();
    let (page, cursor, _) = client
        .paths(
            "test-project",
            "confirmed",
            imported.confirmed_cursor.as_deref(),
        )
        .await
        .unwrap();
    assert!(
        imported
            .apply(root, "confirmed", &page, cursor, WORDS, "")
            .is_err()
    );
    assert_eq!(serde_json::to_string(&imported).unwrap(), before);
    let requests = worker.join().unwrap();
    let first = url::Url::parse(&format!("{endpoint}{}", requests[0].0)).unwrap();
    let params: std::collections::BTreeMap<_, _> = first.query_pairs().collect();
    assert_eq!(params.get("cursor").unwrap(), "old+/=&");
    assert_eq!(params.get("scope").unwrap(), "confirmed");
    assert_eq!(params.get("limit").unwrap(), "200");
    let second = url::Url::parse(&format!("{endpoint}{}", requests[1].0)).unwrap();
    assert!(
        second
            .query_pairs()
            .any(|(k, v)| k == "cursor" && v == "next-page")
    );
}
