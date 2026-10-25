//! Solving an ALTCHA proof of work (PBKDF2/SHA-256) for a Payroof API request.
use hmac::{Hmac, KeyInit, Mac};
use sha2::Sha256;

/// The most work this client does for one challenge, whatever a server asks for.
const MAX_COST: u32 = 5000;
const MAX_COUNTER: u32 = 100_000;

/// Finds the first counter whose derived key starts with the challenge's prefix, as a
/// browser would, using the CPU's SHA-256 instructions where it has them.
pub fn solve(challenge: &altcha::Challenge) -> anyhow::Result<altcha::Solution> {
    let p = &challenge.parameters;
    let prefix = p.key_prefix.to_ascii_lowercase();
    anyhow::ensure!(
        p.algorithm == "PBKDF2/SHA-256"
            && p.key_length == 32
            && (1..=MAX_COST).contains(&p.cost)
            && (1..=64).contains(&prefix.len())
            && prefix.bytes().all(|b| b.is_ascii_hexdigit()),
        "unsupported proof"
    );
    let nonce = hex::decode(&p.nonce)?;
    let salt = hex::decode(&p.salt)?;
    for counter in 0..=MAX_COUNTER {
        let mut password = nonce.clone();
        password.extend_from_slice(&counter.to_be_bytes());
        let key = hex::encode(derive(&password, &salt, p.cost)?);
        if key.starts_with(&prefix) {
            return Ok(altcha::Solution {
                counter,
                derived_key: key,
                time: None,
            });
        }
    }
    anyhow::bail!("proof not found")
}

/// PBKDF2-HMAC-SHA-256 for one 32-byte block.
fn derive(password: &[u8], salt: &[u8], rounds: u32) -> anyhow::Result<[u8; 32]> {
    let keyed = Hmac::<Sha256>::new_from_slice(password)?;
    let mut mac = keyed.clone();
    mac.update(salt);
    mac.update(&1u32.to_be_bytes());
    let mut block: [u8; 32] = mac.finalize().into_bytes().into();
    let mut key = block;
    for _ in 1..rounds {
        let mut mac = keyed.clone();
        mac.update(&block);
        block = mac.finalize().into_bytes().into();
        key.iter_mut().zip(block).for_each(|(k, b)| *k ^= b);
    }
    Ok(key)
}

#[cfg(test)]
mod tests {
    #[test]
    fn solutions_verify_with_the_reference_implementation() {
        for counter in [0, 3] {
            let challenge = altcha::create_challenge(altcha::CreateChallengeOptions {
                algorithm: "PBKDF2/SHA-256".into(),
                cost: 5000,
                counter: Some(counter),
                key_prefix_length: Some(4),
                hmac_signature_secret: Some("secret".into()),
                ..Default::default()
            })
            .unwrap();
            let solution = super::solve(&challenge).unwrap();
            assert_eq!(solution.counter, counter);
            let verified = altcha::verify_solution(altcha::VerifySolutionOptions::new(
                &challenge, &solution, "secret",
            ))
            .unwrap();
            assert!(verified.verified);
        }
    }

    #[test]
    fn unsupported_or_oversized_challenges_are_refused() {
        let mut challenge = altcha::create_challenge(altcha::CreateChallengeOptions {
            algorithm: "PBKDF2/SHA-256".into(),
            cost: 5000,
            counter: Some(0),
            key_prefix_length: Some(4),
            ..Default::default()
        })
        .unwrap();
        challenge.parameters.cost = 5001;
        assert!(super::solve(&challenge).is_err());
        challenge.parameters.cost = 5000;
        challenge.parameters.key_prefix = "zz".into();
        assert!(super::solve(&challenge).is_err());
    }
}
