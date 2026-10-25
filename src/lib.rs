pub(crate) mod abi;
pub mod api;
pub mod assets;
pub mod balance;
pub(crate) mod capability;
pub mod defaults;
pub mod derivation;
pub(crate) mod eip712;
pub mod ffi;
pub mod history;
pub(crate) mod ids;
pub(crate) mod indexer;
pub mod mnemonic;
pub mod networks;
pub mod pairing;
pub mod path_source;
pub(crate) mod plan;
pub mod price;
pub mod projects;
pub mod proof;
pub mod providers;
pub mod recovery;
pub mod secret;
pub(crate) mod send;
pub mod spending;
pub mod state;
pub mod stor;
#[cfg(test)]
pub(crate) mod test_support;
pub mod vault;
pub mod watch_root;
uniffi::setup_scaffolding!();
/// A single-threaded runtime for one blocking call from the host app. Each FFI call
/// runs its network work to completion on the calling (worker) thread.
pub(crate) fn runtime() -> std::io::Result<tokio::runtime::Runtime> {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
}
