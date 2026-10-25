//! Origin-pinned HTTP client with redirects and ambient proxies disabled.
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::time::Duration;
use zeroize::Zeroizing;
const ALTCHA: &str = "/v1/altcha";
const PROJECTS: &str = "/v1/projects";
const RECOVERY: &str = "/v1/recovery";
/// The path of all pairing requests. A pairing link ends with `/<id>`.
pub const PAIRINGS: &str = "/v1/pairings";

/// Every route of the Payroof API this wallet calls. The only place their paths are
/// written, so a path is never assembled by hand at a call site.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Route<'a> {
    /// `GET`: a proof-of-work challenge.
    Altcha,
    /// `POST`: registers a project.
    Projects,
    /// `GET`, `POST`: one project and its account paths.
    Project(&'a str),
    /// `GET`: the project's payment paths.
    ProjectPaths(&'a str),
    /// `GET`, `POST`: the project's credentials.
    ProjectAccess(&'a str),
    /// `DELETE`: one credential of a project.
    AccessGrant { project: &'a str, id: &'a str },
    /// `GET`, `PUT`: a device pairing request.
    Pairing(&'a str),
    /// `POST`: starts recovery by recovery key.
    Recovery,
    /// `PUT`: answers a recovery challenge.
    RecoveryAttempt(&'a str),
}

impl Route<'_> {
    /// The path of the route, starting with `/`.
    pub fn path(self) -> String {
        match self {
            Self::Altcha => ALTCHA.to_string(),
            Self::Projects => PROJECTS.to_string(),
            Self::Project(project) => format!("{PROJECTS}/{project}"),
            Self::ProjectPaths(project) => format!("{PROJECTS}/{project}/paths"),
            Self::ProjectAccess(project) => format!("{PROJECTS}/{project}/access"),
            Self::AccessGrant { project, id } => {
                format!("{PROJECTS}/{project}/access/{id}")
            }
            Self::Pairing(id) => format!("{PAIRINGS}/{id}"),
            Self::Recovery => RECOVERY.to_string(),
            Self::RecoveryAttempt(id) => format!("{RECOVERY}/{id}"),
        }
    }
    /// The full URL under an already validated `origin`.
    pub fn url(self, origin: &str) -> String {
        format!("{origin}{}", self.path())
    }
}

pub fn origin(raw: &str, development: bool) -> anyhow::Result<String> {
    anyhow::ensure!(
        raw.trim() == raw
            && !raw.contains('\\')
            && raw.split_once("://").is_some_and(|(_, rest)| rest
                .split_once('/')
                .is_none_or(|(_, path)| path.is_empty())),
        "expected canonical origin"
    );
    let u = url::Url::parse(raw)?;
    anyhow::ensure!(
        u.username().is_empty()
            && u.password().is_none()
            && u.query().is_none()
            && u.fragment().is_none()
            && u.path() == "/",
        "expected origin"
    );
    anyhow::ensure!(
        u.scheme() == "https"
            || (development && u.scheme() == "http" && crate::networks::development_http_host(&u)),
        "HTTPS required"
    );
    Ok(u.origin().ascii_serialization())
}
pub struct Api {
    origin: String,
    pin: [u8; 32],
    token: Zeroizing<String>,
    http: reqwest::Client,
}
impl Api {
    pub fn new(raw: &str, token: String, pin: [u8; 32], development: bool) -> anyhow::Result<Self> {
        let origin = origin(raw, development)?;
        anyhow::ensure!(
            <[u8; 32]>::from(Sha256::digest(origin.as_bytes())) == pin,
            "credential origin mismatch"
        );
        Ok(Self {
            origin,
            pin,
            token: Zeroizing::new(token),
            http: client()?,
        })
    }
    pub fn pin(raw: &str, development: bool) -> anyhow::Result<[u8; 32]> {
        Ok(Sha256::digest(origin(raw, development)?.as_bytes()).into())
    }
    fn route(&self, path: &str) -> anyhow::Result<url::Url> {
        anyhow::ensure!(
            path.starts_with('/') && !path.starts_with("//") && !path.contains('\\'),
            "expected API-relative path"
        );
        let target = url::Url::parse(&format!("{}{path}", self.origin))?;
        anyhow::ensure!(
            target.origin().ascii_serialization() == self.origin
                && target.username().is_empty()
                && target.password().is_none()
                && target.fragment().is_none(),
            "credential origin mismatch"
        );
        Ok(target)
    }
    pub async fn call(
        &self,
        method: reqwest::Method,
        path: &str,
        body: Option<Value>,
    ) -> anyhow::Result<Value> {
        anyhow::ensure!(
            Self::pin(&self.origin, false).or_else(|_| Self::pin(&self.origin, true))? == self.pin,
            "credential origin mismatch"
        );
        let mut r = self
            .http
            .request(method, self.route(path)?)
            .bearer_auth(&*self.token);
        if let Some(b) = body {
            r = r.json(&b);
        }
        bounded_json(r.send().await?.error_for_status()?).await
    }
    pub async fn verify_root(
        &self,
        project: &str,
        local: &crate::watch_root::WatchRoot,
    ) -> anyhow::Result<Value> {
        let view = self
            .call(reqwest::Method::GET, &Route::Project(project).path(), None)
            .await?;
        anyhow::ensure!(
            view["watch_roots"][0]["path"] == local.path
                && view["watch_roots"][0]["fingerprint"] == local.fingerprint()?,
            "watch root mismatch"
        );
        Ok(view)
    }
    pub async fn paths(
        &self,
        project: &str,
        scope: &str,
        cursor: Option<&str>,
    ) -> anyhow::Result<(String, String, bool)> {
        anyhow::ensure!(matches!(scope, "all" | "confirmed"), "invalid scope");
        let mut request = self
            .http
            .get(self.route(&Route::ProjectPaths(project).path())?)
            .bearer_auth(&*self.token)
            .query(&[("scope", scope), ("limit", "200")]);
        if let Some(c) = cursor {
            request = request.query(&[("cursor", c)]);
        }
        let response = request.send().await?.error_for_status()?;
        let next = response
            .headers()
            .get("payroof-next-cursor")
            .ok_or_else(|| anyhow::anyhow!("missing cursor"))?
            .to_str()?
            .to_owned();
        let more = response
            .headers()
            .get("payroof-has-more")
            .and_then(|v| v.to_str().ok())
            == Some("true");
        let body = bounded_bytes(response, 128_000).await?;
        Ok((String::from_utf8(body)?, next, more))
    }
    pub async fn approve(&self, id: &str, user_allowed: bool) -> anyhow::Result<()> {
        anyhow::ensure!(
            user_allowed && crate::pairing::valid_id(id),
            "explicit approval required"
        );
        let r = self
            .http
            .put(self.route(&Route::Pairing(id).path())?)
            .bearer_auth(&*self.token)
            .send()
            .await?;
        r.error_for_status()?;
        Ok(())
    }
    /// Live credentials of the project: id, name, permissions and creation time.
    pub async fn grants(&self, project: &str) -> anyhow::Result<Value> {
        anyhow::ensure!(valid_segment(project), "invalid project");
        let response = self
            .call(
                reqwest::Method::GET,
                &Route::ProjectAccess(project).path(),
                None,
            )
            .await?;
        Ok(response
            .get("access")
            .filter(|value| value.is_array())
            .ok_or_else(|| anyhow::anyhow!("missing access list"))?
            .clone())
    }
    /// HTTP status of an authenticated read of the project. 401/403 mean this
    /// credential no longer grants access (for example, its token was revoked).
    pub async fn access_status(&self, project: &str) -> anyhow::Result<u16> {
        anyhow::ensure!(valid_segment(project), "invalid project");
        anyhow::ensure!(
            Self::pin(&self.origin, false).or_else(|_| Self::pin(&self.origin, true))? == self.pin,
            "credential origin mismatch"
        );
        let response = self
            .http
            .get(self.route(&Route::Project(project).path())?)
            .bearer_auth(&*self.token)
            .send()
            .await?;
        Ok(response.status().as_u16())
    }
    /// Issues a new credential. The returned `token` is the only copy. Callers
    /// must show it once and never store or log it.
    pub async fn create_grant(
        &self,
        project: &str,
        name: &str,
        permissions: &[String],
    ) -> anyhow::Result<Value> {
        anyhow::ensure!(valid_segment(project), "invalid project");
        anyhow::ensure!(
            name.trim() == name
                && (1..=64).contains(&name.chars().count())
                && !name.chars().any(char::is_control),
            "invalid name"
        );
        anyhow::ensure!(
            (1..=4).contains(&permissions.len())
                && permissions.iter().enumerate().all(|(i, p)| {
                    matches!(p.as_str(), "references" | "paths" | "webhooks" | "access")
                        && !permissions[..i].contains(p)
                }),
            "invalid permissions"
        );
        let response = self
            .call(
                reqwest::Method::POST,
                &Route::ProjectAccess(project).path(),
                Some(json!({"name": name, "permissions": permissions})),
            )
            .await?;
        let text = |key: &str| response.get(key).and_then(Value::as_str);
        anyhow::ensure!(
            text("id").is_some_and(|id| id.starts_with("acc_") && valid_segment(id))
                && text("token").is_some_and(|t| t.starts_with("prf_"))
                && text("name") == Some(name)
                && text("created_at").is_some()
                && response
                    .get("permissions")
                    .and_then(Value::as_array)
                    .is_some_and(|got| {
                        got.len() == permissions.len()
                            && got.iter().all(|g| {
                                g.as_str()
                                    .is_some_and(|g| permissions.iter().any(|p| p == g))
                            })
                    }),
            "invalid access response"
        );
        Ok(json!({
            "id": response["id"], "name": response["name"],
            "permissions": response["permissions"],
            "created_at": response["created_at"], "token": response["token"],
        }))
    }
    pub async fn revoke_grant(&self, project: &str, id: &str) -> anyhow::Result<()> {
        anyhow::ensure!(
            valid_segment(project) && valid_segment(id) && id.starts_with("acc_"),
            "invalid access route"
        );
        self.http
            .delete(self.route(&Route::AccessGrant { project, id }.path())?)
            .bearer_auth(&*self.token)
            .send()
            .await?
            .error_for_status()?;
        Ok(())
    }
}
fn valid_segment(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 128
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || b"_-".contains(&byte))
}
pub fn client() -> anyhow::Result<reqwest::Client> {
    Ok(reqwest::Client::builder()
        .timeout(Duration::from_secs(15))
        .no_proxy()
        .redirect(reqwest::redirect::Policy::none())
        .build()?)
}
/// A request whose answer is read as bounded JSON. Transport errors carry no URL,
/// because provider endpoints embed API keys.
pub async fn fetch_json(request: reqwest::RequestBuilder) -> anyhow::Result<Value> {
    let response = request
        .send()
        .await
        .map_err(reqwest::Error::without_url)?
        .error_for_status()
        .map_err(reqwest::Error::without_url)?;
    bounded_json(response).await
}
pub async fn bounded_bytes(mut r: reqwest::Response, max: usize) -> anyhow::Result<Vec<u8>> {
    let mut b = Vec::new();
    while let Some(c) = r.chunk().await.map_err(reqwest::Error::without_url)? {
        anyhow::ensure!(b.len() + c.len() <= max, "response too large");
        b.extend(c);
    }
    Ok(b)
}
pub async fn bounded_json(r: reqwest::Response) -> anyhow::Result<Value> {
    Ok(serde_json::from_slice(&bounded_bytes(r, 256_000).await?)?)
}
pub async fn proof(
    http: &reqwest::Client,
    origin: &str,
    purpose: &str,
) -> anyhow::Result<altcha::Payload> {
    let c: altcha::Challenge = serde_json::from_value(
        bounded_json(
            http.get(Route::Altcha.url(origin))
                .query(&[("purpose", purpose)])
                .send()
                .await?
                .error_for_status()?,
        )
        .await?,
    )?;
    let solution = crate::proof::solve(&c)?;
    Ok(altcha::Payload {
        challenge: c,
        solution,
    })
}
pub async fn register(
    raw: &str,
    project: &str,
    mnemonic: &str,
    passphrase: &str,
    slot: u32,
    development: bool,
) -> anyhow::Result<Value> {
    let origin = origin(raw, development)?;
    let http = client()?;
    let root = crate::derivation::watch(mnemonic, passphrase, slot)?;
    let recovery_key = crate::recovery::public(mnemonic, passphrase, slot)?;
    let altcha = proof(&http, &origin, "project").await?;
    let request = json!({
        "project": project,
        "recovery_key": {"algorithm": "ed25519", "public_key": recovery_key},
        "watch_roots": [root], "altcha": altcha
    });
    let response = http
        .post(Route::Projects.url(&origin))
        .json(&request)
        .send()
        .await?
        .error_for_status()?;
    bounded_json(response).await
}
/// Whether a request failed because the resource already exists (409): registering an
/// account that already has a project on the API.
pub fn is_conflict(error: &anyhow::Error) -> bool {
    error
        .downcast_ref::<reqwest::Error>()
        .and_then(reqwest::Error::status)
        == Some(reqwest::StatusCode::CONFLICT)
}
/// Recovers access to the account's project, found by its recovery key alone (a key
/// owns one project). The result names the project.
pub async fn recover(
    raw: &str,
    mnemonic: &str,
    passphrase: &str,
    slot: u32,
    development: bool,
) -> anyhow::Result<Value> {
    let origin = origin(raw, development)?;
    let http = client()?;
    let recovery_key = crate::recovery::public(mnemonic, passphrase, slot)?;
    let altcha = proof(&http, &origin, "recovery").await?;
    let request = json!({
        "recovery_key": {"algorithm": "ed25519", "public_key": recovery_key},
        "altcha": altcha
    });
    let response = http
        .post(Route::Recovery.url(&origin))
        .json(&request)
        .send()
        .await?
        .error_for_status()?;
    let c = bounded_json(response).await?;
    let id = c["id"]
        .as_str()
        .ok_or_else(|| anyhow::anyhow!("missing recovery id"))?;
    let challenge = c["challenge"]
        .as_str()
        .ok_or_else(|| anyhow::anyhow!("missing challenge"))?;
    let signature = crate::recovery::sign(
        mnemonic,
        passphrase,
        slot,
        &crate::recovery::Challenge {
            origin: &origin,
            id,
            challenge,
        },
        development,
    )?;
    bounded_json(
        http.put(Route::RecoveryAttempt(id).url(&origin))
            .json(&json!({"signature":signature,"name":"Recovered wallet"}))
            .send()
            .await?
            .error_for_status()?,
    )
    .await
}

#[cfg(test)]
mod credential_routes {
    use super::*;

    #[tokio::test]
    async fn access_management_uses_pinned_canonical_routes_and_bodyless_delete() {
        use std::io::{Read, Write};
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let origin = format!("http://{}", listener.local_addr().unwrap());
        let server = std::thread::spawn(move || {
            for step in 0..2 {
                let (mut socket, _) = listener.accept().unwrap();
                socket
                    .set_read_timeout(Some(Duration::from_secs(5)))
                    .unwrap();
                let mut request = Vec::new();
                while !request.ends_with(b"\r\n\r\n") {
                    let mut byte = [0];
                    socket.read_exact(&mut byte).unwrap();
                    request.push(byte[0]);
                }
                let request = String::from_utf8(request).unwrap();
                assert!(
                    request
                        .to_ascii_lowercase()
                        .contains("authorization: bearer prf_owner\r\n")
                );
                assert!(!request.to_ascii_lowercase().contains("content-type:"));
                if step == 0 {
                    assert!(request.starts_with("GET /v1/projects/store/access HTTP/1.1\r\n"));
                    let body = json!({"access":[{"id":"acc_store","name":"Stor shop","permissions":["references","webhooks"],"created_at":"2026-10-09T00:00:00Z"}]}).to_string();
                    write!(socket, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}", body.len(), body).unwrap();
                } else {
                    assert!(
                        request
                            .starts_with("DELETE /v1/projects/store/access/acc_store HTTP/1.1\r\n")
                    );
                    socket.write_all(b"HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n").unwrap();
                }
            }
        });
        let api = Api::new(
            &origin,
            "prf_owner".into(),
            Api::pin(&origin, true).unwrap(),
            true,
        )
        .unwrap();
        let grants = api.grants("store").await.unwrap();
        assert_eq!(grants[0]["name"], "Stor shop");
        assert!(grants[0].get("token").is_none());
        api.revoke_grant("store", "acc_store").await.unwrap();
        for project in ["../store", "store?query=x", "store/access"] {
            assert!(api.grants(project).await.is_err());
        }
        for id in ["acc_bad?query=x", "acc_bad/other", "tok_store", "access"] {
            assert!(api.revoke_grant("store", id).await.is_err());
        }
        server.join().unwrap();
    }

    #[tokio::test]
    async fn create_grant_posts_validated_body_and_checks_response() {
        use std::io::{Read, Write};
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let origin = format!("http://{}", listener.local_addr().unwrap());
        let server = std::thread::spawn(move || {
            for step in 0..2 {
                let (mut socket, _) = listener.accept().unwrap();
                socket
                    .set_read_timeout(Some(Duration::from_secs(5)))
                    .unwrap();
                let mut request = Vec::new();
                while !request.ends_with(b"\r\n\r\n") {
                    let mut byte = [0];
                    socket.read_exact(&mut byte).unwrap();
                    request.push(byte[0]);
                }
                let head = String::from_utf8(request).unwrap();
                assert!(head.starts_with("POST /v1/projects/store/access HTTP/1.1\r\n"));
                let length: usize = head
                    .to_ascii_lowercase()
                    .lines()
                    .find_map(|l| {
                        l.strip_prefix("content-length: ")
                            .map(|v| v.parse().unwrap())
                    })
                    .unwrap();
                let mut body = vec![0; length];
                socket.read_exact(&mut body).unwrap();
                assert_eq!(
                    serde_json::from_slice::<Value>(&body).unwrap(),
                    json!({"name":"Cashier","permissions":["references","paths"]})
                );
                let token = if step == 0 { "prf_new" } else { "bad_new" };
                let body = json!({"id":"acc_new","name":"Cashier","permissions":["references","paths"],"created_at":"2026-10-09T00:00:00Z","token":token}).to_string();
                write!(socket, "HTTP/1.1 201 Created\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}", body.len(), body).unwrap();
            }
        });
        let api = Api::new(
            &origin,
            "prf_owner".into(),
            Api::pin(&origin, true).unwrap(),
            true,
        )
        .unwrap();
        let perms = vec!["references".to_string(), "paths".to_string()];
        let grant = api.create_grant("store", "Cashier", &perms).await.unwrap();
        assert_eq!(grant["id"], "acc_new");
        assert_eq!(grant["token"], "prf_new");
        assert!(api.create_grant("store", "Cashier", &perms).await.is_err());
        let one = |p: &str| vec![p.to_string()];
        assert!(api.create_grant("../x", "Cashier", &perms).await.is_err());
        for name in ["", " pad ", "bad\nname", &"x".repeat(65)] {
            assert!(api.create_grant("store", name, &perms).await.is_err());
        }
        for p in [vec![], vec!["paths".into(), "paths".into()], one("root")] {
            assert!(api.create_grant("store", "Cashier", &p).await.is_err());
        }
        server.join().unwrap();
    }

    #[tokio::test]
    async fn recover_signs_loopback_challenge_only_with_explicit_development() {
        use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
        use ed25519_dalek::{Signature, VerifyingKey};
        use std::io::{Read, Write};
        const WORDS: &str = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let origin = format!("http://{}", listener.local_addr().unwrap());
        assert!(recover(&origin, WORDS, "", 0, false).await.is_err());
        assert!(
            recover("http://api.example", WORDS, "", 0, true)
                .await
                .is_err()
        );
        let expected_origin = origin.clone();
        let server = std::thread::spawn(move || {
            for step in 0..3 {
                let (mut socket, _) = listener.accept().unwrap();
                socket
                    .set_read_timeout(Some(Duration::from_secs(5)))
                    .unwrap();
                let mut request = Vec::new();
                let mut byte = [0];
                while !request.ends_with(b"\r\n\r\n") {
                    socket.read_exact(&mut byte).unwrap();
                    request.push(byte[0]);
                }
                let header = String::from_utf8(request).unwrap();
                let length: usize = header
                    .lines()
                    .find_map(|line| {
                        let (name, value) = line.split_once(':')?;
                        name.eq_ignore_ascii_case("content-length")
                            .then(|| value.trim().parse().unwrap())
                    })
                    .unwrap_or(0);
                let mut body = vec![0; length];
                socket.read_exact(&mut body).unwrap();
                let response = match step {
                    0 => {
                        assert!(header.starts_with("GET /v1/altcha?purpose=recovery HTTP/1.1\r\n"));
                        serde_json::to_value(
                            altcha::create_challenge(altcha::CreateChallengeOptions {
                                counter: Some(0),
                                cost: 1,
                                ..Default::default()
                            })
                            .unwrap(),
                        )
                        .unwrap()
                    }
                    1 => {
                        assert!(header.starts_with("POST /v1/recovery HTTP/1.1\r\n"));
                        let request: Value = serde_json::from_slice(&body).unwrap();
                        assert!(request.get("project").is_none());
                        assert_eq!(
                            request["recovery_key"]["public_key"],
                            crate::recovery::public(WORDS, "", 0).unwrap()
                        );
                        assert!(request["altcha"]["solution"].is_object());
                        json!({"id":"rec_fixture", "challenge":"fixture-challenge"})
                    }
                    2 => {
                        assert!(header.starts_with("PUT /v1/recovery/rec_fixture HTTP/1.1\r\n"));
                        let request: Value = serde_json::from_slice(&body).unwrap();
                        let signature = Signature::from_slice(
                            &URL_SAFE_NO_PAD
                                .decode(request["signature"].as_str().unwrap())
                                .unwrap(),
                        )
                        .unwrap();
                        let key = VerifyingKey::from_bytes(
                            &URL_SAFE_NO_PAD
                                .decode(crate::recovery::public(WORDS, "", 0).unwrap())
                                .unwrap()
                                .try_into()
                                .unwrap(),
                        )
                        .unwrap();
                        let message = format!(
                            "payroof-recovery-v2\n{expected_origin}\nrec_fixture\nfixture-challenge\n"
                        );
                        key.verify_strict(message.as_bytes(), &signature).unwrap();
                        json!({"project":"manual","token":"fixture-token"})
                    }
                    _ => unreachable!(),
                };
                let response = response.to_string();
                write!(socket, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}", response.len(), response).unwrap();
            }
        });
        let result = recover(&origin, WORDS, "", 0, true).await.unwrap();
        assert_eq!(result["token"], "fixture-token");
        assert_eq!(result["project"], "manual");
        server.join().unwrap();
    }

    #[tokio::test]
    async fn approval_is_bodyless_put_to_pairing_resource() {
        use std::io::{Read, Write};
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let origin = format!("http://{}", listener.local_addr().unwrap());
        let id = format!("pair_{}", "a".repeat(43));
        let expected = format!("PUT /v1/pairings/{id} HTTP/1.1\r\n");
        let server = std::thread::spawn(move || {
            let (mut socket, _) = listener.accept().unwrap();
            socket
                .set_read_timeout(Some(Duration::from_secs(5)))
                .unwrap();
            let mut request = Vec::new();
            while !request.ends_with(b"\r\n\r\n") {
                let mut b = [0];
                socket.read_exact(&mut b).unwrap();
                request.push(b[0]);
            }
            let request = String::from_utf8(request).unwrap();
            assert!(request.starts_with(&expected));
            assert!(
                request
                    .to_ascii_lowercase()
                    .contains("authorization: bearer prf_test\r\n")
            );
            assert!(!request.to_ascii_lowercase().contains("content-type:"));
            socket
                .write_all(
                    b"HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
                )
                .unwrap();
        });
        let api = Api::new(
            &origin,
            "prf_test".into(),
            Api::pin(&origin, true).unwrap(),
            true,
        )
        .unwrap();
        assert!(api.approve(&id, false).await.is_err());
        api.approve(&id, true).await.unwrap();
        server.join().unwrap();
    }

    #[test]
    fn routes_are_built_in_one_place() {
        assert_eq!(Route::Altcha.path(), "/v1/altcha");
        assert_eq!(Route::Projects.path(), "/v1/projects");
        assert_eq!(Route::Project("p").path(), "/v1/projects/p");
        assert_eq!(Route::ProjectPaths("p").path(), "/v1/projects/p/paths");
        assert_eq!(Route::ProjectAccess("p").path(), "/v1/projects/p/access");
        assert_eq!(
            Route::AccessGrant {
                project: "p",
                id: "acc_1"
            }
            .path(),
            "/v1/projects/p/access/acc_1"
        );
        assert_eq!(Route::Pairing("pair_x").path(), "/v1/pairings/pair_x");
        assert_eq!(Route::Recovery.path(), "/v1/recovery");
        assert_eq!(
            Route::RecoveryAttempt("rec_1").url("https://a.example"),
            "https://a.example/v1/recovery/rec_1"
        );
    }

    #[test]
    fn bearer_routes_cannot_change_authority() {
        let origin = "https://api.example";
        let api = Api::new(
            origin,
            "prf_test".into(),
            Api::pin(origin, false).unwrap(),
            false,
        )
        .unwrap();
        for path in [
            "@attacker.example/v1/main",
            "//attacker.example/v1/main",
            "https://attacker.example/v1/main",
            "\\\\attacker.example/v1/main",
            "/v1/main#secret",
        ] {
            assert!(api.route(path).is_err(), "accepted credential route {path}");
        }
        let route = api
            .route("/v1/projects/main/paths?scope=confirmed")
            .unwrap();
        assert_eq!(route.origin().ascii_serialization(), origin);
        assert_eq!(route.path(), "/v1/projects/main/paths");
    }
}
