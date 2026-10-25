//! Configurable USD price oracles: one HTTPS JSON document, one dot path per asset.
use serde_json::Value;

const MAX_PRICE: f64 = 1e12;

/// Walks a dot path (object keys, or array indexes) to a number or numeric string
/// and returns a canonical, non-negative decimal string.
pub(crate) fn pick(document: &Value, field: &str) -> anyhow::Result<String> {
    anyhow::ensure!(!field.is_empty(), "missing price field");
    let mut node = document;
    for key in field.split('.') {
        node = match node {
            Value::Object(map) => map.get(key),
            Value::Array(items) => key.parse::<usize>().ok().and_then(|i| items.get(i)),
            _ => None,
        }
        .ok_or_else(|| anyhow::anyhow!("price field not found"))?;
    }
    let value = match node {
        Value::Number(n) => n.as_f64(),
        Value::String(s) => s.trim().parse::<f64>().ok(),
        _ => None,
    }
    .ok_or_else(|| anyhow::anyhow!("price is not a number"))?;
    anyhow::ensure!(
        value.is_finite() && (0.0..=MAX_PRICE).contains(&value),
        "price out of range"
    );
    let text = format!("{value:.12}");
    Ok(text.trim_end_matches('0').trim_end_matches('.').to_string())
}

/// Fetches one document and reads every field from it. A field that cannot be read
/// is `None`. The request itself failing is an error.
pub(crate) async fn quote(
    url: &str,
    fields: &[String],
    development: bool,
) -> anyhow::Result<Vec<Option<String>>> {
    crate::networks::validate_rpc(url, development)?;
    // Public price APIs (CoinGecko among them) refuse requests without a User-Agent.
    let http = reqwest::Client::builder()
        .user_agent(concat!("PayroofWallet/", env!("CARGO_PKG_VERSION")))
        .timeout(std::time::Duration::from_secs(10))
        .no_proxy()
        .redirect(reqwest::redirect::Policy::none())
        .build()?;
    let document =
        crate::api::bounded_json(http.get(url).send().await?.error_for_status()?).await?;
    Ok(fields.iter().map(|f| pick(&document, f).ok()).collect())
}

#[cfg(test)]
mod tests {
    use serde_json::json;
    #[test]
    fn walks_paths_and_canonicalizes() {
        let doc = json!({"ethereum":{"usd":3000.5},"Price":"1.00","list":[{"p":2}],"neg":-1,"big":1e20,"s":"abc"});
        assert_eq!(super::pick(&doc, "ethereum.usd").unwrap(), "3000.5");
        assert_eq!(super::pick(&doc, "Price").unwrap(), "1");
        assert_eq!(super::pick(&doc, "list.0.p").unwrap(), "2");
        for bad in [
            "",
            "ethereum",
            "ethereum.eur",
            "neg",
            "big",
            "s",
            "list.1.p",
        ] {
            assert!(super::pick(&doc, bad).is_err(), "{bad}");
        }
        assert!(super::pick(&json!({"p":"NaN"}), "p").is_err());
        assert_eq!(
            super::pick(&json!({"p":0.000_001}), "p").unwrap(),
            "0.000001"
        );
    }
    #[test]
    fn rejects_insecure_urls_before_any_request() {
        let run = |url| {
            crate::runtime()
                .unwrap()
                .block_on(super::quote(url, &["a".into()], false))
        };
        assert!(run("http://example.com/p").is_err());
        assert!(run("http://127.0.0.1:1/p").is_err());
    }
}
