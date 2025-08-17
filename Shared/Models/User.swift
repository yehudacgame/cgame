import Foundation

struct User: Codable, Identifiable {
    let id: String
    let email: String
    let createdAt: Date
    
    init(id: String, email: String, createdAt: Date = Date()) {
        self.id = id
        self.email = email
        self.createdAt = createdAt
    }
}