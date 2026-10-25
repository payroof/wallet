use super::*;
use std::sync::{Arc, Mutex};

const A: &str = "0x00000000000000000000000000000000000000a1";
const B: &str = "0x00000000000000000000000000000000000000b2";
const TOKEN: &str = "0x00000000000000000000000000000000000000c3";
const SPAM: &str = "0x00000000000000000000000000000000000000d4";
const CHAIN: &str = "eip155:31337";
const TX: &str = "0x1111111111111111111111111111111111111111111111111111111111111111";
const TX2: &str = "0x2222222222222222222222222222222222222222222222222222222222222222";

fn pad(address: &str) -> String {
    format!("0x{:0>64}", &address[2..])
}

fn log(contract: &str, from: &str, to: &str, data: &str, block: u64, index: u64) -> Value {
    json!({"address": contract, "topics": [TRANSFER, pad(from), pad(to)], "data": data,
        "blockNumber": format!("0x{block:x}"), "logIndex": format!("0x{index:x}"),
        "transactionHash": TX, "removed": false})
}

fn amount(n: u64) -> String {
    format!("0x{n:064x}")
}

fn tokens() -> BTreeSet<String> {
    BTreeSet::from([TOKEN.to_string()])
}

#[test]
fn logs_become_transfers_in_log_order() {
    let logs = json!([
        log(TOKEN, B, A, &amount(7), 12, 3),
        log(TOKEN, A, B, &amount(5), 12, 1),
        {"address": TOKEN, "topics": [TRANSFER, pad(A), pad(B), pad(B)], "data": "0x",
            "blockNumber": "0xc", "logIndex": "0x2", "transactionHash": TX},
        {"address": TOKEN, "topics": [TRANSFER, pad(A), pad(B)], "data": amount(1),
            "blockNumber": "0xc", "logIndex": "0x0", "transactionHash": TX, "removed": true}
    ]);
    let parsed = parse_logs(&logs, &tokens(), 10, 20).unwrap();
    assert_eq!(parsed.len(), 2);
    assert_eq!(
        (parsed[0].amount.as_str(), parsed[0].from.as_str()),
        ("5", A)
    );
    assert_eq!((parsed[1].amount.as_str(), parsed[1].to.as_str()), ("7", A));
    assert_eq!(parsed[0].token.as_deref(), Some(TOKEN));
    assert_eq!(parsed[0].transaction, TX);
}

#[test]
fn hostile_logs_are_rejected() {
    let good = log(TOKEN, A, B, &amount(5), 12, 1);
    for refused in [
        ("address", json!(SPAM)),
        ("data", json!("0x05")),
        ("blockNumber", json!("0x1")),
        ("blockNumber", json!("0xffff")),
        ("logIndex", json!(null)),
        ("data", json!(format!("0x{}", "g".repeat(64)))),
        ("blockNumber", json!("12")),
        ("topics", json!("nope")),
        ("transactionHash", json!("0xabc")),
        (
            "topics",
            json!([TRANSFER, format!("0x{}{}", "1".repeat(24), &A[2..]), pad(B)]),
        ),
        ("topics", json!(["0xdead", pad(A), pad(B)])),
    ] {
        let mut log = good.clone();
        log[refused.0] = refused.1;
        assert!(
            parse_logs(&json!([log]), &tokens(), 10, 20).is_err(),
            "{}",
            refused.0
        );
    }
    assert!(parse_logs(&json!({"x": 1}), &tokens(), 10, 20).is_err());
    assert!(parse_logs(&Value::Array(vec![good; ENTRIES + 1]), &tokens(), 10, 20).is_err());
}

#[test]
fn blocks_yield_native_transfers() {
    let block = json!({"number": "0x5", "timestamp": "0x6553f100", "transactions": [
        {"hash": TX, "from": A, "to": B, "value": "0xde0b6b3a7640000"},
        {"hash": TX2, "from": A, "to": null, "value": "0x1"},
        {"hash": TX2, "from": A, "to": B, "value": "0x0"}
    ]});
    let parsed = parse_block(&block, 5).unwrap();
    assert_eq!(parsed.len(), 1);
    assert_eq!(parsed[0].amount, "1000000000000000000");
    assert_eq!(parsed[0].timestamp, Some(1_700_000_000));
    assert!(parse_block(&block, 6).is_err());
    for bad in [
        json!({"number": "0x5", "timestamp": "0x1", "transactions": "x"}),
        json!({"number": "0x5", "timestamp": "zz", "transactions": []}),
        json!({"number": "0x5", "timestamp": "0x1", "transactions": [{"hash": "0x1", "from": A, "to": B, "value": "0x1"}]}),
        json!({"number": "0x5", "timestamp": "0x1", "transactions": [{"hash": TX, "from": "bad", "to": B, "value": "0x1"}]}),
        json!({"number": "0x5", "timestamp": "0x1", "transactions": [{"hash": TX, "from": A, "to": B, "value": "1"}]}),
        Value::Null,
    ] {
        assert!(parse_block(&bad, 5).is_err());
    }
}

fn transfer(token: Option<&str>, from: &str, to: &str, amount: &str) -> Transfer {
    Transfer {
        token: token.map(String::from),
        transaction: TX.into(),
        from: from.into(),
        to: to.into(),
        amount: amount.into(),
        block: 9,
        timestamp: None,
        failed: false,
    }
}

#[test]
fn only_the_wallets_own_assets_and_addresses_are_reported() {
    let wanted = Wanted::new(
        CHAIN,
        &[
            format!("{CHAIN}/slip44:60"),
            format!("{CHAIN}/erc20:{TOKEN}"),
        ],
    )
    .unwrap();
    let mine = BTreeSet::from([A.to_string()]);
    let mut found = Collector::new(&wanted, &mine);
    found
        .add(vec![
            transfer(None, B, A, "10"),
            transfer(Some(TOKEN), A, B, "20"),
            transfer(Some(TOKEN), A, A, "30"),
            transfer(Some(SPAM), B, A, "40"),
            transfer(Some(TOKEN), B, A, "0"),
            transfer(None, B, B, "50"),
        ])
        .unwrap();
    let entries = found.finish();
    let seen: Vec<_> = entries
        .iter()
        .map(|e| (e.asset.as_str(), e.amount.as_str(), e.direction))
        .collect();
    assert_eq!(entries.len(), 3, "{seen:?}");
    for expected in [
        (format!("{CHAIN}/slip44:60"), "10", "in"),
        (format!("{CHAIN}/erc20:{TOKEN}"), "20", "out"),
        (format!("{CHAIN}/erc20:{TOKEN}"), "30", "self"),
    ] {
        assert!(seen.contains(&(expected.0.as_str(), expected.1, expected.2)));
    }
}

#[test]
fn the_same_transfer_from_two_queries_is_one_entry_but_repeats_stay_distinct() {
    let wanted = Wanted::new(CHAIN, &[format!("{CHAIN}/erc20:{TOKEN}")]).unwrap();
    let mine = BTreeSet::from([A.to_string(), B.to_string()]);
    let mut found = Collector::new(&wanted, &mine);
    let twice = || {
        vec![
            transfer(Some(TOKEN), A, B, "5"),
            transfer(Some(TOKEN), A, B, "5"),
        ]
    };
    found.add(twice()).unwrap();
    found.add(twice()).unwrap();
    let entries = found.finish();
    assert_eq!(entries.len(), 2);
    let mut indexes: Vec<u32> = entries.iter().map(|e| e.index).collect();
    indexes.sort_unstable();
    assert_eq!(indexes, [0, 1]);
    assert!(entries.iter().all(|e| e.direction == "self"));
}

#[test]
fn asset_lists_are_validated() {
    assert!(Wanted::new(CHAIN, &["eip155:1/slip44:60".into()]).is_err());
    assert!(Wanted::new(CHAIN, &[format!("{CHAIN}/erc721:{TOKEN}")]).is_err());
    assert!(Wanted::new(CHAIN, &[format!("{CHAIN}/erc20:0x12")]).is_err());
    assert!(Wanted::new(CHAIN, &[]).is_ok());
    for bad in ["slip44:", "slip44:060", "slip44:9x", "slip44:12345678901"] {
        assert!(
            Wanted::new(CHAIN, &[format!("{CHAIN}/{bad}")]).is_err(),
            "{bad}"
        );
    }
}

#[test]
fn a_networks_own_coin_is_reported_under_its_wallet_id() {
    // POL (966) and BNB (714) are coins too, not only ETH (60).
    for coin in ["slip44:60", "slip44:966", "slip44:714"] {
        let id = format!("{CHAIN}/{coin}");
        let wanted = Wanted::new(CHAIN, std::slice::from_ref(&id)).unwrap();
        assert_eq!(wanted.id(None), Some(id));
        assert_eq!(wanted.id(Some(TOKEN)), None);
    }
}

#[test]
fn cursors_only_move_forward_and_never_past_the_head() {
    let mut map = BTreeMap::new();
    advance(&mut map, A, 100, 100);
    assert_eq!(map[A], 100 - MARGIN);
    advance(&mut map, A, 50, 100);
    assert_eq!(map[A], 100 - MARGIN);
    advance(&mut map, A, 10_000, 120);
    assert_eq!(map[A], 120 - MARGIN);
    advance(&mut map, B, 3, 3);
    assert_eq!(map[B], 0);
    let cursor = Cursor::parse("").unwrap();
    assert!(cursor.index.is_empty() && cursor.rpc.is_empty());
    let text = Cursor {
        index: map.clone(),
        rpc: map,
    }
    .encode()
    .unwrap();
    assert_eq!(Cursor::parse(&text).unwrap().index[A], 120 - MARGIN);
    for bad in [
        "{",
        "[]",
        r#"{"index":{},"rpc":{},"x":1}"#,
        r#"{"index":{"a":-1},"rpc":{}}"#,
    ] {
        assert!(Cursor::parse(bad).is_err(), "{bad}");
    }
    assert!(Cursor::parse(&" ".repeat(70000)).is_err());
}

use crate::test_support::Server;

type Log = Arc<Mutex<Vec<String>>>;

/// An Anvil-like node at head 100.
fn node(log: &Log) -> Server {
    let log = log.clone();
    Server::start(Arc::new(move |_, request| {
        let method = request["method"].as_str().unwrap_or_default();
        log.lock()
            .unwrap()
            .push(format!("{method} {}", request["params"]));
        let result = match method {
            "eth_chainId" => json!("0x7a69"),
            "eth_blockNumber" => json!("0x64"),
            "eth_getLogs" => {
                let filter = &request["params"][0];
                assert_eq!(filter["address"], json!([TOKEN]));
                if filter["topics"][1].is_array() {
                    json!([log_entry(A, B, 5, 96, 1)])
                } else {
                    assert!(filter["topics"][2].is_array());
                    json!([log_entry(B, A, 7, 98, 4)])
                }
            }
            "eth_getBlockByNumber" => {
                let number = u64::from_str_radix(
                    request["params"][0]
                        .as_str()
                        .unwrap()
                        .trim_start_matches("0x"),
                    16,
                )
                .unwrap();
                let txs = if number == 99 && request["params"][1] == true {
                    json!([
                        {"hash": TX2, "from": A, "to": B, "value": "0xde0b6b3a7640000"},
                        {"hash": TX, "from": B, "to": B, "value": "0x5"}
                    ])
                } else {
                    json!([])
                };
                json!({"number": format!("0x{number:x}"), "timestamp": "0x6553f100", "transactions": txs})
            }
            "eth_getTransactionReceipt" => json!({"status": "0x1"}),
            _ => return (200, json!({"jsonrpc":"2.0","id":1,"error":{"code":-1}})),
        };
        (200, json!({"jsonrpc":"2.0","id":1,"result":result}))
    }))
}

fn log_entry(from: &str, to: &str, value: u64, block: u64, index: u64) -> Value {
    log(TOKEN, from, to, &amount(value), block, index)
}

fn run(server: &Server, cursor: &str, development: bool) -> anyhow::Result<Outcome> {
    let keys = providers::Keys::new();
    let assets = [
        format!("{CHAIN}/slip44:60"),
        format!("{CHAIN}/erc20:{TOKEN}"),
    ];
    let addresses = [A.to_string()];
    let rpc = server.base.clone();
    crate::runtime().unwrap().block_on(scan(Request {
        chain: CHAIN,
        rpc: &rpc,
        keys: &keys,
        assets: &assets,
        addresses: &addresses,
        cursor: Cursor::parse(cursor)?,
        development,
    }))
}

#[test]
fn a_local_node_is_scanned_for_tokens_and_native_transfers() {
    let log = Log::default();
    let server = node(&log);
    let outcome = run(&server, "", true).unwrap();
    let summary: Vec<_> = outcome
        .entries
        .iter()
        .map(|e| {
            (
                e.block,
                e.direction,
                e.amount.as_str(),
                e.asset.ends_with("slip44:60"),
            )
        })
        .collect();
    assert_eq!(
        summary,
        [
            (99, "out", "1000000000000000000", true),
            (98, "in", "7", false),
            (96, "out", "5", false)
        ]
    );
    assert!(
        outcome
            .entries
            .iter()
            .all(|e| e.timestamp == Some(1_700_000_000) && !e.failed)
    );
    assert_eq!(outcome.cursor.rpc[A], 100 - MARGIN);
    assert!(outcome.cursor.index.is_empty());

    let again = run(&server, &outcome.cursor.encode().unwrap(), true).unwrap();
    assert_eq!(again.cursor.rpc[A], 100 - MARGIN);
    let calls = log.lock().unwrap().join("\n");
    assert!(calls.contains(r#""fromBlock":"0x5d""#), "{calls}");
    server.finish();
}

#[test]
fn a_cursor_ahead_of_a_reset_chain_starts_over() {
    let log = Log::default();
    let server = node(&log);
    let stale = format!(r#"{{"index":{{}},"rpc":{{"{A}":5000}}}}"#);
    let outcome = run(&server, &stale, true).unwrap();
    assert_eq!(outcome.entries.len(), 3);
    assert_eq!(outcome.cursor.rpc[A], 100 - MARGIN);
    server.finish();
}

#[test]
fn plain_http_endpoints_are_refused_outside_development() {
    let log = Log::default();
    let server = node(&log);
    assert!(run(&server, "", false).is_err());
    server.finish();
    assert!(log.lock().unwrap().is_empty());
}

#[test]
fn activity_sources_are_named_in_the_order_they_are_tried() {
    let none = |_: &str| false;
    let all = |_: &str| true;
    assert_eq!(sources(1, none), ["RPC"]);
    assert_eq!(sources(1, all), ["Etherscan", "Alchemy", "RPC"]);
    // Keys count only on chains their provider serves.
    assert_eq!(sources(31337, all), ["RPC"]);
    let etherscan = |id: &str| id == "etherscan";
    assert_eq!(sources(137, etherscan), ["Etherscan", "RPC"]);
}

#[test]
fn a_wrong_chain_is_refused_before_any_scan() {
    let log = Log::default();
    let server = node(&log);
    let keys = providers::Keys::new();
    let result = crate::runtime().unwrap().block_on(scan(Request {
        chain: "eip155:1",
        rpc: &server.base,
        keys: &keys,
        assets: &[],
        addresses: &[A.to_string()],
        cursor: Cursor::default(),
        development: true,
    }));
    assert!(result.is_err());
    server.finish();
}

#[test]
fn local_endpoints_are_loopback_or_lan_http_only() {
    assert!(local_endpoint("http://127.0.0.1:8545"));
    assert!(local_endpoint("http://localhost:8545"));
    assert!(local_endpoint("http://192.168.0.2:8545"));
    assert!(!local_endpoint("https://127.0.0.1"));
    assert!(!local_endpoint("http://8.8.8.8:8545"));
    assert!(!local_endpoint("https://rpc.example"));
}

/// A public-RPC-like node at head 5000 whose `eth_getLogs` refuses windows wider than
/// `widest` blocks and blocks older than `oldest`. One incoming transfer at block 4990.
fn strict_node(log: &Log, widest: u64, oldest: u64) -> Server {
    let log = log.clone();
    Server::start(Arc::new(move |_, request| {
        let method = request["method"].as_str().unwrap_or_default();
        let number = |v: &Value| {
            u64::from_str_radix(v.as_str().unwrap().trim_start_matches("0x"), 16).unwrap()
        };
        let result = match method {
            "eth_chainId" => json!("0x7a69"),
            "eth_blockNumber" => json!("0x1388"),
            "eth_getLogs" => {
                let filter = &request["params"][0];
                let (from, to) = (number(&filter["fromBlock"]), number(&filter["toBlock"]));
                log.lock().unwrap().push(format!("{from}-{to}"));
                if to - from + 1 > widest || from < oldest {
                    return (
                        200,
                        json!({"jsonrpc":"2.0","id":1,"error":{"code":-32005,"message":"limit exceeded"}}),
                    );
                }
                if filter["topics"][2].is_array() && (from..=to).contains(&4990) {
                    json!([log_entry(B, A, 7, 4990, 1)])
                } else {
                    json!([])
                }
            }
            "eth_getBlockByNumber" => {
                json!({"number": request["params"][0], "timestamp": "0x6553f100", "transactions": []})
            }
            _ => return (200, json!({"jsonrpc":"2.0","id":1,"error":{"code":-1}})),
        };
        (200, json!({"jsonrpc":"2.0","id":1,"result":result}))
    }))
}

#[test]
fn refused_log_windows_are_halved_until_the_endpoint_answers() {
    let log = Log::default();
    let server = strict_node(&log, 50, 0);
    let outcome = run(&server, "", true).unwrap();
    assert_eq!(outcome.entries.len(), 1);
    assert_eq!(
        (outcome.entries[0].block, outcome.entries[0].amount.as_str()),
        (4990, "7")
    );
    // This pass covered 3000..=4999. The cursor keeps the usual re-check margin.
    assert_eq!(outcome.cursor.rpc[A], 4999 - MARGIN);
    let calls = log.lock().unwrap().clone();
    assert!(calls.first().is_some_and(|c| c == "3000-3499"), "{calls:?}");
    assert!(calls.iter().any(|c| c == "3000-3030"), "{calls:?}");
    server.finish();
}

#[test]
fn an_endpoint_serving_only_recent_logs_is_followed_from_the_recent_blocks() {
    let log = Log::default();
    let server = strict_node(&log, 500, 4900);
    let outcome = run(&server, "", true).unwrap();
    assert_eq!(outcome.entries.len(), 1);
    assert_eq!(outcome.cursor.rpc[A], 5000 - MARGIN);
    assert!(log.lock().unwrap().iter().any(|c| c == "4937-5000"));
    server.finish();
}

#[test]
fn an_endpoint_refusing_every_log_query_is_an_error() {
    let log = Log::default();
    let server = strict_node(&log, 0, 0);
    assert!(run(&server, "", true).is_err());
    server.finish();
}
