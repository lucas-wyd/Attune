import Foundation

struct AppIdentity: Codable, Equatable, Hashable, Sendable {
    let bundleIdentifier: String
    let displayName: String
}
