//! Test helpers: a local HTTP server answering every request with a handler, and
//! signature recovery.
use serde_json::Value;
use std::io::{Read, Write};
use std::sync::{Arc, atomic::AtomicBool, atomic::Ordering};
use std::time::Duration;

pub(crate) type Handler = dyn Fn(&str, &Value) -> (u16, Value) + Send + Sync;

/// A local HTTP server: `handler(path, json_body)` answers every request.
pub(crate) struct Server {
    pub base: String,
    stop: Arc<AtomicBool>,
    thread: Option<std::thread::JoinHandle<()>>,
}

impl Server {
    pub fn start(handler: Arc<Handler>) -> Self {
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        let stop = Arc::new(AtomicBool::new(false));
        let flag = stop.clone();
        let thread = std::thread::spawn(move || {
            while let Ok((mut socket, _)) = listener.accept() {
                if flag.load(Ordering::SeqCst) {
                    return;
                }
                socket
                    .set_read_timeout(Some(Duration::from_secs(5)))
                    .unwrap();
                let mut head = Vec::new();
                while !head.ends_with(b"\r\n\r\n") {
                    let mut byte = [0];
                    if socket.read_exact(&mut byte).is_err() {
                        break;
                    }
                    head.push(byte[0]);
                }
                let head = String::from_utf8_lossy(&head).to_string();
                let path = head.split(' ').nth(1).unwrap_or("/").to_string();
                let length: usize = head
                    .lines()
                    .find_map(|l| {
                        let (k, v) = l.split_once(':')?;
                        k.eq_ignore_ascii_case("content-length")
                            .then(|| v.trim().parse().unwrap())
                    })
                    .unwrap_or(0);
                let mut body = vec![0; length];
                let _ = socket.read_exact(&mut body);
                let request = serde_json::from_slice(&body).unwrap_or(Value::Null);
                let (status, answer) = handler(&path, &request);
                let text = answer.to_string();
                let _ = write!(
                    socket,
                    "HTTP/1.1 {status} X\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{text}",
                    text.len()
                );
            }
        });
        Self {
            base,
            stop,
            thread: Some(thread),
        }
    }
    pub fn finish(mut self) {
        self.stop.store(true, Ordering::SeqCst);
        let _ = std::net::TcpStream::connect(self.base.trim_start_matches("http://"));
        self.thread.take().unwrap().join().unwrap();
    }
}

/// The address that produced `r || s` over `digest` (with recovery parity 0 or 1).
pub(crate) fn recover(digest: &[u8; 32], signature: &[u8; 64], parity: u8) -> String {
    use k256::ecdsa::{RecoveryId, Signature, VerifyingKey};
    let key = VerifyingKey::recover_from_prehash(
        digest,
        &Signature::from_slice(signature).unwrap(),
        RecoveryId::from_byte(parity).unwrap(),
    )
    .unwrap();
    crate::derivation::evm_address(&(&key).into())
}
