import SwiftUI
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif
import Foundation

@main
struct CGameApp: App {
    @StateObject private var authService = AuthService()
    
    init() {
        #if canImport(FirebaseCore)
        // Configure Firebase if the plist exists
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            if FirebaseApp.app() == nil {
                FirebaseApp.configure()
                print("🔥 Firebase configured")
            }
            if let app = FirebaseApp.app() {
                print("🔎 Firebase app name: \(app.name), projectID: \(app.options.projectID ?? "nil"), bucket: \(app.options.storageBucket ?? "nil")")
            } else {
                print("⚠️ FirebaseCore loaded but FirebaseApp.app() is nil")
            }
            #if canImport(FirebaseCore)
            // Enable verbose Firebase logging in Debug builds
            #if DEBUG
            FirebaseConfiguration.shared.setLoggerLevel(.debug)
            print("🪵 Firebase logger level set to DEBUG")
            #endif
            #endif
            #if canImport(FirebaseAuth)
            if Auth.auth().currentUser == nil {
                Task { @MainActor in
                    do {
                        let result = try await Auth.auth().signInAnonymously()
                        print("🔐 App: Signed in anonymously at launch: uid=\(result.user.uid)")
                    } catch {
                        print("⚠️ App: Anonymous sign-in failed at launch: \(error.localizedDescription)")
                    }
                }
            } else {
                print("🔐 App: Using existing user uid=\(Auth.auth().currentUser?.uid ?? "nil")")
            }
            #endif
        } else {
            print("ℹ️ GoogleService-Info.plist not found. Running in local mode.")
        }
        #else
        print("ℹ️ Firebase SDK not linked. Running in local mode.")
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authService)
        }
    }
}