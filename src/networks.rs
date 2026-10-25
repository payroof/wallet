/// Plain-HTTP hosts allowed in local development: loopback, or an RFC 1918 LAN IPv4
/// (the Mac's Wi-Fi address that roofer advertises for Anvil and the API).
pub(crate) fn development_http_host(u: &url::Url) -> bool {
    match u.host() {
        Some(url::Host::Domain(d)) => d == "localhost",
        Some(url::Host::Ipv4(ip)) => ip == std::net::Ipv4Addr::LOCALHOST || ip.is_private(),
        Some(url::Host::Ipv6(ip)) => ip == std::net::Ipv6Addr::LOCALHOST,
        None => false,
    }
}
pub fn validate_rpc(raw: &str, development: bool) -> anyhow::Result<()> {
    let u = url::Url::parse(raw)?;
    anyhow::ensure!(
        u.username().is_empty() && u.password().is_none() && u.fragment().is_none(),
        "invalid RPC URL"
    );
    anyhow::ensure!(
        u.scheme() == "https" || (development && u.scheme() == "http" && development_http_host(&u)),
        "HTTPS required"
    );
    Ok(())
}
#[cfg(test)]
mod tests {
    #[test]
    fn local_transport_is_explicit_and_loopback_only() {
        for origin in [
            "http://127.0.0.1:8080",
            "http://localhost:8080",
            "http://[::1]:8080",
            "http://192.168.68.50:8080",
            "http://10.0.0.5:8545",
            "http://172.16.0.1:8545",
        ] {
            assert!(crate::api::origin(origin, false).is_err());
            assert!(super::validate_rpc(origin, false).is_err());
            assert!(crate::api::origin(origin, true).is_ok());
            assert!(super::validate_rpc(origin, true).is_ok());
        }
        for origin in [
            "http://example.com",
            "http://127.0.0.2",
            "http://8.8.8.8",
            "http://172.32.0.1",
            "http://192.169.1.1",
            "http://192.168.1.1.example",
            "http://user@localhost",
        ] {
            assert!(crate::api::origin(origin, true).is_err());
            assert!(super::validate_rpc(origin, true).is_err());
        }
        assert!(crate::api::origin("https://api.example", false).is_ok());
    }
}
