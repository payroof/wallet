//! Derives an independent Recovery Key from mnemonic and Project slot.
use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
use ed25519_dalek::{Signer, SigningKey};
use hmac::{Hmac, KeyInit, Mac};
use sha2::Sha512;
use zeroize::Zeroizing;
/// The BIP-85 application path of the recovery key, `m/83696968'/128169'/32'/{slot}'`:
/// application 128169 derives 32 bytes of entropy, and the account's slot numbers the key.
const BIP85_ROOT: &str = "m/83696968'/128169'/32'";
/// The HMAC key BIP-85 prescribes for turning the derived private key into entropy.
const BIP85_HMAC_KEY: &[u8] = b"bip-entropy-from-k";
/// The first line of every recovery message. It names the protocol, so a signature made
/// for recovery can never be replayed as anything else, and carries the format's version.
const SIGNATURE_DOMAIN: &str = "payroof-recovery-v2";

fn signing_key(mnemonic: &str, passphrase: &str, slot: u32) -> anyhow::Result<SigningKey> {
    anyhow::ensure!(slot < crate::derivation::HARDENED, "slot exhausted");
    let key =
        crate::derivation::private_key(mnemonic, passphrase, &format!("{BIP85_ROOT}/{slot}'"))?;
    let mut mac = Hmac::<Sha512>::new_from_slice(BIP85_HMAC_KEY)
        .map_err(|_| anyhow::anyhow!("invalid recovery key material"))?;
    mac.update(&*key);
    let entropy = Zeroizing::new(<[u8; 64]>::from(mac.finalize().into_bytes()));
    let mut seed = Zeroizing::new([0u8; 32]);
    seed.copy_from_slice(&entropy[..32]);
    Ok(SigningKey::from_bytes(&seed))
}
pub fn public(mnemonic: &str, passphrase: &str, slot: u32) -> anyhow::Result<String> {
    Ok(URL_SAFE_NO_PAD.encode(
        signing_key(mnemonic, passphrase, slot)?
            .verifying_key()
            .to_bytes(),
    ))
}
/// What a recovery signature binds: the API origin and the API's one-time recovery
/// challenge, which the API issued for the key's one project.
pub struct Challenge<'a> {
    pub origin: &'a str,
    pub id: &'a str,
    pub challenge: &'a str,
}
/// Signs a recovery challenge with the slot's recovery key. The origin must be
/// HTTPS unless `development` allows loopback HTTP.
pub fn sign(
    mnemonic: &str,
    passphrase: &str,
    slot: u32,
    c: &Challenge,
    development: bool,
) -> anyhow::Result<String> {
    let origin = crate::api::origin(c.origin, development)?;
    let message = format!("{SIGNATURE_DOMAIN}\n{origin}\n{}\n{}\n", c.id, c.challenge);
    Ok(URL_SAFE_NO_PAD.encode(
        signing_key(mnemonic, passphrase, slot)?
            .sign(message.as_bytes())
            .to_bytes(),
    ))
}
#[cfg(test)]
mod tests {
    use super::*;
    use ed25519_dalek::{Signature, VerifyingKey};
    const WORDS: &str = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

    #[test]
    fn recovery_transport_policy_and_exact_origin_binding() {
        let origin = "http://127.0.0.1:8080";
        assert!(
            sign(
                WORDS,
                "",
                0,
                &Challenge {
                    origin,
                    id: "rec_123",
                    challenge: "challenge"
                },
                false
            )
            .is_err()
        );
        assert!(
            sign(
                WORDS,
                "",
                0,
                &Challenge {
                    origin: "http://api.example:8080",
                    id: "rec_123",
                    challenge: "challenge"
                },
                true
            )
            .is_err()
        );
        let encoded = sign(
            WORDS,
            "",
            0,
            &Challenge {
                origin,
                id: "rec_123",
                challenge: "challenge",
            },
            true,
        )
        .unwrap();
        let signature = Signature::from_slice(&URL_SAFE_NO_PAD.decode(encoded).unwrap()).unwrap();
        let key = VerifyingKey::from_bytes(
            &URL_SAFE_NO_PAD
                .decode(public(WORDS, "", 0).unwrap())
                .unwrap()
                .try_into()
                .unwrap(),
        )
        .unwrap();
        let message = "payroof-recovery-v2\nhttp://127.0.0.1:8080\nrec_123\nchallenge\n";
        key.verify_strict(message.as_bytes(), &signature).unwrap();
        for modified in [
            message.replace("http://", "https://"),
            message.replace(":8080", ":8081"),
            message.replace("rec_123", "rec_456"),
            message.replace("challenge", "changed"),
        ] {
            assert!(key.verify_strict(modified.as_bytes(), &signature).is_err());
        }
        assert!(
            sign(
                WORDS,
                "",
                0,
                &Challenge {
                    origin: "https://api.example:8443",
                    id: "rec_123",
                    challenge: "challenge"
                },
                false
            )
            .is_ok()
        );
    }
}
