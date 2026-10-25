//! The few ABI encodings the send plan needs: 32-byte words, selectors and calldata of
//! the ERC-20, EIP-2612 and EIP-3009 calls, and strict decoding of what a node returns.
use anyhow::Context;
use num_bigint::BigUint;
use sha3::{Digest, Keccak256};

pub(crate) fn keccak(data: &[u8]) -> [u8; 32] {
    Keccak256::digest(data).into()
}

/// First four bytes of the hash of a canonical signature such as `transfer(address,uint256)`.
pub(crate) fn selector(signature: &str) -> [u8; 4] {
    let hash = keccak(signature.as_bytes());
    [hash[0], hash[1], hash[2], hash[3]]
}

/// The all-zero address: the burn address and the "no recipient" value. A send to it is
/// refused because the funds could never be recovered.
pub(crate) const ZERO_ADDRESS: &str = "0x0000000000000000000000000000000000000000";

/// Lowercase `0x` + 40 hex digits, or an error.
pub(crate) fn normalize_address(address: &str) -> anyhow::Result<String> {
    let address = address.trim();
    let hex = address
        .strip_prefix("0x")
        .or_else(|| address.strip_prefix("0X"))
        .context("address must start with 0x")?;
    anyhow::ensure!(
        hex.len() == 40 && hex.chars().all(|c| c.is_ascii_hexdigit()),
        "address must be 0x followed by 40 hex characters"
    );
    Ok(format!("0x{}", hex.to_ascii_lowercase()))
}

pub(crate) fn address_bytes(address: &str) -> anyhow::Result<[u8; 20]> {
    let bytes = hex::decode(
        normalize_address(address)?
            .strip_prefix("0x")
            .unwrap_or_default(),
    )?;
    bytes
        .try_into()
        .map_err(|_| anyhow::anyhow!("invalid address"))
}

pub(crate) fn word_address(address: &str) -> anyhow::Result<[u8; 32]> {
    let mut word = [0u8; 32];
    word[12..].copy_from_slice(&address_bytes(address)?);
    Ok(word)
}

pub(crate) fn word_uint(value: &BigUint) -> anyhow::Result<[u8; 32]> {
    let bytes = value.to_bytes_be();
    anyhow::ensure!(bytes.len() <= 32, "uint256 overflow");
    let mut word = [0u8; 32];
    word[32 - bytes.len()..].copy_from_slice(&bytes);
    Ok(word)
}

pub(crate) fn hex_data(data: &[u8]) -> String {
    format!("0x{}", hex::encode(data))
}

pub(crate) fn hex_quantity(value: &BigUint) -> String {
    format!("0x{}", value.to_str_radix(16))
}

/// A recoverable signature split the way token contracts take it.
#[derive(Clone, Copy)]
pub(crate) struct Split {
    pub v: u8,
    pub r: [u8; 32],
    pub s: [u8; 32],
}

impl Split {
    /// `r || s` and the recovery parity, with the conventional `v` of 27 or 28.
    pub fn new(signature: &[u8; 64], parity: u8) -> Self {
        let mut r = [0u8; 32];
        let mut s = [0u8; 32];
        r.copy_from_slice(&signature[..32]);
        s.copy_from_slice(&signature[32..]);
        Self {
            v: 27 + (parity & 1),
            r,
            s,
        }
    }
    fn words(&self) -> [[u8; 32]; 3] {
        let mut v = [0u8; 32];
        v[31] = self.v;
        [v, self.r, self.s]
    }
}

pub(crate) fn encode(signature: &str, words: &[[u8; 32]]) -> Vec<u8> {
    let mut data = selector(signature).to_vec();
    for word in words {
        data.extend_from_slice(word);
    }
    data
}

/// `transfer(address,uint256)`
pub(crate) fn transfer(to: &str, amount: &BigUint) -> anyhow::Result<Vec<u8>> {
    Ok(encode(
        "transfer(address,uint256)",
        &[word_address(to)?, word_uint(amount)?],
    ))
}

/// `transferFrom(address,address,uint256)`
pub(crate) fn transfer_from(from: &str, to: &str, amount: &BigUint) -> anyhow::Result<Vec<u8>> {
    Ok(encode(
        "transferFrom(address,address,uint256)",
        &[word_address(from)?, word_address(to)?, word_uint(amount)?],
    ))
}

/// EIP-2612 `permit(owner,spender,value,deadline,v,r,s)`
pub(crate) fn permit(
    owner: &str,
    spender: &str,
    value: &BigUint,
    deadline: u64,
    signature: &Split,
) -> anyhow::Result<Vec<u8>> {
    let [v, r, s] = signature.words();
    Ok(encode(
        "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
        &[
            word_address(owner)?,
            word_address(spender)?,
            word_uint(value)?,
            word_uint(&BigUint::from(deadline))?,
            v,
            r,
            s,
        ],
    ))
}

/// EIP-3009 `transferWithAuthorization(from,to,value,validAfter,validBefore,nonce,v,r,s)`
pub(crate) struct Authorization<'a> {
    pub from: &'a str,
    pub to: &'a str,
    pub value: &'a BigUint,
    pub valid_after: u64,
    pub valid_before: u64,
    pub nonce: [u8; 32],
}

pub(crate) fn transfer_with_authorization(
    auth: &Authorization<'_>,
    signature: &Split,
) -> anyhow::Result<Vec<u8>> {
    let [v, r, s] = signature.words();
    Ok(encode(
        "transferWithAuthorization(address,address,uint256,uint256,uint256,bytes32,uint8,bytes32,bytes32)",
        &[
            word_address(auth.from)?,
            word_address(auth.to)?,
            word_uint(auth.value)?,
            word_uint(&BigUint::from(auth.valid_after))?,
            word_uint(&BigUint::from(auth.valid_before))?,
            auth.nonce,
            v,
            r,
            s,
        ],
    ))
}

/// A call with no arguments, or one address argument.
pub(crate) fn query(signature: &str, address: Option<&str>) -> anyhow::Result<String> {
    let words = match address {
        Some(a) => vec![word_address(a)?],
        None => vec![],
    };
    Ok(hex_data(&encode(signature, &words)))
}

/// The bytes of an `eth_call` result (`0x…`, bounded).
pub(crate) fn result_bytes(value: &serde_json::Value) -> anyhow::Result<Vec<u8>> {
    let text = value
        .as_str()
        .and_then(|s| s.strip_prefix("0x"))
        .context("invalid RPC bytes")?;
    anyhow::ensure!(text.len() <= 8192, "RPC bytes too long");
    Ok(hex::decode(text)?)
}

/// A call answering exactly one 32-byte word.
pub(crate) fn one_word(value: &serde_json::Value) -> anyhow::Result<[u8; 32]> {
    result_bytes(value)?
        .try_into()
        .map_err(|_| anyhow::anyhow!("expected a 32-byte answer"))
}

fn word_usize(bytes: &[u8], at: usize) -> anyhow::Result<usize> {
    let word = bytes.get(at..at + 32).context("short ABI value")?;
    anyhow::ensure!(word[..24].iter().all(|b| *b == 0), "ABI value too large");
    Ok(usize::try_from(u64::from_be_bytes(word[24..].try_into()?))?)
}

/// The ABI `string` whose offset sits in the head word at `head`.
pub(crate) fn string_at(bytes: &[u8], head: usize) -> anyhow::Result<String> {
    let offset = word_usize(bytes, head)?;
    let length = word_usize(bytes, offset)?;
    anyhow::ensure!(length <= 256, "text too long");
    let end = offset
        .checked_add(32 + length)
        .context("short ABI string")?;
    let raw = bytes.get(offset + 32..end).context("short ABI string")?;
    Ok(String::from_utf8(raw.to_vec())?)
}

#[cfg(test)]
mod tests {
    use super::*;
    const A: &str = "0x00000000000000000000000000000000000000a1";
    const B: &str = "0x00000000000000000000000000000000000000b2";

    #[test]
    fn selectors_match_the_published_function_ids() {
        // 4byte.directory / EIP texts, independent of the signature strings above.
        assert_eq!(
            hex::encode(selector("transfer(address,uint256)")),
            "a9059cbb"
        );
        assert_eq!(
            hex::encode(selector("transferFrom(address,address,uint256)")),
            "23b872dd"
        );
        assert_eq!(
            hex::encode(selector(
                "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)"
            )),
            "d505accf"
        );
        assert_eq!(
            hex::encode(selector(
                "transferWithAuthorization(address,address,uint256,uint256,uint256,bytes32,uint8,bytes32,bytes32)"
            )),
            "e3ee160e"
        );
        assert_eq!(
            hex::encode(selector("authorizationState(address,bytes32)")),
            "e94a0102"
        );
        assert_eq!(hex::encode(selector("nonces(address)")), "7ecebe00");
        assert_eq!(hex::encode(selector("DOMAIN_SEPARATOR()")), "3644e515");
        assert_eq!(hex::encode(selector("eip712Domain()")), "84b0196e");
    }

    #[test]
    fn calldata_is_selector_then_padded_words() {
        let amount = BigUint::from(1_000_000u32);
        let data = transfer(A, &amount).unwrap();
        assert_eq!(data.len(), 4 + 64);
        assert_eq!(&data[..4], &[0xa9, 0x05, 0x9c, 0xbb]);
        assert_eq!(&data[4..16], &[0u8; 12]);
        assert_eq!(data[35], 0xa1);
        assert_eq!(&data[36..64], &[0u8; 28]);
        assert_eq!(&data[64..], &[0x00, 0x0f, 0x42, 0x40]);

        let data = transfer_from(A, B, &amount).unwrap();
        assert_eq!(&data[..4], &[0x23, 0xb8, 0x72, 0xdd]);
        assert_eq!((data.len(), data[35], data[67]), (4 + 96, 0xa1, 0xb2));

        let signature = Split::new(&[7u8; 64], 1);
        assert_eq!(signature.v, 28);
        let data = permit(A, B, &amount, 1_700_000_900, &signature).unwrap();
        assert_eq!(&data[..4], &[0xd5, 0x05, 0xac, 0xcf]);
        assert_eq!(data.len(), 4 + 7 * 32);
        assert_eq!(
            &data[4 + 3 * 32 + 28..4 + 4 * 32],
            &1_700_000_900u32.to_be_bytes()
        );
        assert_eq!(data[4 + 5 * 32 - 1], 28);
        assert_eq!(&data[4 + 5 * 32..4 + 6 * 32], &[7u8; 32]);

        let auth = Authorization {
            from: A,
            to: B,
            value: &amount,
            valid_after: 0,
            valid_before: 1_700_000_900,
            nonce: [9u8; 32],
        };
        let data = transfer_with_authorization(&auth, &Split::new(&[3u8; 64], 0)).unwrap();
        assert_eq!(&data[..4], &[0xe3, 0xee, 0x16, 0x0e]);
        assert_eq!(data.len(), 4 + 9 * 32);
        assert_eq!(&data[4 + 5 * 32..4 + 6 * 32], &[9u8; 32]);
        assert_eq!(data[4 + 7 * 32 - 1], 27);
    }

    #[test]
    fn words_reject_overflow_and_bad_addresses() {
        assert!(word_uint(&(BigUint::from(1u8) << 256)).is_err());
        assert!(word_uint(&((BigUint::from(1u8) << 256) - 1u8)).is_ok());
        assert!(word_address("0x12").is_err());
        assert!(word_address(&format!("0x{}", "g".repeat(40))).is_err());
        assert_eq!(
            normalize_address(&A.to_uppercase().replace("0X", "0x")).unwrap(),
            A
        );
    }

    #[test]
    fn strings_and_single_words_decode_strictly() {
        let text = format!("{:064x}{:064x}{}{}", 32, 4, "55534443", "0".repeat(56));
        let bytes = hex::decode(text).unwrap();
        assert_eq!(string_at(&bytes, 0).unwrap(), "USDC");
        assert!(string_at(&bytes[..66], 0).is_err());
        assert!(one_word(&serde_json::json!(format!("0x{}", "00".repeat(32)))).is_ok());
        assert!(one_word(&serde_json::json!("0x")).is_err());
        assert!(one_word(&serde_json::json!(format!("0x{}", "00".repeat(33)))).is_err());
    }
}
