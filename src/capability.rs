//! What a token contract proves it supports: EIP-712 typed signatures (EIP-3009
//! `transferWithAuthorization`, EIP-2612 `permit`). Everything is read with `eth_call`.
//! anything unproven counts as unsupported and the plan falls back to a gas top-up.
use crate::abi::{
    encode, hex_data, normalize_address, one_word, query, result_bytes, string_at, word_address,
};
use crate::balance::{abi_text, rpc};
use crate::eip712::{Domain, permit_type_hash};
use num_bigint::BigUint;
use serde_json::{Value, json};

#[derive(Clone, Debug, Default)]
pub(crate) struct Capability {
    /// The token's verified EIP-712 domain. None when it could not be proven.
    pub domain: Option<Domain>,
    pub authorization: bool,
    pub permit: bool,
}

async fn call(
    http: &reqwest::Client,
    endpoint: &str,
    contract: &str,
    data: String,
) -> anyhow::Result<Value> {
    rpc(
        http,
        endpoint,
        "eth_call",
        json!([{"to": contract, "data": data}, "latest"]),
    )
    .await
}

/// Reads the token's capabilities. `probe` is any address, used to ask the owner-specific
/// views. The answers only need to have the right shape.
pub(crate) async fn detect(
    http: &reqwest::Client,
    endpoint: &str,
    chain_id: &BigUint,
    contract: &str,
    probe: &str,
) -> Capability {
    let Some(domain) = domain(http, endpoint, chain_id, contract).await else {
        return Capability::default();
    };
    let authorization = match word_address(probe) {
        Ok(owner) => {
            let data = hex_data(&encode(
                "authorizationState(address,bytes32)",
                &[owner, [0u8; 32]],
            ));
            call(http, endpoint, contract, data)
                .await
                .is_ok_and(|answer| one_word(&answer).is_ok())
        }
        Err(_) => false,
    };
    let permit = match query("nonces(address)", Some(probe)) {
        Ok(data) => match call(http, endpoint, contract, data).await {
            Ok(answer) if one_word(&answer).is_ok() => {
                // Tokens that publish their permit type must publish the standard one
                // (DAI's differs, and its `permit` has another shape).
                match query("PERMIT_TYPEHASH()", None) {
                    Ok(data) => match call(http, endpoint, contract, data).await {
                        Ok(published) => {
                            one_word(&published).is_ok_and(|w| w == permit_type_hash())
                        }
                        Err(_) => true,
                    },
                    Err(_) => false,
                }
            }
            _ => false,
        },
        Err(_) => false,
    };
    Capability {
        domain: Some(domain),
        authorization,
        permit,
    }
}

/// The domain whose separator equals the contract's own `DOMAIN_SEPARATOR()`.
async fn domain(
    http: &reqwest::Client,
    endpoint: &str,
    chain_id: &BigUint,
    contract: &str,
) -> Option<Domain> {
    let contract = normalize_address(contract).ok()?;
    let onchain = one_word(
        &call(
            http,
            endpoint,
            &contract,
            query("DOMAIN_SEPARATOR()", None).ok()?,
        )
        .await
        .ok()?,
    )
    .ok()?;
    let mut names: Vec<String> = Vec::new();
    let mut versions: Vec<String> = Vec::new();
    // ERC-5267 states the domain outright.
    if let Some((name, version)) = eip5267(http, endpoint, chain_id, &contract).await {
        names.push(name);
        versions.push(version);
    }
    if let Ok(value) = call(http, endpoint, &contract, query("name()", None).ok()?).await
        && let Ok(name) = abi_text(&value, 64)
    {
        names.push(name);
    }
    if let Ok(value) = call(http, endpoint, &contract, query("version()", None).ok()?).await
        && let Ok(version) = abi_text(&value, 16)
    {
        versions.push(version);
    }
    versions.extend(["1".to_string(), "2".to_string()]);
    for name in &names {
        for version in &versions {
            let domain = Domain {
                name: name.clone(),
                version: version.clone(),
                chain_id: chain_id.clone(),
                contract: contract.clone(),
            };
            if domain.separator().is_ok_and(|s| s == onchain) {
                return Some(domain);
            }
        }
    }
    None
}

/// `eip712Domain()` answering name and version for exactly this chain and contract.
async fn eip5267(
    http: &reqwest::Client,
    endpoint: &str,
    chain_id: &BigUint,
    contract: &str,
) -> Option<(String, String)> {
    let answer = call(
        http,
        endpoint,
        contract,
        query("eip712Domain()", None).ok()?,
    )
    .await
    .ok()?;
    let bytes = result_bytes(&answer).ok()?;
    // fields (name, version, chainId, verifyingContract set. No salt, no extensions).
    let word = |i: usize| bytes.get(32 * i..32 * i + 32);
    (word(0)?[31] == 0x0f).then_some(())?;
    (BigUint::from_bytes_be(word(3)?) == *chain_id).then_some(())?;
    (word(4)? == word_address(contract).ok()?.as_slice()).then_some(())?;
    Some((string_at(&bytes, 32).ok()?, string_at(&bytes, 64).ok()?))
}
