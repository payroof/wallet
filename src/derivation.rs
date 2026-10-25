use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
use hmac::{Hmac, KeyInit, Mac};
use k256::{
    FieldBytes, ProjectivePoint, PublicKey, Scalar,
    elliptic_curve::{ff::PrimeField, group::Group, sec1::ToSec1Point},
};
use sha2::Sha512;
use sha3::{Digest, Keccak256};

use crate::watch_root::WatchKey;

#[derive(Debug, thiserror::Error)]
pub enum DeriveError {
    #[error("invalid watch key")]
    InvalidWatchKey,
    #[error("hardened child index")]
    Hardened,
    #[error("invalid bip32 child")]
    InvalidChild,
}

/// First hardened BIP-32 index. Account slots and public children stay below it.
pub const HARDENED: u32 = 1 << 31;

pub fn decode_watch_key(w: &WatchKey) -> Result<([u8; 33], [u8; 32]), DeriveError> {
    let pk = URL_SAFE_NO_PAD
        .decode(&w.public_key)
        .map_err(|_| DeriveError::InvalidWatchKey)?;
    let cc = URL_SAFE_NO_PAD
        .decode(&w.chain_code)
        .map_err(|_| DeriveError::InvalidWatchKey)?;
    if pk.len() != 33 || cc.len() != 32 {
        return Err(DeriveError::InvalidWatchKey);
    }
    PublicKey::from_sec1_bytes(&pk).map_err(|_| DeriveError::InvalidWatchKey)?;
    Ok((
        pk.try_into().map_err(|_| DeriveError::InvalidWatchKey)?,
        cc.try_into().map_err(|_| DeriveError::InvalidWatchKey)?,
    ))
}

pub fn derive_public_child(watch: &WatchKey, index: u32) -> Result<PublicKey, DeriveError> {
    if index >= HARDENED {
        return Err(DeriveError::Hardened);
    }
    let (pk_bytes, chain_code) = decode_watch_key(watch)?;
    let parent = PublicKey::from_sec1_bytes(&pk_bytes).map_err(|_| DeriveError::InvalidWatchKey)?;
    let mut mac =
        Hmac::<Sha512>::new_from_slice(&chain_code).map_err(|_| DeriveError::InvalidWatchKey)?;
    mac.update(&pk_bytes);
    mac.update(&index.to_be_bytes());
    let i = mac.finalize().into_bytes();
    let il = *i.first_chunk::<32>().ok_or(DeriveError::InvalidChild)?;
    let scalar = Option::<Scalar>::from(Scalar::from_repr(FieldBytes::from(il)))
        .ok_or(DeriveError::InvalidChild)?;
    if bool::from(scalar.is_zero()) {
        return Err(DeriveError::InvalidChild);
    }
    let point = ProjectivePoint::GENERATOR * scalar + ProjectivePoint::from(*parent.as_affine());
    if bool::from(point.is_identity()) {
        return Err(DeriveError::InvalidChild);
    }
    PublicKey::from_affine(point.to_affine()).map_err(|_| DeriveError::InvalidChild)
}

pub fn evm_address(pubkey: &PublicKey) -> String {
    let p = pubkey.to_sec1_point(false);
    let hash = Keccak256::digest(&p.as_bytes()[1..]);
    format!("0x{}", hex::encode(&hash[12..]))
}

pub fn derive_evm_address(watch: &WatchKey, index: u32) -> Result<String, DeriveError> {
    Ok(evm_address(&derive_public_child(watch, index)?))
}

use bip32::{DerivationPath, XPrv};
use zeroize::Zeroizing;
/// The root of the account's own addresses, `m/44'/60'/{slot}'/0/{index}`, numbered as
/// every EVM wallet numbers them.
pub fn root_path(slot: u32) -> anyhow::Result<String> {
    anyhow::ensure!(slot < HARDENED, "slot exhausted");
    Ok(format!("m/44'/60'/{slot}'/0"))
}
/// The root of the payment addresses a Payroof project hands out,
/// `m/44'/60'/{slot}'/1/{index}`: a branch the account's own addresses never use, so
/// money the merchant receives is never taken for a customer's payment.
pub fn payment_root(slot: u32) -> anyhow::Result<String> {
    anyhow::ensure!(slot < HARDENED, "slot exhausted");
    Ok(format!("m/44'/60'/{slot}'/1"))
}
pub fn private_key(
    mnemonic: &str,
    passphrase: &str,
    path: &str,
) -> anyhow::Result<Zeroizing<[u8; 32]>> {
    let path: DerivationPath = path.parse()?;
    anyhow::ensure!(path.to_string().split('/').count() <= 12, "path too deep");
    let seed = crate::mnemonic::seed(mnemonic, passphrase)?;
    let key = XPrv::derive_from_path(&*seed, &path)?;
    Ok(Zeroizing::new(key.private_key().to_bytes().into()))
}
pub fn watch(
    mnemonic: &str,
    passphrase: &str,
    slot: u32,
) -> anyhow::Result<crate::watch_root::WatchRoot> {
    let path = payment_root(slot)?;
    let seed = crate::mnemonic::seed(mnemonic, passphrase)?;
    let key = XPrv::derive_from_path(&*seed, &path.parse()?)?.public_key();
    Ok(crate::watch_root::WatchRoot {
        family: crate::ids::EVM_NAMESPACE.into(),
        path,
        key: WatchKey {
            algorithm: crate::watch_root::ALGORITHM.into(),
            public_key: URL_SAFE_NO_PAD.encode(key.to_bytes()),
            chain_code: URL_SAFE_NO_PAD.encode(key.attrs().chain_code),
        },
    })
}
pub fn address(mnemonic: &str, passphrase: &str, path: &str) -> anyhow::Result<String> {
    let k = private_key(mnemonic, passphrase, path)?;
    let signing = k256::ecdsa::SigningKey::from_slice(&*k)?;
    let p: k256::PublicKey = signing.verifying_key().into();
    Ok(evm_address(&p))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejects_hardened() {
        let w = WatchKey {
            algorithm: "bip32-secp256k1".into(),
            public_key: "x".into(),
            chain_code: "y".into(),
        };
        assert!(matches!(
            derive_public_child(&w, 1 << 31),
            Err(DeriveError::Hardened)
        ));
    }
}
