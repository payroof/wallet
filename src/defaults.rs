//! The configuration a new wallet starts with, declared in `assets/defaults.json`.
//! Each network and token states its own `color` (`#RRGGBB`) and `logo` (an SVG file under
//! `assets/icons`, named by a relative path). The build embeds exactly the files named
//! there (see `build.rs`) and `load` hands hosts the SVG text, so settings seeded from it
//! are self-contained and hosts never look anything up by ID.
use serde::{Deserialize, Serialize};

include!(concat!(env!("OUT_DIR"), "/logos.rs"));

#[derive(Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Endpoint {
    pub name: String,
    pub url: String,
}
#[derive(Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Price {
    pub url: String,
    pub field: String,
}
#[derive(Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Network {
    pub id: String,
    pub name: String,
    pub transaction_mode: crate::spending::Mode,
    #[serde(default)]
    pub endpoints: Vec<Endpoint>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub endpoint: Option<String>,
    pub enabled: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub explorer: Option<String>,
    /// `#RRGGBB`.
    pub color: String,
    /// The path of the SVG in the file, the SVG text once loaded.
    pub logo: String,
}
#[derive(Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Asset {
    pub id: String,
    pub chain: String,
    pub kind: String,
    pub symbol: String,
    pub decimals: u8,
    pub name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub price: Option<Price>,
    pub color: String,
    pub logo: String,
}
/// Entries added only in local development builds: the Anvil chain, its test coin and
/// the tokens the local stack deploys on a fresh chain (`roofer`: TEST, USDC and DAI from
/// Anvil's first account, at fixed addresses). Endpoints come from the host that runs the
/// stack, so the file leaves those out. The test coin is priced like Ether. A token
/// keeps the price source it declares, if any.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Development {
    networks: Vec<Network>,
    assets: Vec<Asset>,
}
/// The file as written.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Source {
    networks: Vec<Network>,
    assets: Vec<Asset>,
    #[serde(rename = "apiOrigin")]
    api_origin: String,
    #[serde(rename = "storOrigin")]
    stor_origin: String,
    development: Development,
}
/// What hosts receive.
#[derive(Serialize)]
pub struct Defaults {
    pub networks: Vec<Network>,
    pub assets: Vec<Asset>,
    #[serde(rename = "apiOrigin")]
    pub api_origin: String,
    #[serde(rename = "storOrigin")]
    pub stor_origin: String,
}

const SOURCE: &str = include_str!("../assets/defaults.json");

/// Whether `text` is a strict `#RRGGBB`.
pub fn is_color(text: &str) -> bool {
    text.len() == 7 && text.starts_with('#') && text[1..].bytes().all(|b| b.is_ascii_hexdigit())
}

fn embed(color: &str, logo: &mut String, id: &str) -> anyhow::Result<()> {
    anyhow::ensure!(is_color(color), "{id} has an invalid color");
    *logo = embedded_logo(logo)
        .ok_or_else(|| anyhow::anyhow!("{id} names a logo that is not embedded"))?
        .to_string();
    Ok(())
}

/// The shipped defaults with every logo replaced by its SVG text. In local development
/// (`host` is the local stack's host) the Anvil chain is added, off, with its test coin
/// priced like Ether and the local stack's test tokens. The file ships inside the binary and the tests load it both ways,
/// so an error here means a broken build and never a user's data.
pub fn load(host: Option<&str>) -> anyhow::Result<Defaults> {
    let source: Source = serde_json::from_str(SOURCE)?;
    let mut defaults = Defaults {
        networks: source.networks,
        assets: source.assets,
        api_origin: source.api_origin,
        stor_origin: source.stor_origin,
    };
    if let Some(host) = host {
        let development = source.development;
        let rpc = format!("http://{host}:8545");
        let ether = defaults
            .assets
            .iter()
            .find(|asset| asset.id == "eip155:1/slip44:60")
            .and_then(|asset| asset.price.clone())
            .ok_or_else(|| anyhow::anyhow!("the defaults price no Ether"))?;
        for mut network in development.networks {
            network.endpoints = vec![Endpoint {
                name: "Local Anvil".into(),
                url: rpc.clone(),
            }];
            network.endpoint = Some(rpc.clone());
            defaults.networks.push(network);
        }
        for mut asset in development.assets {
            if asset.kind == "native" {
                asset.price = Some(ether.clone());
            }
            defaults.assets.push(asset);
        }
        defaults.api_origin = format!("http://{host}:8080");
        defaults.stor_origin = format!("http://{host}:8081");
    }
    for network in &mut defaults.networks {
        embed(&network.color, &mut network.logo, &network.id)?;
    }
    for asset in &mut defaults.assets {
        embed(&asset.color, &mut asset.logo, &asset.id)?;
    }
    Ok(defaults)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::spending::Mode;
    use std::collections::BTreeSet;

    fn declared() -> serde_json::Value {
        serde_json::from_str(SOURCE).unwrap()
    }

    /// Every `logo` the file names, with the entry's ID.
    fn references(file: &serde_json::Value) -> Vec<(String, String)> {
        let mut found = Vec::new();
        for list in [
            &file["networks"],
            &file["assets"],
            &file["development"]["networks"],
            &file["development"]["assets"],
        ] {
            for entry in list.as_array().unwrap() {
                found.push((
                    entry["id"].as_str().unwrap().to_string(),
                    entry["logo"].as_str().unwrap().to_string(),
                ));
            }
        }
        found
    }

    #[test]
    fn every_network_declares_a_known_transaction_mode() {
        let file = declared();
        let listed = file["networks"].as_array().unwrap().len();
        let modes = load(None).unwrap().networks;
        assert_eq!(modes.len(), listed);
        assert!(modes.iter().any(|n| n.transaction_mode == Mode::Legacy));
        assert!(modes.iter().any(|n| n.transaction_mode == Mode::Eip1559));
    }

    #[test]
    fn colors_are_strict_hex() {
        assert!(is_color("#627EEA") && is_color("#abcdef"));
        for bad in [
            "", "#", "627EEA", "#12345", "#1234567", "#GGGGGG", "blue", "#12 456",
        ] {
            assert!(!is_color(bad), "{bad}");
        }
    }

    #[test]
    fn every_entry_has_a_valid_color_and_an_existing_valid_logo() {
        for host in [None, Some("127.0.0.1")] {
            let defaults = load(host).unwrap();
            let entries = defaults
                .networks
                .iter()
                .map(|n| (&n.id, &n.color, &n.logo))
                .chain(defaults.assets.iter().map(|a| (&a.id, &a.color, &a.logo)));
            for (id, color, logo) in entries {
                assert!(is_color(color), "{id} color {color}");
                assert!(
                    logo.starts_with("<svg") && logo.trim_end().ends_with("</svg>"),
                    "{id} logo is SVG text"
                );
                assert!(logo.len() <= 16 * 1024, "{id} logo is small");
            }
        }
    }

    #[test]
    fn development_entries_are_only_added_for_a_host() {
        let plain = load(None).unwrap();
        assert!(plain.networks.iter().all(|n| n.id != "eip155:31337"));
        let local = load(Some("127.0.0.1")).unwrap();
        let anvil = local
            .networks
            .iter()
            .find(|n| n.id == "eip155:31337")
            .unwrap();
        assert!(!anvil.enabled);
        assert_eq!(anvil.endpoint.as_deref(), Some("http://127.0.0.1:8545"));
        assert!(
            local
                .assets
                .iter()
                .any(|a| a.id == "eip155:31337/slip44:60" && a.price.is_some())
        );
        // The local stack's tokens, with their own prices (none for TEST).
        let token = |symbol: &str| {
            local
                .assets
                .iter()
                .find(|a| a.chain == "eip155:31337" && a.symbol == symbol)
                .unwrap_or_else(|| panic!("{symbol} on Anvil"))
        };
        assert_eq!(token("USDC").decimals, 6);
        assert_eq!(token("USDC").price.as_ref().unwrap().field, "usd-coin.usd");
        assert_eq!(token("DAI").decimals, 18);
        assert_eq!(token("DAI").price.as_ref().unwrap().field, "dai.usd");
        assert!(token("TEST").price.is_none());
        assert!(
            plain.assets.iter().all(|a| a.chain != "eip155:31337"),
            "test tokens only in local development"
        );
    }

    #[test]
    fn the_icons_folder_holds_exactly_the_named_files() {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("assets/icons");
        let named: BTreeSet<String> = references(&declared()).into_iter().map(|r| r.1).collect();
        let mut stack = vec![root.clone()];
        let mut present = BTreeSet::new();
        while let Some(dir) = stack.pop() {
            for entry in std::fs::read_dir(dir).unwrap() {
                let path = entry.unwrap().path();
                if path.is_dir() {
                    stack.push(path);
                } else {
                    let relative = path.strip_prefix(&root).unwrap();
                    present.insert(relative.to_str().unwrap().to_string());
                }
            }
        }
        assert_eq!(present, named, "every file is named and every name exists");
    }
}
