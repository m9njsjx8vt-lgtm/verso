import Foundation

struct ChatMessage: Identifiable, Equatable {
    enum Role: String { case user, assistant }
    var id: UUID = UUID()
    var role: Role
    var content: String
    var timestamp: Date = Date()
}
