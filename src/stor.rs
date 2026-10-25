//! Stor (<https://github.com/payroof/stor>): a project's store is created with one request carrying its subdomain,
//! its Google Sheet, and the payment URL and KEY Stor writes into the sheet's Payments
//! tab. After that, the merchant edits the sheet. The Wallet never talks to Stor again.
use serde_json::{Value, json};

/// What a store's key may do on its project: create payment addresses (references,
/// paths) and be told of payments (webhooks). Never `access`, so it can't make keys.
pub const PERMISSIONS: [&str; 3] = ["references", "paths", "webhooks"];
/// Store subdomains: 3–40 lowercase letters, digits or inner hyphens.
pub fn valid_subdomain(s: &str) -> bool {
    (3..=40).contains(&s.len())
        && s.bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-')
        && !s.starts_with('-')
        && !s.ends_with('-')
}
/// What a Stor server asks of a new store: the account a sheet is shared with, and
/// where its stores live.
pub async fn info(origin: &str) -> anyhow::Result<Value> {
    let http = crate::api::client()?;
    let v = crate::api::bounded_json(
        http.get(format!("{origin}/v1/info"))
            .send()
            .await?
            .error_for_status()?,
    )
    .await?;
    let text = |key: &str| {
        v[key]
            .as_str()
            .filter(|s| (1..=200).contains(&s.len()) && !s.chars().any(char::is_control))
    };
    let share =
        text("share_with").ok_or_else(|| anyhow::anyhow!("Stor has no account to share with"))?;
    let suffix = text("store_suffix").ok_or_else(|| anyhow::anyhow!("invalid Stor info"))?;
    let scheme = origin.split_once("://").map_or("https", |(s, _)| s);
    Ok(json!({
        "stor": origin, "share_with": share,
        "store_url": format!("{scheme}://{{store}}.{suffix}")
    }))
}
/// Creates the store. Stor's refusals come back as `{"error": code}`, so the host can
/// say what to fix. Anything else is an error.
pub async fn create(
    origin: &str,
    subdomain: &str,
    source: &str,
    url: &str,
    key: &str,
) -> anyhow::Result<Value> {
    if !valid_subdomain(subdomain) {
        return Ok(json!({"error": "invalid_subdomain"}));
    }
    anyhow::ensure!(
        (1..=500).contains(&source.len()) && !source.chars().any(char::is_control),
        "invalid source"
    );
    let http = crate::api::client()?;
    let altcha = crate::api::proof(&http, origin, "store").await?;
    let response = http
        .post(format!("{origin}/v1/stores"))
        .json(&json!({
            "subdomain": subdomain, "source": source,
            "payments": {"url": url, "key": key}, "altcha": altcha
        }))
        .send()
        .await?;
    let status = response.status();
    let body = crate::api::bounded_json(response).await.unwrap_or_default();
    if status.is_success() {
        let store = body["url"]
            .as_str()
            .filter(|u| u.starts_with("https://") || u.starts_with("http://"))
            .ok_or_else(|| anyhow::anyhow!("invalid Stor response"))?;
        return Ok(json!({"url": store}));
    }
    let code = body["error"]
        .as_str()
        .filter(|c| {
            (1..=64).contains(&c.len()) && c.bytes().all(|b| b.is_ascii_lowercase() || b == b'_')
        })
        .ok_or_else(|| anyhow::anyhow!("Stor unavailable"))?;
    Ok(json!({"error": code}))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn subdomains_are_checked_before_any_request() {
        for good in ["shop", "my-store", "a1b"] {
            assert!(valid_subdomain(good), "{good}");
        }
        for bad in ["ab", "-shop", "shop-", "Shop", "my_store", &"a".repeat(41)] {
            assert!(!valid_subdomain(bad), "{bad}");
        }
    }
    #[tokio::test]
    async fn a_stor_tells_who_to_share_with_and_where_stores_live() {
        use std::io::{Read, Write};
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let origin = format!("http://{}", listener.local_addr().unwrap());
        let server = std::thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut request = [0; 4096];
            let n = stream.read(&mut request).unwrap();
            assert!(request[..n].starts_with(b"GET /v1/info HTTP/1.1"));
            let body =
                r#"{"store_suffix":"stor.example","share_with":"m@x.iam.gserviceaccount.com"}"#;
            write!(
                stream,
                "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: {}\r\nconnection: close\r\n\r\n{body}",
                body.len()
            )
            .unwrap();
        });
        let info = info(&origin).await.unwrap();
        server.join().unwrap();
        assert_eq!(
            info,
            json!({"stor": origin, "share_with": "m@x.iam.gserviceaccount.com",
                   "store_url": "http://{store}.stor.example"})
        );
    }
    #[tokio::test]
    async fn a_refused_store_reports_stor_code_and_a_created_one_its_address() {
        use std::io::{Read, Write};
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let origin = format!("http://{}", listener.local_addr().unwrap());
        let server = std::thread::spawn(move || {
            let challenge = altcha::create_challenge(altcha::CreateChallengeOptions {
                algorithm: "PBKDF2/SHA-256".into(),
                cost: 5000,
                counter: Some(0),
                key_prefix_length: Some(4),
                hmac_signature_secret: Some("test".into()),
                ..Default::default()
            })
            .unwrap();
            let answers = [
                (200, serde_json::to_string(&challenge).unwrap()),
                (
                    409,
                    r#"{"error":"subdomain_taken","message":"x"}"#.to_string(),
                ),
                (200, serde_json::to_string(&challenge).unwrap()),
                (
                    201,
                    r#"{"store":"shop","url":"http://shop.stor.localhost:8081"}"#.into(),
                ),
            ];
            for (status, body) in answers {
                let (mut stream, _) = listener.accept().unwrap();
                let mut request = vec![0; 65536];
                let n = stream.read(&mut request).unwrap();
                let head = String::from_utf8_lossy(&request[..n]).to_string();
                if head.starts_with("POST") {
                    // The body may arrive after the head.
                    let length: usize = head
                        .lines()
                        .find_map(|l| {
                            l.to_ascii_lowercase()
                                .strip_prefix("content-length: ")
                                .map(|v| v.trim().parse().unwrap())
                        })
                        .unwrap();
                    let mut received = head.split_once("\r\n\r\n").unwrap().1.len();
                    let mut rest = Vec::new();
                    while received < length {
                        let mut chunk = vec![0; 65536];
                        let m = stream.read(&mut chunk).unwrap();
                        received += m;
                        rest.extend_from_slice(&chunk[..m]);
                    }
                    let full = format!("{}{}", head, String::from_utf8_lossy(&rest));
                    let sent: Value =
                        serde_json::from_str(full.split_once("\r\n\r\n").unwrap().1).unwrap();
                    assert_eq!(sent["payments"]["key"], "prf_key");
                    assert!(sent["altcha"]["solution"].is_object());
                }
                write!(
                    stream,
                    "HTTP/1.1 {status} X\r\ncontent-type: application/json\r\ncontent-length: {}\r\nconnection: close\r\n\r\n{body}",
                    body.len()
                )
                .unwrap();
            }
        });
        let url = "http://127.0.0.1:8080/v1/projects/shop";
        let refused = create(&origin, "shop", "sheet-id", url, "prf_key")
            .await
            .unwrap();
        assert_eq!(refused, json!({"error": "subdomain_taken"}));
        let created = create(&origin, "shop", "sheet-id", url, "prf_key")
            .await
            .unwrap();
        assert_eq!(created, json!({"url": "http://shop.stor.localhost:8081"}));
        server.join().unwrap();
        let invalid = create(&origin, "Shop", "sheet-id", url, "prf_key")
            .await
            .unwrap();
        assert_eq!(invalid, json!({"error": "invalid_subdomain"}));
    }
}
