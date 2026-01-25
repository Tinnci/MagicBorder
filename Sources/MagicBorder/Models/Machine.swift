import Foundation

struct Machine: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    var isOnline: Bool
}
