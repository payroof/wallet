import Foundation

/// Names for new accounts: an adjective from the roofs at night and an animal that
/// lives up there, e.g. "Moonlit Raccoon". A new account gets one at once. It can be
/// renamed in Edit.
enum AccountNames {
  static let adjectives = [
    "Copper", "Slate", "Moonlit", "Sleepy", "Midnight", "Rusty", "Starry", "Windy", "Cozy", "Lucky",
  ]
  static let animals = [
    "Cat", "Pigeon", "Owl", "Raccoon", "Fox", "Crow", "Seagull", "Squirrel", "Bat", "Sparrow",
  ]
  /// A random name no account has yet (compared ignoring case). Once all hundred are
  /// taken, a random one with a number after it.
  static func random(avoiding used: some Collection<String>) -> String {
    var generator = SystemRandomNumberGenerator()
    return random(avoiding: used, using: &generator)
  }
  static func random(
    avoiding used: some Collection<String>, using generator: inout some RandomNumberGenerator
  ) -> String {
    let taken = Set(used.map { $0.lowercased() })
    let all = adjectives.flatMap { adjective in animals.map { "\(adjective) \($0)" } }
    if let name = all.filter({ !taken.contains($0.lowercased()) }).randomElement(using: &generator)
    {
      return name
    }
    let base = all.randomElement(using: &generator) ?? "Rooftop Cat"
    var number = 2
    while taken.contains("\(base) \(number)".lowercased()) { number += 1 }
    return "\(base) \(number)"
  }
}
