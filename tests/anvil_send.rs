//! Send end to end against a local Anvil chain, through the public wallet API only.
//!
//! Ignored by default. Start the chain and run (see docs/apple.md for the local stack):
//!
//! ```text
//! anvil --port 18545 --chain-id 31337 --mnemonic "abandon … abandon art"
//! PAYROOF_E2E_AUTH_BIN=<creation hex of an EIP-2612 + EIP-3009 token>
//! PAYROOF_E2E_PLAIN_BIN=<creation hex of a token with neither standard>
//! PAYROOF_WALLET_LOCAL_DEVELOPMENT=1 cargo test --locked --features local-development \
//!   --test anvil_send -- --ignored --test-threads=1
//! ```
//!
//! The account is slot 0 of the test mnemonic (`m/44'/60'/0'/0/i`). Anvil's own unlocked
//! accounts are the same keys, so account 9 (never part of the wallet) funds and deploys.

use payroof_wallet_core::ffi::{Wallet, local_development_enabled};
use serde_json::{Value, json};
use std::sync::{Arc, Mutex, MutexGuard, OnceLock};

const DEFAULT_RPC: &str = "http://127.0.0.1:18545";
const CHAIN: &str = "eip155:31337";
const MNEMONIC: &str = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art";
const PIN: &str = "123456";
const ONE: u128 = 1_000_000_000_000_000_000;
const RECIPIENT: &str = "0x1111111111111111111111111111111111111111";

/// Scenarios share one chain and one wallet account. They run one at a time.
static CHAIN_LOCK: Mutex<()> = Mutex::new(());

fn serial() -> MutexGuard<'static, ()> {
    CHAIN_LOCK
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

fn rpc_url() -> String {
    std::env::var("PAYROOF_E2E_RPC").unwrap_or_else(|_| DEFAULT_RPC.into())
}

fn rpc(method: &str, params: Value) -> Value {
    static RT: OnceLock<tokio::runtime::Runtime> = OnceLock::new();
    let rt = RT.get_or_init(|| {
        tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("runtime")
    });
    let url = rpc_url();
    rt.block_on(async move {
        let body: Value = reqwest::Client::new()
            .post(url)
            .json(&json!({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}))
            .send()
            .await
            .expect("rpc request")
            .json()
            .await
            .expect("rpc json");
        assert!(body.get("error").is_none(), "{method}: {body}");
        body["result"].clone()
    })
}

fn hex_u128(v: &Value) -> u128 {
    u128::from_str_radix(v.as_str().expect("hex").trim_start_matches("0x"), 16).expect("u128")
}

fn pad(addr: &str) -> String {
    format!("{:0>64}", addr.trim_start_matches("0x").to_lowercase())
}

fn eth(addr: &str) -> u128 {
    hex_u128(&rpc("eth_getBalance", json!([addr, "latest"])))
}

fn set_eth(addr: &str, wei: u128) {
    rpc("anvil_setBalance", json!([addr, format!("0x{wei:x}")]));
}

fn token_balance(token: &str, addr: &str) -> u128 {
    let data = format!("0x70a08231{}", pad(addr));
    hex_u128(&rpc(
        "eth_call",
        json!([{"to": token, "data": data}, "latest"]),
    ))
}

/// Sends from the funder account (Anvil account 9, outside the wallet) and waits for the receipt.
fn funder_tx(to: Option<&str>, data: &str) -> Value {
    let accounts = rpc("eth_accounts", json!([]));
    let mut tx = json!({"from": accounts[9], "data": data, "gas": "0x7a1200"});
    if let Some(to) = to {
        tx["to"] = json!(to);
    }
    let hash = rpc("eth_sendTransaction", json!([tx]));
    let receipt = rpc("eth_getTransactionReceipt", json!([hash]));
    assert_eq!(
        receipt["status"], "0x1",
        "funder tx {hash} failed: {receipt}"
    );
    receipt
}

fn deploy(env: &str) -> String {
    let path =
        std::env::var(env).unwrap_or_else(|_| panic!("set {env} to a creation-code hex file"));
    let code = std::fs::read_to_string(path).expect("read bytecode");
    let data = format!("0x{}", code.trim().trim_start_matches("0x"));
    funder_tx(None, &data)["contractAddress"]
        .as_str()
        .expect("contract address")
        .to_string()
}

fn mint(token: &str, to: &str, amount: u128) {
    let data = format!("0x40c10f19{}{:064x}", pad(to), amount);
    funder_tx(Some(token), &data);
}

/// A wallet whose slot 0 holds the test account. The first address is `m/44'/60'/0'/0/0`.
fn wallet() -> Arc<Wallet> {
    let w = Wallet::create(MNEMONIC.into(), PIN.into()).expect("create");
    w.unlock(PIN.into()).expect("unlock");
    assert_eq!(w.add_project("e2e".into(), Some(0)).expect("project"), 0);
    w
}

fn address(w: &Wallet, index: u32) -> String {
    let v: Value =
        serde_json::from_str(&w.address(0, Some(index)).expect("address")).expect("json");
    assert_eq!(v["path"], format!("m/44'/60'/0'/0/{index}"));
    v["address"].as_str().expect("address").to_string()
}

fn plan(w: &Wallet, request: &Value) -> Value {
    let out = w
        .plan_send(rpc_url(), request.to_string(), false)
        .expect("plan_send");
    serde_json::from_str(&out).expect("plan json")
}

fn num(v: &Value) -> u128 {
    v.as_str().expect("decimal string").parse().expect("u128")
}

/// Confirms the plan and executes every step in order. Returns the transaction hashes.
fn execute(w: &Wallet, plan: &Value) -> Vec<String> {
    w.confirm_plan(true).expect("confirm");
    let steps = plan["plan"]["steps"].as_array().expect("steps");
    (0..steps.len())
        .map(|i| {
            w.execute_step(u32::try_from(i).expect("step index"))
                .expect("execute_step")
        })
        .collect()
}

struct Sent {
    from: String,
    value: u128,
    gas_cost: u128,
}

/// Each transaction: sender, native value moved, and gas paid (receipt gasUsed × price).
fn sent(hash: &str) -> Sent {
    let tx = rpc("eth_getTransactionByHash", json!([hash]));
    let receipt = rpc("eth_getTransactionReceipt", json!([hash]));
    assert_eq!(receipt["status"], "0x1", "step reverted: {receipt}");
    Sent {
        from: tx["from"].as_str().unwrap().to_lowercase(),
        value: hex_u128(&tx["value"]),
        gas_cost: hex_u128(&receipt["gasUsed"]) * hex_u128(&receipt["effectiveGasPrice"]),
    }
}

/// Every step mined within its reviewed gas limit and fee. Returns the sent transactions.
fn check_steps(plan: &Value, hashes: &[String]) -> Vec<Sent> {
    let steps = plan["plan"]["steps"].as_array().unwrap();
    assert_eq!(steps.len(), hashes.len());
    let txs: Vec<Sent> = hashes.iter().map(|h| sent(h)).collect();
    for ((step, hash), tx) in steps.iter().zip(hashes).zip(&txs) {
        let r = rpc("eth_getTransactionReceipt", json!([hash]));
        assert!(
            hex_u128(&r["gasUsed"]) <= step["gas_limit"].as_str().unwrap().parse::<u128>().unwrap()
        );
        assert!(
            tx.gas_cost <= num(&step["maximum_fee"]),
            "step fee above its reviewed maximum"
        );
    }
    let total: u128 = txs.iter().map(|t| t.gas_cost).sum();
    assert!(
        total <= num(&plan["plan"]["maximum_fee"]),
        "total gas above reviewed maximum_fee"
    );
    txs
}

fn token_request(token: &str, amount: &str) -> Value {
    json!({"chain": CHAIN, "asset": format!("{CHAIN}/erc20:{token}"), "to": RECIPIENT, "amount": amount, "slot": 0})
}

fn sponsor_gas_and_value(txs: &[Sent], who: &str) -> u128 {
    txs.iter()
        .filter(|t| t.from == who.to_lowercase())
        .map(|t| t.gas_cost + t.value)
        .sum()
}

#[test]
#[ignore = "needs Anvil on 18545 and PAYROOF_WALLET_LOCAL_DEVELOPMENT=1 with --features local-development"]
fn authorization_spreads_4_5_over_five_sources_sponsored() {
    let _s = serial();
    assert!(
        local_development_enabled(),
        "run with the local-development feature and env"
    );
    let w = wallet();
    let accounts = rpc("eth_accounts", json!([]));
    assert_eq!(
        accounts[0].as_str().unwrap().to_lowercase(),
        address(&w, 0).to_lowercase()
    );
    let token = deploy("PAYROOF_E2E_AUTH_BIN");
    let sources: Vec<String> = (0..5).map(|i| address(&w, i)).collect();
    let sponsor = address(&w, 5);
    for s in &sources {
        set_eth(s, 0);
        mint(&token, s, ONE);
    }
    set_eth(&sponsor, 10 * ONE);
    let sponsor_before = eth(&sponsor);

    let p = plan(&w, &token_request(&token, "4500000000000000000"));
    assert!(p.get("problem").is_none(), "unexpected problem: {p}");
    assert_eq!(
        p["plan"]["sponsor"]["address"]
            .as_str()
            .unwrap()
            .to_lowercase(),
        sponsor.to_lowercase()
    );
    let steps = p["plan"]["steps"].as_array().unwrap();
    assert_eq!(
        p["plan"]["sources"].as_array().unwrap().len(),
        5,
        "4.5 of 5x1 needs five legs"
    );
    assert_eq!(steps.len(), 5);
    let planned: u128 = steps.iter().map(|s| num(&s["amount"])).sum();
    assert_eq!(planned, 4_500_000_000_000_000_000);
    for s in steps {
        assert_eq!(s["kind"], "authorization");
        assert_eq!(
            s["payer"].as_str().unwrap().to_lowercase(),
            sponsor.to_lowercase()
        );
        assert_eq!(s["to"].as_str().unwrap().to_lowercase(), RECIPIENT);
    }

    let hashes = execute(&w, &p);
    let txs = check_steps(&p, &hashes);

    assert_eq!(token_balance(&token, RECIPIENT), 4_500_000_000_000_000_000);
    for s in steps {
        let owner = s["owner"].as_str().unwrap();
        let amount = num(&s["amount"]);
        assert_eq!(
            token_balance(&token, owner),
            ONE - amount,
            "source drained as planned"
        );
    }
    assert_eq!(
        sponsor_before - eth(&sponsor),
        sponsor_gas_and_value(&txs, &sponsor),
        "sponsor paid exactly the gas of the five submissions"
    );
}

#[test]
#[ignore = "needs Anvil on 18545 and PAYROOF_WALLET_LOCAL_DEVELOPMENT=1 with --features local-development"]
fn top_up_then_transfer_for_token_without_standards() {
    let _s = serial();
    assert!(
        local_development_enabled(),
        "run with the local-development feature and env"
    );
    let w = wallet();
    let token = deploy("PAYROOF_E2E_PLAIN_BIN");
    let sources: Vec<String> = (0..5).map(|i| address(&w, i)).collect();
    let sponsor = address(&w, 5);
    for s in &sources {
        set_eth(s, 0);
        mint(&token, s, ONE);
    }
    set_eth(&sponsor, 10 * ONE);
    let sponsor_before = eth(&sponsor);

    let p = plan(&w, &token_request(&token, "4500000000000000000"));
    assert!(p.get("problem").is_none(), "unexpected problem: {p}");
    let steps = p["plan"]["steps"].as_array().unwrap();
    let tops: Vec<&Value> = steps.iter().filter(|s| s["kind"] == "top_up").collect();
    let transfers: Vec<&Value> = steps.iter().filter(|s| s["kind"] == "transfer").collect();
    assert_eq!(tops.len(), 5, "one exact top-up per source");
    assert_eq!(transfers.len(), 5);
    for t in &transfers {
        let dep =
            usize::try_from(t["after"][0].as_u64().expect("dependency")).expect("dependency index");
        assert_eq!(steps[dep]["kind"], "top_up");
        assert_eq!(
            steps[dep]["to"], t["owner"],
            "transfer waits for its own top-up"
        );
    }

    let hashes = execute(&w, &p);
    let txs = check_steps(&p, &hashes);

    assert_eq!(token_balance(&token, RECIPIENT), 4_500_000_000_000_000_000);
    for s in &transfers {
        let owner = s["owner"].as_str().unwrap();
        assert_eq!(token_balance(&token, owner), ONE - num(&s["amount"]));
    }
    // Each source got exactly its top-up and spent gas from it. Nothing else.
    for s in &sources {
        let received: u128 = tops
            .iter()
            .filter(|t| t["to"].as_str().unwrap().eq_ignore_ascii_case(s))
            .map(|t| num(&t["amount"]))
            .sum();
        let spent: u128 = txs
            .iter()
            .filter(|t| t.from == s.to_lowercase())
            .map(|t| t.gas_cost)
            .sum();
        assert_eq!(
            eth(s),
            received - spent,
            "source native balance is top-up minus its own gas"
        );
    }
    let sponsor_outlay: u128 = tops.iter().map(|t| num(&t["amount"])).sum();
    assert_eq!(
        sponsor_before - eth(&sponsor),
        sponsor_gas_and_value(&txs, &sponsor)
    );
    assert!(sponsor_outlay > 0);
}

#[test]
#[ignore = "needs Anvil on 18545 and PAYROOF_WALLET_LOCAL_DEVELOPMENT=1 with --features local-development"]
fn native_multi_source_each_source_pays_its_own_fee() {
    let _s = serial();
    assert!(
        local_development_enabled(),
        "run with the local-development feature and env"
    );
    let w = wallet();
    let sources: Vec<String> = (0..5).map(|i| address(&w, i)).collect();
    let sponsor = address(&w, 5);
    set_eth(&sponsor, 0);
    for (i, s) in sources.iter().enumerate() {
        set_eth(s, if i < 3 { ONE / 100 } else { 0 });
    }
    let recipient_before = eth(RECIPIENT);

    let p = plan(
        &w,
        &json!({"chain": CHAIN, "asset": format!("{CHAIN}/slip44:60"), "to": RECIPIENT, "amount": "15000000000000000", "slot": 0}),
    );
    assert!(p.get("problem").is_none(), "unexpected problem: {p}");
    let steps = p["plan"]["steps"].as_array().unwrap();
    assert_eq!(steps.len(), 2, "two 0.01 balances cover 0.015");
    for s in steps {
        assert_eq!(s["kind"], "transfer");
        assert_eq!(s["payer"], s["owner"], "native sources pay their own fee");
    }
    assert_eq!(
        num(&steps[0]["amount"]) + num(&steps[1]["amount"]),
        15_000_000_000_000_000
    );

    let before: Vec<u128> = steps
        .iter()
        .map(|s| eth(s["owner"].as_str().unwrap()))
        .collect();
    let hashes = execute(&w, &p);
    let txs = check_steps(&p, &hashes);

    assert_eq!(
        eth(RECIPIENT) - recipient_before,
        15_000_000_000_000_000,
        "recipient exact"
    );
    for (i, s) in steps.iter().enumerate() {
        let owner = s["owner"].as_str().unwrap();
        let paid: u128 = txs
            .iter()
            .filter(|t| t.from == owner.to_lowercase())
            .map(|t| t.gas_cost)
            .sum();
        assert_eq!(
            eth(owner),
            before[i] - num(&s["amount"]) - paid,
            "source drained as planned"
        );
    }
}

#[test]
#[ignore = "needs Anvil on 18545 and PAYROOF_WALLET_LOCAL_DEVELOPMENT=1 with --features local-development"]
fn no_sponsor_is_a_structured_problem() {
    let _s = serial();
    assert!(
        local_development_enabled(),
        "run with the local-development feature and env"
    );
    let w = wallet();
    let token = deploy("PAYROOF_E2E_AUTH_BIN");
    for i in 0..5 {
        let s = address(&w, i);
        set_eth(&s, 0);
        mint(&token, &s, ONE);
    }
    set_eth(&address(&w, 5), 0);

    let p = plan(&w, &token_request(&token, "100000000000000000"));
    let problem = &p["problem"];
    assert_eq!(problem["code"], "no_sponsor", "got {p}");
    assert_eq!(num(&problem["held"]), 0);
    assert!(num(&problem["needed"]) > 0);
    assert!(p.get("plan").is_none());
    assert!(
        w.confirm_plan(true).is_err(),
        "no plan may be confirmed after a problem"
    );
}

#[test]
#[ignore = "needs Anvil on 18545 and PAYROOF_WALLET_LOCAL_DEVELOPMENT=1 with --features local-development"]
fn steps_run_in_order_and_lock_discards_the_plan() {
    let _s = serial();
    assert!(
        local_development_enabled(),
        "run with the local-development feature and env"
    );
    let w = wallet();
    let token = deploy("PAYROOF_E2E_AUTH_BIN");
    for i in 0..5 {
        let s = address(&w, i);
        set_eth(&s, 0);
        mint(&token, &s, ONE);
    }
    set_eth(&address(&w, 5), 10 * ONE);

    let p = plan(&w, &token_request(&token, "4500000000000000000"));
    assert!(p.get("plan").is_some(), "unexpected problem: {p}");
    w.confirm_plan(true).expect("confirm");
    assert!(
        w.execute_step(2).is_err(),
        "out-of-order step must be refused"
    );
    assert!(w.execute_step(0).is_err(), "a refused step ends the plan");

    let p = plan(&w, &token_request(&token, "4500000000000000000"));
    w.confirm_plan(true).expect("confirm");
    w.lock();
    w.unlock(PIN.into()).expect("unlock");
    assert!(
        w.execute_step(0).is_err(),
        "locking discards the reviewed plan"
    );
    assert_eq!(token_balance(&token, RECIPIENT), 0, "nothing moved");
    assert!(p.get("plan").is_some());
}
