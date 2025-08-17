import SwiftUI

// Local minimal AuthService used for testing builds
class AuthService: ObservableObject {
    @Published var currentUser: User? = User(id: "local", email: "local@cgame.app", createdAt: Date())
    @Published var isAuthenticated: Bool = true
}

@main
struct CGameApp: App {
    @StateObject private var authService = AuthService()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authService)
        }
    }
}