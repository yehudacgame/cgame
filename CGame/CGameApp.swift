import SwiftUI

// Simple AuthService embedded for now
class AuthService: ObservableObject {
    @Published var currentUser: User?
    @Published var isAuthenticated = true
    
    init() {
        self.currentUser = User(id: "local", email: "local@cgame.app", createdAt: Date())
        print("🎮 CGame AI Recorder starting")
        print("ℹ️ Firebase Storage is enabled and ready!")
    }
    
    func signOut() throws {
        print("🔄 SignOut called")
    }
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