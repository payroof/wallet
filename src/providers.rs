//! Provider API keys and the endpoints they unlock. A key lives only in the encrypted
//! vault. Hosts see the opaque reference `provider:<id>` and never a resolved URL.
//!
//! The `Spec` rows behind `Provider::spec` are the one table of what each provider is: its id, URL template and the slug it
//! uses for each chain. Everything else (which providers serve a chain, which URL a key
//! opens) is derived from it. The built-in public keys are not code. They are declared in
//! `assets/providers.json` and embedded at build time (see `build.rs`) as `PRESETS`.
use crate::ids::ChainId;
use std::collections::BTreeMap;
use zeroize::Zeroizing;

include!(concat!(env!("OUT_DIR"), "/presets.rs"));

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Provider {
    Alchemy,
    Infura,
    Ankr,
    Etherscan,
}

/// What a provider's key opens.
enum Service {
    /// A JSON-RPC endpoint per chain. `{slug}` and `{key}` in the template are replaced.
    Rpc(&'static str),
    /// One address-history API for every chain it lists. The slug is the `chainid` value.
    Indexer(&'static str),
}

struct Spec {
    id: &'static str,
    service: Service,
    /// Each served chain with the provider's name for it.
    chains: &'static [(u64, &'static str)],
}

static ALCHEMY: Spec = Spec {
    id: "alchemy",
    service: Service::Rpc("https://{slug}.g.alchemy.com/v2/{key}"),
    chains: &[
        (1, "eth-mainnet"),
        (10, "opt-mainnet"),
        (56, "bnb-mainnet"),
        (137, "polygon-mainnet"),
        (8453, "base-mainnet"),
        (42161, "arb-mainnet"),
        (84532, "base-sepolia"),
        (11_155_111, "eth-sepolia"),
    ],
};
static INFURA: Spec = Spec {
    id: "infura",
    service: Service::Rpc("https://{slug}.infura.io/v3/{key}"),
    chains: &[
        (1, "mainnet"),
        (10, "optimism-mainnet"),
        (56, "bsc-mainnet"),
        (137, "polygon-mainnet"),
        (8453, "base-mainnet"),
        (42161, "arbitrum-mainnet"),
        (84532, "base-sepolia"),
        (11_155_111, "sepolia"),
    ],
};
static ANKR: Spec = Spec {
    id: "ankr",
    service: Service::Rpc("https://rpc.ankr.com/{slug}/{key}"),
    chains: &[
        (1, "eth"),
        (10, "optimism"),
        (56, "bsc"),
        (137, "polygon"),
        (8453, "base"),
        (42161, "arbitrum"),
        (84532, "base_sepolia"),
        (11_155_111, "eth_sepolia"),
    ],
};
// Etherscan V2 serves every chain here with one key.
static ETHERSCAN: Spec = Spec {
    id: "etherscan",
    service: Service::Indexer("https://api.etherscan.io/v2/api"),
    chains: &[
        (1, "1"),
        (10, "10"),
        (56, "56"),
        (137, "137"),
        (8453, "8453"),
        (42161, "42161"),
        (84532, "84532"),
        (11_155_111, "11155111"),
    ],
};
const PROVIDERS: [Provider; 4] = [
    Provider::Alchemy,
    Provider::Infura,
    Provider::Ankr,
    Provider::Etherscan,
];
/// The prefix of an endpoint that names a provider instead of a URL.
const PREFIX: &str = "provider:";
/// The longest key a provider is asked to accept.
const MAX_KEY_LENGTH: usize = 128;
/// Ethereum mainnet, where every provider's key is checked.
const MAINNET: u64 = 1;

impl Provider {
    /// The provider's row in the table.
    fn spec(self) -> &'static Spec {
        match self {
            Self::Alchemy => &ALCHEMY,
            Self::Infura => &INFURA,
            Self::Ankr => &ANKR,
            Self::Etherscan => &ETHERSCAN,
        }
    }
    pub fn from_id(id: &str) -> Option<Self> {
        PROVIDERS.into_iter().find(|provider| provider.id() == id)
    }
    pub fn id(self) -> &'static str {
        self.spec().id
    }
    /// `provider:<id>` as stored in settings and passed to the core.
    pub fn reference(self) -> String {
        format!("{PREFIX}{}", self.id())
    }
    pub fn from_reference(endpoint: &str) -> Option<Self> {
        endpoint.strip_prefix(PREFIX).and_then(Self::from_id)
    }
    fn slug(self, chain: u64) -> Option<&'static str> {
        self.spec()
            .chains
            .iter()
            .find(|(id, _)| *id == chain)
            .map(|(_, slug)| *slug)
    }
    /// Whether a key of this provider adds a JSON-RPC endpoint on `chain`.
    fn serves_rpc(self, chain: u64) -> bool {
        matches!(self.spec().service, Service::Rpc(_)) && self.slug(chain).is_some()
    }
    /// The JSON-RPC URL for a chain, with the key embedded. Sensitive.
    pub fn rpc(self, chain: u64, key: &str) -> Option<Zeroizing<String>> {
        let Service::Rpc(template) = self.spec().service else {
            return None;
        };
        let slug = self.slug(chain)?;
        Some(Zeroizing::new(
            template.replace("{slug}", slug).replace("{key}", key),
        ))
    }
    /// The key used on `chain`: the user's own, otherwise a built-in one serving it.
    pub fn key(self, keys: &Keys, chain: u64) -> Option<&str> {
        keys.get(self.id())
            .map(String::as_str)
            .or_else(|| self.preset(chain))
    }
    fn preset(self, chain: u64) -> Option<&'static str> {
        PRESETS
            .iter()
            .find(|(provider, chains, _)| *provider == self.id() && chains.contains(&chain))
            .map(|(_, _, key)| *key)
    }
    /// The address-history API base, when this provider offers one and serves the chain.
    pub fn indexer(self, chain: u64) -> Option<&'static str> {
        match self.spec().service {
            Service::Indexer(base) if self.slug(chain).is_some() => Some(base),
            _ => None,
        }
    }
}

/// Providers whose key adds an RPC endpoint to this chain.
pub fn rpc_providers(chain: u64) -> Vec<&'static str> {
    PROVIDERS
        .into_iter()
        .filter(|p| p.serves_rpc(chain))
        .map(Provider::id)
        .collect()
}

/// Providers with a built-in key for this chain.
pub fn preset_providers(chain: u64) -> Vec<&'static str> {
    PROVIDERS
        .into_iter()
        .filter(|p| p.preset(chain).is_some())
        .map(Provider::id)
        .collect()
}

pub fn valid_key(key: &str) -> bool {
    (1..=MAX_KEY_LENGTH).contains(&key.len())
        && key
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

/// The EIP-155 number of a chain ID string.
pub fn chain_number(chain: &str) -> anyhow::Result<u64> {
    Ok(chain.parse::<ChainId>()?.number())
}

/// Asks the provider itself whether it accepts `key`: Ethereum mainnet's chain ID
/// through an RPC provider's URL, a block number from Etherscan V2. Errors carry no
/// key and no URL.
pub async fn verify(provider: Provider, key: &str) -> anyhow::Result<()> {
    anyhow::ensure!(valid_key(key), "invalid key");
    let http = crate::api::client()?;
    if provider == Provider::Etherscan {
        let base = provider
            .indexer(MAINNET)
            .ok_or_else(|| anyhow::anyhow!("provider does not serve Ethereum"))?;
        check_etherscan(&http, base, key).await
    } else {
        let url = provider
            .rpc(MAINNET, key)
            .ok_or_else(|| anyhow::anyhow!("provider does not serve Ethereum"))?;
        check_rpc(&http, &url).await
    }
}

async fn check_rpc(http: &reqwest::Client, url: &str) -> anyhow::Result<()> {
    let id = crate::balance::rpc(http, url, "eth_chainId", serde_json::json!([])).await?;
    anyhow::ensure!(
        crate::balance::parse_quantity(&id)? == MAINNET.into(),
        "not Ethereum mainnet"
    );
    Ok(())
}

async fn check_etherscan(http: &reqwest::Client, base: &str, key: &str) -> anyhow::Result<()> {
    let chain = MAINNET.to_string();
    let body = crate::api::fetch_json(http.get(base).query(&[
        ("chainid", chain.as_str()),
        ("module", "proxy"),
        ("action", "eth_blockNumber"),
        ("apikey", key),
    ]))
    .await?;
    // A rejected key answers with status "0" and a text result.
    anyhow::ensure!(body["status"] != "0", "key rejected");
    crate::balance::parse_quantity(&body["result"])?;
    Ok(())
}

/// Keys by provider id, as kept in the vault.
pub type Keys = BTreeMap<String, String>;

/// An endpoint ready for a request: plain URLs pass through, provider references
/// become that provider's URL for the chain. The result may contain a key and must
/// never be returned to a host or included in an error.
pub fn resolve(keys: &Keys, endpoint: &str, chain: &str) -> anyhow::Result<Zeroizing<String>> {
    let Some(provider) = Provider::from_reference(endpoint) else {
        anyhow::ensure!(!endpoint.starts_with(PREFIX), "unknown provider");
        return Ok(Zeroizing::new(endpoint.to_string()));
    };
    let number = chain_number(chain)?;
    let key = provider
        .key(keys, number)
        .ok_or_else(|| anyhow::anyhow!("no key for this provider"))?;
    provider
        .rpc(number, key)
        .ok_or_else(|| anyhow::anyhow!("provider does not serve this chain"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{Read, Write};

    /// Serves one canned JSON body and returns the request line it received.
    fn serve(body: &'static str) -> (String, std::thread::JoinHandle<String>) {
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let url = format!("http://{}", listener.local_addr().unwrap());
        let handle = std::thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut buffer = [0u8; 4096];
            let n = stream.read(&mut buffer).unwrap();
            let request = String::from_utf8_lossy(&buffer[..n]).to_string();
            write!(
                stream,
                "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                body.len()
            )
            .unwrap();
            request
        });
        (url, handle)
    }

    fn check<F: std::future::Future<Output = anyhow::Result<()>>>(f: F) -> anyhow::Result<()> {
        tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap()
            .block_on(f)
    }

    #[test]
    fn rpc_keys_are_accepted_only_for_ethereum_mainnet() {
        let http = crate::api::client().unwrap();
        let (url, request) = serve(r#"{"jsonrpc":"2.0","id":1,"result":"0x1"}"#);
        check(check_rpc(&http, &url)).unwrap();
        assert!(request.join().unwrap().contains("eth_chainId"));
        for body in [
            r#"{"jsonrpc":"2.0","id":1,"result":"0x89"}"#,
            r#"{"jsonrpc":"2.0","id":1,"error":{"code":-32000,"message":"bad key"}}"#,
            r#"{"jsonrpc":"2.0","id":1,"result":"mainnet"}"#,
        ] {
            let (url, request) = serve(body);
            assert!(check(check_rpc(&http, &url)).is_err());
            request.join().unwrap();
        }
    }

    #[test]
    fn etherscan_keys_are_checked_by_a_block_number() {
        let http = crate::api::client().unwrap();
        let (url, request) = serve(r#"{"jsonrpc":"2.0","id":1,"result":"0x1312d00"}"#);
        check(check_etherscan(&http, &url, KEY)).unwrap();
        let line = request.join().unwrap();
        assert!(line.contains("chainid=1") && line.contains("action=eth_blockNumber"));
        for body in [
            r#"{"status":"0","message":"NOTOK","result":"Invalid API Key"}"#,
            r#"{"status":"1","message":"OK","result":"text"}"#,
            r"{}",
        ] {
            let (url, request) = serve(body);
            let error = check(check_etherscan(&http, &url, KEY)).unwrap_err();
            assert!(!format!("{error} {error:?}").contains(KEY));
            request.join().unwrap();
        }
    }

    #[test]
    fn verification_failures_never_expose_the_key() {
        let http = crate::api::client().unwrap();
        // Nothing listens on the discard port, so the request fails in transport.
        let url = format!("http://127.0.0.1:9/v2/{KEY}");
        let error = check(check_rpc(&http, &url)).unwrap_err();
        assert!(!format!("{error} {error:?}").contains(KEY));
        let error = check(check_etherscan(&http, "http://127.0.0.1:9/api", KEY)).unwrap_err();
        assert!(!format!("{error} {error:?}").contains(KEY));
        assert!(check(verify(Provider::Alchemy, "bad key")).is_err());
    }

    const KEY: &str = "k3y-SECRET_0123";

    fn keys() -> Keys {
        Keys::from([
            ("alchemy".into(), KEY.into()),
            ("etherscan".into(), KEY.into()),
        ])
    }

    #[test]
    fn references_resolve_with_the_vault_key() {
        let url = resolve(&keys(), "provider:alchemy", "eip155:8453").unwrap();
        assert_eq!(*url, format!("https://base-mainnet.g.alchemy.com/v2/{KEY}"));
        let all = Keys::from([("infura".into(), KEY.into()), ("ankr".into(), KEY.into())]);
        assert_eq!(
            *resolve(&all, "provider:infura", "eip155:42161").unwrap(),
            format!("https://arbitrum-mainnet.infura.io/v3/{KEY}")
        );
        assert_eq!(
            *resolve(&all, "provider:ankr", "eip155:11155111").unwrap(),
            format!("https://rpc.ankr.com/eth_sepolia/{KEY}")
        );
        assert_eq!(
            *resolve(&all, "https://rpc.example", "eip155:1").unwrap(),
            "https://rpc.example"
        );
    }

    #[test]
    fn resolution_failures_never_expose_the_key() {
        let cases = [
            // No key of the user's, and no built-in one on Optimism.
            ("provider:infura", "eip155:10"),
            ("provider:alchemy", "eip155:31337"),
            ("provider:alchemy", "eip155:01"),
            ("provider:etherscan", "eip155:1"),
            ("provider:unknown", "eip155:1"),
            ("provider:", "eip155:1"),
        ];
        for (endpoint, chain) in cases {
            let error = resolve(&keys(), endpoint, chain).unwrap_err();
            assert!(!format!("{error} {error:?}").contains(KEY), "{endpoint}");
        }
    }

    #[test]
    fn built_in_keys_serve_only_their_chains_and_yield_to_the_users() {
        let none = Keys::new();
        // Polygon has its own built-in Alchemy key, Ethereum another. Base has none.
        let polygon = resolve(&none, "provider:alchemy", "eip155:137").unwrap();
        let ethereum = resolve(&none, "provider:alchemy", "eip155:1").unwrap();
        assert!(polygon.starts_with("https://polygon-mainnet.g.alchemy.com/v2/"));
        assert!(ethereum.starts_with("https://eth-mainnet.g.alchemy.com/v2/"));
        assert_ne!(polygon[polygon.len() - 8..], ethereum[ethereum.len() - 8..]);
        assert!(resolve(&none, "provider:alchemy", "eip155:8453").is_err());
        assert!(resolve(&none, "provider:infura", "eip155:10").is_err());
        assert!(resolve(&none, "provider:etherscan", "eip155:1").is_err());
        assert_eq!(
            *resolve(&keys(), "provider:alchemy", "eip155:137").unwrap(),
            format!("https://polygon-mainnet.g.alchemy.com/v2/{KEY}")
        );
        assert_eq!(preset_providers(137), ["alchemy", "infura", "ankr"]);
        assert_eq!(preset_providers(56), ["ankr"]);
        assert!(preset_providers(10).is_empty() && preset_providers(31337).is_empty());
        for (id, chains, key) in PRESETS {
            let provider = Provider::from_id(id).expect("a preset names a known provider");
            assert!(valid_key(key));
            for chain in *chains {
                assert!(provider.slug(*chain).is_some(), "{id} serves {chain}");
            }
        }
    }

    #[test]
    fn the_table_is_complete_and_consistent() {
        let mut ids = std::collections::BTreeSet::new();
        for provider in PROVIDERS {
            assert_eq!(Provider::from_id(provider.id()), Some(provider));
            assert!(ids.insert(provider.id()), "ids are unique");
            let spec = provider.spec();
            assert_ne!(spec.chains, []);
            for (chain, slug) in spec.chains {
                assert_ne!(*slug, "");
                assert_eq!(
                    provider.rpc(*chain, "K").is_some(),
                    matches!(spec.service, Service::Rpc(_))
                );
                assert_eq!(
                    provider.indexer(*chain).is_some(),
                    matches!(spec.service, Service::Indexer(_))
                );
            }
            if let Service::Rpc(template) = spec.service {
                assert!(template.contains("{slug}") && template.contains("{key}"));
                assert!(template.starts_with("https://"));
            }
        }
        assert_eq!(Provider::from_id("unknown"), None);
    }

    #[test]
    fn keys_are_short_url_safe_tokens() {
        for good in ["a", "Ab_9-z", &"x".repeat(128)] {
            assert!(valid_key(good));
        }
        for bad in [
            "",
            &"x".repeat(129),
            "a b",
            "a/b",
            "a?b",
            "a&b=c",
            "é",
            "a\n",
        ] {
            assert!(!valid_key(bad));
        }
    }

    #[test]
    fn tables_cover_the_default_networks() {
        for chain in [1, 10, 56, 137, 8453, 42161] {
            assert_eq!(rpc_providers(chain), ["alchemy", "infura", "ankr"]);
            assert!(Provider::Etherscan.indexer(chain).is_some());
        }
        assert_eq!(rpc_providers(31337), [] as [&str; 0]);
        assert!(Provider::Etherscan.indexer(31337).is_none());
        assert!(Provider::Alchemy.indexer(1).is_none());
        for p in [Provider::Alchemy, Provider::Etherscan] {
            assert_eq!(Provider::from_reference(&p.reference()), Some(p));
        }
    }
}
