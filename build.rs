//! Build-time embedding of the two asset files the core reads.
//!
//! Logos: embeds the files that `assets/defaults.json` names, and only those. The JSON is
//! the one list: each entry's `logo` is a path under `assets/icons`. A missing file or a
//! path that leaves that folder fails the build. The generated `embedded_logo` is the only
//! way the core reads a logo, so nothing is looked up by ID or by convention.
//!
//! Provider presets: turns `assets/providers.json` into the `PRESETS` constant that
//! `src/providers.rs` includes. A malformed file fails the build, so the core never parses
//! it at run time.
use std::collections::BTreeSet;
use std::fmt::Write as _;
use std::path::{Component, Path, PathBuf};

fn main() {
    let root = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").expect("manifest dir"));
    let out = PathBuf::from(std::env::var("OUT_DIR").expect("out dir"));
    embed_logos(&root, &out);
    embed_presets(&root, &out);
}

fn embed_logos(root: &Path, out: &Path) {
    println!("cargo:rerun-if-changed=assets/defaults.json");
    println!("cargo:rerun-if-changed=assets/icons");
    let text = std::fs::read_to_string(root.join("assets/defaults.json")).expect("defaults.json");
    let value: serde_json::Value = serde_json::from_str(&text).expect("defaults.json is JSON");
    let mut references = BTreeSet::new();
    for list in [
        &value["networks"],
        &value["assets"],
        &value["development"]["networks"],
        &value["development"]["assets"],
    ] {
        for entry in list.as_array().into_iter().flatten() {
            let id = entry["id"].as_str().unwrap_or("?");
            let logo = entry["logo"]
                .as_str()
                .unwrap_or_else(|| panic!("{id} declares no logo"));
            let safe = Path::new(logo)
                .components()
                .all(|part| matches!(part, Component::Normal(_)));
            assert!(
                safe && Path::new(logo).extension().is_some_and(|ext| ext == "svg"),
                "{id}: logo must be a relative .svg path under assets/icons"
            );
            references.insert(logo.to_string());
        }
    }
    let mut code = String::from(
        "/// The SVG text of a logo named in `assets/defaults.json`.\n\
         pub(crate) fn embedded_logo(path: &str) -> Option<&'static str> {\n    match path {\n",
    );
    for logo in &references {
        let file = root.join("assets/icons").join(logo);
        assert!(
            file.is_file(),
            "logo {logo} does not exist under assets/icons"
        );
        writeln!(
            code,
            "        {logo:?} => Some(include_str!({:?})),",
            file.to_str().expect("UTF-8 path")
        )
        .expect("write to string");
    }
    code.push_str("        _ => None,\n    }\n}\n");
    std::fs::write(out.join("logos.rs"), code).expect("write logos.rs");
}

/// Writes `PRESETS: &[(&str, &[u64], &str)]`, one `(provider id, chains, key)` per entry.
fn embed_presets(root: &Path, out: &Path) {
    println!("cargo:rerun-if-changed=assets/providers.json");
    let text = std::fs::read_to_string(root.join("assets/providers.json")).expect("providers.json");
    let value: serde_json::Value = serde_json::from_str(&text).expect("providers.json is JSON");
    let mut code = String::from("const PRESETS: &[(&str, &[u64], &str)] = &[\n");
    for entry in value["presets"].as_array().expect("presets is a list") {
        let provider = entry["provider"].as_str().expect("preset names a provider");
        let key = entry["key"].as_str().expect("preset has a key");
        let chains: Vec<u64> = entry["chains"]
            .as_array()
            .expect("preset lists chains")
            .iter()
            .map(|chain| chain.as_u64().expect("chain is a number"))
            .collect();
        assert!(!chains.is_empty(), "{provider} preset lists no chain");
        writeln!(code, "    ({provider:?}, &{chains:?}, {key:?}),").expect("write to string");
    }
    code.push_str("];\n");
    std::fs::write(out.join("presets.rs"), code).expect("write presets.rs");
}
