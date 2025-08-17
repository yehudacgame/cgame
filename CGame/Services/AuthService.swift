import Foundation
import SwiftUI

// Hybrid AuthService that works with or without Firebase
class AuthService: ObservableObject {
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    
    init() {
        // Start in local mode with a default user
        print("🎮 AuthService: Starting in local mode")
        self.currentUser = User(
            id: "local-user",
            email: "local@cgame.app",
            createdAt: Date()
        )
        self.isAuthenticated = true
        
        // Check if Firebase is available (will be when GoogleService-Info.plist is added)
        checkFirebaseAvailability()
    }
    
    private func checkFirebaseAvailability() {
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            print("🔥 Firebase configuration detected! Cloud features will be available.")
            // TODO: Initialize Firebase when GoogleService-Info.plist is present
        } else {
            print("📱 Running in local mode. Add GoogleService-Info.plist for cloud features.")
        }
    }
    
    func signOut() throws {
        print("🔄 AuthService: Sign out (local mode)")
        // In local mode, just refresh the user
        self.currentUser = User(
            id: "local-user",
            email: "local@cgame.app", 
            createdAt: Date()
        )
        self.isAuthenticated = true
    }
    
    // MARK: - Future Firebase Methods (will be enabled when Firebase is configured)
    
    func signInWithGoogle() async throws {
        print("ℹ️ Google Sign-In requires Firebase configuration")
        throw AuthError.firebaseNotConfigured
    }
    
    func signInWithApple() async throws {
        print("ℹ️ Apple Sign-In requires Firebase configuration")
        throw AuthError.firebaseNotConfigured
    }
    
    func signInAnonymously() async throws {
        print("ℹ️ Anonymous Sign-In requires Firebase configuration")
        throw AuthError.firebaseNotConfigured
    }
}

enum AuthError: Error, LocalizedError {
    case firebaseNotConfigured
    case invalidCredential
    case invalidState
    case signInCancelled
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .firebaseNotConfigured:
            return "Firebase not configured. Add GoogleService-Info.plist to enable cloud features."
        case .invalidCredential:
            return "Invalid credential received"
        case .invalidState:
            return "Invalid authentication state"
        case .signInCancelled:
            return "Sign in was cancelled"
        case .networkError:
            return "Network connection error"
        }
    }
}