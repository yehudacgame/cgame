import Foundation

@MainActor
class AuthViewModel: ObservableObject {
    @Published var user: User?
    @Published var isAuthenticated = true // Always authenticated for local mode
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    init() {
        // Local mode - always authenticated
        user = User(id: "local-user", email: "local@cgame.app")
        isAuthenticated = true
    }
    
    func checkAuthStatus() {
        // Local mode - always authenticated
        isAuthenticated = true
    }
    
    func signIn(email: String, password: String) {
        // Local mode - always succeeds
        isAuthenticated = true
        user = User(id: "local-user", email: email)
    }
    
    func signUp(email: String, password: String) {
        // Local mode - always succeeds
        isAuthenticated = true
        user = User(id: "local-user", email: email)
    }
    
    func signInWithApple(result: Any) {
        // Local mode - not implemented
        isAuthenticated = true
    }
    
    func signOut() {
        // Local mode - not implemented for testing
        print("Sign out not available in local testing mode")
    }
    
    func clearError() {
        errorMessage = nil
    }
}