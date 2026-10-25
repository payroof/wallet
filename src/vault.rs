//! Versioned envelope encryption. PIN changes only rewrap the data key.
use crate::secret::{open, random, seal};
use argon2::{Algorithm, Argon2, Params, Version};
use serde::{Deserialize, Serialize};
use zeroize::Zeroizing;
/// The only vault format. A vault of any other version is refused.
const VERSION: u32 = 1;
/// The KDF every vault names. Anything else is refused as an unsafe profile.
const KDF_ALGORITHM: &str = "argon2id";
/// Argon2id cost of a new vault: 64 MiB, three passes, one lane. `pin_key` accepts a wider
/// range so the cost can be raised later without locking anyone out.
const KDF_MEMORY_KIB: u32 = 65_536;
const KDF_ITERATIONS: u32 = 3;
const KDF_PARALLELISM: u32 = 1;
/// The memory, pass and lane ranges `pin_key` accepts from a stored vault.
const KDF_MEMORY_RANGE_KIB: std::ops::RangeInclusive<u32> = 65_536..=262_144;
const KDF_ITERATIONS_RANGE: std::ops::RangeInclusive<u32> = 3..=10;
const KDF_PARALLELISM_RANGE: std::ops::RangeInclusive<u32> = 1..=4;
/// The passcode length in bytes.
const PIN_BYTES: std::ops::RangeInclusive<usize> = 6..=128;
/// Binds every ciphertext of a vault to this format, its wallet and its purpose, so one
/// cannot be moved into another place. The wallet ID and the purpose follow it.
const AAD_DOMAIN: &str = "payroof-wallet:v1";
/// The longest wallet ID a vault accepts.
const MAX_WALLET_ID: usize = 100;

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Kdf {
    pub algorithm: String,
    pub memory_kib: u32,
    pub iterations: u32,
    pub parallelism: u32,
    pub salt: [u8; 16],
}
#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Vault {
    pub version: u32,
    pub wallet_id: String,
    pub kdf: Kdf,
    pub wrapped_key: String,
    pub secrets: String,
}
fn pin_key(pin: &str, k: &Kdf) -> anyhow::Result<Zeroizing<[u8; 32]>> {
    anyhow::ensure!(
        PIN_BYTES.contains(&pin.len()),
        "passcode must contain 6..128 bytes"
    );
    anyhow::ensure!(
        k.algorithm == KDF_ALGORITHM
            && KDF_MEMORY_RANGE_KIB.contains(&k.memory_kib)
            && KDF_ITERATIONS_RANGE.contains(&k.iterations)
            && KDF_PARALLELISM_RANGE.contains(&k.parallelism),
        "unsafe KDF profile"
    );
    let params = Params::new(k.memory_kib, k.iterations, k.parallelism, Some(32))?;
    let mut key = Zeroizing::new([0; 32]);
    Argon2::new(Algorithm::Argon2id, Version::V0x13, params).hash_password_into(
        pin.as_bytes(),
        &k.salt,
        &mut *key,
    )?;
    Ok(key)
}
impl Vault {
    fn aad(&self, purpose: &str) -> String {
        format!("{AAD_DOMAIN}:{}:{purpose}", self.wallet_id)
    }
    pub fn create(wallet_id: String, pin: &str, secrets: &[u8]) -> anyhow::Result<Self> {
        let kdf = Kdf {
            algorithm: KDF_ALGORITHM.into(),
            memory_kib: KDF_MEMORY_KIB,
            iterations: KDF_ITERATIONS,
            parallelism: KDF_PARALLELISM,
            salt: random()?,
        };
        let kek = pin_key(pin, &kdf)?;
        let dek = Zeroizing::new(random::<32>()?);
        let mut vault = Self {
            version: VERSION,
            wallet_id,
            kdf,
            wrapped_key: String::new(),
            secrets: String::new(),
        };
        vault.wrapped_key = seal(&kek, vault.aad("dek").as_bytes(), &*dek)?;
        vault.secrets = seal(&dek, vault.aad("secrets").as_bytes(), secrets)?;
        Ok(vault)
    }
    pub fn unlock(&self, pin: &str) -> anyhow::Result<Zeroizing<[u8; 32]>> {
        anyhow::ensure!(
            self.version == VERSION && self.wallet_id.len() <= MAX_WALLET_ID,
            "unsupported vault"
        );
        let kek = pin_key(pin, &self.kdf)?;
        let b = open(&kek, self.aad("dek").as_bytes(), &self.wrapped_key)?;
        let mut out = Zeroizing::new([0; 32]);
        anyhow::ensure!(b.len() == 32, "invalid DEK");
        out.copy_from_slice(&b);
        Ok(out)
    }
    pub fn read(&self, dek: &[u8; 32]) -> anyhow::Result<Zeroizing<Vec<u8>>> {
        open(dek, self.aad("secrets").as_bytes(), &self.secrets)
    }
    pub fn write(&mut self, dek: &[u8; 32], secrets: &[u8]) -> anyhow::Result<()> {
        self.secrets = seal(dek, self.aad("secrets").as_bytes(), secrets)?;
        Ok(())
    }
    pub fn change_pin(&mut self, old: &str, new: &str) -> anyhow::Result<()> {
        let dek = self.unlock(old)?;
        let kdf = Kdf {
            algorithm: KDF_ALGORITHM.into(),
            memory_kib: KDF_MEMORY_KIB,
            iterations: KDF_ITERATIONS,
            parallelism: KDF_PARALLELISM,
            salt: random()?,
        };
        let kek = pin_key(new, &kdf)?;
        let wrapped = seal(&kek, self.aad("dek").as_bytes(), &*dek)?;
        self.kdf = kdf;
        self.wrapped_key = wrapped;
        Ok(())
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn envelope_and_rewrap() {
        let mut v = Vault::create("wallet".into(), "987654", b"secret").unwrap();
        assert!(v.unlock("111111").is_err());
        let dek = v.unlock("987654").unwrap();
        assert_eq!(&*v.read(&dek).unwrap(), b"secret");
        let c = v.secrets.clone();
        v.change_pin("987654", "654321").unwrap();
        assert_eq!(c, v.secrets);
        assert!(v.unlock("987654").is_err());
        let k = v.unlock("654321").unwrap();
        assert_eq!(*dek, *k);
        v.wallet_id = "other".into();
        assert!(v.read(&k).is_err());
    }
    #[test]
    fn bound_before_allocation() {
        let mut v = Vault::create("w".into(), "123456", b"s").unwrap();
        v.kdf.memory_kib = u32::MAX;
        assert!(v.unlock("123456").is_err());
    }
}
