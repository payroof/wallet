//! Pairing links, `<origin>/v1/pairings/<id>`, which a device shows so a wallet can
//! approve it. Parsing is strict: the link must already be in its canonical form.

/// What every pairing ID starts with.
pub const ID_PREFIX: &str = "pair_";
/// The exact length of a pairing ID, prefix included.
pub const ID_LENGTH: usize = 48;

/// The path a link carries before the ID: the API's pairing route and a slash.
pub fn path_prefix() -> String {
    format!("{}/", crate::api::PAIRINGS)
}

/// Whether `id` is shaped like a pairing ID. Whether it exists is the API's to say.
pub fn valid_id(id: &str) -> bool {
    id.starts_with(ID_PREFIX)
        && id.len() == ID_LENGTH
        && id
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"_-".contains(&b))
}

/// The API origin and pairing ID of a link, with plain HTTP refused.
pub fn parse(raw: &str) -> anyhow::Result<(String, String)> {
    parse_with_development(raw, false)
}
/// Like `parse`, and accepts the local development hosts when `development` is set.
pub fn parse_with_development(raw: &str, development: bool) -> anyhow::Result<(String, String)> {
    anyhow::ensure!(
        !raw.contains('\\') && !raw.contains("/./") && !raw.contains("/../") && raw.trim() == raw,
        "noncanonical pairing URL"
    );
    let u = url::Url::parse(raw)?;
    anyhow::ensure!(
        u.username().is_empty()
            && u.password().is_none()
            && u.query().is_none()
            && u.fragment().is_none(),
        "invalid pairing URL"
    );
    crate::api::origin(&u.origin().ascii_serialization(), development)?;
    let id = u
        .path()
        .strip_prefix(path_prefix().as_str())
        .ok_or_else(|| anyhow::anyhow!("invalid pairing path"))?;
    anyhow::ensure!(valid_id(id), "invalid pairing id");
    let original_path = raw
        .split_once("://")
        .and_then(|(_, rest)| rest.split_once('/'))
        .map(|(_, path)| format!("/{path}"));
    anyhow::ensure!(
        original_path.as_deref() == Some(u.path()),
        "normalized pairing path is not allowed"
    );
    Ok((u.origin().ascii_serialization(), id.into()))
}
#[cfg(test)]
mod tests {
    use super::{ID_LENGTH, ID_PREFIX, parse, path_prefix, valid_id};

    #[test]
    fn the_format_constants_describe_the_ids_the_tests_use() {
        let id = format!("pair_{}", "a".repeat(43));
        assert_eq!((ID_PREFIX, ID_LENGTH), ("pair_", id.len()));
        assert!(valid_id(&id));
        assert_eq!(path_prefix(), "/v1/pairings/");
        for bad in [
            "",
            "pair_",
            "pair_a",
            &id[..47],
            &format!("{id}a"),
            &id.replace("pair_", "pain_"),
            &format!("pair_{}!", "a".repeat(42)),
        ] {
            assert!(!valid_id(bad), "{bad}");
        }
    }
    #[test]
    fn local_pairing_is_explicit_and_loopback_only() {
        let id = format!("pair_{}", "a".repeat(43));
        let local = format!("http://127.0.0.1:8080/v1/pairings/{id}");
        assert!(parse(&local).is_err());
        assert_eq!(
            super::parse_with_development(&local, true).unwrap().0,
            "http://127.0.0.1:8080"
        );
        for host in ["api.example", "127.0.0.2", "8.8.8.8", "192.169.1.1"] {
            assert!(
                super::parse_with_development(&format!("http://{host}/v1/pairings/{id}"), true)
                    .is_err()
            );
        }
    }
    #[test]
    fn local_pairing_accepts_lan_ipv4() {
        let id = format!("pair_{}", "a".repeat(43));
        let lan = format!("http://192.168.68.50:8080/v1/pairings/{id}");
        assert!(parse(&lan).is_err());
        assert_eq!(
            super::parse_with_development(&lan, true).unwrap().0,
            "http://192.168.68.50:8080"
        );
    }
    #[test]
    fn strict_pairing_urls() {
        let id = format!("pair_{}", "a".repeat(43));
        assert_eq!(
            parse(&format!("https://api.example:8443/v1/pairings/{id}")).unwrap(),
            ("https://api.example:8443".into(), id.clone())
        );
        for raw in [
            format!("http://api.example/v1/pairings/{id}"),
            format!("https://user@api.example/v1/pairings/{id}"),
            format!("https://api.example/v1/pairings/{id}?token=x"),
            format!("https://api.example/v1/pairings/{id}#x"),
            format!("https://api.example/v1/pairings/{id}/"),
            format!("https://api.example/v1/pairings/{id}/extra"),
            format!("https://api.example/v1/pairings/%2e%2e/pairings/{id}"),
            format!("https://api.example/v1/pairings/%70{}", &id[1..]),
            format!("https://api.example/v1/pairings/../pairings/{id}"),
            format!("https://api.example/v1/pairings/.%2e/pairings/{id}"),
            format!("https://api.example\\v1\\pairings\\{id}"),
            format!(" https://api.example/v1/pairings/{id}"),
        ] {
            assert!(parse(&raw).is_err(), "accepted {raw}");
        }
    }
}
