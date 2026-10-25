//! The send plan: which of the account's addresses fund a payment, and who pays the gas.
//! Pure decisions over balances, one fee quote and what the token supports. No network
//! and no keys. `send` gathers the facts and carries the plan out.
use crate::spending::Mode;
use num_bigint::BigUint;
use serde::{Serialize, Serializer};

/// Gas ceilings of calls whose cost is not estimated (reviewed, then enforced).
pub(crate) const AUTHORIZATION_GAS: u32 = 150_000;
pub(crate) const PERMIT_GAS: u32 = 120_000;
pub(crate) const TRANSFER_FROM_GAS: u32 = 120_000;

fn decimal<S: Serializer>(value: &BigUint, serializer: S) -> Result<S::Ok, S::Error> {
    serializer.collect_str(value)
}

/// One of the account's addresses and what it holds.
#[derive(Clone, Debug)]
pub(crate) struct Holder {
    pub path: String,
    pub address: String,
    /// Balance of the asset being sent.
    pub balance: BigUint,
    /// Balance of the network's coin.
    pub native: BigUint,
}

/// What the token proves it supports.
#[derive(Clone, Copy, Debug, Default)]
pub(crate) struct Support {
    pub authorization: bool,
    pub permit: bool,
}

pub(crate) struct Input<'a> {
    pub network: &'a str,
    pub asset: &'a str,
    pub recipient: &'a str,
    pub amount: &'a BigUint,
    /// The asset is the network's coin, so every source pays its own fee.
    pub native_asset: bool,
    pub holders: &'a [Holder],
    pub prefer: Option<&'a str>,
    pub mode: Mode,
    pub max_fee_per_gas: &'a BigUint,
    /// Gas limit of the transfer of the asset.
    pub transfer_gas: u32,
    /// Gas limit of a plain coin transfer (the top-up).
    pub top_up_gas: u32,
    pub support: Support,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum Kind {
    Transfer,
    TopUp,
    Authorization,
    Permit,
    TransferFrom,
}

#[derive(Clone, Debug, Serialize)]
pub(crate) struct Party {
    pub path: String,
    pub address: String,
}

#[derive(Clone, Debug, Serialize)]
pub(crate) struct Source {
    pub path: String,
    pub address: String,
    #[serde(serialize_with = "decimal")]
    pub amount: BigUint,
}

#[derive(Clone, Debug, Serialize)]
pub(crate) struct Step {
    pub kind: Kind,
    pub payer_path: String,
    pub payer: String,
    pub owner_path: String,
    pub owner: String,
    pub to: String,
    #[serde(serialize_with = "decimal")]
    pub amount: BigUint,
    #[serde(serialize_with = "decimal")]
    pub gas_limit: BigUint,
    #[serde(serialize_with = "decimal")]
    pub maximum_fee: BigUint,
    pub after: Vec<usize>,
}

#[derive(Clone, Debug, Serialize)]
pub(crate) struct Plan {
    pub network: String,
    pub asset: String,
    pub recipient: String,
    #[serde(serialize_with = "decimal")]
    pub amount: BigUint,
    pub mode: Mode,
    #[serde(serialize_with = "decimal")]
    pub max_fee_per_gas: BigUint,
    #[serde(serialize_with = "decimal")]
    pub maximum_fee: BigUint,
    pub sponsor: Option<Party>,
    pub sources: Vec<Source>,
    pub steps: Vec<Step>,
}

/// Why no plan exists. Amounts are atomic (`insufficient_funds`) or wei (`no_sponsor`).
#[derive(Debug, Serialize, PartialEq, Eq)]
#[serde(tag = "code", rename_all = "snake_case")]
pub(crate) enum Problem {
    InsufficientFunds {
        #[serde(serialize_with = "decimal")]
        held: BigUint,
        #[serde(serialize_with = "decimal")]
        needed: BigUint,
    },
    NoSponsor {
        #[serde(serialize_with = "decimal")]
        held: BigUint,
        #[serde(serialize_with = "decimal")]
        needed: BigUint,
    },
    NoAddresses,
}

pub(crate) enum Outcome {
    Plan(Box<Plan>),
    Problem(Problem),
}

/// How one leg's gas is paid.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Method {
    SelfPay,
    Authorization,
    Permit,
    TopUp,
}

struct Leg<'a> {
    holder: &'a Holder,
    amount: BigUint,
    method: Method,
}

fn minus(a: &BigUint, b: &BigUint) -> BigUint {
    if a > b { a - b } else { BigUint::default() }
}

/// Whether the outcome depended on what the token supports, so that `send` must probe
/// the token and build again. (A plan without such steps, or a missing-funds problem,
/// would come out the same whatever the token supports.)
pub(crate) fn uses_support(outcome: &Outcome) -> bool {
    match outcome {
        Outcome::Plan(plan) => plan
            .steps
            .iter()
            .any(|s| matches!(s.kind, Kind::Authorization | Kind::Permit)),
        Outcome::Problem(problem) => matches!(problem, Problem::NoSponsor { .. }),
    }
}

fn fee_for(input: &Input<'_>, gas: u32) -> BigUint {
    BigUint::from(gas) * input.max_fee_per_gas
}

/// How a holder pays for its own leg, or who else must.
fn method_for(input: &Input<'_>, transfer_fee: &BigUint, holder: &Holder) -> Method {
    if input.native_asset || &holder.native >= transfer_fee {
        Method::SelfPay
    } else if input.support.authorization {
        Method::Authorization
    } else if input.support.permit {
        Method::Permit
    } else {
        Method::TopUp
    }
}

/// Who pays for the legs that cannot pay for themselves. `None` when every leg pays its own.
fn find_sponsor<'a>(
    input: &Input<'a>,
    legs: &[Leg<'_>],
    transfer_fee: &BigUint,
) -> Result<Option<&'a Holder>, Problem> {
    if legs.iter().all(|l| l.method == Method::SelfPay) {
        return Ok(None);
    }
    let mut candidates: Vec<&'a Holder> = input.holders.iter().collect();
    candidates.sort_by(|a, b| b.native.cmp(&a.native));
    let cost = |c: &Holder| {
        let mut total = BigUint::default();
        for leg in legs {
            total += match leg.method {
                Method::SelfPay if leg.holder.address == c.address => transfer_fee.clone(),
                Method::SelfPay => BigUint::default(),
                Method::Authorization => fee_for(input, AUTHORIZATION_GAS),
                Method::Permit => fee_for(input, PERMIT_GAS) + fee_for(input, TRANSFER_FROM_GAS),
                Method::TopUp => {
                    fee_for(input, input.top_up_gas) + minus(transfer_fee, &leg.holder.native)
                }
            };
        }
        total
    };
    // A source that cannot pay for itself cannot sponsor either.
    let eligible = |c: &Holder| {
        legs.iter()
            .all(|l| l.holder.address != c.address || l.method == Method::SelfPay)
    };
    if let Some(found) = candidates
        .iter()
        .copied()
        .find(|c| eligible(c) && c.native >= cost(c))
    {
        return Ok(Some(found));
    }
    let richest = candidates[0];
    Err(Problem::NoSponsor {
        held: richest.native.clone(),
        needed: cost(richest),
    })
}

/// The steps in dispatch order, with what waits for another step after it.
fn build_steps(
    input: &Input<'_>,
    legs: &[Leg<'_>],
    sponsor: Option<&Holder>,
    transfer_fee: &BigUint,
) -> Result<Vec<Step>, Problem> {
    // First everything that can go at once, then what waits for it.
    let mut steps: Vec<Step> = Vec::new();
    let mut waiting: Vec<(usize, Kind, &Leg<'_>)> = Vec::new();
    let step = |kind: Kind,
                payer: &Holder,
                owner: &Holder,
                to: &str,
                amount: &BigUint,
                gas: u32,
                after: Vec<usize>| Step {
        kind,
        payer_path: payer.path.clone(),
        payer: payer.address.clone(),
        owner_path: owner.path.clone(),
        owner: owner.address.clone(),
        to: to.to_string(),
        amount: amount.clone(),
        gas_limit: BigUint::from(gas),
        maximum_fee: fee_for(input, gas),
        after,
    };
    for leg in legs {
        let holder = leg.holder;
        match (leg.method, sponsor) {
            (Method::SelfPay, _) => steps.push(step(
                Kind::Transfer,
                holder,
                holder,
                input.recipient,
                &leg.amount,
                input.transfer_gas,
                vec![],
            )),
            (Method::Authorization, Some(sponsor)) => steps.push(step(
                Kind::Authorization,
                sponsor,
                holder,
                input.recipient,
                &leg.amount,
                AUTHORIZATION_GAS,
                vec![],
            )),
            (Method::Permit, Some(sponsor)) => {
                waiting.push((steps.len(), Kind::TransferFrom, leg));
                steps.push(step(
                    Kind::Permit,
                    sponsor,
                    holder,
                    input.recipient,
                    &leg.amount,
                    PERMIT_GAS,
                    vec![],
                ));
            }
            (Method::TopUp, Some(sponsor)) => {
                waiting.push((steps.len(), Kind::Transfer, leg));
                steps.push(step(
                    Kind::TopUp,
                    sponsor,
                    sponsor,
                    &holder.address,
                    &minus(transfer_fee, &holder.native),
                    input.top_up_gas,
                    vec![],
                ));
            }
            // A sponsor was found whenever a leg needs one. Never reached.
            _ => {
                return Err(Problem::NoSponsor {
                    held: BigUint::default(),
                    needed: BigUint::default(),
                });
            }
        }
    }
    for (first, kind, leg) in waiting {
        let holder = leg.holder;
        steps.push(match (kind, sponsor) {
            (Kind::TransferFrom, Some(sponsor)) => step(
                Kind::TransferFrom,
                sponsor,
                holder,
                input.recipient,
                &leg.amount,
                TRANSFER_FROM_GAS,
                vec![first],
            ),
            _ => step(
                Kind::Transfer,
                holder,
                holder,
                input.recipient,
                &leg.amount,
                input.transfer_gas,
                vec![first],
            ),
        });
    }
    Ok(steps)
}

pub(crate) fn build(input: &Input<'_>) -> Outcome {
    if input.holders.is_empty() {
        return Outcome::Problem(Problem::NoAddresses);
    }
    let transfer_fee = fee_for(input, input.transfer_gas);
    let spendable = |h: &Holder| {
        if input.native_asset {
            minus(&h.balance, &transfer_fee)
        } else {
            h.balance.clone()
        }
    };
    let usable: Vec<BigUint> = input.holders.iter().map(spendable).collect();
    let held = usable.iter().fold(BigUint::default(), |sum, v| sum + v);
    if &held < input.amount {
        return Outcome::Problem(Problem::InsufficientFunds {
            held,
            needed: input.amount.clone(),
        });
    }
    let self_paying = |h: &Holder| input.native_asset || h.native >= transfer_fee;
    let legs: Vec<Leg<'_>> = select(input, &usable, &self_paying)
        .into_iter()
        .map(|(index, amount)| {
            let holder = &input.holders[index];
            Leg {
                holder,
                amount,
                method: method_for(input, &transfer_fee, holder),
            }
        })
        .collect();
    let sponsor = match find_sponsor(input, &legs, &transfer_fee) {
        Ok(sponsor) => sponsor,
        Err(problem) => return Outcome::Problem(problem),
    };
    let steps = match build_steps(input, &legs, sponsor, &transfer_fee) {
        Ok(steps) => steps,
        Err(problem) => return Outcome::Problem(problem),
    };
    let maximum_fee = steps
        .iter()
        .fold(BigUint::default(), |sum, s| sum + &s.maximum_fee);
    if maximum_fee.bits() > 256 {
        return Outcome::Problem(Problem::InsufficientFunds {
            held,
            needed: input.amount.clone(),
        });
    }
    Outcome::Plan(Box::new(Plan {
        network: input.network.to_string(),
        asset: input.asset.to_string(),
        recipient: input.recipient.to_string(),
        amount: input.amount.clone(),
        mode: input.mode,
        max_fee_per_gas: input.max_fee_per_gas.clone(),
        maximum_fee,
        sponsor: sponsor.map(|s| Party {
            path: s.path.clone(),
            address: s.address.clone(),
        }),
        sources: legs
            .iter()
            .map(|l| Source {
                path: l.holder.path.clone(),
                address: l.holder.address.clone(),
                amount: l.amount.clone(),
            })
            .collect(),
        steps,
    }))
}

/// The fewest legs that add up to the amount, as (holder index, amount). The preferred
/// path goes first when given. Else one address that covers it all (one that pays its
/// own gas first). Else the largest balances first.
fn select(
    input: &Input<'_>,
    usable: &[BigUint],
    self_paying: &dyn Fn(&Holder) -> bool,
) -> Vec<(usize, BigUint)> {
    let mut order: Vec<usize> = (0..usable.len())
        .filter(|i| usable[*i] != BigUint::default())
        .collect();
    let preferred = input
        .prefer
        .and_then(|p| order.iter().position(|i| input.holders[*i].path == p));
    let first = if let Some(position) = preferred {
        Some(order.remove(position))
    } else {
        let covering = |i: &&usize| &usable[**i] >= input.amount;
        let pick = order
            .iter()
            .filter(covering)
            .find(|i| self_paying(&input.holders[**i]))
            .or_else(|| order.iter().find(covering))
            .copied();
        pick.inspect(|i| order.retain(|o| o != i))
    };
    order.sort_by(|a, b| usable[*b].cmp(&usable[*a]));
    let mut remaining = input.amount.clone();
    let mut legs = Vec::new();
    for index in first.into_iter().chain(order) {
        if remaining == BigUint::default() {
            break;
        }
        let part = usable[index].clone().min(remaining.clone());
        remaining -= &part;
        legs.push((index, part));
    }
    legs
}

#[cfg(test)]
mod tests {
    use super::*;

    const RECIPIENT: &str = "0x00000000000000000000000000000000000000ee";
    // With a fee of one wei per gas, fees equal gas: transfer 1_000, top-up 100,
    // authorization 150_000, permit + transferFrom 240_000.
    const NATIVE: u64 = 10_000_000;

    fn n(v: u64) -> BigUint {
        BigUint::from(v)
    }

    fn holder(index: u8, balance: u64, native: u64) -> Holder {
        Holder {
            path: format!("m/44'/60'/0'/0/{index}"),
            address: format!("0x{index:040x}"),
            balance: n(balance),
            native: n(native),
        }
    }

    struct Case {
        holders: Vec<Holder>,
        amount: u64,
        prefer: Option<String>,
        native_asset: bool,
        support: Support,
    }

    impl Case {
        fn token(holders: Vec<Holder>, amount: u64) -> Self {
            Self {
                holders,
                amount,
                prefer: None,
                native_asset: false,
                support: Support {
                    authorization: true,
                    permit: true,
                },
            }
        }
        fn build(&self) -> Outcome {
            let (amount, fee) = (n(self.amount), n(1));
            build(&Input {
                network: "eip155:1",
                asset: "eip155:1/erc20:0x00000000000000000000000000000000000000c3",
                recipient: RECIPIENT,
                amount: &amount,
                native_asset: self.native_asset,
                holders: &self.holders,
                prefer: self.prefer.as_deref(),
                mode: Mode::Eip1559,
                max_fee_per_gas: &fee,
                transfer_gas: 1_000,
                top_up_gas: 100,
                support: self.support,
            })
        }
        fn plan(&self) -> Plan {
            match self.build() {
                Outcome::Plan(plan) => *plan,
                Outcome::Problem(problem) => panic!("{problem:?}"),
            }
        }
        fn problem(&self) -> Problem {
            match self.build() {
                Outcome::Problem(problem) => problem,
                Outcome::Plan(_) => panic!("expected a problem"),
            }
        }
    }

    fn kinds(plan: &Plan) -> Vec<Kind> {
        plan.steps.iter().map(|s| s.kind).collect()
    }

    fn legs(plan: &Plan) -> Vec<(String, u64)> {
        plan.sources
            .iter()
            .map(|s| (s.address.clone(), u64::try_from(&s.amount).unwrap()))
            .collect()
    }

    #[test]
    fn one_address_that_covers_the_amount_wins_and_self_paying_comes_first() {
        // h0 covers 400 but cannot pay gas. H1 covers it too and can.
        let holders = vec![holder(0, 500, 0), holder(1, 450, NATIVE)];
        let plan = Case::token(holders.clone(), 400).plan();
        assert_eq!(legs(&plan), [(holders[1].address.clone(), 400)]);
        assert_eq!(kinds(&plan), [Kind::Transfer]);
        assert!(plan.sponsor.is_none());
        assert_eq!(plan.maximum_fee, n(1_000));
        // Only h0 covers 480: it needs a sponsor, h1 (the one with native coin).
        let plan = Case::token(holders.clone(), 480).plan();
        assert_eq!(legs(&plan), [(holders[0].address.clone(), 480)]);
        assert_eq!(kinds(&plan), [Kind::Authorization]);
        let step = &plan.steps[0];
        assert_eq!(
            (&step.payer, &step.owner),
            (&holders[1].address, &holders[0].address)
        );
        assert_eq!(step.gas_limit, n(150_000));
        assert_eq!(plan.sponsor.as_ref().unwrap().address, holders[1].address);
    }

    #[test]
    fn the_preferred_path_goes_first_even_when_it_does_not_cover_everything() {
        let holders = vec![
            holder(0, 500, NATIVE),
            holder(1, 300, NATIVE),
            holder(2, 100, NATIVE),
        ];
        let mut case = Case::token(holders.clone(), 350);
        case.prefer = Some(holders[2].path.clone());
        assert_eq!(
            legs(&case.plan()),
            [
                (holders[2].address.clone(), 100),
                (holders[0].address.clone(), 250)
            ]
        );
        case.prefer = Some(holders[1].path.clone());
        assert_eq!(
            legs(&case.plan()),
            [
                (holders[1].address.clone(), 300),
                (holders[0].address.clone(), 50)
            ]
        );
        case.prefer = Some(holders[0].path.clone());
        assert_eq!(legs(&case.plan()), [(holders[0].address.clone(), 350)]);
    }

    #[test]
    fn without_a_single_cover_the_largest_balances_are_used_first() {
        let holders = vec![
            holder(0, 100, NATIVE),
            holder(1, 300, NATIVE),
            holder(2, 200, NATIVE),
        ];
        let plan = Case::token(holders.clone(), 550).plan();
        assert_eq!(
            legs(&plan),
            [
                (holders[1].address.clone(), 300),
                (holders[2].address.clone(), 200),
                (holders[0].address.clone(), 50)
            ]
        );
        let total: BigUint = plan.sources.iter().fold(n(0), |s, l| s + &l.amount);
        assert_eq!(total, n(550));
        assert_eq!(plan.maximum_fee, n(3_000));
    }

    #[test]
    fn the_sponsor_is_the_richest_address_that_can_cover_every_sponsored_fee() {
        let holders = vec![
            holder(0, 100, 0),
            holder(1, 100, 0),
            holder(2, 0, 400_000),
            holder(3, 0, 900_000),
        ];
        let plan = Case::token(holders.clone(), 200).plan();
        assert_eq!(plan.sponsor.as_ref().unwrap().address, holders[3].address);
        assert_eq!(kinds(&plan), [Kind::Authorization, Kind::Authorization]);
        assert_eq!(plan.maximum_fee, n(300_000));
        // Two authorizations cost 300_000: neither of these can sponsor them.
        let mut poor = holders.clone();
        poor[2].native = n(250_000);
        poor[3].native = n(280_000);
        assert_eq!(
            Case::token(poor, 200).problem(),
            Problem::NoSponsor {
                held: n(280_000),
                needed: n(300_000)
            }
        );
    }

    #[test]
    fn a_self_paying_source_that_sponsors_pays_its_own_fee_too() {
        // h1 pays 150_000 for h0's authorization and 1_000 for its own transfer.
        let holders = vec![holder(0, 300, 0), holder(1, 300, 150_999)];
        let case = Case::token(holders.clone(), 600);
        assert_eq!(
            case.problem(),
            Problem::NoSponsor {
                held: n(150_999),
                needed: n(151_000)
            }
        );
        let holders = vec![holder(0, 300, 0), holder(1, 300, 151_000)];
        let plan = Case::token(holders, 600).plan();
        assert_eq!(kinds(&plan), [Kind::Authorization, Kind::Transfer]);
        assert_eq!(plan.steps[1].payer, plan.steps[1].owner);
    }

    #[test]
    fn methods_fall_back_from_authorization_to_permit_to_top_up() {
        let holders = vec![holder(0, 1_000, 300), holder(1, 0, NATIVE)];
        let mut case = Case::token(holders.clone(), 1_000);
        case.support = Support {
            authorization: false,
            permit: true,
        };
        let plan = case.plan();
        assert_eq!(kinds(&plan), [Kind::Permit, Kind::TransferFrom]);
        assert_eq!(plan.steps[1].after, [0]);
        assert_eq!(plan.steps[0].gas_limit, n(120_000));
        assert_eq!(plan.steps[1].gas_limit, n(120_000));
        assert_eq!(plan.steps[1].amount, n(1_000));
        assert_eq!(plan.steps[1].payer, holders[1].address);
        assert_eq!(plan.steps[1].owner, holders[0].address);
        assert_eq!(plan.maximum_fee, n(240_000));

        case.support = Support::default();
        let plan = case.plan();
        assert_eq!(kinds(&plan), [Kind::TopUp, Kind::Transfer]);
        // The exact missing native coin: the source's fee (1_000) less what it holds (300).
        assert_eq!(plan.steps[0].amount, n(700));
        assert_eq!(plan.steps[0].to, holders[0].address);
        assert_eq!(plan.steps[0].payer, holders[1].address);
        assert_eq!(plan.steps[0].owner, holders[1].address);
        assert_eq!(plan.steps[0].gas_limit, n(100));
        assert_eq!(plan.steps[1].after, [0]);
        assert_eq!(plan.steps[1].payer, holders[0].address);
        assert_eq!(plan.maximum_fee, n(1_100));
    }

    #[test]
    fn steps_that_can_go_at_once_come_before_the_ones_that_wait() {
        let holders = vec![holder(0, 400, 0), holder(1, 400, 0), holder(2, 400, NATIVE)];
        let mut case = Case::token(holders, 1_200);
        case.support = Support::default();
        let plan = case.plan();
        assert_eq!(
            kinds(&plan),
            [
                Kind::TopUp,
                Kind::TopUp,
                Kind::Transfer,
                Kind::Transfer,
                Kind::Transfer
            ]
        );
        assert_eq!(plan.steps[3].after, [0]);
        assert_eq!(plan.steps[4].after, [1]);
        assert_eq!(plan.steps[2].after, [] as [usize; 0]);
        for (i, step) in plan.steps.iter().enumerate() {
            assert!(step.after.iter().all(|d| *d < i));
        }
    }

    #[test]
    fn native_coin_sources_pay_their_own_fee_and_spend_balance_minus_it() {
        let holders = vec![
            holder(0, 5_000, 5_000),
            holder(1, 1_000, 1_000),
            holder(2, 900, 900),
        ];
        let mut case = Case::token(holders.clone(), 3_500);
        case.native_asset = true;
        let plan = case.plan();
        // Spendable: 4_000, 0 (the rest is dust under the fee), 0.
        assert_eq!(legs(&plan), [(holders[0].address.clone(), 3_500)]);
        assert_eq!(kinds(&plan), [Kind::Transfer]);
        assert!(plan.sponsor.is_none());
        assert_eq!(plan.maximum_fee, n(1_000));
        case.amount = 4_000;
        assert_eq!(legs(&case.plan()), [(holders[0].address.clone(), 4_000)]);
        case.amount = 4_001;
        assert_eq!(
            case.problem(),
            Problem::InsufficientFunds {
                held: n(4_000),
                needed: n(4_001)
            }
        );
        let holders = vec![holder(0, 3_000, 3_000), holder(1, 4_000, 4_000)];
        let mut case = Case::token(holders.clone(), 3_500);
        case.native_asset = true;
        let plan = case.plan();
        assert_eq!(
            legs(&plan),
            [
                (holders[1].address.clone(), 3_000),
                (holders[0].address.clone(), 500)
            ]
        );
        assert_eq!(plan.maximum_fee, n(2_000));
        assert!(
            plan.steps
                .iter()
                .all(|s| s.payer == s.owner && s.kind == Kind::Transfer)
        );
    }

    #[test]
    fn problems_are_structured() {
        assert_eq!(Case::token(vec![], 1).problem(), Problem::NoAddresses);
        let short = Case::token(vec![holder(0, 5, NATIVE), holder(1, 6, 0)], 12);
        assert_eq!(
            short.problem(),
            Problem::InsufficientFunds {
                held: n(11),
                needed: n(12)
            }
        );
        let nobody = Case::token(vec![holder(0, 12, 0), holder(1, 0, 0)], 12);
        assert_eq!(
            nobody.problem(),
            Problem::NoSponsor {
                held: n(0),
                needed: n(150_000)
            }
        );
        let json = serde_json::to_value(nobody.problem()).unwrap();
        assert_eq!(
            json,
            serde_json::json!({"code": "no_sponsor", "held": "0", "needed": "150000"})
        );
        assert_eq!(
            serde_json::to_value(Problem::NoAddresses).unwrap(),
            serde_json::json!({"code": "no_addresses"})
        );
    }

    #[test]
    fn the_plan_serializes_as_the_host_expects() {
        let holders = vec![holder(0, 300, 300), holder(1, 100, 0), holder(2, 0, NATIVE)];
        let mut case = Case::token(holders, 400);
        case.support = Support::default();
        let json = serde_json::to_value(case.plan()).unwrap();
        assert_eq!(json["mode"], "eip1559");
        assert_eq!(json["amount"], "400");
        assert_eq!(json["max_fee_per_gas"], "1");
        assert_eq!(json["steps"][0]["kind"], "top_up");
        assert_eq!(json["steps"][0]["gas_limit"], "100");
        assert_eq!(json["steps"][0]["after"], serde_json::json!([]));
        assert_eq!(json["steps"][2]["after"], serde_json::json!([0]));
        assert_eq!(json["sources"][0]["amount"], "300");
        assert!(json["sponsor"]["path"].as_str().unwrap().starts_with("m/"));
        let keys: Vec<&str> = json["steps"][0]
            .as_object()
            .unwrap()
            .keys()
            .map(String::as_str)
            .collect();
        for key in [
            "kind",
            "payer_path",
            "payer",
            "owner_path",
            "owner",
            "to",
            "amount",
            "gas_limit",
            "maximum_fee",
            "after",
        ] {
            assert!(keys.contains(&key), "{key}");
        }
    }

    #[test]
    fn support_matters_only_to_plans_that_use_it() {
        let sponsored = Case::token(vec![holder(0, 10, 0), holder(1, 0, NATIVE)], 10);
        assert!(uses_support(&sponsored.build()));
        let own = Case::token(vec![holder(0, 10, NATIVE)], 10);
        assert!(!uses_support(&own.build()));
        let short = Case::token(vec![holder(0, 1, 0)], 10);
        assert!(!uses_support(&short.build()));
        let nobody = Case::token(vec![holder(0, 10, 0)], 10);
        assert!(uses_support(&nobody.build()));
    }
}
