use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
/// The key algorithm of a watch root: BIP-32 public derivation on secp256k1.
pub const ALGORITHM: &str = "bip32-secp256k1";
#[derive(Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WatchKey {
    pub algorithm: String,
    pub public_key: String,
    pub chain_code: String,
}
#[derive(Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WatchRoot {
    pub family: String,
    pub path: String,
    pub key: WatchKey,
}
/// Domain tag that starts every fingerprint, so a fingerprint of a watch root can never
/// equal a hash made for another purpose.
const FINGERPRINT_DOMAIN: &[u8] = b"payroof-watch-v1\0";
impl WatchRoot {
    pub fn validate(&self) -> anyhow::Result<()> {
        anyhow::ensure!(
            self.family == crate::ids::EVM_NAMESPACE && self.key.algorithm == ALGORITHM,
            "unsupported watch root"
        );
        let slot = self
            .path
            .strip_prefix("m/44'/60'/")
            .and_then(|s| s.strip_suffix("'/1"))
            .ok_or_else(|| anyhow::anyhow!("invalid root"))?;
        let n: u32 = slot.parse()?;
        anyhow::ensure!(
            n < crate::derivation::HARDENED && n.to_string() == slot,
            "invalid slot"
        );
        crate::derivation::decode_watch_key(&self.key)?;
        Ok(())
    }
    /// Canonical fingerprint: SHA256("payroof-watch-v1\0" || family || 0 || path || 0 || SEC1 || chain code).
    pub fn fingerprint(&self) -> anyhow::Result<String> {
        let (pk, cc) = crate::derivation::decode_watch_key(&self.key)?;
        let mut h = Sha256::new();
        h.update(FINGERPRINT_DOMAIN);
        h.update(self.family.as_bytes());
        h.update([0]);
        h.update(self.path.as_bytes());
        h.update([0]);
        h.update(pk);
        h.update(cc);
        Ok(format!("sha256:{}", hex::encode(h.finalize())))
    }
}
