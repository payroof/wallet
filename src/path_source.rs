use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
#[derive(Default, Serialize, Deserialize)]
pub struct Imported {
    pub addresses: BTreeMap<String, String>,
    pub confirmed_cursor: Option<String>,
    pub all_cursor: Option<String>,
}
pub fn validate_child(root: &str, path: &str) -> anyhow::Result<u32> {
    let prefix = format!("{root}/");
    let index = path
        .strip_prefix(&prefix)
        .ok_or_else(|| anyhow::anyhow!("path outside project"))?;
    let n: u32 = index.parse()?;
    anyhow::ensure!(
        n < crate::derivation::HARDENED && n.to_string() == index,
        "invalid path child"
    );
    Ok(n)
}
impl Imported {
    /// Persist the entire value atomically so a failed page cannot advance the cursor.
    pub fn apply(
        &mut self,
        root: &str,
        scope: &str,
        page: &str,
        cursor: String,
        mnemonic: &str,
        passphrase: &str,
    ) -> anyhow::Result<()> {
        anyhow::ensure!(
            matches!(scope, "all" | "confirmed") && page.len() <= 128_000,
            "invalid feed"
        );
        let mut candidate = BTreeMap::new();
        for path in page.lines() {
            validate_child(root, path)?;
            candidate.insert(
                path.to_string(),
                crate::derivation::address(mnemonic, passphrase, path)?,
            );
        }
        self.addresses.extend(candidate);
        if scope == "all" {
            self.all_cursor = Some(cursor);
        } else {
            self.confirmed_cursor = Some(cursor);
        }
        Ok(())
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn exact_children() {
        let r = "m/44'/60'/7'/1";
        assert_eq!(validate_child(r, &format!("{r}/77")).unwrap(), 77);
        for p in [
            "m/44'/60'/8'/1/77",
            "m/44'/60'/7'/0/77",
            "m/44'/60'/7'/1/77/1",
            "m/44'/60'/7'/1/00",
        ] {
            assert!(validate_child(r, p).is_err());
        }
    }
}
