import Foundation

struct AccessReview: Codable, Sendable {
  var id: String
  var name: String
  var permissions: [String]
  var status: String
  var expiresAt: String
  enum CodingKeys: String, CodingKey {
    case id, name, permissions, status
    case expiresAt = "expires_at"
  }
}

struct PathConnection: Codable, Identifiable, Sendable {
  var origin: String
  var project: String
  var slot: UInt32
  var root: String
  var fingerprint: String
  var id: String { origin + "#" + project }
}

/// A live credential of a project, as the API lists it.
struct AccessGrant: Codable, Identifiable, Sendable {
  var id: String
  var name: String
  var permissions: [String]
  var createdAt: String
  enum CodingKeys: String, CodingKey {
    case id, name, permissions
    case createdAt = "created_at"
  }
}
