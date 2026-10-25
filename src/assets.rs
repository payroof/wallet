pub fn address(s: &str) -> anyhow::Result<()> {
    anyhow::ensure!(
        s.starts_with("0x") && s.len() == 42 && s[2..].bytes().all(|b| b.is_ascii_hexdigit()),
        "invalid EVM address"
    );
    Ok(())
}
pub fn atomic(s: &str) -> anyhow::Result<num_bigint::BigUint> {
    anyhow::ensure!(
        !s.is_empty()
            && s.len() <= 78
            && (s == "0" || !s.starts_with('0'))
            && s.bytes().all(|b| b.is_ascii_digit()),
        "invalid atomic amount"
    );
    let n = num_bigint::BigUint::parse_bytes(s.as_bytes(), 10)
        .ok_or_else(|| anyhow::anyhow!("invalid amount"))?;
    anyhow::ensure!(n.bits() <= 256, "uint256 overflow");
    Ok(n)
}
