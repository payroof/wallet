use bip39::{Language, Mnemonic};
use zeroize::Zeroizing;
pub fn generate() -> anyhow::Result<Zeroizing<String>> {
    let entropy = Zeroizing::new(crate::secret::random::<32>()?);
    Ok(Zeroizing::new(
        Mnemonic::from_entropy_in(Language::English, &*entropy)?.to_string(),
    ))
}
pub fn normalize(input: &str) -> anyhow::Result<Zeroizing<String>> {
    let s = Zeroizing::new(
        input
            .split_whitespace()
            .map(str::to_lowercase)
            .collect::<Vec<_>>()
            .join(" "),
    );
    let m = Mnemonic::parse_in_normalized(Language::English, &s)?;
    Ok(Zeroizing::new(m.to_string()))
}
pub fn seed(words: &str, passphrase: &str) -> anyhow::Result<Zeroizing<[u8; 64]>> {
    let m = Mnemonic::parse_in_normalized(Language::English, &normalize(words)?)?;
    Ok(Zeroizing::new(m.to_seed(passphrase)))
}
