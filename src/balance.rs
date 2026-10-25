use crate::ids::{AssetId, ChainId};
use num_bigint::BigUint;
use serde_json::{Value, json};
use std::collections::BTreeSet;
pub(crate) async fn rpc(
    http: &reqwest::Client,
    endpoint: &str,
    method: &str,
    params: Value,
) -> anyhow::Result<Value> {
    let v = crate::api::fetch_json(
        http.post(endpoint)
            .json(&json!({"jsonrpc":"2.0","id":1,"method":method,"params":params})),
    )
    .await?;
    anyhow::ensure!(v.get("error").is_none(), "RPC request rejected");
    Ok(v.get("result")
        .ok_or_else(|| anyhow::anyhow!("missing RPC result"))?
        .clone())
}
pub(crate) fn parse_quantity(value: &Value) -> anyhow::Result<BigUint> {
    let s = value
        .as_str()
        .and_then(|s| s.strip_prefix("0x"))
        .ok_or_else(|| anyhow::anyhow!("invalid RPC integer"))?;
    anyhow::ensure!(!s.is_empty() && s.len() <= 64, "integer overflow");
    BigUint::parse_bytes(s.as_bytes(), 16).ok_or_else(|| anyhow::anyhow!("invalid RPC integer"))
}
pub async fn check_chain(
    http: &reqwest::Client,
    endpoint: &str,
    chain: &str,
) -> anyhow::Result<()> {
    let actual = parse_quantity(&rpc(http, endpoint, "eth_chainId", json!([])).await?)?;
    let expected: ChainId = chain.parse()?;
    anyhow::ensure!(
        BigUint::from(expected.number()) == actual,
        "RPC chain mismatch"
    );
    Ok(())
}
pub async fn balance(
    endpoint: &str,
    chain: &str,
    asset: &str,
    addresses: &[String],
    development: bool,
) -> anyhow::Result<String> {
    let unique: Vec<String> = addresses
        .iter()
        .collect::<BTreeSet<_>>()
        .into_iter()
        .cloned()
        .collect();
    let values = balances(endpoint, chain, asset, &unique, development).await?;
    Ok(values
        .into_iter()
        .fold(BigUint::default(), |sum, v| sum + v)
        .to_string())
}
/// Per-address balances in input order, after one RPC chain-identity check.
pub async fn balances(
    endpoint: &str,
    chain: &str,
    asset: &str,
    addresses: &[String],
    development: bool,
) -> anyhow::Result<Vec<BigUint>> {
    crate::networks::validate_rpc(endpoint, development)?;
    let http = crate::api::client()?;
    check_chain(&http, endpoint, chain).await?;
    let asset: AssetId = asset.parse()?;
    anyhow::ensure!(
        asset.chain == chain.parse::<ChainId>()?,
        "asset chain mismatch"
    );
    let mut values = Vec::with_capacity(addresses.len());
    for address in addresses {
        crate::assets::address(address)?;
        let value = if let Some(contract) = asset.contract() {
            rpc(&http,endpoint,"eth_call",json!([{"to":contract,"data":format!("0x70a08231000000000000000000000000{}",&address[2..])},"latest"])).await?
        } else {
            rpc(
                &http,
                endpoint,
                "eth_getBalance",
                json!([address, "latest"]),
            )
            .await?
        };
        values.push(parse_quantity(&value)?);
    }
    Ok(values)
}
/// What a token contract says about itself, read with `eth_call` after a chain check.
/// A symbol proves nothing about authenticity. It only saves typing.
#[derive(Debug, PartialEq, Eq)]
pub struct TokenDetails {
    pub symbol: String,
    pub name: String,
    pub decimals: u8,
}
pub async fn token_details(
    endpoint: &str,
    chain: &str,
    contract: &str,
    development: bool,
) -> anyhow::Result<TokenDetails> {
    crate::networks::validate_rpc(endpoint, development)?;
    crate::assets::address(contract)?;
    let http = crate::api::client()?;
    check_chain(&http, endpoint, chain).await?;
    let code = rpc(&http, endpoint, "eth_getCode", json!([contract, "latest"])).await?;
    anyhow::ensure!(
        code.as_str().is_some_and(|c| c.len() > 2),
        "no contract at this address"
    );
    let call = |selector: &'static str| {
        let http = &http;
        async move {
            rpc(
                http,
                endpoint,
                "eth_call",
                json!([{"to": contract, "data": selector}, "latest"]),
            )
            .await
        }
    };
    let decimals = parse_quantity(&call("0x313ce567").await?)?;
    let decimals = u8::try_from(decimals).ok().filter(|d| *d <= 36);
    let decimals = decimals.ok_or_else(|| anyhow::anyhow!("unsupported decimals"))?;
    let symbol = abi_text(&call("0x95d89b41").await?, 32)?;
    anyhow::ensure!(!symbol.is_empty(), "empty symbol");
    // A name is optional: some tokens don't implement it.
    let name = match call("0x06fdde03").await {
        Ok(value) => abi_text(&value, 64).unwrap_or_default(),
        Err(_) => String::new(),
    };
    Ok(TokenDetails {
        symbol,
        name,
        decimals,
    })
}
/// Decodes an ABI `string` return, or the `bytes32` form that some token contracts (MKR
/// for one) still return for `symbol` and `name`, into printable text of at most `limit`
/// characters. The `bytes32` form is what a node really sends for those tokens, so it
/// is part of reading them.
pub(crate) fn abi_text(value: &Value, limit: usize) -> anyhow::Result<String> {
    let hex = value
        .as_str()
        .and_then(|s| s.strip_prefix("0x"))
        .ok_or_else(|| anyhow::anyhow!("invalid RPC bytes"))?;
    anyhow::ensure!(hex.len() % 2 == 0 && hex.len() <= 4096, "invalid RPC bytes");
    let bytes = (0..hex.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&hex[i..i + 2], 16))
        .collect::<Result<Vec<_>, _>>()?;
    let word = |i: usize| -> anyhow::Result<usize> {
        let w = bytes
            .get(i..i + 32)
            .ok_or_else(|| anyhow::anyhow!("short ABI value"))?;
        anyhow::ensure!(w[..24].iter().all(|b| *b == 0), "ABI value too large");
        Ok(usize::try_from(u64::from_be_bytes(w[24..].try_into()?))?)
    };
    let raw = if bytes.len() == 32 {
        bytes.split(|b| *b == 0).next().unwrap_or_default().to_vec()
    } else {
        let offset = word(0)?;
        let length = word(offset)?;
        bytes
            .get(offset + 32..offset + 32 + length)
            .ok_or_else(|| anyhow::anyhow!("short ABI string"))?
            .to_vec()
    };
    let text = String::from_utf8(raw)?;
    let text: String = text.chars().filter(|c| !c.is_control()).collect();
    let text = text.trim();
    anyhow::ensure!(text.chars().count() <= limit, "text too long");
    Ok(text.to_string())
}
#[cfg(test)]
mod token_tests {
    use super::abi_text;
    use serde_json::json;
    #[test]
    fn token_text_decodes_abi_strings_and_bytes32() {
        // "USDC" as an ABI string: offset 32, length 4, padded data.
        let string = format!("0x{:064x}{:064x}{}{}", 32, 4, "55534443", "0".repeat(56));
        assert_eq!(abi_text(&json!(string), 32).unwrap(), "USDC");
        // "MKR" as bytes32.
        let bytes32 = format!("0x{}{}", "4d4b52", "0".repeat(58));
        assert_eq!(abi_text(&json!(bytes32), 32).unwrap(), "MKR");
        // Control characters are dropped. Oversize, short and malformed values fail.
        let control = format!("0x{:064x}{:064x}{}{}", 32, 3, "410a42", "0".repeat(58));
        assert_eq!(abi_text(&json!(control), 32).unwrap(), "AB");
        let long = format!("0x{:064x}{:064x}{}", 32, 40, "41".repeat(64));
        assert!(abi_text(&json!(long), 32).is_err());
        assert!(abi_text(&json!(format!("0x{:064x}{:064x}", 32, 64)), 32).is_err());
        assert!(abi_text(&json!("0x123"), 32).is_err());
        assert!(abi_text(&json!(1), 32).is_err());
    }
}
