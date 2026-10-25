//! Narrow native boundary. No generic private-key export or network-signing command.
#![allow(
    clippy::needless_pass_by_value,
    reason = "UniFFI-exported functions must take owned arguments, so the signatures cannot borrow"
)]
use crate::{state::UnlockSession, vault::Vault};
use serde::{Deserialize, Serialize};
use std::sync::{Arc, Mutex};
use zeroize::{Zeroize, Zeroizing};
// Native local mode is deliberately unavailable in normal release builds. macOS also needs
// the runtime opt-in. An iPhone can't receive one, so there the `local-development` feature
// (only built into the separate ios-device-local app) is the opt-in.
fn local_development() -> bool {
    cfg!(feature = "local-development")
        && (cfg!(target_os = "ios")
            || std::env::var("PAYROOF_WALLET_LOCAL_DEVELOPMENT").as_deref() == Ok("1"))
}
/// Host of the local stack (roofer up): loopback on the Mac, or the Mac's LAN IPv4 baked in
/// at build time (`PAYROOF_LOCAL_HOST`) for a phone. Anything but a valid IPv4 falls back.
fn local_host() -> String {
    option_env!("PAYROOF_LOCAL_HOST")
        .and_then(|h| h.parse::<std::net::Ipv4Addr>().ok())
        .filter(|ip| ip.is_loopback() || ip.is_private())
        .map_or_else(|| "127.0.0.1".into(), |ip| ip.to_string())
}
#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum WalletError {
    #[error("operation rejected")]
    Rejected,
}
fn checked<T>(r: anyhow::Result<T>) -> Result<T, WalletError> {
    r.map_err(|_| WalletError::Rejected)
}
#[derive(Serialize, Deserialize)]
struct Secrets {
    words: String,
    passphrase: String,
    credentials: std::collections::BTreeMap<String, Credential>,
    /// Provider API keys by provider id. Only the host-visible ids ever leave Rust.
    providers: crate::providers::Keys,
}
#[derive(Serialize, Deserialize)]
struct Credential {
    token: String,
    origin_pin: [u8; 32],
}
impl Drop for Secrets {
    fn drop(&mut self) {
        self.words.zeroize();
        self.passphrase.zeroize();
        for v in self.credentials.values_mut() {
            v.token.zeroize();
        }
        for key in self.providers.values_mut() {
            key.zeroize();
        }
    }
}
struct KeyCopy(crate::providers::Keys);
impl Drop for KeyCopy {
    fn drop(&mut self) {
        for key in self.0.values_mut() {
            key.zeroize();
        }
    }
}
#[derive(uniffi::Object)]
pub struct Wallet {
    inner: Mutex<Inner>,
}
struct Inner {
    vault: Vault,
    session: UnlockSession,
    projects: crate::projects::Projects,
    plan: Option<crate::send::PlanState>,
}
/// An account's `(path, address)` pairs, as a send reads them.
type SendAccount = Vec<(String, String)>;
impl Wallet {
    /// What a network request needs: the endpoint resolved (provider keys inside) and
    /// the addresses of `paths`. The lock is released before the request is sent, so
    /// the wallet's other calls (an address, a review) never wait for a slow endpoint.
    fn request(
        &self,
        endpoint: &str,
        chain: &str,
        paths: &[String],
    ) -> anyhow::Result<(Zeroizing<String>, Vec<String>)> {
        let s = self.secrets()?;
        let endpoint = crate::providers::resolve(&s.providers, endpoint, chain)?;
        let addresses = paths
            .iter()
            .map(|p| crate::derivation::address(&s.words, &s.passphrase, p))
            .collect::<anyhow::Result<Vec<_>>>()?;
        Ok((endpoint, addresses))
    }
    /// A copy of the provider keys for one request made without the lock. Wiped on drop.
    fn keys(&self) -> anyhow::Result<KeyCopy> {
        Ok(KeyCopy(self.secrets()?.providers.clone()))
    }
    /// A copy of the unlocked secrets, wiped on drop, for work that waits on the
    /// network: the lock is held only while the vault is read.
    fn secrets(&self) -> anyhow::Result<Secrets> {
        let mut i = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("state unavailable"))?;
        read(&mut i)
    }
    /// Changes the secrets as stored now (not a copy read before a request, which
    /// another call may have changed since) and saves them, under the lock.
    fn update<T>(
        &self,
        change: impl FnOnce(&mut Secrets) -> anyhow::Result<T>,
    ) -> anyhow::Result<T> {
        let mut i = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("state unavailable"))?;
        let mut s = read(&mut i)?;
        let value = change(&mut s)?;
        save(&mut i, &s)?;
        Ok(value)
    }
    /// The API client of a connected project, built from a copy of its credential.
    /// None when this device holds no credential for it.
    fn api(&self, origin: &str, project: &str) -> anyhow::Result<Option<crate::api::Api>> {
        let s = self.secrets()?;
        let normalized = crate::api::origin(origin, local_development())?;
        s.credentials
            .get(&format!("{normalized}#{project}"))
            .map(|c| {
                crate::api::Api::new(origin, c.token.clone(), c.origin_pin, local_development())
            })
            .transpose()
    }
    /// A send's account, `(path, address)` pairs, with the endpoint it is read through.
    /// Only the account's own paths (kept here, never the host's) are used.
    fn send_account(
        &self,
        endpoint: &str,
        request: &crate::send::Request,
    ) -> anyhow::Result<(Zeroizing<String>, SendAccount)> {
        let paths: Vec<String> = {
            let i = self
                .inner
                .lock()
                .map_err(|_| anyhow::anyhow!("state unavailable"))?;
            i.projects
                .visible
                .iter()
                .find(|p| p.slot == request.slot)
                .ok_or_else(|| anyhow::anyhow!("unknown project"))?
                .paths
                .iter()
                .cloned()
                .collect()
        };
        let (endpoint, addresses) = self.request(endpoint, &request.chain, &paths)?;
        Ok((endpoint, paths.into_iter().zip(addresses).collect()))
    }
    fn connected(&self, origin: &str, project: &str) -> anyhow::Result<crate::api::Api> {
        self.api(origin, project)?
            .ok_or_else(|| anyhow::anyhow!("project not connected"))
    }
}
#[uniffi::export]
impl Wallet {
    #[uniffi::constructor]
    pub fn load(vault_json: String, public_json: String) -> Result<Arc<Self>, WalletError> {
        checked((|| {
            Ok(Arc::new(Self {
                inner: Mutex::new(Inner {
                    vault: serde_json::from_str(&vault_json)?,
                    session: UnlockSession::default(),
                    projects: if public_json.is_empty() {
                        crate::projects::Projects::default()
                    } else {
                        serde_json::from_str(&public_json)?
                    },
                    plan: None,
                }),
            }))
        })())
    }
    #[uniffi::constructor]
    pub fn create(words: String, pin: String) -> Result<Arc<Self>, WalletError> {
        let words = Zeroizing::new(words);
        let pin = Zeroizing::new(pin);
        checked((|| {
            let words = crate::mnemonic::normalize(&words)?;
            let secrets = Secrets {
                words: words.to_string(),
                passphrase: String::new(),
                credentials: std::collections::BTreeMap::default(),
                providers: std::collections::BTreeMap::default(),
            };
            let payload = Zeroizing::new(serde_json::to_vec(&secrets)?);
            let vault = Vault::create(crate::secret::id("wallet_")?, &pin, &payload)?;
            Ok(Arc::new(Self {
                inner: Mutex::new(Inner {
                    vault,
                    session: UnlockSession::default(),
                    projects: crate::projects::Projects::default(),
                    plan: None,
                }),
            }))
        })())
    }
    pub fn unlock(&self, pin: String) -> Result<(), WalletError> {
        let pin = Zeroizing::new(pin);
        checked((|| {
            let mut i = self
                .inner
                .lock()
                .map_err(|_| anyhow::anyhow!("state unavailable"))?;
            let Inner { vault, session, .. } = &mut *i;
            session.unlock(vault, &pin)
        })())
    }
    pub fn device_key(&self) -> Result<Vec<u8>, WalletError> {
        checked((|| {
            let i = self
                .inner
                .lock()
                .map_err(|_| anyhow::anyhow!("state unavailable"))?;
            Ok(i.session.key()?.to_vec())
        })())
    }
    pub fn unlock_device(&self, key: Vec<u8>) -> Result<(), WalletError> {
        let key = Zeroizing::new(key);
        checked((|| {
            let mut i = self
                .inner
                .lock()
                .map_err(|_| anyhow::anyhow!("state unavailable"))?;
            let bytes: [u8; 32] = key.as_slice().try_into()?;
            let Inner { vault, session, .. } = &mut *i;
            session.device_unlock(vault, bytes)
        })())
    }
    pub fn lock(&self) {
        if let Ok(mut i) = self.inner.lock() {
            i.session.lock();
            i.plan = None;
        }
    }
    pub fn vault_json(&self) -> Result<String, WalletError> {
        checked((|| {
            let i = self
                .inner
                .lock()
                .map_err(|_| anyhow::anyhow!("state unavailable"))?;
            Ok(serde_json::to_string(&i.vault)?)
        })())
    }
    pub fn is_unlocked(&self) -> bool {
        self.inner.lock().is_ok_and(|i| i.session.key().is_ok())
    }
    pub fn public_json(&self) -> Result<String, WalletError> {
        checked((|| {
            let i = self
                .inner
                .lock()
                .map_err(|_| anyhow::anyhow!("state unavailable"))?;
            Ok(serde_json::to_string(&i.projects)?)
        })())
    }
    pub fn query_balance(
        &self,
        endpoint: String,
        chain: String,
        asset: String,
        paths: Vec<String>,
    ) -> Result<String, WalletError> {
        checked((|| {
            let (endpoint, addresses) = self.request(&endpoint, &chain, &paths)?;
            crate::runtime()?.block_on(crate::balance::balance(
                &endpoint,
                &chain,
                &asset,
                &addresses,
                local_development(),
            ))
        })())
    }
    /// Balance of one asset for each path, in the same order. One chain check.
    pub fn query_address_balances(
        &self,
        endpoint: String,
        chain: String,
        asset: String,
        paths: Vec<String>,
    ) -> Result<Vec<String>, WalletError> {
        checked((|| {
            let (endpoint, addresses) = self.request(&endpoint, &chain, &paths)?;
            let values = crate::runtime()?.block_on(crate::balance::balances(
                &endpoint,
                &chain,
                &asset,
                &addresses,
                local_development(),
            ))?;
            Ok(values.into_iter().map(|v| v.to_string()).collect())
        })())
    }
    pub fn transaction_status(
        &self,
        endpoint: String,
        chain: String,
        transaction: String,
    ) -> Result<String, WalletError> {
        checked((|| {
            anyhow::ensure!(
                transaction.starts_with("0x")
                    && transaction.len() == 66
                    && transaction[2..].bytes().all(|b| b.is_ascii_hexdigit()),
                "invalid transaction"
            );
            let (endpoint, _) = self.request(&endpoint, &chain, &[])?;
            let status = crate::runtime()?.block_on(crate::spending::receipt(
                &endpoint,
                &transaction,
                &chain,
                local_development(),
            ))?;
            Ok(match status {
                None => "pending",
                Some(true) => "confirmed",
                Some(false) => "failed",
            }
            .into())
        })())
    }
    pub fn add_project(&self, label: String, slot: Option<u32>) -> Result<u32, WalletError> {
        checked((|| {
            let mut i = self
                .inner
                .lock()
                .map_err(|_| anyhow::anyhow!("state unavailable"))?;
            i.projects.add(label, slot)
        })())
    }
    pub fn address(&self, slot: u32, index: Option<u32>) -> Result<String, WalletError> {
        checked((|| {
            let mut i = self
                .inner
                .lock()
                .map_err(|_| anyhow::anyhow!("state unavailable"))?;
            let s = read(&mut i)?;
            let path = i.projects.add_address(slot, index)?;
            let address = crate::derivation::address(&s.words, &s.passphrase, &path)?;
            Ok(serde_json::json!({"path":path,"address":address}).to_string())
        })())
    }
    pub fn exact_path(&self, path: String) -> Result<String, WalletError> {
        checked((|| {
            let mut i = self
                .inner
                .lock()
                .map_err(|_| anyhow::anyhow!("state unavailable"))?;
            let s = read(&mut i)?;
            let canonical: bip32::DerivationPath = path.parse()?;
            let canonical = canonical.to_string();
            let address = crate::derivation::address(&s.words, &s.passphrase, &canonical)?;
            Ok(serde_json::json!({"path":canonical,"address":address}).to_string())
        })())
    }
    /// The recovery words, so the user can back them up again. Only while unlocked,
    /// and only with the PIN: device unlock or an open session alone never reveal them.
    pub fn recovery_words(&self, pin: String) -> Result<String, WalletError> {
        let pin = Zeroizing::new(pin);
        checked((|| {
            let mut i = self
                .inner
                .lock()
                .map_err(|_| anyhow::anyhow!("state unavailable"))?;
            let Inner { vault, session, .. } = &mut *i;
            session.key()?;
            let key = session.verify(vault, &pin)?;
            let secrets: Secrets = serde_json::from_slice(&vault.read(&key)?)?;
            Ok(secrets.words.clone())
        })())
    }
    pub fn change_pin(&self, old: String, new: String) -> Result<(), WalletError> {
        let old = Zeroizing::new(old);
        let new = Zeroizing::new(new);
        checked((|| {
            let mut i = self
                .inner
                .lock()
                .map_err(|_| anyhow::anyhow!("state unavailable"))?;
            i.vault.change_pin(&old, &new)
        })())
    }
    /// Connects an account to its project on the API: registers it as `project`, or,
    /// when the account already has a project there (made on another device, or
    /// connected before), recovers access to that one under its own name. Returns the
    /// connection with `recovered` saying which happened.
    pub fn connect(
        &self,
        origin: String,
        project: String,
        slot: u32,
    ) -> Result<String, WalletError> {
        checked((|| {
            let s = self.secrets()?;
            let runtime = crate::runtime()?;
            let development = local_development();
            let (result, recovered) = runtime.block_on(async {
                match crate::api::register(
                    &origin,
                    &project,
                    &s.words,
                    &s.passphrase,
                    slot,
                    development,
                )
                .await
                {
                    Err(error) if crate::api::is_conflict(&error) => {
                        crate::api::recover(&origin, &s.words, &s.passphrase, slot, development)
                            .await
                            .map(|result| (result, true))
                    }
                    other => other.map(|result| (result, false)),
                }
            })?;
            let project = if recovered {
                result["project"]
                    .as_str()
                    .ok_or_else(|| anyhow::anyhow!("missing project"))?
                    .to_string()
            } else {
                project
            };
            let token = result["token"]
                .as_str()
                .ok_or_else(|| anyhow::anyhow!("missing token"))?;
            let normalized = crate::api::origin(&origin, development)?;
            let pin = crate::api::Api::pin(&origin, development)?;
            let api = crate::api::Api::new(&origin, token.into(), pin, development)?;
            let root = crate::derivation::watch(&s.words, &s.passphrase, slot)?;
            runtime.block_on(api.verify_root(&project, &root))?;
            self.update(|s| {
                s.credentials.insert(
                    format!("{normalized}#{project}"),
                    Credential {
                        token: token.into(),
                        origin_pin: pin,
                    },
                );
                Ok(())
            })?;
            Ok(serde_json::json!({"origin":normalized,"project":project,"slot":slot,"root":root.path,"fingerprint":root.fingerprint()?,"origin_pin":hex::encode(pin),"recovered":recovered}).to_string())
        })())
    }
    pub fn pairing(
        &self,
        link: String,
        project: String,
        allow: bool,
    ) -> Result<String, WalletError> {
        checked((|| {
            let (origin, id) = crate::pairing::parse_with_development(&link, local_development())?;
            let runtime = crate::runtime()?;
            if !allow {
                return runtime
                    .block_on(async {
                        crate::api::bounded_json(
                            crate::api::client()?
                                .get(crate::api::Route::Pairing(&id).url(&origin))
                                .send()
                                .await?
                                .error_for_status()?,
                        )
                        .await
                    })
                    .map(|v| v.to_string());
            }
            let api = self.connected(&origin, &project)?;
            runtime.block_on(api.approve(&id, true))?;
            Ok("approved".into())
        })())
    }
    pub fn grants(&self, origin: String, project: String) -> Result<String, WalletError> {
        checked((|| {
            let api = self.connected(&origin, &project)?;
            Ok(crate::runtime()?
                .block_on(api.grants(&project))?
                .to_string())
        })())
    }
    /// Whether this device's stored credential still opens the project:
    /// "active", "revoked" (no credential, or the API answers 401/403) or
    /// "unavailable" (network or server problem. Nothing is concluded).
    pub fn connection_status(
        &self,
        origin: String,
        project: String,
    ) -> Result<String, WalletError> {
        checked((|| {
            let Some(api) = self.api(&origin, &project)? else {
                return Ok("revoked".to_string());
            };
            let status = crate::runtime()?
                .block_on(api.access_status(&project))
                .unwrap_or(0);
            Ok(match status {
                200..=299 => "active",
                401 | 403 => "revoked",
                _ => "unavailable",
            }
            .to_string())
        })())
    }
    /// Forgets this device's credential for a project. The project itself stays
    /// on the API and can be reconnected later through recovery.
    pub fn disconnect(&self, origin: String, project: String) -> Result<(), WalletError> {
        checked((|| {
            let normalized = crate::api::origin(&origin, local_development())?;
            self.update(|s| {
                if let Some(mut credential) =
                    s.credentials.remove(&format!("{normalized}#{project}"))
                {
                    credential.token.zeroize();
                }
                Ok(())
            })
        })())
    }
    /// Issues a new API token for the project and returns
    /// `{"id","name","permissions","created_at","token"}`. The token appears
    /// only in this result: show it once, never store or log it.
    pub fn create_grant(
        &self,
        origin: String,
        project: String,
        name: String,
        permissions: Vec<String>,
    ) -> Result<String, WalletError> {
        checked((|| {
            // `connected` copies the credential and releases the lock first.
            let api = self.connected(&origin, &project)?;
            Ok(crate::runtime()?
                .block_on(api.create_grant(&project, &name, &permissions))?
                .to_string())
        })())
    }
    /// Creates a store for the project on the Stor server `stor`: a key that can only create payment
    /// addresses (references, paths, webhooks) goes into the sheet's Payments tab with
    /// the project's URL. Returns `{"url"}`, or Stor's `{"error"}`. A store that isn't
    /// created takes its key back.
    pub fn create_store(
        &self,
        origin: String,
        project: String,
        stor: String,
        subdomain: String,
        source: String,
    ) -> Result<String, WalletError> {
        checked((|| {
            let api = self.connected(&origin, &project)?;
            let stor = crate::api::origin(&stor, local_development())?;
            let url = crate::api::Route::Project(&project)
                .url(&crate::api::origin(&origin, local_development())?);
            crate::runtime()?.block_on(async {
                if !crate::stor::valid_subdomain(&subdomain) {
                    return Ok(serde_json::json!({"error": "invalid_subdomain"}).to_string());
                }
                let (grant, key) = store_grant(&api, &project, &subdomain).await?;
                let result = crate::stor::create(&stor, &subdomain, &source, &url, &key).await;
                if !result.as_ref().is_ok_and(|v| v.get("url").is_some())
                    && let Some(id) = grant["id"].as_str()
                {
                    let _ = api.revoke_grant(&project, id).await;
                }
                Ok(result?.to_string())
            })
        })())
    }
    /// The Payments tab's URL and KEY for a store that already exists (made on Stor's
    /// page, or from another device): the same key New store makes, named after the
    /// store, which can only create payment addresses. Returns `{"url","key"}`. The key
    /// appears only in this result.
    pub fn create_store_key(
        &self,
        origin: String,
        project: String,
        subdomain: String,
    ) -> Result<String, WalletError> {
        checked((|| {
            anyhow::ensure!(
                crate::stor::valid_subdomain(&subdomain),
                "invalid store address"
            );
            let api = self.connected(&origin, &project)?;
            let url = crate::api::Route::Project(&project)
                .url(&crate::api::origin(&origin, local_development())?);
            let (_, key) = crate::runtime()?.block_on(store_grant(&api, &project, &subdomain))?;
            Ok(serde_json::json!({"url": url, "key": key.as_str()}).to_string())
        })())
    }
    pub fn revoke_grant(
        &self,
        origin: String,
        project: String,
        id: String,
    ) -> Result<(), WalletError> {
        checked((|| {
            let api = self.connected(&origin, &project)?;
            crate::runtime()?.block_on(api.revoke_grant(&project, &id))
        })())
    }
    pub fn sync(
        &self,
        origin: String,
        project: String,
        slot: u32,
        imported_json: String,
        scope: String,
    ) -> Result<String, WalletError> {
        checked((|| {
            let api = self.connected(&origin, &project)?;
            let s = self.secrets()?;
            let root = crate::derivation::watch(&s.words, &s.passphrase, slot)?;
            let mut imported: crate::path_source::Imported = if imported_json.is_empty() {
                crate::path_source::Imported::default()
            } else {
                serde_json::from_str(&imported_json)?
            };
            let runtime = crate::runtime()?;
            runtime.block_on(api.verify_root(&project, &root))?;
            let cursor = if scope == "all" {
                imported.all_cursor.as_deref()
            } else {
                imported.confirmed_cursor.as_deref()
            };
            let (page, cursor, _) = runtime.block_on(api.paths(&project, &scope, cursor))?;
            imported.apply(&root.path, &scope, &page, cursor, &s.words, &s.passphrase)?;
            self.inner
                .lock()
                .map_err(|_| anyhow::anyhow!("state unavailable"))?
                .projects
                .add_payment_paths(slot, imported.addresses.keys())?;
            Ok(serde_json::to_string(&imported)?)
        })())
    }
    /// Stores a provider key in the vault, or removes it when `key` is nil. The key is
    /// never readable again: hosts learn only which providers have one.
    pub fn set_provider_key(
        &self,
        provider: String,
        key: Option<String>,
    ) -> Result<(), WalletError> {
        let key = key.map(Zeroizing::new);
        checked((|| {
            let provider = crate::providers::Provider::from_id(&provider)
                .ok_or_else(|| anyhow::anyhow!("unknown provider"))?;
            let mut i = self
                .inner
                .lock()
                .map_err(|_| anyhow::anyhow!("state unavailable"))?;
            let mut s = read(&mut i)?;
            match &key {
                Some(key) => {
                    anyhow::ensure!(crate::providers::valid_key(key), "invalid key");
                    s.providers.insert(provider.id().into(), key.to_string());
                }
                None => {
                    if let Some(mut old) = s.providers.remove(provider.id()) {
                        old.zeroize();
                    }
                }
            }
            save(&mut i, &s)
        })())
    }
    /// Ids of the providers that have a key.
    pub fn provider_keys(&self) -> Result<Vec<String>, WalletError> {
        checked((|| {
            let mut i = self
                .inner
                .lock()
                .map_err(|_| anyhow::anyhow!("state unavailable"))?;
            Ok(read(&mut i)?.providers.keys().cloned().collect())
        })())
    }
    /// Connectivity and chain identity only: URL policy plus `eth_chainId`. No address
    /// or wallet secret is involved.
    pub fn check_endpoint(&self, endpoint: String, chain: String) -> Result<(), WalletError> {
        checked((|| {
            let (endpoint, _) = self.request(&endpoint, &chain, &[])?;
            crate::networks::validate_rpc(&endpoint, local_development())?;
            let http = crate::api::client()?;
            crate::runtime()?.block_on(crate::balance::check_chain(&http, &endpoint, &chain))
        })())
    }
    /// A token contract's own symbol, name and decimals, to prefill Add token. Read-only.
    /// the endpoint is checked to be the given chain first.
    pub fn read_token(
        &self,
        endpoint: String,
        chain: String,
        contract: String,
    ) -> Result<TokenDetails, WalletError> {
        checked((|| {
            let (endpoint, _) = self.request(&endpoint, &chain, &[])?;
            let details = crate::runtime()?.block_on(crate::balance::token_details(
                &endpoint,
                &chain,
                &contract.to_ascii_lowercase(),
                local_development(),
            ))?;
            Ok(TokenDetails {
                symbol: details.symbol,
                name: details.name,
                decimals: details.decimals,
            })
        })())
    }
    /// New transfers at the account's addresses, found without the Payroof API: the
    /// entries as JSON and the cursor to pass next time. Only the given assets count.
    pub fn history(
        &self,
        endpoint: String,
        chain: String,
        assets: Vec<String>,
        paths: Vec<String>,
        cursor: String,
    ) -> Result<String, WalletError> {
        checked((|| {
            let (rpc, addresses) = self.request(&endpoint, &chain, &paths)?;
            let keys = self.keys()?;
            let outcome =
                crate::runtime()?.block_on(crate::history::scan(crate::history::Request {
                    chain: &chain,
                    rpc: &rpc,
                    keys: &keys.0,
                    assets: &assets,
                    addresses: &addresses,
                    cursor: crate::history::Cursor::parse(&cursor)?,
                    development: local_development(),
                }))?;
            Ok(serde_json::json!({
                "entries": outcome.entries,
                "cursor": outcome.cursor.encode()?,
                "source": outcome.source,
            })
            .to_string())
        })())
    }
    /// Plans a send from the addresses of one account: which of them fund it and who
    /// pays the gas. Only the account's own paths (kept here, never the host's) are used.
    /// Returns `{"plan": …}` or `{"problem": …}`. Nothing is signed.
    pub fn plan_send(
        &self,
        endpoint: String,
        request_json: String,
        legacy: bool,
    ) -> Result<String, WalletError> {
        checked((|| {
            let request: crate::send::Request = serde_json::from_str(&request_json)?;
            let (endpoint, account) = self.send_account(&endpoint, &request)?;
            let created = crate::runtime()?.block_on(crate::send::create(
                &endpoint,
                &request,
                &account,
                crate::spending::Mode::from_legacy(legacy),
                local_development(),
            ))?;
            let mut i = self
                .inner
                .lock()
                .map_err(|_| anyhow::anyhow!("state unavailable"))?;
            i.session.key()?;
            match created {
                crate::send::Created::Plan(state) => {
                    let review = serde_json::json!({"plan": state.review()}).to_string();
                    i.plan = Some(*state);
                    Ok(review)
                }
                crate::send::Created::Problem(problem) => {
                    i.plan = None;
                    Ok(format!("{{\"problem\":{problem}}}"))
                }
            }
        })())
    }
    /// The most the account can send of the request's asset, as Review would plan it:
    /// for the network's coin, every address's balance less the fee of its own
    /// transfer. For a token, its whole balance. `to` may be empty (any recipient costs
    /// the same). `amount` is ignored. Returns `{"maximum": "<atomic>"}`. Nothing is kept.
    pub fn send_maximum(
        &self,
        endpoint: String,
        request_json: String,
        legacy: bool,
    ) -> Result<String, WalletError> {
        checked((|| {
            let mut request: crate::send::Request = serde_json::from_str(&request_json)?;
            let (endpoint, account) = self.send_account(&endpoint, &request)?;
            let Some((_, first)) = account.first() else {
                return Ok(serde_json::json!({"maximum": "0"}).to_string());
            };
            if request.to.trim().is_empty() {
                request.to.clone_from(first);
            }
            // More than anything can hold: the planner answers with what is spendable.
            request.amount = ((num_bigint::BigUint::from(1u8) << 256u32) - 1u8).to_string();
            let created = crate::runtime()?.block_on(crate::send::create(
                &endpoint,
                &request,
                &account,
                crate::spending::Mode::from_legacy(legacy),
                local_development(),
            ))?;
            let maximum = match created {
                crate::send::Created::Problem(problem) => {
                    let problem: serde_json::Value = serde_json::from_str(&problem)?;
                    match problem["code"].as_str() {
                        Some("insufficient_funds") => problem["held"]
                            .as_str()
                            .ok_or_else(|| anyhow::anyhow!("invalid problem"))?
                            .to_string(),
                        Some("no_addresses") => "0".into(),
                        _ => anyhow::bail!("no maximum"),
                    }
                }
                crate::send::Created::Plan(_) => anyhow::bail!("no maximum"),
            };
            Ok(serde_json::json!({"maximum": maximum}).to_string())
        })())
    }
    /// The user's decision on the reviewed plan. `false` discards it.
    pub fn confirm_plan(&self, allow: bool) -> Result<(), WalletError> {
        checked((|| {
            let mut i = self
                .inner
                .lock()
                .map_err(|_| anyhow::anyhow!("state unavailable"))?;
            i.session.key()?;
            if !allow {
                i.plan = None;
                return Ok(());
            }
            i.plan
                .as_mut()
                .ok_or_else(|| anyhow::anyhow!("missing review"))?
                .confirm();
            Ok(())
        })())
    }
    /// Signs and broadcasts one step of the confirmed plan. Returns its transaction hash.
    /// Steps run in order. The plan ends with its last step, on any failure, or when the
    /// wallet locks. Only a step whose dependency is not mined yet may be asked again.
    pub fn execute_step(&self, index: u32) -> Result<String, WalletError> {
        checked((|| {
            // The plan is taken out while the network is used, so no other call can
            // run it at the same time. The lock is not held meanwhile.
            let (mut state, secrets) = {
                let mut i = self
                    .inner
                    .lock()
                    .map_err(|_| anyhow::anyhow!("state unavailable"))?;
                let secrets = read(&mut i)?;
                let state = i
                    .plan
                    .take()
                    .ok_or_else(|| anyhow::anyhow!("missing review"))?;
                (state, secrets)
            };
            let result = crate::runtime()?.block_on(state.execute(
                index as usize,
                &secrets.words,
                &secrets.passphrase,
            ));
            drop(secrets);
            let keep = match &result {
                Ok(_) => !state.finished(),
                Err(error) => error.is::<crate::send::Pending>(),
            };
            if keep {
                let mut i = self
                    .inner
                    .lock()
                    .map_err(|_| anyhow::anyhow!("state unavailable"))?;
                if i.session.key().is_ok() && i.plan.is_none() {
                    i.plan = Some(state);
                }
            }
            result
        })())
    }
    pub fn rename_project(&self, slot: u32, label: String) -> Result<(), WalletError> {
        checked((|| {
            let mut i = self
                .inner
                .lock()
                .map_err(|_| anyhow::anyhow!("state unavailable"))?;
            i.projects.rename(slot, label)
        })())
    }
    /// Removes an account from the list. Its slot stays used and funds stay on-chain.
    pub fn remove_project(&self, slot: u32) -> Result<(), WalletError> {
        checked((|| {
            let mut i = self
                .inner
                .lock()
                .map_err(|_| anyhow::anyhow!("state unavailable"))?;
            i.projects.remove(slot)
        })())
    }
}
fn read(i: &mut Inner) -> anyhow::Result<Secrets> {
    let Inner { vault, session, .. } = i;
    let key = session.key()?;
    Ok(serde_json::from_slice(&vault.read(key)?)?)
}
fn save(i: &mut Inner, secrets: &Secrets) -> anyhow::Result<()> {
    let bytes = Zeroizing::new(serde_json::to_vec(secrets)?);
    let Inner { vault, session, .. } = i;
    vault.write(session.key()?, &bytes)
}
#[uniffi::export]
pub fn local_development_enabled() -> bool {
    local_development()
}
/// Initial, user-editable configuration: networks with their RPC endpoints, colors and
/// logo SVG text, assets and the suggested API origin. It is declared in
/// `assets/defaults.json` (see `defaults`). Hosts copy it into ordinary settings exactly
/// once, when a wallet is created. Afterwards these entries are edited and removed like
/// any other. Local development builds add the workspace's Anvil chain (see roofer), off
/// like any test network until the user turns it on.
///
/// # Panics
///
/// Never for a build that passes the `defaults` tests, which load the embedded file.
#[uniffi::export]
pub fn default_configuration() -> String {
    let host = local_development().then(local_host);
    // The defaults are embedded in the binary and the `defaults` tests load them with and
    // without a local host, so this cannot fail for a build that passes them.
    crate::defaults::load(host.as_deref())
        .and_then(|defaults| Ok(serde_json::to_string(&defaults)?))
        .expect("the embedded default configuration is valid, as the defaults tests check")
}
/// A key for a store's Payments tab, named after the store: it can only create payment
/// addresses (references, paths) and their notifications (webhooks), never spend.
async fn store_grant(
    api: &crate::api::Api,
    project: &str,
    subdomain: &str,
) -> anyhow::Result<(serde_json::Value, Zeroizing<String>)> {
    let permissions = crate::stor::PERMISSIONS.map(String::from);
    let grant = api
        .create_grant(project, &format!("Stor {subdomain}"), &permissions)
        .await?;
    let key = Zeroizing::new(
        grant["token"]
            .as_str()
            .ok_or_else(|| anyhow::anyhow!("no key"))?
            .to_string(),
    );
    Ok((grant, key))
}
/// What a Stor server asks of a new store: the account to share a Google Sheet with,
/// and its stores' address as `…{store}…`. `stor` is the server the user chose (the
/// default configuration's `storOrigin` is only a suggestion).
#[uniffi::export]
pub fn stor_info(stor: String) -> Result<String, WalletError> {
    checked((|| {
        let origin = crate::api::origin(&stor, local_development())?;
        Ok(crate::runtime()?
            .block_on(crate::stor::info(&origin))?
            .to_string())
    })())
}
#[derive(uniffi::Record)]
pub struct TokenDetails {
    pub symbol: String,
    pub name: String,
    pub decimals: u8,
}
/// Whether the provider accepts the key, asked of the provider itself. Nothing is
/// stored. The error says nothing about the key.
#[uniffi::export]
pub fn verify_provider_key(provider: String, key: String) -> Result<(), WalletError> {
    let key = Zeroizing::new(key);
    checked((|| {
        let provider = crate::providers::Provider::from_id(&provider)
            .ok_or_else(|| anyhow::anyhow!("unknown provider"))?;
        crate::runtime()?.block_on(crate::providers::verify(provider, &key))
    })())
}
/// Providers whose key adds an RPC endpoint (`provider:<id>`) to a chain.
#[uniffi::export]
pub fn rpc_providers(chain: String) -> Vec<String> {
    crate::providers::chain_number(&chain)
        .map(crate::providers::rpc_providers)
        .unwrap_or_default()
        .into_iter()
        .map(String::from)
        .collect()
}
/// Where `history` reads a chain's activity, in the order tried, given the providers
/// the user has a key for (built-in keys count on the chains they serve). Names only,
/// for display.
#[uniffi::export]
pub fn history_sources(chain: String, keys: Vec<String>) -> Vec<String> {
    crate::providers::chain_number(&chain)
        .map(|number| {
            let presets = crate::providers::preset_providers(number);
            crate::history::sources(number, |id| {
                keys.iter().any(|k| k == id) || presets.contains(&id)
            })
        })
        .unwrap_or_default()
}
/// Providers with a built-in key for a chain: their endpoints work without a key of
/// the user's own. The keys themselves stay in the core.
#[uniffi::export]
pub fn preset_providers(chain: String) -> Vec<String> {
    crate::providers::chain_number(&chain)
        .map(crate::providers::preset_providers)
        .unwrap_or_default()
        .into_iter()
        .map(String::from)
        .collect()
}
/// USD prices for several dot-path fields of one oracle document, fetched once.
/// Each entry is a canonical decimal, or nil when that field cannot be read.
#[uniffi::export]
pub fn prices(url: String, fields: Vec<String>) -> Result<Vec<Option<String>>, WalletError> {
    checked((|| {
        crate::runtime()?.block_on(crate::price::quote(&url, &fields, local_development()))
    })())
}
/// How a pairing link is shaped, so hosts that scan or paste one check it the way the
/// core does instead of repeating the constants. The core still parses every link itself.
#[derive(uniffi::Record)]
pub struct PairingLinkFormat {
    /// The path before the ID, `/v1/pairings/`.
    pub path_prefix: String,
    /// What every ID starts with, `pair_`.
    pub id_prefix: String,
    /// The exact length of an ID, prefix included.
    pub id_length: u32,
}
#[uniffi::export]
pub fn pairing_link_format() -> PairingLinkFormat {
    PairingLinkFormat {
        path_prefix: crate::pairing::path_prefix(),
        id_prefix: crate::pairing::ID_PREFIX.into(),
        id_length: u32::try_from(crate::pairing::ID_LENGTH).unwrap_or(u32::MAX),
    }
}
#[uniffi::export]
pub fn generate_mnemonic() -> Result<String, WalletError> {
    checked(crate::mnemonic::generate().map(|s| s.to_string()))
}
#[cfg(test)]
mod local_tests {
    #[test]
    fn recovery_words_need_an_unlocked_wallet_and_the_pin() {
        let words = super::generate_mnemonic().unwrap();
        let wallet = super::Wallet::create(words.clone(), "123456".into()).unwrap();
        // Locked: even the right PIN reveals nothing.
        assert!(wallet.recovery_words("123456".into()).is_err());
        wallet.unlock("123456".into()).unwrap();
        assert!(wallet.recovery_words("654321".into()).is_err());
        assert_eq!(wallet.recovery_words("123456".into()).unwrap(), words);
        wallet.lock();
        assert!(wallet.recovery_words("123456".into()).is_err());
    }
    #[test]
    fn projects_are_renamed_and_a_plan_needs_an_unlocked_wallet() {
        let wallet =
            super::Wallet::create(super::generate_mnemonic().unwrap(), "123456".into()).unwrap();
        wallet.unlock("123456".into()).unwrap();
        let slot = wallet.add_project("First".into(), None).unwrap();
        wallet.rename_project(slot, "Second".into()).unwrap();
        assert!(wallet.public_json().unwrap().contains("Second"));
        for bad in [String::new(), "x".repeat(101)] {
            assert!(wallet.rename_project(slot, bad).is_err());
        }
        assert!(wallet.rename_project(slot + 1, "Other".into()).is_err());
        wallet.rename_project(slot, "é".repeat(100)).unwrap();
        // No plan yet: nothing to confirm or run. Discarding is always fine.
        assert!(wallet.confirm_plan(true).is_err());
        assert!(wallet.execute_step(0).is_err());
        wallet.confirm_plan(false).unwrap();
        let request = |slot: u32| {
            format!(
                r#"{{"chain":"eip155:1","asset":"eip155:1/slip44:60","to":"0x00000000000000000000000000000000000000ee","amount":"1","slot":{slot}}}"#
            )
        };
        assert!(
            wallet
                .plan_send("https://rpc.example".into(), request(slot + 1), false)
                .is_err()
        );
        wallet.lock();
        assert!(
            wallet
                .plan_send("https://rpc.example".into(), request(slot), false)
                .is_err()
        );
        assert!(wallet.confirm_plan(false).is_err());
    }
    #[test]
    fn history_sources_are_keyed_providers_then_rpc() {
        assert_eq!(
            super::history_sources("eip155:31337".into(), vec![]),
            ["RPC"]
        );
        let sources = super::history_sources("eip155:1".into(), vec!["etherscan".into()]);
        assert_eq!(
            (
                sources.first().map(String::as_str),
                sources.last().map(String::as_str)
            ),
            (Some("Etherscan"), Some("RPC"))
        );
    }
    /// Every default network and token carries a valid color and its logo as SVG text.
    fn assert_look(id: &str, entry: &serde_json::Value) {
        let color = entry["color"].as_str().unwrap_or_default();
        assert!(crate::defaults::is_color(color), "{id} color {color:?}");
        let logo = entry["logo"].as_str().unwrap_or_default();
        assert!(
            logo.starts_with("<svg") && logo.trim_end().ends_with("</svg>"),
            "{id} logo"
        );
    }
    #[test]
    fn default_configuration_is_well_formed() {
        let value: serde_json::Value =
            serde_json::from_str(&super::default_configuration()).unwrap();
        let networks = value["networks"].as_array().unwrap();
        let assets = value["assets"].as_array().unwrap();
        assert!(value["apiOrigin"].as_str().unwrap().starts_with("http"));
        let mut chains = std::collections::BTreeSet::new();
        for network in networks {
            let id = network["id"].as_str().unwrap();
            assert!(chains.insert(id.to_string()), "duplicate network {id}");
            assert!(id.strip_prefix("eip155:").unwrap().parse::<u64>().is_ok());
            let endpoints = network["endpoints"].as_array().unwrap();
            assert!(!endpoints.is_empty(), "{id} has a usable endpoint");
            let urls: std::collections::BTreeSet<_> = endpoints
                .iter()
                .map(|e| e["url"].as_str().unwrap())
                .collect();
            assert_eq!(urls.len(), endpoints.len());
            assert!(urls.contains(network["endpoint"].as_str().unwrap()));
            if let Some(explorer) = network.get("explorer") {
                crate::networks::validate_rpc(
                    explorer.as_str().unwrap(),
                    super::local_development(),
                )
                .unwrap();
            }
            assert!(network.get("indexer").is_none());
            assert_look(id, network);
            for url in urls {
                crate::networks::validate_rpc(url, super::local_development()).unwrap();
                assert!(!url.contains('?'), "defaults carry no API keys");
            }
        }
        if super::local_development() {
            // Anvil is added, off. The real networks and tokens are untouched.
            let anvil = networks.iter().find(|n| n["id"] == "eip155:31337").unwrap();
            assert_eq!(anvil["enabled"], false);
            assert_eq!(
                anvil["endpoint"],
                format!("http://{}:8545", super::local_host())
            );
            assert_eq!(
                value["apiOrigin"],
                format!("http://{}:8080", super::local_host())
            );
            assert!(assets.iter().any(|a| a["id"] == "eip155:31337/slip44:60"));
            assert!(assets.iter().any(|a| a["kind"] == "erc20"));
            assert!(
                networks
                    .iter()
                    .filter(|n| n["id"] != "eip155:31337")
                    .all(|n| n["endpoint"].as_str().unwrap().starts_with("https://"))
            );
        }
        let mut ids = std::collections::BTreeSet::new();
        for asset in assets {
            let id = asset["id"].as_str().unwrap();
            let chain = asset["chain"].as_str().unwrap();
            assert!(ids.insert(id.to_string()), "duplicate asset {id}");
            assert!(chains.contains(chain) && id.starts_with(&format!("{chain}/")));
            assert!(asset["decimals"].as_u64().unwrap() <= 36);
            assert_look(id, asset);
            if let Some(price) = asset.get("price") {
                crate::networks::validate_rpc(
                    price["url"].as_str().unwrap(),
                    super::local_development(),
                )
                .unwrap();
                assert_ne!(price["field"].as_str().unwrap(), "");
            }
            if let Some((_, contract)) = id.split_once("/erc20:") {
                crate::assets::address(contract).unwrap();
                assert_eq!(contract, contract.to_lowercase());
            } else {
                assert_eq!(asset["kind"], "native");
            }
        }
    }
    #[test]
    fn native_local_mode_requires_build_and_runtime_opt_in() {
        assert_eq!(
            super::local_development_enabled(),
            cfg!(feature = "local-development")
                && std::env::var("PAYROOF_WALLET_LOCAL_DEVELOPMENT").as_deref() == Ok("1")
        );
    }
}
