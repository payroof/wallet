//! Carrying a send out: gather the facts for a plan (balances, one fee quote, gas
//! estimates, what the token supports), then, only after the user confirmed the reviewed
//! plan, sign and broadcast its steps one at a time. Nothing is signed before that.
use crate::abi::{self, hex_data, hex_quantity, normalize_address};
use crate::balance::{check_chain, parse_quantity, rpc};
use crate::capability::{self, Capability};
use crate::ids::{AssetId, ChainId};
use crate::plan::{self, Holder, Input, Kind, Outcome, Plan, Problem, Step, Support};
use crate::spending::{EvmSigner, Mode, Tx, WalletSigner};
use crate::{eip712, spending};
use anyhow::Context;
use num_bigint::BigUint;
use serde::Deserialize;
use serde_json::json;
use std::collections::BTreeMap;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use zeroize::Zeroizing;

/// The first step must start soon after the quote. The whole plan within this time.
const FIRST_STEP: Duration = Duration::from_secs(120);
const WHOLE_PLAN: Duration = Duration::from_mins(15);
/// How long a signed permit or authorization stays valid.
const SIGNATURE_LIFETIME: u64 = 15 * 60;

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Request {
    pub chain: String,
    pub asset: String,
    pub to: String,
    pub amount: String,
    pub slot: u32,
    pub prefer: Option<String>,
}

/// A dependency of the step has not been mined yet. The plan stays usable: ask again.
#[derive(Debug)]
pub struct Pending;

impl std::fmt::Display for Pending {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("a previous step is not confirmed yet")
    }
}

impl std::error::Error for Pending {}

pub enum Created {
    Plan(Box<PlanState>),
    Problem(String),
}

/// A reviewed plan and how far it has been carried out.
pub struct PlanState {
    plan: Plan,
    /// Resolved endpoint. Provider keys may be inside.
    endpoint: Zeroizing<String>,
    chain_id: BigUint,
    /// `None` when the asset is the network's coin.
    contract: Option<String>,
    capability: Capability,
    priority: BigUint,
    created: Instant,
    confirmed: bool,
    hashes: Vec<String>,
    nonces: BTreeMap<String, BigUint>,
    development: bool,
}

/// Gas limits are the node's estimate plus a quarter.
fn padded(gas: &BigUint) -> anyhow::Result<u32> {
    Ok(u32::try_from(gas * 125u32 / 100u32)?)
}

async fn estimate(
    http: &reqwest::Client,
    endpoint: &str,
    from: &str,
    to: &str,
    value: &BigUint,
    data: &[u8],
) -> anyhow::Result<u32> {
    padded(&parse_quantity(
        &rpc(
            http,
            endpoint,
            "eth_estimateGas",
            json!([{"from": from, "to": to, "value": hex_quantity(value), "data": hex_data(data)}, "latest"]),
        )
        .await?,
    )?)
}

/// Gas for a plain transfer of the network's coin, when no estimate can be made.
const TRANSFER_GAS: u32 = 21_000;
/// Gas assumed for a token transfer when the account is short and nothing is estimated.
const TOKEN_TRANSFER_GAS: u32 = 100_000;
/// The most bits a fee per gas may have: it must fit a transaction's 128-bit budget.
const FEE_BITS: u64 = 128;

/// The parts of a request that passed validation, parsed once.
struct Checked {
    recipient: String,
    amount: BigUint,
    chain: ChainId,
    asset: AssetId,
}

/// Validates a request against the account before anything is read from the network.
fn check(request: &Request, account: &[(String, String)]) -> anyhow::Result<Checked> {
    let recipient = normalize_address(&request.to)?;
    anyhow::ensure!(recipient != abi::ZERO_ADDRESS, "zero recipient");
    let amount = crate::assets::atomic(&request.amount)?;
    anyhow::ensure!(amount > BigUint::default(), "positive amount required");
    let chain: ChainId = request.chain.parse()?;
    let asset: AssetId = request.asset.parse()?;
    anyhow::ensure!(asset.chain == chain, "asset chain mismatch");
    if let Some(prefer) = &request.prefer {
        anyhow::ensure!(
            account.iter().any(|(path, _)| path == prefer),
            "unknown preferred path"
        );
    }
    Ok(Checked {
        recipient,
        amount,
        chain,
        asset,
    })
}

/// What each of the account's addresses holds of the asset and of the network's coin.
async fn read_holders(
    endpoint: &str,
    checked: &Checked,
    account: &[(String, String)],
    development: bool,
) -> anyhow::Result<Vec<Holder>> {
    let addresses: Vec<String> = account.iter().map(|(_, a)| a.clone()).collect();
    let chain = checked.chain.to_string();
    let natives = crate::balance::balances(
        endpoint,
        &chain,
        &checked.chain.native().to_string(),
        &addresses,
        development,
    )
    .await?;
    let balances = if checked.asset.contract().is_some() {
        crate::balance::balances(
            endpoint,
            &chain,
            &checked.asset.to_string(),
            &addresses,
            development,
        )
        .await?
    } else {
        natives.clone()
    };
    Ok(account
        .iter()
        .zip(balances.into_iter().zip(natives))
        .map(|((path, address), (balance, native))| Holder {
            path: path.clone(),
            address: address.clone(),
            balance,
            native,
        })
        .collect())
}

/// One fee quote for the whole plan: the most to pay per gas and the priority part of it.
async fn quote_fee(
    http: &reqwest::Client,
    endpoint: &str,
    mode: Mode,
) -> anyhow::Result<(BigUint, BigUint)> {
    let (max_fee_per_gas, priority) = match mode {
        Mode::Legacy => (
            parse_quantity(&rpc(http, endpoint, "eth_gasPrice", json!([])).await?)?,
            BigUint::default(),
        ),
        Mode::Eip1559 => {
            let priority =
                parse_quantity(&rpc(http, endpoint, "eth_maxPriorityFeePerGas", json!([])).await?)?;
            let block = rpc(
                http,
                endpoint,
                "eth_getBlockByNumber",
                json!(["latest", false]),
            )
            .await?;
            let base = parse_quantity(&block["baseFeePerGas"])?;
            (base * 2u32 + &priority, priority)
        }
    };
    anyhow::ensure!(max_fee_per_gas.bits() <= FEE_BITS, "fee overflow");
    Ok((max_fee_per_gas, priority))
}

/// Gas for the transfer itself and for topping up an address with the coin, estimated
/// from addresses that can actually make the calls.
async fn estimate_gas(
    http: &reqwest::Client,
    endpoint: &str,
    checked: &Checked,
    holders: &[Holder],
) -> anyhow::Result<(u32, u32)> {
    let contract = checked.asset.contract();
    let (recipient, amount) = (&checked.recipient, &checked.amount);
    let held = holders
        .iter()
        .fold(BigUint::default(), |s, h| s + &h.balance);
    let funded = held >= *amount;
    let transfer_gas = match (contract, funded) {
        (Some(contract), true) => {
            let from = richest(holders, |h| &h.balance).context("no funded address")?;
            let part = from.balance.clone().min(amount.clone());
            estimate(
                http,
                endpoint,
                &from.address,
                contract,
                &BigUint::default(),
                &abi::transfer(recipient, &part)?,
            )
            .await?
        }
        // The network's coin: even short of funds, since what the account can send is
        // its balance less this fee, and the problem names that figure.
        (None, _) => match richest(holders, |h| &h.native) {
            Some(from) => {
                let part = from.native.clone().min(amount.clone());
                estimate(http, endpoint, &from.address, recipient, &part, &[]).await?
            }
            None => TRANSFER_GAS,
        },
        // A token short of funds: the problem (its balance) does not depend on gas.
        (Some(_), false) => TOKEN_TRANSFER_GAS,
    };
    let top_up_gas = match (contract, richest(holders, |h| &h.native)) {
        (Some(_), Some(from)) if funded => {
            estimate(
                http,
                endpoint,
                &from.address,
                &holders[0].address,
                &BigUint::from(1u8),
                &[],
            )
            .await?
        }
        _ => TRANSFER_GAS,
    };
    Ok((transfer_gas, top_up_gas))
}

/// Plans a send from the account's `(path, address)` pairs.
pub async fn create(
    endpoint: &str,
    request: &Request,
    account: &[(String, String)],
    mode: Mode,
    development: bool,
) -> anyhow::Result<Created> {
    crate::networks::validate_rpc(endpoint, development)?;
    let checked = check(request, account)?;
    if account.is_empty() {
        return Ok(Created::Problem(serde_json::to_string(
            &Problem::NoAddresses,
        )?));
    }
    let http = crate::api::client()?;
    check_chain(&http, endpoint, &request.chain).await?;
    let holders = read_holders(endpoint, &checked, account, development).await?;
    let (max_fee_per_gas, priority) = quote_fee(&http, endpoint, mode).await?;
    let (transfer_gas, top_up_gas) = estimate_gas(&http, endpoint, &checked, &holders).await?;

    let contract = checked.asset.contract().map(str::to_string);
    let input = |support: Support| Input {
        network: &request.chain,
        asset: &request.asset,
        recipient: &checked.recipient,
        amount: &checked.amount,
        native_asset: contract.is_none(),
        holders: &holders,
        prefer: request.prefer.as_deref(),
        mode,
        max_fee_per_gas: &max_fee_per_gas,
        transfer_gas,
        top_up_gas,
        support,
    };
    let chain_id = BigUint::from(checked.chain.number());
    let mut outcome = plan::build(&input(Support {
        authorization: true,
        permit: true,
    }));
    let mut capability = Capability::default();
    if let Some(contract) = &contract
        && plan::uses_support(&outcome)
    {
        capability =
            capability::detect(&http, endpoint, &chain_id, contract, &holders[0].address).await;
        outcome = plan::build(&input(Support {
            authorization: capability.authorization,
            permit: capability.permit,
        }));
    }
    Ok(match outcome {
        Outcome::Problem(problem) => Created::Problem(serde_json::to_string(&problem)?),
        Outcome::Plan(plan) => Created::Plan(Box::new(PlanState {
            plan: *plan,
            endpoint: Zeroizing::new(endpoint.to_string()),
            chain_id,
            contract,
            capability,
            priority,
            created: Instant::now(),
            confirmed: false,
            hashes: Vec::new(),
            nonces: BTreeMap::new(),
            development,
        })),
    })
}

/// The holder with the most of something (the first on a tie), if any has any.
fn richest(holders: &[Holder], key: impl Fn(&Holder) -> &BigUint) -> Option<&Holder> {
    holders
        .iter()
        .filter(|h| *key(h) != BigUint::default())
        .reduce(|a, b| if key(b) > key(a) { b } else { a })
}

fn unix_now() -> anyhow::Result<u64> {
    Ok(SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs())
}

/// The key of `path`, accepted only if it belongs to the address the plan shows.
fn signer(words: &str, passphrase: &str, path: &str, address: &str) -> anyhow::Result<EvmSigner> {
    let key = crate::derivation::private_key(words, passphrase, path)?;
    let signer = EvmSigner::from_private_key(&key[..])?;
    anyhow::ensure!(signer.address() == address, "signing path mismatch");
    Ok(signer)
}

/// The call a step makes: destination, native value and data.
struct Call {
    to: String,
    value: BigUint,
    data: Vec<u8>,
}

impl PlanState {
    pub fn review(&self) -> &Plan {
        &self.plan
    }

    pub fn confirm(&mut self) {
        self.confirmed = true;
    }

    pub fn finished(&self) -> bool {
        self.hashes.len() == self.plan.steps.len()
    }

    /// Signs and broadcasts step `index`, which must be the next one.
    pub async fn execute(
        &mut self,
        index: usize,
        words: &str,
        passphrase: &str,
    ) -> anyhow::Result<String> {
        anyhow::ensure!(self.confirmed, "plan not confirmed");
        anyhow::ensure!(index == self.hashes.len(), "steps run in order");
        let step = self.plan.steps.get(index).context("unknown step")?.clone();
        let age = self.created.elapsed();
        anyhow::ensure!(
            age < WHOLE_PLAN && (index > 0 || age < FIRST_STEP),
            "quote expired"
        );
        crate::networks::validate_rpc(&self.endpoint, self.development)?;
        let http = crate::api::client()?;
        check_chain(&http, &self.endpoint, &self.plan.network).await?;
        for dependency in &step.after {
            let hash = self.hashes.get(*dependency).context("missing dependency")?;
            match spending::receipt_status(&http, &self.endpoint, hash).await? {
                Some(true) => {}
                None => return Err(Pending.into()),
                Some(false) => anyhow::bail!("a previous step failed"),
            }
        }
        let call = self.call(&step, words, passphrase, &http).await?;

        // The chain validates the call (and any signature in it) before anything is spent.
        let estimated = parse_quantity(
            &rpc(
                &http,
                &self.endpoint,
                "eth_estimateGas",
                json!([{"from": step.payer, "to": call.to, "value": hex_quantity(&call.value),
                        "data": hex_data(&call.data)}, "latest"]),
            )
            .await?,
        )?;
        anyhow::ensure!(estimated <= step.gas_limit, "gas above the reviewed limit");
        let balance = parse_quantity(
            &rpc(
                &http,
                &self.endpoint,
                "eth_getBalance",
                json!([step.payer, "latest"]),
            )
            .await?,
        )?;
        anyhow::ensure!(
            balance >= &step.maximum_fee + &call.value,
            "not enough for the fee"
        );
        let pending = parse_quantity(
            &rpc(
                &http,
                &self.endpoint,
                "eth_getTransactionCount",
                json!([step.payer, "pending"]),
            )
            .await?,
        )?;
        let nonce = match self.nonces.get(&step.payer) {
            Some(last) => pending.max(last + 1u32),
            None => pending,
        };
        let payer = signer(words, passphrase, &step.payer_path, &step.payer)?;
        let raw = spending::sign_transaction(
            &payer,
            &Tx {
                mode: self.plan.mode,
                chain_id: self.chain_id.clone(),
                nonce: nonce.clone(),
                priority: self.priority.clone(),
                max_fee: self.plan.max_fee_per_gas.clone(),
                gas: step.gas_limit.clone(),
                to: call.to,
                value: call.value,
                data: call.data,
            },
        )?;
        let hash = spending::send_raw(&http, &self.endpoint, &raw).await?;
        self.nonces.insert(step.payer.clone(), nonce);
        self.hashes.push(hash.clone());
        Ok(hash)
    }

    async fn call(
        &self,
        step: &Step,
        words: &str,
        passphrase: &str,
        http: &reqwest::Client,
    ) -> anyhow::Result<Call> {
        let token = || self.contract.clone().context("not a token plan");
        let recipient = &self.plan.recipient;
        let domain = || {
            self.capability
                .domain
                .as_ref()
                .context("token domain unproven")
        };
        let valid_before = || Ok::<_, anyhow::Error>(unix_now()? + SIGNATURE_LIFETIME);
        Ok(match step.kind {
            Kind::Transfer => match &self.contract {
                Some(contract) => Call {
                    to: contract.clone(),
                    value: BigUint::default(),
                    data: abi::transfer(recipient, &step.amount)?,
                },
                None => Call {
                    to: recipient.clone(),
                    value: step.amount.clone(),
                    data: vec![],
                },
            },
            Kind::TopUp => Call {
                to: step.to.clone(),
                value: step.amount.clone(),
                data: vec![],
            },
            Kind::Authorization => {
                let owner = signer(words, passphrase, &step.owner_path, &step.owner)?;
                let nonce = crate::secret::random::<32>()?;
                let valid_before = valid_before()?;
                let digest = eip712::Transfer {
                    from: &step.owner,
                    to: recipient,
                    value: &step.amount,
                    valid_after: 0,
                    valid_before,
                    nonce,
                }
                .digest(&domain()?.separator()?)?;
                let (signature, parity) = owner.sign_recoverable(&digest)?;
                Call {
                    to: token()?,
                    value: BigUint::default(),
                    data: abi::transfer_with_authorization(
                        &abi::Authorization {
                            from: &step.owner,
                            to: recipient,
                            value: &step.amount,
                            valid_after: 0,
                            valid_before,
                            nonce,
                        },
                        &abi::Split::new(&signature, parity),
                    )?,
                }
            }
            Kind::Permit => {
                let owner = signer(words, passphrase, &step.owner_path, &step.owner)?;
                let contract = token()?;
                let nonce = BigUint::from_bytes_be(&abi::one_word(
                    &rpc(
                        http,
                        &self.endpoint,
                        "eth_call",
                        json!([{"to": contract, "data": abi::query("nonces(address)", Some(&step.owner))?}, "latest"]),
                    )
                    .await?,
                )?);
                let deadline = valid_before()?;
                let digest = eip712::Permit {
                    owner: &step.owner,
                    spender: &step.payer,
                    value: &step.amount,
                    nonce: &nonce,
                    deadline,
                }
                .digest(&domain()?.separator()?)?;
                let (signature, parity) = owner.sign_recoverable(&digest)?;
                Call {
                    to: contract,
                    value: BigUint::default(),
                    data: abi::permit(
                        &step.owner,
                        &step.payer,
                        &step.amount,
                        deadline,
                        &abi::Split::new(&signature, parity),
                    )?,
                }
            }
            Kind::TransferFrom => Call {
                to: token()?,
                value: BigUint::default(),
                data: abi::transfer_from(&step.owner, recipient, &step.amount)?,
            },
        })
    }
}

#[cfg(test)]
mod tests;
