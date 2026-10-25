use super::*;
use crate::abi::keccak;
use crate::test_support::{Server, recover};
use serde_json::Value;
use std::sync::{Arc, Mutex};

const WORDS: &str =
    "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
const TOKEN: &str = "0x00000000000000000000000000000000000000c3";
const RECIPIENT: &str = "0x00000000000000000000000000000000000000ee";
const CHAIN: &str = "eip155:31337";
const ETHER: u128 = 1_000_000_000_000_000_000;
// Fees: priority 1 gwei, base fee 10 gwei, so the maximum is 21 gwei per gas.
const MAX_FEE: u64 = 21_000_000_000;

fn path(index: usize) -> String {
    format!("m/44'/60'/0'/0/{index}")
}

fn address(index: usize) -> String {
    crate::derivation::address(WORDS, "", &path(index)).unwrap()
}

fn account() -> Vec<(String, String)> {
    (0..3).map(|i| (path(i), address(i))).collect()
}

fn token_asset() -> String {
    format!("{CHAIN}/erc20:{TOKEN}")
}

fn request(asset: &str, amount: &str) -> Request {
    Request {
        chain: CHAIN.into(),
        asset: asset.into(),
        to: RECIPIENT.into(),
        amount: amount.into(),
        slot: 0,
        prefer: None,
    }
}

/// What the fake node knows and has been asked.
#[allow(
    clippy::struct_field_names,
    reason = "the fields mirror the node's own vocabulary, and `id` alone would read as ambiguous"
)]
struct Chain {
    chain_id: u64,
    token: BTreeMap<String, u128>,
    native: BTreeMap<String, u128>,
    authorization: bool,
    permit: bool,
    authorization_gas: u64,
    sent: Vec<Vec<u8>>,
    /// Transaction hash -> mined successfully. Absent while pending.
    mined: BTreeMap<String, bool>,
    calls: Vec<String>,
}

impl Chain {
    fn new() -> Self {
        Self {
            chain_id: 31337,
            token: BTreeMap::new(),
            native: BTreeMap::new(),
            authorization: false,
            permit: false,
            authorization_gas: 90_000,
            sent: Vec::new(),
            mined: BTreeMap::new(),
            calls: Vec::new(),
        }
    }
}

fn token_domain() -> eip712::Domain {
    eip712::Domain {
        name: "USD Coin".into(),
        version: "2".into(),
        chain_id: BigUint::from(31337u32),
        contract: TOKEN.into(),
    }
}

fn abi_string(text: &str) -> String {
    let padded = text.len().div_ceil(32) * 32;
    format!(
        "0x{:064x}{:064x}{}{}",
        32,
        text.len(),
        hex::encode(text),
        "0".repeat((padded - text.len()) * 2)
    )
}

fn word(value: u128) -> Value {
    json!(format!("0x{value:064x}"))
}

struct Node {
    server: Server,
    chain: Arc<Mutex<Chain>>,
}

impl Node {
    fn start(chain: Chain) -> Self {
        let chain = Arc::new(Mutex::new(chain));
        let shared = chain.clone();
        let server = Server::start(Arc::new(move |_, request| {
            let mut chain = shared.lock().unwrap();
            let method = request["method"].as_str().unwrap_or_default().to_string();
            chain.calls.push(method.clone());
            let params = &request["params"];
            let failure =
                || json!({"jsonrpc":"2.0","id":1,"error":{"code":3,"message":"reverted"}});
            let result = match method.as_str() {
                "eth_chainId" => json!(format!("0x{:x}", chain.chain_id)),
                "eth_gasPrice" | "eth_maxPriorityFeePerGas" => json!("0x3b9aca00"),
                "eth_getBlockByNumber" => json!({"baseFeePerGas": "0x2540be400"}),
                "eth_getTransactionCount" => json!("0x5"),
                "eth_getBalance" => {
                    let who = params[0].as_str().unwrap();
                    json!(format!(
                        "0x{:x}",
                        chain.native.get(who).copied().unwrap_or(0)
                    ))
                }
                "eth_estimateGas" => {
                    let data = params[0]["data"].as_str().unwrap();
                    let gas = if data.starts_with("0xe3ee160e") {
                        chain.authorization_gas
                    } else if data == "0x" {
                        21_000
                    } else {
                        50_000
                    };
                    json!(format!("0x{gas:x}"))
                }
                "eth_sendRawTransaction" => {
                    let raw =
                        hex::decode(params[0].as_str().unwrap().trim_start_matches("0x")).unwrap();
                    let hash = format!("0x{}", hex::encode(keccak(&raw)));
                    chain.sent.push(raw);
                    json!(hash)
                }
                "eth_getTransactionReceipt" => match chain.mined.get(params[0].as_str().unwrap()) {
                    Some(ok) => json!({"status": if *ok { "0x1" } else { "0x0" }}),
                    None => Value::Null,
                },
                "eth_call" => {
                    assert_eq!(params[0]["to"], TOKEN);
                    let data = params[0]["data"].as_str().unwrap();
                    let argument = data
                        .get(34..74)
                        .map(|a| format!("0x{a}"))
                        .unwrap_or_default();
                    match &data[2..10] {
                        "70a08231" => word(chain.token.get(&argument).copied().unwrap_or(0)),
                        "3644e515" if chain.authorization || chain.permit => {
                            json!(format!(
                                "0x{}",
                                hex::encode(token_domain().separator().unwrap())
                            ))
                        }
                        "06fdde03" => json!(abi_string("USD Coin")),
                        "54fd4d50" => json!(abi_string("2")),
                        "e94a0102" if chain.authorization => word(0),
                        "7ecebe00" if chain.permit => word(0),
                        _ => return (200, failure()),
                    }
                }
                _ => return (200, failure()),
            };
            (200, json!({"jsonrpc":"2.0","id":1,"result":result}))
        }));
        Self { server, chain }
    }
    fn url(&self) -> String {
        self.server.base.clone()
    }
    fn chain(&self) -> std::sync::MutexGuard<'_, Chain> {
        self.chain.lock().unwrap()
    }
    fn plan(&self, asset: &str, amount: &str, mode: Mode) -> anyhow::Result<Created> {
        crate::runtime().unwrap().block_on(create(
            &self.url(),
            &request(asset, amount),
            &account(),
            mode,
            true,
        ))
    }
    fn state(&self, asset: &str, amount: &str) -> PlanState {
        match self.plan(asset, amount, Mode::Eip1559).unwrap() {
            Created::Plan(state) => *state,
            Created::Problem(problem) => panic!("{problem}"),
        }
    }
}

fn execute(state: &mut PlanState, index: usize) -> anyhow::Result<String> {
    crate::runtime()
        .unwrap()
        .block_on(state.execute(index, WORDS, ""))
}

/// A sent EIP-1559 transaction taken apart: the fields and who signed it.
struct Sent {
    nonce: u64,
    gas: u64,
    to: String,
    value: BigUint,
    data: Vec<u8>,
    signer: String,
}

fn item(data: &[u8]) -> (usize, usize) {
    let long = |base: u8| {
        let n = (data[0] - base) as usize;
        (
            1 + n,
            data[1..=n].iter().fold(0usize, |l, b| l << 8 | *b as usize),
        )
    };
    match data[0] {
        0..=0x7f => (0, 1),
        0x80..=0xb7 => (1, (data[0] - 0x80) as usize),
        0xb8..=0xbf => long(0xb7),
        0xc0..=0xf7 => (1, (data[0] - 0xc0) as usize),
        _ => long(0xf7),
    }
}

/// The items of an RLP list as (whole encoding, payload).
fn items(list: &[u8]) -> Vec<(&[u8], &[u8])> {
    let (header, length) = item(list);
    let mut rest = &list[header..header + length];
    let mut out = Vec::new();
    while !rest.is_empty() {
        let (h, l) = item(rest);
        out.push((&rest[..h + l], &rest[h..h + l]));
        rest = &rest[h + l..];
    }
    out
}

fn number(payload: &[u8]) -> BigUint {
    BigUint::from_bytes_be(payload)
}

fn pad(payload: &[u8]) -> [u8; 32] {
    let mut out = [0u8; 32];
    out[32 - payload.len()..].copy_from_slice(payload);
    out
}

fn decode(raw: &[u8]) -> Sent {
    assert_eq!(raw[0], 2, "EIP-1559 transaction");
    let fields = items(&raw[1..]);
    assert_eq!(fields.len(), 12);
    let body: Vec<u8> = fields[..9]
        .iter()
        .flat_map(|(e, _)| e.iter().copied())
        .collect();
    let mut unsigned = vec![2];
    unsigned.extend(if body.len() < 56 {
        vec![0xc0 + u8::try_from(body.len()).unwrap()]
    } else {
        let length = BigUint::from(body.len()).to_bytes_be();
        let mut header = vec![0xf7 + u8::try_from(length.len()).unwrap()];
        header.extend(length);
        header
    });
    unsigned.extend(&body);
    let digest = keccak(&unsigned);
    let mut signature = [0u8; 64];
    signature[..32].copy_from_slice(&pad(fields[10].1));
    signature[32..].copy_from_slice(&pad(fields[11].1));
    let parity = fields[9].1.first().copied().unwrap_or(0);
    Sent {
        nonce: u64::try_from(number(fields[1].1)).unwrap(),
        gas: u64::try_from(number(fields[4].1)).unwrap(),
        to: format!("0x{}", hex::encode(fields[5].1)),
        value: number(fields[6].1),
        data: fields[7].1.to_vec(),
        signer: recover(&digest, &signature, parity),
    }
}

fn hash_of(raw: &[u8]) -> String {
    format!("0x{}", hex::encode(keccak(raw)))
}

#[test]
fn authorization_plan_is_signed_by_the_owner_and_paid_by_the_sponsor() {
    let mut chain = Chain::new();
    chain.authorization = true;
    chain.token.insert(address(0), 600);
    chain.token.insert(address(1), 400);
    chain.native.insert(address(1), ETHER);
    let node = Node::start(chain);
    let mut state = node.state(&token_asset(), "1000");

    let plan = state.review().clone();
    let kinds: Vec<_> = plan.steps.iter().map(|s| s.kind).collect();
    assert_eq!(kinds, [Kind::Authorization, Kind::Transfer]);
    assert_eq!(plan.sponsor.as_ref().unwrap().address, address(1));
    assert_eq!(plan.max_fee_per_gas, BigUint::from(MAX_FEE));
    // 150_000 reviewed for the authorization, 50_000 estimated + 25% for the transfer.
    assert_eq!(
        plan.maximum_fee,
        BigUint::from((150_000u64 + 62_500) * MAX_FEE)
    );
    let json = serde_json::to_value(&plan).unwrap();
    assert_eq!(json["network"], CHAIN);
    assert_eq!(json["steps"][0]["kind"], "authorization");
    assert_eq!(json["steps"][0]["gas_limit"], "150000");
    assert_eq!(json["sources"][1]["amount"], "400");
    // Nothing is signed or sent while the plan is only a review.
    assert_eq!(node.chain().sent, [] as [std::vec::Vec<u8>; 0]);
    assert!(execute(&mut state, 0).is_err(), "unconfirmed plan");
    state.confirm();
    assert!(execute(&mut state, 1).is_err(), "steps run in order");
    assert_eq!(node.chain().sent, [] as [std::vec::Vec<u8>; 0]);

    let first = execute(&mut state, 0).unwrap();
    let second = execute(&mut state, 1).unwrap();
    assert!(state.finished());
    assert!(execute(&mut state, 2).is_err());
    let sent = node.chain().sent.clone();
    assert_eq!(sent.len(), 2);
    assert_eq!((first, second), (hash_of(&sent[0]), hash_of(&sent[1])));

    // The sponsor submits both. Its nonces follow each other though the node still
    // reports the same pending count.
    let (a, b) = (decode(&sent[0]), decode(&sent[1]));
    assert_eq!(
        (a.signer.as_str(), b.signer.as_str()),
        (address(1).as_str(), address(1).as_str())
    );
    assert_eq!((a.nonce, b.nonce), (5, 6));
    assert_eq!((a.to.as_str(), b.to.as_str()), (TOKEN, TOKEN));
    assert_eq!((a.gas, b.gas), (150_000, 62_500));
    assert_eq!(a.value, BigUint::default());
    assert_eq!(
        b.data,
        abi::transfer(RECIPIENT, &BigUint::from(400u32)).unwrap()
    );

    // The first call is transferWithAuthorization signed by the owner (address 0)
    // for the recipient and the exact amount, valid for a short while.
    assert_eq!(&a.data[..4], &[0xe3, 0xee, 0x16, 0x0e]);
    let arg = |i: usize| &a.data[4 + 32 * i..4 + 32 * (i + 1)];
    assert_eq!(arg(0), abi::word_address(&address(0)).unwrap());
    assert_eq!(arg(1), abi::word_address(RECIPIENT).unwrap());
    assert_eq!(number(arg(2)), BigUint::from(600u32));
    assert_eq!(number(arg(3)), BigUint::default());
    let valid_before = u64::try_from(number(arg(4))).unwrap();
    let now = unix_now().unwrap();
    assert!((now + 800..=now + SIGNATURE_LIFETIME).contains(&valid_before));
    let nonce: [u8; 32] = arg(5).try_into().unwrap();
    assert_ne!(nonce, [0u8; 32]);
    let value = BigUint::from(600u32);
    let digest = eip712::Transfer {
        from: &address(0),
        to: RECIPIENT,
        value: &value,
        valid_after: 0,
        valid_before,
        nonce,
    }
    .digest(&token_domain().separator().unwrap())
    .unwrap();
    let mut signature = [0u8; 64];
    signature[..32].copy_from_slice(arg(7));
    signature[32..].copy_from_slice(arg(8));
    let v = arg(6)[31];
    assert_eq!(recover(&digest, &signature, v - 27), address(0));
}

#[test]
fn permit_waits_for_its_receipt_and_is_signed_for_the_sponsor() {
    let mut chain = Chain::new();
    chain.permit = true;
    chain.token.insert(address(0), 1000);
    chain.native.insert(address(2), ETHER);
    let node = Node::start(chain);
    let mut state = node.state(&token_asset(), "1000");
    let kinds: Vec<_> = state.review().steps.iter().map(|s| s.kind).collect();
    assert_eq!(kinds, [Kind::Permit, Kind::TransferFrom]);
    assert_eq!(state.review().steps[1].after, [0]);
    state.confirm();

    let permit = execute(&mut state, 0).unwrap();
    // The permit is not mined yet: the plan waits, and nothing more is sent.
    let error = execute(&mut state, 1).unwrap_err();
    assert!(error.is::<Pending>());
    assert_eq!(node.chain().sent.len(), 1);
    node.chain().mined.insert(permit, true);
    execute(&mut state, 1).unwrap();
    assert!(state.finished());

    let sent = node.chain().sent.clone();
    let (permit, transfer) = (decode(&sent[0]), decode(&sent[1]));
    assert_eq!(
        (permit.signer.as_str(), transfer.signer.as_str()),
        (address(2).as_str(), address(2).as_str())
    );
    assert_eq!((permit.nonce, transfer.nonce), (5, 6));
    assert_eq!((permit.gas, transfer.gas), (120_000, 120_000));
    assert_eq!(
        transfer.data,
        abi::transfer_from(&address(0), RECIPIENT, &BigUint::from(1000u32)).unwrap()
    );
    // permit(owner, spender = sponsor, exact value, deadline, v, r, s), signed by the owner.
    let arg = |i: usize| &permit.data[4 + 32 * i..4 + 32 * (i + 1)];
    assert_eq!(&permit.data[..4], &[0xd5, 0x05, 0xac, 0xcf]);
    assert_eq!(arg(0), abi::word_address(&address(0)).unwrap());
    assert_eq!(arg(1), abi::word_address(&address(2)).unwrap());
    assert_eq!(number(arg(2)), BigUint::from(1000u32));
    let deadline = u64::try_from(number(arg(3))).unwrap();
    assert!(deadline <= unix_now().unwrap() + SIGNATURE_LIFETIME);
    let (value, nonce) = (BigUint::from(1000u32), BigUint::default());
    let digest = eip712::Permit {
        owner: &address(0),
        spender: &address(2),
        value: &value,
        nonce: &nonce,
        deadline,
    }
    .digest(&token_domain().separator().unwrap())
    .unwrap();
    let mut signature = [0u8; 64];
    signature[..32].copy_from_slice(arg(5));
    signature[32..].copy_from_slice(arg(6));
    assert_eq!(recover(&digest, &signature, arg(4)[31] - 27), address(0));
}

#[test]
fn top_up_funds_the_exact_fee_and_the_transfer_waits_for_it() {
    let mut chain = Chain::new();
    chain.token.insert(address(0), 1000);
    chain.native.insert(address(1), ETHER);
    let node = Node::start(chain);
    let mut state = node.state(&token_asset(), "1000");
    let plan = state.review().clone();
    let kinds: Vec<_> = plan.steps.iter().map(|s| s.kind).collect();
    assert_eq!(kinds, [Kind::TopUp, Kind::Transfer]);
    // The source holds nothing, so the top-up is the whole fee of its transfer.
    let fee = BigUint::from(62_500u64 * MAX_FEE);
    assert_eq!(plan.steps[0].amount, fee);
    assert_eq!(plan.steps[0].to, address(0));
    assert_eq!(plan.steps[0].gas_limit, BigUint::from(26_250u32));
    state.confirm();

    let top_up = execute(&mut state, 0).unwrap();
    assert!(execute(&mut state, 1).unwrap_err().is::<Pending>());
    // A failed top-up ends the plan: the error is not the retryable kind.
    node.chain().mined.insert(top_up.clone(), false);
    let error = execute(&mut state, 1).unwrap_err();
    assert!(!error.is::<Pending>());
    assert_eq!(node.chain().sent.len(), 1);

    // Once mined (and the node shows the coin), the source pays its own transfer.
    node.chain().mined.insert(top_up, true);
    node.chain()
        .native
        .insert(address(0), fee.to_string().parse().unwrap());
    execute(&mut state, 1).unwrap();
    let sent = node.chain().sent.clone();
    let (first, second) = (decode(&sent[0]), decode(&sent[1]));
    assert_eq!(first.signer, address(1));
    assert_eq!(first.to, address(0));
    assert_eq!(first.value, fee);
    assert_eq!(first.data, [] as [u8; 0]);
    assert_eq!(second.signer, address(0));
    assert_eq!(second.nonce, 5);
    assert_eq!(second.to, TOKEN);
    assert_eq!(
        second.data,
        abi::transfer(RECIPIENT, &BigUint::from(1000u32)).unwrap()
    );
}

#[test]
fn a_call_above_the_reviewed_ceiling_is_refused_before_broadcast() {
    let mut chain = Chain::new();
    chain.authorization = true;
    chain.token.insert(address(0), 100);
    chain.native.insert(address(1), ETHER);
    let node = Node::start(chain);
    let mut state = node.state(&token_asset(), "100");
    assert_eq!(state.review().steps[0].kind, Kind::Authorization);
    state.confirm();
    node.chain().authorization_gas = 150_001;
    // The node's estimate of the signed call (which also validates the signature on
    // chain) is what is checked, not a fixed assumption.
    assert!(execute(&mut state, 0).is_err());
    assert_eq!(node.chain().sent, [] as [std::vec::Vec<u8>; 0]);
}

#[test]
fn an_expired_quote_signs_nothing() {
    let mut chain = Chain::new();
    chain.token.insert(address(0), 100);
    chain.native.insert(address(0), ETHER);
    let node = Node::start(chain);
    let mut state = node.state(&token_asset(), "100");
    state.confirm();
    state.created = Instant::now()
        .checked_sub(Duration::from_secs(121))
        .unwrap();
    assert!(execute(&mut state, 0).is_err());
    state.created = Instant::now();
    assert!(
        !node
            .chain()
            .calls
            .contains(&"eth_sendRawTransaction".to_string())
    );
    execute(&mut state, 0).unwrap();
}

#[test]
fn a_chain_change_is_noticed_when_a_step_runs() {
    let mut chain = Chain::new();
    chain.token.insert(address(0), 100);
    chain.native.insert(address(0), ETHER);
    let node = Node::start(chain);
    let mut state = node.state(&token_asset(), "100");
    state.confirm();
    node.chain().chain_id = 1;
    assert!(execute(&mut state, 0).is_err());
    assert_eq!(node.chain().sent, [] as [std::vec::Vec<u8>; 0]);
}

#[test]
fn native_coin_sends_pay_each_sources_own_fee() {
    let mut chain = Chain::new();
    chain.native.insert(address(0), 2 * ETHER);
    chain.native.insert(address(1), ETHER);
    let node = Node::start(chain);
    let native = format!("{CHAIN}/slip44:60");
    let amount = (2 * ETHER + ETHER / 2).to_string();
    let mut state = node.state(&native, &amount);
    let plan = state.review().clone();
    assert!(plan.sponsor.is_none());
    assert_eq!(plan.sources.len(), 2);
    let fee = BigUint::from(26_250u64 * MAX_FEE);
    assert_eq!(plan.sources[0].amount, BigUint::from(2 * ETHER) - &fee);
    assert_eq!(plan.sources[1].amount, BigUint::from(ETHER / 2) + &fee);
    state.confirm();
    execute(&mut state, 0).unwrap();
    execute(&mut state, 1).unwrap();
    let sent = node.chain().sent.clone();
    let (a, b) = (decode(&sent[0]), decode(&sent[1]));
    assert_eq!(
        (a.signer.as_str(), b.signer.as_str()),
        (address(0).as_str(), address(1).as_str())
    );
    assert_eq!((a.to.as_str(), b.to.as_str()), (RECIPIENT, RECIPIENT));
    assert_eq!(a.value + b.value, BigUint::from(2 * ETHER + ETHER / 2));
    assert!(a.data.is_empty() && b.data.is_empty());
}

#[test]
fn problems_come_back_as_data_not_errors() {
    let mut chain = Chain::new();
    chain.token.insert(address(0), 100);
    chain.native.insert(address(1), 5);
    let node = Node::start(chain);
    let problem = |amount: &str| match node.plan(&token_asset(), amount, Mode::Legacy).unwrap() {
        Created::Problem(text) => serde_json::from_str::<Value>(&text).unwrap(),
        Created::Plan(_) => panic!("expected a problem"),
    };
    assert_eq!(
        problem("101"),
        json!({"code": "insufficient_funds", "held": "100", "needed": "101"})
    );
    // 100 tokens are there, but nobody holds the coin to pay for moving them:
    // the token has no standard for it, so a top-up is needed: its own fee (26_250
    // gas) plus the transfer's (62_500 gas) at 1 gwei (legacy).
    assert_eq!(
        problem("100"),
        json!({"code": "no_sponsor", "held": "5", "needed": "88750000000000"})
    );
    node.server.finish();
    let empty = crate::runtime().unwrap().block_on(create(
        "http://127.0.0.1:1",
        &request(&token_asset(), "1"),
        &[],
        Mode::Legacy,
        true,
    ));
    match empty.unwrap() {
        Created::Problem(text) => assert_eq!(text, r#"{"code":"no_addresses"}"#),
        Created::Plan(_) => panic!("expected a problem"),
    }
}

#[test]
fn a_request_is_checked_before_any_balance_is_read() {
    let node = Node::start(Chain::new());
    for (asset, to, amount) in [
        (token_asset(), "0x12", "1"),
        (token_asset(), RECIPIENT, "0"),
        (token_asset(), RECIPIENT, "01"),
        (
            token_asset(),
            "0x0000000000000000000000000000000000000000",
            "1",
        ),
        (
            "eip155:1/erc20:0x00000000000000000000000000000000000000c3".into(),
            RECIPIENT,
            "1",
        ),
        (format!("{CHAIN}/erc721:{TOKEN}"), RECIPIENT, "1"),
    ] {
        let mut bad = request(&asset, amount);
        bad.to = to.into();
        let result = crate::runtime().unwrap().block_on(create(
            &node.url(),
            &bad,
            &account(),
            Mode::Eip1559,
            true,
        ));
        assert!(result.is_err(), "{asset} {to} {amount}");
    }
    let mut unknown = request(&token_asset(), "1");
    unknown.prefer = Some("m/44'/60'/9'/0/0".into());
    let result = crate::runtime().unwrap().block_on(create(
        &node.url(),
        &unknown,
        &account(),
        Mode::Eip1559,
        true,
    ));
    assert!(result.is_err());
    assert_eq!(node.chain().calls, [] as [std::string::String; 0]);
    // A node on another chain is refused after the identity check alone.
    node.chain().chain_id = 1;
    assert!(node.plan(&token_asset(), "1", Mode::Eip1559).is_err());
    assert_eq!(node.chain().calls, ["eth_chainId"]);
    // Plain HTTP is not allowed outside development.
    let result = crate::runtime().unwrap().block_on(create(
        &node.url(),
        &request(&token_asset(), "1"),
        &account(),
        Mode::Eip1559,
        false,
    ));
    assert!(result.is_err());
}

#[test]
fn only_the_plans_own_addresses_can_sign() {
    assert!(signer(WORDS, "", &path(0), &address(0)).is_ok());
    assert!(signer(WORDS, "", &path(0), &address(1)).is_err());
    assert!(signer(WORDS, "other", &path(0), &address(0)).is_err());
}

#[test]
fn request_json_rejects_unknown_fields_and_bad_slots() {
    let good = r#"{"chain":"eip155:1","asset":"a","to":"b","amount":"1","slot":0}"#;
    assert!(serde_json::from_str::<Request>(good).is_ok());
    assert!(serde_json::from_str::<Request>(&good.replace('}', r#","path":"m/0"}"#)).is_err());
    assert!(serde_json::from_str::<Request>(&good.replace(r#""slot":0"#, r#""slot":-1"#)).is_err());
    assert!(
        serde_json::from_str::<Request>(&good.replace(r#""slot":0"#, r#""slot":"0""#)).is_err()
    );
}
