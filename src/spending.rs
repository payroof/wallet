//! Local EVM signing: the key-backed signer, and legacy / EIP-1559 transactions encoded
//! and signed from it. What to send and when is decided by `send`.
use crate::abi::{address_bytes, hex_data};
use crate::balance::rpc;
use anyhow::Context;
use num_bigint::BigUint;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sha3::{Digest, Keccak256};
/// How a transaction pays for gas. The one type for it everywhere: the plan JSON and the
/// shipped network defaults spell it `eip1559` or `legacy` (serde), and hosts choose it
/// through the `legacy` flag of the send calls (`from_legacy`).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Mode {
    /// Type 2 transaction with a fee cap and a priority fee.
    Eip1559,
    /// Pre-London transaction with a single gas price, for chains without a base fee.
    Legacy,
}

impl Mode {
    /// The mode a host's `legacy` flag selects.
    pub fn from_legacy(legacy: bool) -> Self {
        if legacy { Self::Legacy } else { Self::Eip1559 }
    }
}
pub trait WalletSigner: Send + Sync {
    fn family(&self) -> &str;
    fn address(&self) -> String;
    /// Sign a 32-byte digest, returning `r || s` and the recovery parity.
    fn sign_recoverable(&self, digest: &[u8; 32]) -> anyhow::Result<([u8; 64], u8)>;
}

/// Local EVM signer backed by an in-memory secp256k1 key.
///
/// SECURITY: no `Debug`/`Serialize`, so key bytes cannot be logged or cached by
/// accident. `k256` zeroizes its own key material on drop.
pub struct EvmSigner {
    key: k256::ecdsa::SigningKey,
}

impl EvmSigner {
    /// Build a signer from a raw 32-byte secp256k1 scalar. Accepts both `&[u8]`
    /// and `&Zeroizing<[u8; 32]>` so callers can hand over key material without
    /// copying it out of its zeroizing container.
    pub fn from_private_key(bytes: impl AsRef<[u8]>) -> anyhow::Result<Self> {
        let key = k256::ecdsa::SigningKey::from_slice(bytes.as_ref())
            .map_err(|_| anyhow::anyhow!("invalid EVM private key"))?;
        Ok(Self { key })
    }

    /// Lowercase `0x`-prefixed EVM address of this key.
    pub fn address(&self) -> String {
        let public_key: k256::PublicKey = self.key.verifying_key().into();
        crate::derivation::evm_address(&public_key)
    }
}

impl WalletSigner for EvmSigner {
    fn family(&self) -> &str {
        crate::ids::EVM_NAMESPACE
    }

    fn address(&self) -> String {
        EvmSigner::address(self)
    }

    fn sign_recoverable(&self, digest: &[u8; 32]) -> anyhow::Result<([u8; 64], u8)> {
        let (signature, recovery_id) = self.key.sign_prehash_recoverable(digest);
        let mut bytes = [0u8; 64];
        bytes.copy_from_slice(signature.to_bytes().as_slice());
        Ok((bytes, recovery_id.to_byte()))
    }
}

/// Everything a signed transaction commits to. Legacy transactions use `max_fee` as
/// their gas price and ignore `priority`.
pub struct Tx {
    pub mode: Mode,
    pub chain_id: BigUint,
    pub nonce: BigUint,
    pub priority: BigUint,
    pub max_fee: BigUint,
    pub gas: BigUint,
    pub to: String,
    pub value: BigUint,
    pub data: Vec<u8>,
}

/// The raw signed transaction (EIP-155 legacy, or EIP-1559 type 2).
pub fn sign_transaction(signer: &dyn WalletSigner, tx: &Tx) -> anyhow::Result<Vec<u8>> {
    let to = rlp_bytes(&address_bytes(&tx.to)?);
    let fields = match tx.mode {
        Mode::Legacy => vec![
            rlp_uint(&tx.nonce),
            rlp_uint(&tx.max_fee),
            rlp_uint(&tx.gas),
            to,
            rlp_uint(&tx.value),
            rlp_bytes(&tx.data),
        ],
        Mode::Eip1559 => vec![
            rlp_uint(&tx.chain_id),
            rlp_uint(&tx.nonce),
            rlp_uint(&tx.priority),
            rlp_uint(&tx.max_fee),
            rlp_uint(&tx.gas),
            to,
            rlp_uint(&tx.value),
            rlp_bytes(&tx.data),
            rlp_list(&[]),
        ],
    };
    let prefix: &[u8] = match tx.mode {
        Mode::Legacy => &[],
        Mode::Eip1559 => &[2],
    };
    let mut unsigned = fields.clone();
    if matches!(tx.mode, Mode::Legacy) {
        unsigned.extend([
            rlp_uint(&tx.chain_id),
            rlp_uint(&BigUint::default()),
            rlp_uint(&BigUint::default()),
        ]);
    }
    let mut payload = prefix.to_vec();
    payload.extend(rlp_list(&unsigned));
    let digest: [u8; 32] = Keccak256::digest(&payload).into();
    let (signature, parity) = signer.sign_recoverable(&digest)?;
    let recovery = match tx.mode {
        Mode::Legacy => &tx.chain_id * 2u32 + 35u32 + u32::from(parity),
        Mode::Eip1559 => BigUint::from(parity),
    };
    let mut wire_fields = fields;
    wire_fields.extend([
        rlp_uint(&recovery),
        rlp_minimal_scalar(&signature[..32]),
        rlp_minimal_scalar(&signature[32..]),
    ]);
    let mut raw = prefix.to_vec();
    raw.extend(rlp_list(&wire_fields));
    Ok(raw)
}

/// Hash of a raw signed transaction, as nodes report it.
pub fn transaction_hash(raw: &[u8]) -> String {
    hex_data(&Keccak256::digest(raw))
}

/// Submits a signed transaction. The node's answer must be the hash we computed.
pub async fn send_raw(
    http: &reqwest::Client,
    endpoint: &str,
    raw: &[u8],
) -> anyhow::Result<String> {
    let result = rpc(
        http,
        endpoint,
        "eth_sendRawTransaction",
        json!([hex_data(raw)]),
    )
    .await?;
    let hash = parse_tx_hash(&result)?;
    anyhow::ensure!(hash == transaction_hash(raw), "unexpected transaction hash");
    Ok(hash)
}

/// `Some(success)` once the transaction is mined, `None` while it is not.
pub async fn receipt_status(
    http: &reqwest::Client,
    endpoint: &str,
    transaction: &str,
) -> anyhow::Result<Option<bool>> {
    let r = rpc(
        http,
        endpoint,
        "eth_getTransactionReceipt",
        json!([transaction]),
    )
    .await?;
    if r.is_null() {
        return Ok(None);
    }
    Ok(Some(r["status"] == "0x1"))
}

pub async fn receipt(
    endpoint: &str,
    transaction: &str,
    chain: &str,
    development: bool,
) -> anyhow::Result<Option<bool>> {
    crate::networks::validate_rpc(endpoint, development)?;
    let http = crate::api::client()?;
    crate::balance::check_chain(&http, endpoint, chain).await?;
    receipt_status(&http, endpoint, transaction).await
}

fn parse_tx_hash(value: &Value) -> anyhow::Result<String> {
    let text = value
        .as_str()
        .context("eth_sendRawTransaction returned a non-string result")?;
    let hex = text
        .strip_prefix("0x")
        .context("transaction hash missing 0x prefix")?;
    anyhow::ensure!(
        hex.len() == 64 && hex.chars().all(|c| c.is_ascii_hexdigit()),
        "invalid transaction hash from the RPC endpoint"
    );
    Ok(format!("0x{}", hex.to_ascii_lowercase()))
}

// --- minimal RLP encoder -----------------------------------------------------

/// RLP byte string: a single byte below `0x80` encodes as itself. Empty and
/// larger payloads carry a length prefix.
fn rlp_bytes(data: &[u8]) -> Vec<u8> {
    if data.len() == 1 && data[0] < 0x80 {
        return data.to_vec();
    }
    let mut out = rlp_length(data.len(), 0x80);
    out.extend_from_slice(data);
    out
}

/// RLP unsigned integer. Zero encodes as the empty string `0x80`.
fn rlp_uint(value: &BigUint) -> Vec<u8> {
    if value == &BigUint::default() {
        return vec![0x80];
    }
    rlp_bytes(&value.to_bytes_be())
}

fn rlp_list(items: &[Vec<u8>]) -> Vec<u8> {
    let payload: Vec<u8> = items.concat();
    let mut out = rlp_length(payload.len(), 0xc0);
    out.extend_from_slice(&payload);
    out
}

fn rlp_length(len: usize, offset: u8) -> Vec<u8> {
    if let Ok(short) = u8::try_from(len)
        && short < 56
    {
        return vec![offset + short];
    }
    let len_bytes = BigUint::from(len).to_bytes_be();
    let width = u8::try_from(len_bytes.len()).expect("a usize needs at most eight bytes");
    let mut out = Vec::with_capacity(1 + len_bytes.len());
    out.push(offset + 55 + width);
    out.extend_from_slice(&len_bytes);
    out
}

/// Minimal big-endian EIP-1559 signature scalar: leading zero bytes are
/// dropped and a zero value encodes as the empty string `0x80`.
fn rlp_minimal_scalar(bytes: &[u8]) -> Vec<u8> {
    let first = bytes
        .iter()
        .position(|byte| *byte != 0)
        .unwrap_or(bytes.len());
    rlp_bytes(&bytes[first..])
}

#[cfg(test)]
mod vectors {
    use super::*;
    /// Independent published wire fixture: <https://eips.ethereum.org/EIPS/eip-155>
    #[test]
    fn published_eip155_signature_and_rlp() {
        let n = |s: &str| BigUint::parse_bytes(s.as_bytes(), 10).unwrap();
        let fields = vec![
            rlp_uint(&n("9")),
            rlp_uint(&n("20000000000")),
            rlp_uint(&n("21000")),
            rlp_bytes(&hex::decode("3535353535353535353535353535353535353535").unwrap()),
            rlp_uint(&n("1000000000000000000")),
            rlp_bytes(&[]),
        ];
        let mut unsigned = fields.clone();
        unsigned.extend([rlp_uint(&n("1")), rlp_uint(&n("0")), rlp_uint(&n("0"))]);
        let payload = rlp_list(&unsigned);
        assert_eq!(
            hex::encode(&payload),
            "ec098504a817c800825208943535353535353535353535353535353535353535880de0b6b3a764000080018080"
        );
        let digest: [u8; 32] = Keccak256::digest(&payload).into();
        assert_eq!(
            hex::encode(digest),
            "daf5a779ae972f972197303d7b574746c7ef83eadac0f2791ad23db92e4c8e53"
        );
        let signer = EvmSigner::from_private_key([0x46; 32]).unwrap();
        let (signature, parity) = signer.sign_recoverable(&digest).unwrap();
        let mut wire_fields = fields;
        wire_fields.extend([
            rlp_uint(&n(&(35 + 2 + u32::from(parity)).to_string())),
            rlp_minimal_scalar(&signature[..32]),
            rlp_minimal_scalar(&signature[32..]),
        ]);
        assert_eq!(
            hex::encode(rlp_list(&wire_fields)),
            "f86c098504a817c800825208943535353535353535353535353535353535353535880de0b6b3a76400008025a028ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276a067cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83"
        );
    }
    #[test]
    fn signature_scalars_are_minimal_and_zero_is_empty() {
        assert_eq!(rlp_minimal_scalar(&[0, 0, 1]), vec![1]);
        assert_eq!(rlp_minimal_scalar(&[0; 32]), vec![0x80]);
    }
}

#[cfg(test)]
mod transactions {
    use super::*;
    fn tx(mode: Mode) -> Tx {
        Tx {
            mode,
            chain_id: BigUint::from(1u8),
            nonce: BigUint::from(9u8),
            priority: BigUint::from(2_000_000_000u64),
            max_fee: BigUint::from(20_000_000_000u64),
            gas: BigUint::from(21_000u32),
            to: "0x3535353535353535353535353535353535353535".into(),
            value: BigUint::from(1_000_000_000_000_000_000u64),
            data: vec![],
        }
    }
    #[test]
    fn legacy_transactions_match_the_published_eip155_example() {
        let signer = EvmSigner::from_private_key([0x46; 32]).unwrap();
        let raw = sign_transaction(&signer, &tx(Mode::Legacy)).unwrap();
        assert_eq!(
            hex::encode(&raw),
            "f86c098504a817c800825208943535353535353535353535353535353535353535880de0b6b3a76400008025a028ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276a067cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83"
        );
        assert_eq!(transaction_hash(&raw).len(), 66);
    }
    #[test]
    fn eip1559_transactions_are_type_two_and_signed_by_the_sender() {
        let signer = EvmSigner::from_private_key([0x46; 32]).unwrap();
        let raw = sign_transaction(&signer, &tx(Mode::Eip1559)).unwrap();
        assert_eq!(raw[0], 2);
        // The unsigned payload is everything but the last three items (v, r, s).
        let t = tx(Mode::Eip1559);
        let unsigned = [
            rlp_uint(&t.chain_id),
            rlp_uint(&t.nonce),
            rlp_uint(&t.priority),
            rlp_uint(&t.max_fee),
            rlp_uint(&t.gas),
            rlp_bytes(&address_bytes(&t.to).unwrap()),
            rlp_uint(&t.value),
            rlp_bytes(&[]),
            rlp_list(&[]),
        ];
        let mut payload = vec![2];
        payload.extend(rlp_list(&unsigned));
        let digest: [u8; 32] = Keccak256::digest(&payload).into();
        // r and s are the 64 bytes before the end of the raw transaction when both are 32 bytes.
        let (signature, parity) = signer.sign_recoverable(&digest).unwrap();
        assert!(hex::encode(&raw).contains(&hex::encode(&signature[..32])));
        assert_eq!(
            crate::test_support::recover(&digest, &signature, parity),
            signer.address()
        );
    }
}
