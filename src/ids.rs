//! Typed CAIP-style identifiers. Hosts and settings keep chains and assets as strings
//! (`eip155:1`, `eip155:1/erc20:0x…`, `eip155:1/slip44:60`). The core parses each string
//! once, here, and works with the validated value from then on. `Display` writes back
//! the canonical string, so a parsed identifier round-trips exactly.
use std::fmt;
use std::str::FromStr;

/// The CAIP-2 namespace of every chain this wallet supports.
pub const EVM_NAMESPACE: &str = "eip155";
/// The separator between a chain and its asset reference in a CAIP-19 asset ID.
const ASSET_SEPARATOR: char = '/';
/// Asset namespace of a token contract.
const ERC20: &str = "erc20:";
/// Asset namespace of a network's own coin, numbered by SLIP-44.
const SLIP44: &str = "slip44:";
/// SLIP-44 coin type of Ether, which every EVM chain's quote and fee logic starts from.
pub const ETHER_COIN: u32 = 60;

/// An EVM chain, `eip155:<number>` with a canonical decimal number above zero.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct ChainId(u64);

impl ChainId {
    pub const fn new(number: u64) -> Option<Self> {
        if number == 0 {
            None
        } else {
            Some(Self(number))
        }
    }
    pub const fn number(self) -> u64 {
        self.0
    }
    /// The network's own coin on this chain, as the planner and balance reads address it.
    pub const fn native(self) -> AssetId {
        AssetId {
            chain: self,
            kind: AssetKind::Native(ETHER_COIN),
        }
    }
}

/// Whether `text` is a canonical decimal: digits only, no sign, no leading zero.
fn canonical_decimal(text: &str) -> bool {
    !text.is_empty()
        && text.bytes().all(|b| b.is_ascii_digit())
        && (text == "0" || !text.starts_with('0'))
}

impl FromStr for ChainId {
    type Err = anyhow::Error;
    fn from_str(text: &str) -> anyhow::Result<Self> {
        let number = text
            .strip_prefix(EVM_NAMESPACE)
            .and_then(|rest| rest.strip_prefix(':'))
            .filter(|number| canonical_decimal(number))
            .ok_or_else(|| anyhow::anyhow!("unsupported chain"))?;
        Self::new(number.parse()?).ok_or_else(|| anyhow::anyhow!("unsupported chain"))
    }
}

impl fmt::Display for ChainId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{EVM_NAMESPACE}:{}", self.0)
    }
}

/// What an asset is on its chain.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum AssetKind {
    /// The network's own coin, by SLIP-44 coin type.
    Native(u32),
    /// A token contract, as a lowercase `0x` address.
    Erc20(String),
}

/// An asset on a chain, `<chain>/slip44:<coin>` or `<chain>/erc20:<contract>`.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct AssetId {
    pub chain: ChainId,
    pub kind: AssetKind,
}

impl AssetId {
    pub fn erc20(chain: ChainId, contract: &str) -> anyhow::Result<Self> {
        crate::assets::address(contract)?;
        Ok(Self {
            chain,
            kind: AssetKind::Erc20(contract.to_ascii_lowercase()),
        })
    }
    /// The token contract, or `None` for the network's coin.
    pub fn contract(&self) -> Option<&str> {
        match &self.kind {
            AssetKind::Erc20(contract) => Some(contract),
            AssetKind::Native(_) => None,
        }
    }
}

impl FromStr for AssetId {
    type Err = anyhow::Error;
    fn from_str(text: &str) -> anyhow::Result<Self> {
        let (chain, reference) = text
            .split_once(ASSET_SEPARATOR)
            .ok_or_else(|| anyhow::anyhow!("unsupported asset"))?;
        let chain: ChainId = chain.parse()?;
        if let Some(coin) = reference.strip_prefix(SLIP44) {
            let coin = Some(coin)
                .filter(|coin| canonical_decimal(coin))
                .and_then(|coin| coin.parse().ok())
                .ok_or_else(|| anyhow::anyhow!("unsupported asset"))?;
            return Ok(Self {
                chain,
                kind: AssetKind::Native(coin),
            });
        }
        let contract = reference
            .strip_prefix(ERC20)
            .ok_or_else(|| anyhow::anyhow!("unsupported asset"))?;
        Self::erc20(chain, contract)
    }
}

impl fmt::Display for AssetId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match &self.kind {
            AssetKind::Native(coin) => write!(f, "{}{ASSET_SEPARATOR}{SLIP44}{coin}", self.chain),
            AssetKind::Erc20(contract) => {
                write!(f, "{}{ASSET_SEPARATOR}{ERC20}{contract}", self.chain)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const TOKEN: &str = "0x00000000000000000000000000000000000000c3";

    #[test]
    fn chains_are_canonical_eip155_numbers() {
        assert_eq!("eip155:8453".parse::<ChainId>().unwrap().number(), 8453);
        for bad in [
            "",
            "eip155",
            "eip155:",
            "eip155:0",
            "eip155:01",
            "eip155:+1",
            "eip155:1 ",
            "eip155:-1",
            "eip155:99999999999999999999",
            "solana:1",
            "EIP155:1",
            "1",
        ] {
            assert!(bad.parse::<ChainId>().is_err(), "{bad}");
        }
        assert_eq!(ChainId::new(137).unwrap().to_string(), "eip155:137");
        assert!(ChainId::new(0).is_none());
    }

    #[test]
    fn assets_round_trip_and_normalize_contracts() {
        let native: AssetId = "eip155:1/slip44:60".parse().unwrap();
        assert_eq!(native.kind, AssetKind::Native(60));
        assert_eq!(native.contract(), None);
        assert_eq!(native.to_string(), "eip155:1/slip44:60");
        assert_eq!(ChainId::new(1).unwrap().native(), native);
        let upper = format!("eip155:1/erc20:0x{}", "AB".repeat(20));
        let token: AssetId = upper.parse().unwrap();
        assert_eq!(token.contract(), Some(&*format!("0x{}", "ab".repeat(20))));
        assert_eq!(
            token.to_string(),
            format!("eip155:1/erc20:0x{}", "ab".repeat(20))
        );
        assert_eq!(token.chain.number(), 1);
        let canonical = format!("eip155:10/erc20:{TOKEN}");
        assert_eq!(canonical.parse::<AssetId>().unwrap().to_string(), canonical);
    }

    #[test]
    fn malformed_assets_are_rejected() {
        for bad in [
            String::new(),
            "eip155:1".into(),
            "eip155:1/".into(),
            "eip155:1/slip44:".into(),
            "eip155:1/slip44:060".into(),
            "eip155:1/slip44:99999999999".into(),
            "eip155:1/slip44:-1".into(),
            "eip155:1/erc20:".into(),
            "eip155:1/erc20:0x12".into(),
            format!("eip155:1/erc20:{}zz", &TOKEN[..40]),
            format!("eip155:1/erc721:{TOKEN}"),
            format!("eip155:0/erc20:{TOKEN}"),
            format!("eip155:1/erc20:{TOKEN}/extra"),
        ] {
            assert!(bad.parse::<AssetId>().is_err(), "{bad}");
        }
    }
}
