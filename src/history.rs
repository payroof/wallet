//! Local activity: what happened at the account's addresses, found without the Payroof
//! API. Sources are tried in order and the next one is used when one fails: Etherscan V2
//! (key), Alchemy transfers (key), then plain RPC. Every source is untrusted. Each field
//! is validated, and only the wallet's own assets are reported, so airdropped spam never
//! appears.
use crate::ids::{AssetId, AssetKind, ChainId};
use crate::{assets, balance, indexer, providers};
use num_bigint::BigUint;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::collections::{BTreeMap, BTreeSet, HashMap};

/// Blocks re-read on every pass: indexers lag the head and shallow reorgs happen.
const MARGIN: u64 = 8;
/// Addresses served by an indexer per refresh, lowest cursor first.
const ADDRESSES: usize = 10;
/// Requests to indexers per refresh.
const REQUESTS: usize = 24;
/// Blocks scanned over plain RPC per refresh, and the most one request covers.
const SPAN: u64 = 2000;
const WINDOW: u64 = 500;
/// Smallest log window tried before giving up on a range.
const MIN_WINDOW: u64 = 8;
/// Many free public RPCs serve logs of recent blocks only. This many still work there.
const RECENT: u64 = 64;
/// Addresses in one `eth_getLogs` topic filter.
const TOPICS: usize = 32;
/// Distinct blocks whose timestamp is looked up for log results.
const TIMESTAMPS: usize = 32;
const ENTRIES: usize = 2000;
const TRANSFER: &str = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef";

#[derive(Serialize)]
pub struct Entry {
    pub chain: String,
    pub asset: String,
    pub transaction: String,
    /// Position among identical transfers of one transaction. With the other fields
    /// it identifies the transfer whichever source reported it.
    pub index: u32,
    pub from: String,
    pub to: String,
    pub amount: String,
    pub block: u64,
    pub timestamp: Option<u64>,
    pub direction: &'static str,
    pub failed: bool,
}

/// A transfer as one source reported it, validated but not yet matched to the wallet.
pub(crate) struct Transfer {
    /// Lowercase contract. `None` is the native coin.
    pub token: Option<String>,
    pub transaction: String,
    pub from: String,
    pub to: String,
    pub amount: String,
    pub block: u64,
    pub timestamp: Option<u64>,
    pub failed: bool,
}

/// One response of an indexer: its transfers and how far it got.
pub(crate) struct Page {
    pub transfers: Vec<Transfer>,
    /// More rows may follow. The last block may be incomplete.
    pub full: bool,
    pub first: u64,
    pub last: u64,
}

impl Page {
    /// The last block certainly complete, given the range asked for.
    pub fn covered(&self, end: u64) -> u64 {
        match (self.full, self.first == self.last) {
            (false, _) => end,
            (true, true) => self.last,
            (true, false) => self.last - 1,
        }
    }
}

/// Where scanning stopped, per address and kind of source. Indexers and RPC cover
/// different history, so adding a key later still fills in the past.
#[derive(Default, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Cursor {
    index: BTreeMap<String, u64>,
    rpc: BTreeMap<String, u64>,
}

impl Cursor {
    pub fn parse(text: &str) -> anyhow::Result<Self> {
        if text.is_empty() {
            return Ok(Self::default());
        }
        anyhow::ensure!(text.len() <= 65536, "cursor too large");
        Ok(serde_json::from_str(text)?)
    }
    pub fn encode(&self) -> anyhow::Result<String> {
        Ok(serde_json::to_string(self)?)
    }
}

/// Moves an address forward, never back and never past the head.
fn advance(map: &mut BTreeMap<String, u64>, address: &str, covered: u64, head: u64) {
    let to = covered.min(head).saturating_sub(MARGIN);
    let slot = map.entry(address.to_string()).or_insert(0);
    *slot = (*slot).max(to);
}

pub struct Request<'a> {
    pub chain: &'a str,
    /// The network's endpoint, already resolved. Keys may be inside. Never log it.
    pub rpc: &'a str,
    pub keys: &'a providers::Keys,
    pub assets: &'a [String],
    pub addresses: &'a [String],
    pub cursor: Cursor,
    pub development: bool,
}

pub struct Outcome {
    pub entries: Vec<Entry>,
    pub cursor: Cursor,
    /// Which source answered, as named by `sources`.
    pub source: String,
}

/// The wallet's own assets on the chain.
struct Wanted {
    chain: String,
    /// The network's coin as the wallet lists it (`slip44:60` ETH, `slip44:966` POL, …).
    native: Option<String>,
    tokens: BTreeSet<String>,
}

impl Wanted {
    fn new(chain: &str, ids: &[String]) -> anyhow::Result<Self> {
        let chain_id: ChainId = chain.parse()?;
        let mut wanted = Self {
            chain: chain_id.to_string(),
            native: None,
            tokens: BTreeSet::new(),
        };
        for id in ids {
            let asset: AssetId = id.parse()?;
            anyhow::ensure!(asset.chain == chain_id, "asset chain mismatch");
            match asset.kind {
                AssetKind::Native(_) => wanted.native = Some(asset.to_string()),
                AssetKind::Erc20(contract) => {
                    wanted.tokens.insert(contract);
                }
            }
        }
        Ok(wanted)
    }
    /// The wallet's ID for a transfer's asset, if the wallet lists it.
    fn id(&self, token: Option<&str>) -> Option<String> {
        match token {
            None => self.native.clone(),
            Some(c) => self
                .tokens
                .contains(c)
                .then(|| format!("{}/erc20:{c}", self.chain)),
        }
    }
}

/// Matches transfers to the wallet and merges what several queries returned.
struct Collector<'a> {
    wanted: &'a Wanted,
    mine: &'a BTreeSet<String>,
    found: BTreeMap<String, Entry>,
}

impl<'a> Collector<'a> {
    fn new(wanted: &'a Wanted, mine: &'a BTreeSet<String>) -> Self {
        Self {
            wanted,
            mine,
            found: BTreeMap::new(),
        }
    }
    /// One response's transfers. Identical transfers of a transaction are numbered
    /// within the response, which makes the same transfer from another response (the
    /// other direction, another address) land on the same key.
    fn add(&mut self, batch: Vec<Transfer>) -> anyhow::Result<()> {
        let mut seen: HashMap<String, u32> = HashMap::new();
        for t in batch {
            let Some(asset) = self.wanted.id(t.token.as_deref()) else {
                continue;
            };
            let (from, to) = (self.mine.contains(&t.from), self.mine.contains(&t.to));
            if (!from && !to) || t.amount == "0" {
                continue;
            }
            let base = format!("{}:{asset}:{}:{}:{}", t.transaction, t.from, t.to, t.amount);
            let counter = seen.entry(base.clone()).or_default();
            let index = *counter;
            *counter += 1;
            self.found.insert(
                format!("{base}:{index}"),
                Entry {
                    chain: self.wanted.chain.clone(),
                    asset,
                    transaction: t.transaction,
                    index,
                    from: t.from,
                    to: t.to,
                    amount: t.amount,
                    block: t.block,
                    timestamp: t.timestamp,
                    direction: match (from, to) {
                        (true, true) => "self",
                        (true, false) => "out",
                        _ => "in",
                    },
                    failed: t.failed,
                },
            );
            anyhow::ensure!(self.found.len() <= ENTRIES, "too many transfers");
        }
        Ok(())
    }
    fn finish(self) -> Vec<Entry> {
        let mut entries: Vec<Entry> = self.found.into_values().collect();
        entries.sort_by_key(|e| std::cmp::Reverse(e.block));
        entries
    }
}

enum Source {
    Index(indexer::Index),
    Rpc,
}

/// Where a chain's activity is read, in the order tried: Etherscan V2 with a key,
/// Alchemy with a key (the user's or a built-in one for the chain), then the RPC. Names
/// only, for display. No key or URL with a key is ever part of one.
pub fn sources(number: u64, has_key: impl Fn(&str) -> bool) -> Vec<String> {
    let mut names = Vec::new();
    if has_key("etherscan") && providers::Provider::Etherscan.indexer(number).is_some() {
        names.push("Etherscan".to_string());
    }
    if has_key("alchemy") && providers::rpc_providers(number).contains(&"alchemy") {
        names.push("Alchemy".to_string());
    }
    names.push("RPC".to_string());
    names
}

pub async fn scan(request: Request<'_>) -> anyhow::Result<Outcome> {
    let Request {
        chain,
        rpc,
        keys,
        assets: ids,
        addresses,
        mut cursor,
        development,
    } = request;
    crate::networks::validate_rpc(rpc, development)?;
    let http = crate::api::client()?;
    balance::check_chain(&http, rpc, chain).await?;
    let head = u64::try_from(balance::parse_quantity(
        &balance::rpc(&http, rpc, "eth_blockNumber", json!([])).await?,
    )?)?;
    // A cursor ahead of the head means the chain was reset or replaced: start over.
    cursor.index.retain(|_, at| *at <= head);
    cursor.rpc.retain(|_, at| *at <= head);
    let number = providers::chain_number(chain)?;
    let wanted = Wanted::new(chain, ids)?;
    let mut mine = BTreeSet::new();
    for address in addresses {
        assets::address(address)?;
        mine.insert(address.to_ascii_lowercase());
    }
    let names = sources(number, |id| {
        providers::Provider::from_id(id).is_some_and(|p| p.key(keys, number).is_some())
    });
    let mut sources = Vec::new();
    if let Some(key) = providers::Provider::Etherscan.key(keys, number)
        && let Some(base) = providers::Provider::Etherscan.indexer(number)
    {
        sources.push(Source::Index(indexer::Index::Etherscan(
            indexer::Etherscan::keyed(base, number, key),
        )));
    }
    if let Some(key) = providers::Provider::Alchemy.key(keys, number)
        && let Some(url) = providers::Provider::Alchemy.rpc(number, key)
    {
        sources.push(Source::Index(indexer::Index::Alchemy(url)));
    }
    sources.push(Source::Rpc);
    anyhow::ensure!(names.len() == sources.len(), "activity sources differ");
    let mut failure = anyhow::anyhow!("no activity source");
    for (source, name) in sources.iter().zip(names) {
        let mut next = Cursor {
            index: cursor.index.clone(),
            rpc: cursor.rpc.clone(),
        };
        let mut found = Collector::new(&wanted, &mine);
        let run = match source {
            Source::Rpc => {
                let local = development && local_endpoint(rpc);
                scan_rpc(&http, rpc, local, &mut next.rpc, &mut found, head).await
            }
            Source::Index(index) => {
                scan_index(&http, index, &mut next.index, &mut found, head).await
            }
        };
        match run {
            Ok(()) => {
                return Ok(Outcome {
                    entries: found.finish(),
                    cursor: next,
                    source: name,
                });
            }
            Err(error) => failure = error,
        }
    }
    Err(failure)
}

fn local_endpoint(rpc: &str) -> bool {
    url::Url::parse(rpc)
        .is_ok_and(|u| u.scheme() == "http" && crate::networks::development_http_host(&u))
}

/// Indexer sources: per address, lowest cursor first, within the request budget.
async fn scan_index(
    http: &reqwest::Client,
    index: &indexer::Index,
    cursor: &mut BTreeMap<String, u64>,
    found: &mut Collector<'_>,
    head: u64,
) -> anyhow::Result<()> {
    let mut throttle = indexer::Throttle::new(REQUESTS);
    let mut order: Vec<&String> = found.mine.iter().collect();
    order.sort_by_key(|a| cursor.get(*a).copied());
    let order: Vec<String> = order.into_iter().take(ADDRESSES).cloned().collect();
    for address in order {
        let mut start = cursor.get(&address).map_or(0, |c| c + 1);
        while start <= head {
            if throttle.spent() {
                return Ok(());
            }
            let pages = index
                .pages(http, &mut throttle, &address, start, head)
                .await?;
            let covered = pages.iter().map(|p| p.covered(head)).min().unwrap_or(head);
            for page in pages {
                found.add(page.transfers)?;
            }
            advance(cursor, &address, covered, head);
            start = covered + 1;
        }
    }
    Ok(())
}

/// Plain RPC: token `Transfer` logs of the wallet's own tokens, and, only on a local
/// development node, native transfers by reading blocks. Public chains are far too
/// large for that.
async fn scan_rpc(
    http: &reqwest::Client,
    rpc: &str,
    local: bool,
    cursor: &mut BTreeMap<String, u64>,
    found: &mut Collector<'_>,
    head: u64,
) -> anyhow::Result<()> {
    let first = head.saturating_sub(SPAN);
    let mut start = found
        .mine
        .iter()
        .map(|a| cursor.get(a).map_or(first, |c| c + 1))
        .min()
        .unwrap_or(head + 1);
    let mut end = head.min(start.saturating_add(SPAN - 1));
    if start > end {
        return Ok(());
    }
    let mine: Vec<String> = found.mine.iter().cloned().collect();
    let contracts: Vec<&String> = found.wanted.tokens.iter().collect();
    if !contracts.is_empty() {
        let stamped = match token_logs(http, rpc, &contracts, &mine, found, start, end).await {
            Ok(stamped) => stamped,
            Err(error) => {
                // The endpoint refuses older blocks even in small windows: follow the
                // recent ones it serves. Older history needs an indexer or a key.
                let recent = head.saturating_sub(RECENT - 1);
                if recent <= start {
                    return Err(error);
                }
                (start, end) = (recent, head);
                token_logs(http, rpc, &contracts, &mine, found, start, end).await?
            }
        };
        let blocks: BTreeSet<u64> = stamped.iter().flatten().map(|t| t.block).collect();
        let mut times = HashMap::new();
        for number in blocks.into_iter().take(TIMESTAMPS) {
            let block = balance::rpc(
                http,
                rpc,
                "eth_getBlockByNumber",
                json!([format!("0x{number:x}"), false]),
            )
            .await?;
            times.insert(number, block_time(&block)?);
        }
        for mut batch in stamped {
            for t in &mut batch {
                t.timestamp = times.get(&t.block).copied();
            }
            found.add(batch)?;
        }
    }
    if local && found.wanted.native.is_some() {
        for number in start..=end {
            let block = balance::rpc(
                http,
                rpc,
                "eth_getBlockByNumber",
                json!([format!("0x{number:x}"), true]),
            )
            .await?;
            let mut batch = parse_block(&block, number)?;
            for t in &mut batch {
                if found.mine.contains(&t.from) || found.mine.contains(&t.to) {
                    let receipt = balance::rpc(
                        http,
                        rpc,
                        "eth_getTransactionReceipt",
                        json!([t.transaction]),
                    )
                    .await?;
                    anyhow::ensure!(receipt.is_object(), "missing receipt");
                    t.failed = receipt["status"] != "0x1";
                }
            }
            found.add(batch)?;
        }
    }
    for address in &mine {
        advance(cursor, address, end, head);
    }
    Ok(())
}

/// `Transfer` logs from and to the account over `[start, end]`. A window the endpoint
/// refuses (range or result limits) is halved, down to `MIN_WINDOW` blocks.
async fn token_logs(
    http: &reqwest::Client,
    rpc: &str,
    contracts: &[&String],
    mine: &[String],
    found: &Collector<'_>,
    start: u64,
    end: u64,
) -> anyhow::Result<Vec<Vec<Transfer>>> {
    let mut stamped = Vec::new();
    let mut window = WINDOW;
    let mut from = start;
    while from <= end {
        let to = end.min(from + window - 1);
        let mut batch = Vec::new();
        let mut refused = None;
        'filters: for chunk in mine.chunks(TOPICS) {
            let padded: Vec<String> = chunk
                .iter()
                .map(|a| format!("0x{:0>64}", &a[2..]))
                .collect();
            for topics in [json!([TRANSFER, padded]), json!([TRANSFER, null, padded])] {
                let filter = json!([{
                    "fromBlock": format!("0x{from:x}"), "toBlock": format!("0x{to:x}"),
                    "address": contracts, "topics": topics
                }]);
                match balance::rpc(http, rpc, "eth_getLogs", filter).await {
                    Ok(logs) => batch.push(parse_logs(&logs, &found.wanted.tokens, from, to)?),
                    Err(error) => {
                        refused = Some(error);
                        break 'filters;
                    }
                }
            }
        }
        match refused {
            None => {
                stamped.extend(batch);
                from = to + 1;
            }
            Some(_) if window > MIN_WINDOW => window /= 2,
            Some(error) => return Err(error),
        }
    }
    Ok(stamped)
}

pub(crate) fn address_value(value: &Value) -> anyhow::Result<String> {
    let text = value
        .as_str()
        .ok_or_else(|| anyhow::anyhow!("invalid address"))?;
    assets::address(text)?;
    Ok(text.to_ascii_lowercase())
}

pub(crate) fn hash_value(value: &Value) -> anyhow::Result<String> {
    let text = value
        .as_str()
        .filter(|t| {
            t.len() == 66 && t.starts_with("0x") && t[2..].bytes().all(|b| b.is_ascii_hexdigit())
        })
        .ok_or_else(|| anyhow::anyhow!("invalid transaction hash"))?;
    Ok(text.to_ascii_lowercase())
}

pub(crate) fn quantity_u64(value: &Value) -> anyhow::Result<u64> {
    Ok(u64::try_from(balance::parse_quantity(value)?)?)
}

fn in_range(block: u64, start: u64, end: u64) -> anyhow::Result<u64> {
    anyhow::ensure!((start..=end).contains(&block), "block out of range");
    Ok(block)
}

fn parse_logs(
    logs: &Value,
    tokens: &BTreeSet<String>,
    start: u64,
    end: u64,
) -> anyhow::Result<Vec<Transfer>> {
    let logs = logs
        .as_array()
        .filter(|l| l.len() <= ENTRIES)
        .ok_or_else(|| anyhow::anyhow!("invalid logs"))?;
    let party = |topic: &Value| -> anyhow::Result<String> {
        let t = topic
            .as_str()
            .filter(|t| t.len() == 66 && t.starts_with("0x"))
            .ok_or_else(|| anyhow::anyhow!("invalid topic"))?;
        anyhow::ensure!(t[2..26].bytes().all(|b| b == b'0'), "invalid topic");
        address_value(&json!(format!("0x{}", &t[26..])))
    };
    let mut parsed = Vec::new();
    for log in logs {
        if log["removed"] == true {
            continue;
        }
        let contract = address_value(&log["address"])?;
        anyhow::ensure!(tokens.contains(&contract), "unexpected contract");
        let topics = log["topics"]
            .as_array()
            .ok_or_else(|| anyhow::anyhow!("invalid topics"))?;
        // A fourth topic is an NFT transfer sharing the signature.
        if topics.len() != 3 {
            continue;
        }
        anyhow::ensure!(
            topics[0]
                .as_str()
                .is_some_and(|t| t.eq_ignore_ascii_case(TRANSFER)),
            "unexpected event"
        );
        let data = log["data"]
            .as_str()
            .filter(|d| d.len() == 66 && d.starts_with("0x"))
            .ok_or_else(|| anyhow::anyhow!("invalid data"))?;
        let amount = balance::parse_quantity(&json!(data))?.to_string();
        let block = in_range(quantity_u64(&log["blockNumber"])?, start, end)?;
        parsed.push((
            (block, quantity_u64(&log["logIndex"])?),
            Transfer {
                token: Some(contract),
                transaction: hash_value(&log["transactionHash"])?,
                from: party(&topics[1])?,
                to: party(&topics[2])?,
                amount,
                block,
                timestamp: None,
                failed: false,
            },
        ));
    }
    parsed.sort_by_key(|(order, _)| *order);
    Ok(parsed.into_iter().map(|(_, t)| t).collect())
}

fn block_time(block: &Value) -> anyhow::Result<u64> {
    quantity_u64(&block["timestamp"])
}

fn parse_block(block: &Value, number: u64) -> anyhow::Result<Vec<Transfer>> {
    anyhow::ensure!(quantity_u64(&block["number"])? == number, "wrong block");
    let timestamp = Some(block_time(block)?);
    let txs = block["transactions"]
        .as_array()
        .filter(|t| t.len() <= 10000)
        .ok_or_else(|| anyhow::anyhow!("invalid block"))?;
    let mut list = Vec::new();
    for tx in txs {
        let value: BigUint = balance::parse_quantity(&tx["value"])?;
        if tx["to"].is_null() || value == BigUint::default() {
            continue;
        }
        list.push(Transfer {
            token: None,
            transaction: hash_value(&tx["hash"])?,
            from: address_value(&tx["from"])?,
            to: address_value(&tx["to"])?,
            amount: value.to_string(),
            block: number,
            timestamp,
            failed: false,
        });
    }
    Ok(list)
}

#[cfg(test)]
mod tests;
