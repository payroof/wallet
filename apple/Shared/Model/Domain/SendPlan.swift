import Foundation

/// What a plan step does on chain (the core's `kind`).
enum PlanStepKind: String, Codable, Sendable {
  case transfer
  case topUp = "top_up"
  case authorization
  case permit
  case transferFrom = "transfer_from"
  /// Fee plumbing, not a payment to the recipient: shown small in Activity.
  var isInternal: Bool { self == .topUp || self == .permit }
}

struct PlanParty: Codable, Equatable, Sendable {
  var path: String
  var address: String
}

/// One leg: an address that sends part of the amount to the recipient.
struct PlanSource: Codable, Equatable, Sendable {
  var path: String
  var address: String
  var amount: String
}

struct PlanStep: Codable, Equatable, Sendable {
  var kind: PlanStepKind
  /// Who signs the transaction and pays its gas.
  var payerPath: String
  var payer: String
  /// Whose funds move. The payer for `transfer` and `top_up`.
  var ownerPath: String
  var owner: String
  var to: String
  var amount: String
  var gasLimit: String
  var maximumFee: String
  /// Indexes of the steps that must be confirmed first.
  var after: [Int]
  enum CodingKeys: String, CodingKey {
    case kind, payer, owner, to, amount, after
    case payerPath = "payer_path"
    case ownerPath = "owner_path"
    case gasLimit = "gas_limit"
    case maximumFee = "maximum_fee"
  }
  /// Someone other than the owner pays this step's gas.
  var sponsored: Bool { payerPath != ownerPath }
}

/// The core's reviewed plan for a send (see "Send plan" in docs/architecture.md).
struct SendPlan: Codable, Equatable, Sendable {
  var network: ChainID
  var asset: AssetID
  var recipient: String
  var amount: String
  var mode: TransactionMode
  var maxFeePerGas: String
  var maximumFee: String
  var sponsor: PlanParty?
  var sources: [PlanSource]
  var steps: [PlanStep]
  enum CodingKeys: String, CodingKey {
    case network, asset, recipient, amount, mode, sponsor, sources, steps
    case maxFeePerGas = "max_fee_per_gas"
    case maximumFee = "maximum_fee"
  }
  /// More than a plain transfer: several legs, a sponsor, or any extra step.
  var needsFlow: Bool {
    steps.count > 1 || steps.contains { $0.sponsored } || sources.count > 1
  }
}

/// Why the core could not make a plan.
/// The most an account can send of one asset (atomic units), as the core plans it: for
/// a network's coin, what is left after each address's transfer fee.
struct SendLimit: Equatable, Sendable {
  var slot: UInt32
  var asset: AssetID
  var atomic: String
}

enum SendProblem: Decodable, Equatable, Sendable {
  case insufficientFunds(held: String, needed: String)
  case noSponsor(held: String, needed: String)
  case noAddresses
  private enum Keys: String, CodingKey { case code, held, needed }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: Keys.self)
    switch try values.decode(String.self, forKey: .code) {
    case "insufficient_funds":
      self = .insufficientFunds(
        held: try values.decode(String.self, forKey: .held),
        needed: try values.decode(String.self, forKey: .needed))
    case "no_sponsor":
      self = .noSponsor(
        held: try values.decode(String.self, forKey: .held),
        needed: try values.decode(String.self, forKey: .needed))
    case "no_addresses": self = .noAddresses
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .code, in: values, debugDescription: "unknown problem")
    }
  }
}

/// `{"plan": …}` or `{"problem": …}`. Exactly one.
enum SendPlanResponse: Decodable, Sendable {
  case plan(SendPlan)
  case problem(SendProblem)
  private enum Keys: String, CodingKey { case plan, problem }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: Keys.self)
    if let plan = try values.decodeIfPresent(SendPlan.self, forKey: .plan) {
      self = .plan(plan)
    } else {
      self = .problem(try values.decode(SendProblem.self, forKey: .problem))
    }
  }
}

/// Where one step of a running send stands.
enum StepProgress: Equatable, Sendable {
  case pending
  /// Being signed, or waiting for the steps it depends on.
  case working
  case sent(String)
  case failed
}
