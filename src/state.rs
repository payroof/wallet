use std::time::{Duration, Instant};
use zeroize::{Zeroize, Zeroizing};
/// The unlocked vault key. How long it stays unlocked is the app's policy: it calls
/// `lock` on inactivity, sleep and screen lock.
pub struct UnlockSession {
    key: Option<Zeroizing<[u8; 32]>>,
    failures: u32,
    next_try: Instant,
}
impl Default for UnlockSession {
    fn default() -> Self {
        Self {
            key: None,
            failures: 0,
            next_try: Instant::now(),
        }
    }
}
impl UnlockSession {
    pub fn unlock(&mut self, vault: &crate::vault::Vault, pin: &str) -> anyhow::Result<()> {
        self.key = Some(self.verify(vault, pin)?);
        Ok(())
    }
    /// Checks the PIN and returns the vault key, without unlocking. Failures count
    /// toward the same growing delay as unlocking, so neither path guesses faster.
    pub fn verify(
        &mut self,
        vault: &crate::vault::Vault,
        pin: &str,
    ) -> anyhow::Result<Zeroizing<[u8; 32]>> {
        anyhow::ensure!(Instant::now() >= self.next_try, "unlock delayed");
        if let Ok(k) = vault.unlock(pin) {
            self.failures = 0;
            Ok(k)
        } else {
            self.failures = self.failures.saturating_add(1);
            let delay = if self.failures >= 3 {
                1u64 << self.failures.min(8)
            } else {
                0
            };
            self.next_try = Instant::now() + Duration::from_secs(delay);
            anyhow::bail!("unlock failed")
        }
    }
    pub fn device_unlock(&mut self, v: &crate::vault::Vault, key: [u8; 32]) -> anyhow::Result<()> {
        let key = Zeroizing::new(key);
        let _ = v.read(&key)?;
        self.key = Some(key);
        Ok(())
    }
    pub fn key(&self) -> anyhow::Result<&[u8; 32]> {
        self.key
            .as_deref()
            .ok_or_else(|| anyhow::anyhow!("wallet locked"))
    }
    pub fn lock(&mut self) {
        if let Some(mut key) = self.key.take() {
            key.zeroize();
        }
    }
}
