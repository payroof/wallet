//! Keyed indexer sources of activity: Etherscan V2's account API and Alchemy's asset
//! transfers.
//! Responses are untrusted and bounded. Requests are throttled.
use crate::history::{Page, Transfer, address_value, hash_value, quantity_u64};
use crate::{assets, balance};
use serde_json::{Value, json};
use std::time::{Duration, Instant};
use zeroize::Zeroizing;

/// Rows asked of an indexer at once. Small pages keep every response bounded.
const PAGE: usize = 100;
const INTERVAL: Duration = Duration::from_millis(250);

/// At most four requests a second, and a budget per refresh.
pub(crate) struct Throttle {
    last: Option<Instant>,
    left: usize,
}

impl Throttle {
    pub fn new(budget: usize) -> Self {
        Self {
            last: None,
            left: budget,
        }
    }
    pub fn spent(&self) -> bool {
        self.left == 0
    }
    async fn wait(&mut self) {
        if let Some(last) = self.last {
            tokio::time::sleep(INTERVAL.saturating_sub(last.elapsed())).await;
        }
        self.last = Some(Instant::now());
        self.left = self.left.saturating_sub(1);
    }
}

pub(crate) enum Index {
    Etherscan(Etherscan),
    Alchemy(Zeroizing<String>),
}

impl Index {
    /// One request per kind of transfer, covering the blocks `start..=end`.
    pub async fn pages(
        &self,
        http: &reqwest::Client,
        throttle: &mut Throttle,
        address: &str,
        start: u64,
        end: u64,
    ) -> anyhow::Result<Vec<Page>> {
        match self {
            Self::Etherscan(source) => {
                let mut pages = Vec::new();
                for (action, native) in [("txlist", true), ("tokentx", false)] {
                    let body = source
                        .query(http, throttle, action, address, start, end)
                        .await?;
                    pages.push(parse_etherscan(&body, native, start, end)?);
                }
                Ok(pages)
            }
            Self::Alchemy(url) => {
                let mut pages = Vec::new();
                for side in ["fromAddress", "toAddress"] {
                    throttle.wait().await;
                    let result = balance::rpc(
                        http,
                        url,
                        "alchemy_getAssetTransfers",
                        json!([{
                            "fromBlock": format!("0x{start:x}"), "toBlock": format!("0x{end:x}"),
                            side: address, "category": ["external", "erc20"],
                            "withMetadata": true, "excludeZeroValue": true,
                            "maxCount": format!("0x{PAGE:x}"), "order": "asc"
                        }]),
                    )
                    .await?;
                    pages.push(parse_alchemy(&result, start, end)?);
                }
                Ok(pages)
            }
        }
    }
}

/// The Etherscan V2 account API (one key, any chain).
pub(crate) struct Etherscan {
    base: String,
    chain: u64,
    key: Zeroizing<String>,
}

impl Etherscan {
    pub fn keyed(base: &str, chain: u64, key: &str) -> Self {
        Self {
            base: base.into(),
            chain,
            key: Zeroizing::new(key.into()),
        }
    }
    async fn query(
        &self,
        http: &reqwest::Client,
        throttle: &mut Throttle,
        action: &str,
        address: &str,
        start: u64,
        end: u64,
    ) -> anyhow::Result<Value> {
        let params = [
            ("module", "account".to_string()),
            ("action", action.to_string()),
            ("address", address.to_string()),
            ("startblock", start.to_string()),
            ("endblock", end.to_string()),
            ("page", "1".to_string()),
            ("offset", PAGE.to_string()),
            ("sort", "asc".to_string()),
            ("chainid", self.chain.to_string()),
            ("apikey", self.key.to_string()),
        ];
        throttle.wait().await;
        crate::api::fetch_json(http.get(&self.base).query(&params)).await
    }
}

fn decimal(value: &Value) -> anyhow::Result<u64> {
    value
        .as_str()
        .filter(|t| !t.is_empty() && t.len() <= 20 && t.bytes().all(|b| b.is_ascii_digit()))
        .and_then(|t| t.parse().ok())
        .ok_or_else(|| anyhow::anyhow!("invalid number"))
}

fn in_range(block: u64, start: u64, end: u64) -> anyhow::Result<u64> {
    anyhow::ensure!((start..=end).contains(&block), "block out of range");
    Ok(block)
}

/// `txlist` (native) or `tokentx` rows. An empty list is an empty answer whatever
/// the status says. Anything else must say "1".
pub(crate) fn parse_etherscan(
    body: &Value,
    native: bool,
    start: u64,
    end: u64,
) -> anyhow::Result<Page> {
    let rows = body["result"]
        .as_array()
        .filter(|r| r.len() <= PAGE)
        .ok_or_else(|| anyhow::anyhow!("invalid indexer answer"))?;
    let mut page = Page {
        transfers: Vec::new(),
        full: rows.len() == PAGE,
        first: u64::MAX,
        last: 0,
    };
    if rows.is_empty() {
        page.first = 0;
        return Ok(page);
    }
    anyhow::ensure!(body["status"] == "1", "indexer refused the request");
    for row in rows {
        let block = in_range(decimal(&row["blockNumber"])?, start, end)?;
        page.first = page.first.min(block);
        page.last = page.last.max(block);
        if native && row["to"] == "" {
            continue;
        }
        let failed = match (native, row["isError"].as_str()) {
            (false, _) | (true, Some("0")) => false,
            (true, Some("1")) => true,
            _ => anyhow::bail!("invalid status"),
        };
        let amount = row["value"]
            .as_str()
            .ok_or_else(|| anyhow::anyhow!("invalid amount"))?;
        assets::atomic(amount)?;
        page.transfers.push(Transfer {
            token: if native {
                None
            } else {
                Some(address_value(&row["contractAddress"])?)
            },
            transaction: hash_value(&row["hash"])?,
            from: address_value(&row["from"])?,
            to: address_value(&row["to"])?,
            amount: amount.into(),
            block,
            timestamp: Some(decimal(&row["timeStamp"])?),
            failed,
        });
    }
    Ok(page)
}

/// The `result` of `alchemy_getAssetTransfers`. A page key means more rows follow.
pub(crate) fn parse_alchemy(result: &Value, start: u64, end: u64) -> anyhow::Result<Page> {
    let rows = result["transfers"]
        .as_array()
        .filter(|r| r.len() <= PAGE)
        .ok_or_else(|| anyhow::anyhow!("invalid indexer answer"))?;
    let mut page = Page {
        transfers: Vec::new(),
        full: result["pageKey"].is_string(),
        first: u64::MAX,
        last: 0,
    };
    if rows.is_empty() {
        page.first = 0;
    }
    for row in rows {
        let block = in_range(quantity_u64(&row["blockNum"])?, start, end)?;
        page.first = page.first.min(block);
        page.last = page.last.max(block);
        let token = match row["category"].as_str() {
            Some("external") => None,
            Some("erc20") => Some(address_value(&row["rawContract"]["address"])?),
            _ => continue,
        };
        if row["to"].is_null() || row["rawContract"]["value"].is_null() {
            continue;
        }
        let timestamp = match row["metadata"]["blockTimestamp"].as_str() {
            Some(text) => {
                Some(unix_time(text).ok_or_else(|| anyhow::anyhow!("invalid timestamp"))?)
            }
            None => None,
        };
        page.transfers.push(Transfer {
            token,
            transaction: hash_value(&row["hash"])?,
            from: address_value(&row["from"])?,
            to: address_value(&row["to"])?,
            amount: balance::parse_quantity(&row["rawContract"]["value"])?.to_string(),
            block,
            timestamp,
            failed: false,
        });
    }
    Ok(page)
}

/// Unix seconds of `YYYY-MM-DDTHH:MM:SS[.fff]Z`.
fn unix_time(text: &str) -> Option<u64> {
    let bytes = text.as_bytes();
    let fraction_ok = bytes.len() == 20
        || (bytes.len() > 21
            && bytes.len() <= 30
            && bytes[19] == b'.'
            && bytes[20..bytes.len() - 1].iter().all(u8::is_ascii_digit));
    if !text.is_ascii() || !fraction_ok || !text.ends_with('Z') {
        return None;
    }
    for (at, mark) in [(4, b'-'), (7, b'-'), (10, b'T'), (13, b':'), (16, b':')] {
        if bytes[at] != mark {
            return None;
        }
    }
    let number = |from: usize, to: usize| -> Option<i64> {
        let part = &text[from..to];
        part.bytes()
            .all(|b| b.is_ascii_digit())
            .then(|| part.parse().ok())?
    };
    let (year, month, day) = (number(0, 4)?, number(5, 7)?, number(8, 10)?);
    let (hour, minute, second) = (number(11, 13)?, number(14, 16)?, number(17, 19)?);
    if year < 1970 || !(1..=12).contains(&month) || !(1..=31).contains(&day) {
        return None;
    }
    if hour > 23 || minute > 59 || second > 59 {
        return None;
    }
    // Days since the epoch (proleptic Gregorian calendar).
    let year = year - i64::from(month <= 2);
    let era = year / 400;
    let year_of_era = year - era * 400;
    let day_of_year = (153 * (month + if month > 2 { -3 } else { 9 }) + 2) / 5 + day - 1;
    let day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    let days = era * 146_097 + day_of_era - 719_468;
    u64::try_from(days * 86400 + hour * 3600 + minute * 60 + second).ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    const A: &str = "0x00000000000000000000000000000000000000a1";
    const B: &str = "0x00000000000000000000000000000000000000b2";
    const TOKEN: &str = "0x00000000000000000000000000000000000000c3";
    const TX: &str = "0x1111111111111111111111111111111111111111111111111111111111111111";

    fn native_row(block: &str) -> Value {
        json!({"blockNumber": block, "timeStamp": "1700000000", "hash": TX, "from": A,
            "to": B, "value": "1000", "isError": "0", "input": "0x"})
    }

    #[test]
    fn etherscan_native_rows_are_normalized() {
        let body = json!({"status":"1","message":"OK","result":[
            native_row("10"),
            {"blockNumber":"11","timeStamp":"1700000012","hash":TX,"from":A,"to":"","value":"5","isError":"0"},
            {"blockNumber":"12","timeStamp":"1700000024","hash":TX,"from":A,"to":B,"value":"7","isError":"1"}
        ]});
        let page = parse_etherscan(&body, true, 0, 100).unwrap();
        assert_eq!((page.first, page.last, page.full), (10, 12, false));
        assert_eq!(page.transfers.len(), 2);
        let t = &page.transfers[0];
        assert_eq!(
            (t.token.clone(), t.amount.as_str(), t.block),
            (None, "1000", 10)
        );
        assert_eq!(t.timestamp, Some(1_700_000_000));
        assert!(!t.failed && page.transfers[1].failed);
    }

    #[test]
    fn etherscan_token_rows_carry_the_contract() {
        let body = json!({"status":"1","result":[{"blockNumber":"5","timeStamp":"1","hash":TX,
            "from":A,"to":B,"contractAddress":TOKEN.to_uppercase().replace("0X","0x"),"value":"42"}]});
        let page = parse_etherscan(&body, false, 0, 9).unwrap();
        assert_eq!(page.transfers[0].token.as_deref(), Some(TOKEN));
        assert_eq!(page.transfers[0].amount, "42");
    }

    #[test]
    fn empty_answers_are_empty_not_errors() {
        let body = json!({"status":"0","message":"No transactions found","result":[]});
        let page = parse_etherscan(&body, true, 0, 9).unwrap();
        assert!(page.transfers.is_empty() && !page.full);
        assert_eq!(page.covered(9), 9);
    }

    #[test]
    fn hostile_etherscan_answers_are_rejected() {
        let bad_rows = [
            json!({"blockNumber":"10","timeStamp":"1","hash":"0x12","from":A,"to":B,"value":"1","isError":"0"}),
            json!({"blockNumber":"10","timeStamp":"1","hash":TX,"from":"nope","to":B,"value":"1","isError":"0"}),
            json!({"blockNumber":"10","timeStamp":"1","hash":TX,"from":A,"to":B,"value":"01","isError":"0"}),
            json!({"blockNumber":"10","timeStamp":"1","hash":TX,"from":A,"to":B,"value":"-1","isError":"0"}),
            json!({"blockNumber":"10","timeStamp":"1","hash":TX,"from":A,"to":B,"value":"1","isError":"2"}),
            json!({"blockNumber":"10","timeStamp":"1","hash":TX,"from":A,"to":B,"value":1,"isError":"0"}),
            json!({"blockNumber":"0x10","timeStamp":"1","hash":TX,"from":A,"to":B,"value":"1","isError":"0"}),
            json!({"blockNumber":"500","timeStamp":"1","hash":TX,"from":A,"to":B,"value":"1","isError":"0"}),
            json!({"blockNumber":"10","timeStamp":"x","hash":TX,"from":A,"to":B,"value":"1","isError":"0"}),
            json!({"blockNumber":"10","timeStamp":"1","hash":TX,"from":A,"to":B,"value":"1".repeat(79),"isError":"0"}),
        ];
        for row in bad_rows {
            let body = json!({"status":"1","result":[row]});
            assert!(parse_etherscan(&body, true, 0, 100).is_err(), "{body}");
        }
        for body in [
            json!({"status":"0","message":"NOTOK","result":"Invalid API Key"}),
            json!({"status":"0","result":[native_row("10")]}),
            json!({"status":"1"}),
            json!({"status":"1","result":[null]}),
            json!({"status":"1","result":vec![native_row("10"); PAGE + 1]}),
        ] {
            assert!(parse_etherscan(&body, true, 0, 100).is_err(), "{body}");
        }
        let token_without_contract = json!({"status":"1","result":[native_row("10")]});
        assert!(parse_etherscan(&token_without_contract, false, 0, 100).is_err());
    }

    #[test]
    fn full_pages_cover_only_complete_blocks() {
        let rows: Vec<Value> = (0..PAGE)
            .map(|i| native_row(&format!("{}", 10 + i / 10)))
            .collect();
        let page = parse_etherscan(&json!({"status":"1","result":rows}), true, 0, 100).unwrap();
        assert!(page.full);
        assert_eq!((page.first, page.last, page.covered(100)), (10, 19, 18));
        let one: Vec<Value> = (0..PAGE).map(|_| native_row("10")).collect();
        let page = parse_etherscan(&json!({"status":"1","result":one}), true, 0, 100).unwrap();
        assert_eq!(page.covered(100), 10);
    }

    fn alchemy_row(category: &str, value: &Value) -> Value {
        json!({"blockNum":"0xa","hash":TX,"from":A,"to":B,"category":category,
            "value":0.5,"asset":"X","uniqueId":"u",
            "rawContract":{"value":value,"address":TOKEN,"decimal":"0x6"},
            "metadata":{"blockTimestamp":"2023-11-14T22:13:20.000Z"}})
    }

    #[test]
    fn alchemy_transfers_use_exact_raw_values() {
        let result = json!({"transfers":[
            alchemy_row("erc20", &json!("0x3e8")),
            alchemy_row("external", &json!("0x1")),
            alchemy_row("erc721", &json!("0x1")),
            alchemy_row("erc20", &Value::Null)
        ],"pageKey":"next"});
        let page = parse_alchemy(&result, 0, 100).unwrap();
        assert!(page.full);
        assert_eq!(page.transfers.len(), 2);
        assert_eq!(page.transfers[0].amount, "1000");
        assert_eq!(page.transfers[0].token.as_deref(), Some(TOKEN));
        assert_eq!(page.transfers[0].timestamp, Some(1_700_000_000));
        assert_eq!(page.transfers[1].token, None);
        assert_eq!((page.first, page.last), (10, 10));
    }

    #[test]
    fn hostile_alchemy_answers_are_rejected() {
        let mut bad = alchemy_row("external", &json!("0x1"));
        bad["blockNum"] = json!("0x1000");
        let mut nonhex = alchemy_row("external", &json!("1000"));
        nonhex["hash"] = json!(TX);
        let mut stamp = alchemy_row("external", &json!("0x1"));
        stamp["metadata"]["blockTimestamp"] = json!("yesterday");
        let mut oversized = alchemy_row("external", &json!(format!("0x{}", "f".repeat(65))));
        oversized["to"] = json!(B);
        for row in [bad, nonhex, stamp, oversized] {
            assert!(parse_alchemy(&json!({"transfers":[row]}), 0, 100).is_err());
        }
        assert!(parse_alchemy(&json!({"transfers":"x"}), 0, 100).is_err());
        assert!(parse_alchemy(&json!({}), 0, 100).is_err());
    }

    #[test]
    fn timestamps_are_strict_utc() {
        assert_eq!(unix_time("1970-01-01T00:00:00Z"), Some(0));
        assert_eq!(unix_time("2024-01-01T00:00:00Z"), Some(1_704_067_200));
        assert_eq!(unix_time("2024-02-29T23:59:59.123Z"), Some(1_709_251_199));
        for bad in [
            "",
            "2024-01-01",
            "2024-01-01T00:00:00",
            "2024-13-01T00:00:00Z",
            "2024-01-01T24:00:00Z",
            "1969-12-31T23:59:59Z",
            "2024-01-01T00:00:00+00:00",
            "2024-01-01T00:00:00.Z",
            "+024-01-01T00:00:00Z",
            "2024-01-01 00:00:00Z",
        ] {
            assert_eq!(unix_time(bad), None, "{bad}");
        }
    }

    #[tokio::test]
    async fn queries_carry_the_key_and_errors_hide_it() {
        use std::io::{Read, Write};
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let base = format!("http://{}/v2/api", listener.local_addr().unwrap());
        let server = std::thread::spawn(move || {
            let mut requests = Vec::new();
            for status in ["200 OK", "500 Internal Server Error"] {
                let (mut socket, _) = listener.accept().unwrap();
                let mut head = Vec::new();
                while !head.ends_with(b"\r\n\r\n") {
                    let mut byte = [0];
                    socket.read_exact(&mut byte).unwrap();
                    head.push(byte[0]);
                }
                requests.push(String::from_utf8(head).unwrap());
                let body = r#"{"status":"0","message":"No transactions found","result":[]}"#;
                write!(socket, "HTTP/1.1 {status}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}", body.len()).unwrap();
            }
            requests
        });
        let http = crate::api::client().unwrap();
        let mut throttle = Throttle::new(8);
        let keyed = Etherscan::keyed(&base, 8453, "k3y");
        keyed
            .query(&http, &mut throttle, "txlist", A, 5, 90)
            .await
            .unwrap();
        let error = keyed
            .query(&http, &mut throttle, "txlist", A, 5, 90)
            .await
            .unwrap_err();
        assert!(!format!("{error:?}").contains("k3y"));
        let requests = server.join().unwrap();
        for part in [
            "GET /v2/api?",
            "module=account",
            "action=txlist",
            "startblock=5",
            "endblock=90",
            "offset=100",
            "sort=asc",
            "chainid=8453",
            "apikey=k3y",
        ] {
            assert!(requests[0].contains(part), "{part}");
        }
    }

    #[tokio::test]
    async fn throttle_spaces_requests_and_spends_its_budget() {
        let mut throttle = Throttle::new(2);
        let started = Instant::now();
        throttle.wait().await;
        assert!(!throttle.spent());
        throttle.wait().await;
        assert!(throttle.spent());
        assert!(started.elapsed() >= INTERVAL);
    }
}
