//! EIP-712 typed data for the two token authorizations the wallet signs: EIP-2612
//! `Permit` and EIP-3009 `TransferWithAuthorization`. Both are static structs, so a
//! struct hash is the type hash followed by the encoded members.
use crate::abi::{keccak, word_address, word_uint};
use num_bigint::BigUint;

/// The EIP-712 domain of a token contract.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Domain {
    pub name: String,
    pub version: String,
    pub chain_id: BigUint,
    /// Lowercase `0x` address of the token.
    pub contract: String,
}

impl Domain {
    pub fn separator(&self) -> anyhow::Result<[u8; 32]> {
        let mut data = keccak(
            b"EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)",
        )
        .to_vec();
        data.extend(keccak(self.name.as_bytes()));
        data.extend(keccak(self.version.as_bytes()));
        data.extend(word_uint(&self.chain_id)?);
        data.extend(word_address(&self.contract)?);
        Ok(keccak(&data))
    }
}

/// `keccak256(0x1901 || domainSeparator || structHash)`
pub(crate) fn digest(separator: &[u8; 32], struct_hash: &[u8; 32]) -> [u8; 32] {
    let mut data = vec![0x19, 0x01];
    data.extend_from_slice(separator);
    data.extend_from_slice(struct_hash);
    keccak(&data)
}

pub(crate) const PERMIT_TYPE: &str =
    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)";
const AUTHORIZATION_TYPE: &str = "TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)";

/// Type hash a token must report as `PERMIT_TYPEHASH()`, if it reports one.
pub(crate) fn permit_type_hash() -> [u8; 32] {
    keccak(PERMIT_TYPE.as_bytes())
}

#[derive(Clone, Copy)]
pub(crate) struct Permit<'a> {
    pub owner: &'a str,
    pub spender: &'a str,
    pub value: &'a BigUint,
    pub nonce: &'a BigUint,
    pub deadline: u64,
}

impl Permit<'_> {
    pub fn digest(&self, separator: &[u8; 32]) -> anyhow::Result<[u8; 32]> {
        let mut data = permit_type_hash().to_vec();
        data.extend(word_address(self.owner)?);
        data.extend(word_address(self.spender)?);
        data.extend(word_uint(self.value)?);
        data.extend(word_uint(self.nonce)?);
        data.extend(word_uint(&BigUint::from(self.deadline))?);
        Ok(digest(separator, &keccak(&data)))
    }
}

#[derive(Clone, Copy)]
pub(crate) struct Transfer<'a> {
    pub from: &'a str,
    pub to: &'a str,
    pub value: &'a BigUint,
    pub valid_after: u64,
    pub valid_before: u64,
    pub nonce: [u8; 32],
}

impl Transfer<'_> {
    pub fn digest(&self, separator: &[u8; 32]) -> anyhow::Result<[u8; 32]> {
        let mut data = keccak(AUTHORIZATION_TYPE.as_bytes()).to_vec();
        data.extend(word_address(self.from)?);
        data.extend(word_address(self.to)?);
        data.extend(word_uint(self.value)?);
        data.extend(word_uint(&BigUint::from(self.valid_after))?);
        data.extend(word_uint(&BigUint::from(self.valid_before))?);
        data.extend(self.nonce);
        Ok(digest(separator, &keccak(&data)))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::spending::{EvmSigner, WalletSigner};

    fn h(text: &str) -> [u8; 32] {
        hex::decode(text).unwrap().try_into().unwrap()
    }

    /// The worked example of the EIP-712 specification (`Ether Mail`), including its
    /// published signature by the key `keccak256("cow")`.
    #[test]
    fn matches_the_eip712_specification_example() {
        let domain = Domain {
            name: "Ether Mail".into(),
            version: "1".into(),
            chain_id: BigUint::from(1u8),
            contract: "0xcccccccccccccccccccccccccccccccccccccccc".into(),
        };
        let separator = domain.separator().unwrap();
        assert_eq!(
            separator,
            h("f2cee375fa42b42143804025fc449deafd50cc031ca257e0b194a650a912090f")
        );
        let person = |name: &str, wallet: &str| {
            let mut data = keccak(b"Person(string name,address wallet)").to_vec();
            data.extend(keccak(name.as_bytes()));
            data.extend(word_address(wallet).unwrap());
            keccak(&data)
        };
        let mut mail = keccak(
            b"Mail(Person from,Person to,string contents)Person(string name,address wallet)",
        )
        .to_vec();
        mail.extend(person("Cow", "0xcd2a3d9f938e13cd947ec05abc7fe734df8dd826"));
        mail.extend(person("Bob", "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"));
        mail.extend(keccak(b"Hello, Bob!"));
        let struct_hash = keccak(&mail);
        assert_eq!(
            struct_hash,
            h("c52c0ee5d84264471806290a3f2c4cecfc5490626bf912d01f240d7a274b371e")
        );
        let message = digest(&separator, &struct_hash);
        assert_eq!(
            message,
            h("be609aee343fb3c4b28e1df9e632fca64fcfaede20f02e86244efddf30957bd2")
        );
        let signer = EvmSigner::from_private_key(keccak(b"cow")).unwrap();
        assert_eq!(
            signer.address(),
            "0xcd2a3d9f938e13cd947ec05abc7fe734df8dd826"
        );
        let (signature, parity) = signer.sign_recoverable(&message).unwrap();
        assert_eq!(
            hex::encode(signature),
            "4355c47d63924e8a72e509b65029052eb6c299d53a04e167c5775fd466751c9d07299936d304c153f6443dfa05f40ff007d72911b6f72307f996231605b91562"
        );
        assert_eq!(27 + parity, 28);
    }

    #[test]
    fn usdc_domain_separator_matches_the_deployed_token() {
        // Circle USDC on Ethereum mainnet: DOMAIN_SEPARATOR() as read from the contract.
        let domain = Domain {
            name: "USD Coin".into(),
            version: "2".into(),
            chain_id: BigUint::from(1u8),
            contract: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48".into(),
        };
        assert_eq!(
            domain.separator().unwrap(),
            h("06c37168a7db5138defc7866392bb87a741f9b3d104deb5094588ce041cae335")
        );
    }

    #[test]
    fn type_hashes_match_the_standards() {
        assert_eq!(
            permit_type_hash(),
            h("6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9")
        );
        assert_eq!(
            keccak(AUTHORIZATION_TYPE.as_bytes()),
            h("7c7c6cdb67a18743f49ec6fa9b35f50d52ed05cbed4cc592e13b44501c1a2267")
        );
    }

    #[test]
    fn struct_digests_bind_every_member_and_the_domain() {
        let separator = [5u8; 32];
        let (a, b) = (
            "0x00000000000000000000000000000000000000a1",
            "0x00000000000000000000000000000000000000b2",
        );
        let value = BigUint::from(10u8);
        let nonce = BigUint::from(0u8);
        let base = Permit {
            owner: a,
            spender: b,
            value: &value,
            nonce: &nonce,
            deadline: 100,
        };
        let d = base.digest(&separator).unwrap();
        let other = BigUint::from(11u8);
        let variants = [
            Permit {
                value: &other,
                ..base
            },
            Permit {
                nonce: &other,
                ..base
            },
            Permit {
                deadline: 101,
                ..base
            },
            Permit { owner: b, ..base },
            Permit { spender: a, ..base },
        ];
        for v in variants {
            assert_ne!(v.digest(&separator).unwrap(), d);
        }
        assert_ne!(base.digest(&[6u8; 32]).unwrap(), d);

        let t = Transfer {
            from: a,
            to: b,
            value: &value,
            valid_after: 0,
            valid_before: 100,
            nonce: [1u8; 32],
        };
        let d = t.digest(&separator).unwrap();
        assert_ne!(
            Transfer {
                nonce: [2u8; 32],
                ..t
            }
            .digest(&separator)
            .unwrap(),
            d
        );
        assert_ne!(
            Transfer {
                valid_before: 99,
                ..t
            }
            .digest(&separator)
            .unwrap(),
            d
        );
        assert_ne!(Transfer { to: a, ..t }.digest(&separator).unwrap(), d);
    }

    #[test]
    fn a_signed_digest_recovers_to_the_owner() {
        let signer = EvmSigner::from_private_key([0x11; 32]).unwrap();
        let value = BigUint::from(1u8);
        let digest = Transfer {
            from: &signer.address(),
            to: "0x00000000000000000000000000000000000000b2",
            value: &value,
            valid_after: 0,
            valid_before: 9,
            nonce: [4u8; 32],
        }
        .digest(&[8u8; 32])
        .unwrap();
        let (bytes, parity) = signer.sign_recoverable(&digest).unwrap();
        let split = crate::abi::Split::new(&bytes, parity);
        assert!(split.v == 27 || split.v == 28);
        assert_eq!(
            crate::test_support::recover(&digest, &bytes, split.v - 27),
            signer.address()
        );
    }
}
