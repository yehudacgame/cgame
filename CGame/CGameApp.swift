import SwiftUI
import AVFoundation
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
    @Environment(\.scenePhase) private var scenePhase
    
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
        // Process any pending session (creates clips in Clips directory)
        processPendingSessionIfAny()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authService)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { processPendingSessionIfAny() }
        }
    }
}

// MARK: - Lightweight pending session processor
extension CGameApp {
    private func processPendingSessionIfAny() {
        guard let defaults = UserDefaults(suiteName: "group.com.cgame.shared") else { return }
        guard defaults.bool(forKey: "broadcastFinished") == true else { return }
        defaults.set(false, forKey: "broadcastFinished")

        guard let pending = AppGroupManager.shared.loadPendingSessionInfo() else { return }
        let sessionURL = pending.sessionURL
        let killEvents = pending.killEvents

        let pre: Double = defaults.object(forKey: "preRollDuration") != nil ? defaults.double(forKey: "preRollDuration") : 5.0
        let post: Double = defaults.object(forKey: "postRollDuration") != nil ? defaults.double(forKey: "postRollDuration") : 5.0

        trimClips(sessionURL: sessionURL, kills: killEvents, pre: pre, post: post) {
            AppGroupManager.shared.clearPendingSessionInfo()
        }
    }

    private func trimClips(sessionURL: URL, kills: [(Date, Double, String)], pre: Double, post: Double, completion: @escaping () -> Void) {
        let asset = AVAsset(url: sessionURL)
        let duration = asset.duration.seconds

        let group = DispatchGroup()
        for (index, kill) in kills.enumerated() {
            let killTime = kill.1
            let start = max(0, min(killTime - pre, duration))
            let end = min(duration, max(start, killTime + post))
            let timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                        duration: CMTime(seconds: end - start, preferredTimescale: 600))

            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let filename = "kill_\(index + 1)_\(df.string(from: kill.0)).mp4"

            guard let destDir = AppGroupManager.shared.getClipsDirectory() else { continue }
            let outURL = destDir.appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: outURL)

            group.enter()
            exportPassthrough(asset: asset, timeRange: timeRange, outputURL: outURL) { _ in
                group.leave()
            }
        }

        group.notify(queue: .main, execute: completion)
    }

    private func exportPassthrough(asset: AVAsset, timeRange: CMTimeRange, outputURL: URL, completion: @escaping (Bool) -> Void) {
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            completion(false)
            return
        }
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.timeRange = timeRange
        session.shouldOptimizeForNetworkUse = true
        session.exportAsynchronously {
            completion(session.status == .completed)
        }
    }
}