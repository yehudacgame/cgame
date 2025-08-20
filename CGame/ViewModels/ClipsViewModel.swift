import Foundation
import AVFoundation
import CoreMedia
import UIKit
#if canImport(FirebaseStorage)
import FirebaseStorage
#endif
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

@MainActor
class ClipsViewModel: ObservableObject {
    @Published var clips: [Clip] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isProcessingClips = false
    @Published var processingCompletedCount: Int = 0
    @Published var processingTotalCount: Int = 0
    
    private var processingTimer: DispatchSourceTimer?
    private let processingQueue = DispatchQueue(label: "com.cgame.clips-processing", qos: .userInitiated)

    init() {
        loadClips()
        startProcessingPendingClips()
    }

    func loadClips() {
        NSLog("🎬 ClipsViewModel: loadClips() called")
        isLoading = true
        errorMessage = nil
        
        Task(priority: .userInitiated) {
            let urls = AppGroupManager.shared.getAllClipFiles()
            NSLog("🎬 ClipsViewModel: Found \(urls.count) clip URLs from AppGroupManager")
            var loadedClips: [Clip] = []
            
            for url in urls {
                let fileExists = FileManager.default.fileExists(atPath: url.path)
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
                guard fileExists && fileSize > 0 else { continue }
                let pathExtension = url.pathExtension.lowercased()
                guard pathExtension == "mp4" || pathExtension == "mov" else { continue }
                
                do {
                    let asset = AVAsset(url: url)
                    let duration = try await asset.load(.duration).seconds
                    let timestamp = (try? FileManager.default.attributesOfItem(atPath: url.path)[.creationDate] as? Date) ?? Date()
                    let clip = Clip(
                        id: url.lastPathComponent,
                        game: "Call of Duty",
                        events: ["Kill"],
                        timestamp: timestamp,
                        duration: duration,
                        storagePath: url.path,
                        localURL: url
                    )
                    loadedClips.append(clip)
                } catch {
                    let timestamp = (try? FileManager.default.attributesOfItem(atPath: url.path)[.creationDate] as? Date) ?? Date()
                    let clip = Clip(
                        id: url.lastPathComponent,
                        game: "Call of Duty",
                        events: ["Kill"],
                        timestamp: timestamp,
                        duration: 0,
                        storagePath: url.path,
                        localURL: url
                    )
                    loadedClips.append(clip)
                }
            }
            self.clips = loadedClips.sorted(by: { $0.timestamp > $1.timestamp })
            if loadedClips.isEmpty { self.errorMessage = "No clips found in directory" }
            isLoading = false
        }
    }
    
    func deleteClip(_ clip: Clip) {
        if let localURL = clip.localURL {
            try? FileManager.default.removeItem(at: localURL)
                if let index = clips.firstIndex(where: { $0.id == clip.id }) {
                    clips.remove(at: index)
            }
        }
    }

    func refreshClips() { loadClips() }
    func clearError() { errorMessage = nil }
    
    // MARK: - Session Monitoring
    private func startProcessingPendingClips() {
        NSLog("🚀 ClipsViewModel: Starting session metadata monitoring timer")
        processingTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: processingQueue)
        timer.schedule(deadline: .now(), repeating: 2.0)
        timer.setEventHandler { [weak self] in
            Task { await self?.checkForNewSessions() }
        }
        processingTimer = timer
        timer.resume()
        Task { await checkForNewSessions() }
    }
    
    private func checkForNewSessions() async {
        guard let sessionInfo = AppGroupManager.shared.loadPendingSessionInfo() else { return }
        let sessionUpdatedAt = UserDefaults(suiteName: "group.com.cgame.shared")?.double(forKey: "session_updated_at") ?? 0
        let lastProcessedAt = UserDefaults.standard.double(forKey: "last_processed_session_at")
        guard sessionUpdatedAt > lastProcessedAt else { return }
        UserDefaults.standard.set(sessionUpdatedAt, forKey: "last_processed_session_at")
        await processSessionInfo(sessionInfo)
    }
    
    private func processSessionInfo(_ sessionInfo: (sessionURL: URL, killEvents: [(Date, Double, String)])) async {
        NSLog("🎬 ClipsViewModel: Processing session with \(sessionInfo.killEvents.count) kills")
        await MainActor.run {
            self.isProcessingClips = true
            self.processingCompletedCount = 0
        }

        // Group kills into multi-kill windows based on cooldown from settings
        let settings = readClipSettings()
        let groups = groupKillsByCooldown(sessionInfo.killEvents, cooldownSeconds: settings.cooldownSeconds)
        NSLog("🎯 ClipsViewModel: Grouped into \(groups.count) clip(s) with cooldown=\(settings.cooldownSeconds)s")
        await MainActor.run { self.processingTotalCount = groups.count }

        var processedClipCount = 0
        for (index, group) in groups.enumerated() {
            if await createGroupKillClip(sessionURL: sessionInfo.sessionURL, killGroup: group, groupIndex: index + 1, settings: settings) {
                processedClipCount += 1
            }
            await MainActor.run { self.processingCompletedCount = processedClipCount }
        }
        
        AppGroupManager.shared.clearPendingSessionInfo()
        if processedClipCount == groups.count {
            try? FileManager.default.removeItem(at: sessionInfo.sessionURL)
            NSLog("🗑️ ClipsViewModel: Cleaned up session file: \(sessionInfo.sessionURL.lastPathComponent)")
        }
        await MainActor.run {
            self.isProcessingClips = false
            self.loadClips()
        }
    }
    
    private func createKillClipFromSessionInfo(sessionURL: URL, killEvent: (Date, Double, String), index: Int) async -> Bool {
        // Resolve session file path in case the saved URL points to an inaccessible extension sandbox path
        guard let resolvedURL = resolveAccessibleSessionURL(originalURL: sessionURL) else {
            NSLog("❌ ClipsViewModel: Session file not found at original or fallback locations: \(sessionURL.lastPathComponent)")
            return false
        }
        if resolvedURL != sessionURL { NSLog("🔁 ClipsViewModel: Using fallback session URL: \(resolvedURL.path)") }
        
        let asset = AVAsset(url: resolvedURL)
        do {
            let duration = try await asset.load(.duration)
            let sessionDurationSeconds = duration.seconds
            let preRoll: Double = readClipSettings().preRollSeconds
            let postRoll: Double = readClipSettings().postRollSeconds
            let sessionStartDate = extractSessionStartFromFilename(sessionURL.lastPathComponent)
            let killOffsetInSession = killEvent.0.timeIntervalSince(sessionStartDate)
            let startTime = max(0, killOffsetInSession - preRoll)
            let endTime = min(sessionDurationSeconds, killOffsetInSession + postRoll)
            let clipStart = CMTime(seconds: startTime, preferredTimescale: 600)
            let clipDuration = CMTime(seconds: endTime - startTime, preferredTimescale: 600)
            let timeRange = CMTimeRange(start: clipStart, duration: clipDuration)
            
            guard let clipsDir = AppGroupManager.shared.getClipsDirectory() else { return false }
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let timestamp = dateFormatter.string(from: killEvent.0)
            let clipFilename = "kill_\(index)_\(timestamp).mp4"
            let outputURL = clipsDir.appendingPathComponent(clipFilename)
            
            guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else { return false }
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .mp4
            exportSession.timeRange = timeRange
        
            // COD Mobile rotation fix (landscape in portrait)
        do {
            if let videoTrack = try await asset.loadTracks(withMediaType: .video).first {
                let videoComposition = AVMutableVideoComposition()
                    videoComposition.renderSize = CGSize(width: 1920, height: 888)
                videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
                let instruction = AVMutableVideoCompositionInstruction()
                instruction.timeRange = timeRange
                let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
                let rotateTransform = CGAffineTransform(rotationAngle: -CGFloat.pi/2)
                let translateTransform = CGAffineTransform(translationX: 0, y: 888)
                let finalTransform = rotateTransform.concatenating(translateTransform)
                layerInstruction.setTransform(finalTransform, at: .zero)
                instruction.layerInstructions = [layerInstruction]
                videoComposition.instructions = [instruction]
                exportSession.videoComposition = videoComposition
            }
        } catch {
            NSLog("⚠️ ClipsViewModel: Could not load video tracks for rotation fix: \(error)")
        }
        
        await exportSession.export()
            switch exportSession.status {
            case .completed:
                NSLog("✅ ClipsViewModel: Kill clip #\(index) exported: \(clipFilename)")
                
                // Optional cloud upload if Firebase is configured
                #if canImport(FirebaseCore)
                if FirebaseApp.app() != nil {
                    do {
                        let clipId = clipFilename.replacingOccurrences(of: ".mp4", with: "")
                        let userId = await resolveUserIdForCloud()
                        NSLog("☁️ ClipsViewModel: Preparing cloud upload for userId=\(userId), clipId=\(clipId)")
                        
                        // Upload video
                        _ = try await StorageService.shared.uploadClip(from: outputURL, clipId: clipId, userId: userId)
                        
                        // Generate thumbnail
                        let thumbGenerator = AVAssetImageGenerator(asset: asset)
                        thumbGenerator.appliesPreferredTrackTransform = true
                        let thumbTime = CMTime(seconds: max(0.5, startTime + 1.0), preferredTimescale: 600)
                        if let cgImage = try? thumbGenerator.copyCGImage(at: thumbTime, actualTime: nil) {
                            let image = UIImage(cgImage: cgImage)
                            if let jpegData = image.jpegData(compressionQuality: 0.8) {
                                let thumbnailURL = try await StorageService.shared.uploadThumbnail(from: jpegData, clipId: clipId, userId: userId)
                                #if canImport(FirebaseFirestore)
                                let db = Firestore.firestore()
                                try await db.collection("users").document(userId).collection("clips").document(clipId).setData([
                                    "game": "Call of Duty",
                                    "events": ["Kill"],
                                    "timestamp": Timestamp(date: killEvent.0),
                                    "duration": endTime - startTime,
                                    "storagePath": "clips/\(userId)/\(clipId).mp4",
                                    "thumbnailURL": thumbnailURL
                                ])
                                NSLog("✅ ClipsViewModel: Cloud metadata saved for clipId=\(clipId), userId=\(userId)")
                                #endif
                            }
                        }
                    } catch {
                        NSLog("⚠️ ClipsViewModel: Cloud upload failed for clip #\(index): \(error.localizedDescription)")
                    }
                }
                else {
                    NSLog("ℹ️ ClipsViewModel: Firebase not configured at runtime; skipping cloud upload")
                }
                #endif
                
                return true
            default:
                NSLog("❌ ClipsViewModel: Kill clip #\(index) export failed: \(exportSession.error?.localizedDescription ?? "Unknown")")
                return false
            }
        } catch {
            NSLog("❌ ClipsViewModel: Failed to load asset duration: \(error)")
            return false
        }
    }
    
    // MARK: - Cloud auth helper
    private func resolveUserIdForCloud() async -> String {
        #if canImport(FirebaseCore)
        guard FirebaseApp.app() != nil else { return "anonymous" }
        #if canImport(FirebaseAuth)
        if Auth.auth().currentUser == nil {
            do {
                let result = try await Auth.auth().signInAnonymously()
                NSLog("🔐 ClipsViewModel: Signed in anonymously: uid=\(result.user.uid)")
                return result.user.uid
            } catch {
                NSLog("⚠️ ClipsViewModel: Anonymous sign-in failed: \(error.localizedDescription)")
                return "anonymous"
            }
        } else {
            let uid = Auth.auth().currentUser?.uid ?? "anonymous"
            NSLog("🔐 ClipsViewModel: Using existing user uid=\(uid)")
            return uid
        }
        #else
        return "anonymous"
        #endif
        #else
        return "anonymous"
        #endif
    }
    
    private func extractSessionStartFromFilename(_ filename: String) -> Date {
        let components = filename.replacingOccurrences(of: "session_", with: "").replacingOccurrences(of: ".mp4", with: "")
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        dateFormatter.timeZone = TimeZone.current
        return dateFormatter.date(from: components) ?? Date()
    }
    
    private func resolveAccessibleSessionURL(originalURL: URL) -> URL? {
        // First, check the original path
        if FileManager.default.fileExists(atPath: originalURL.path) { return originalURL }
        
        // Fallback: try App Group clips directory with same filename
        if let clipsDir = AppGroupManager.shared.getClipsDirectory() {
            let candidate = clipsDir.appendingPathComponent(originalURL.lastPathComponent)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        
        // Fallback: try App Group root (extension might have saved at container root)
        if let container = AppGroupManager.shared.containerURL {
            let candidate = container.appendingPathComponent(originalURL.lastPathComponent)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        
        return nil
    }
}


// MARK: - Multi-kill grouping helpers
private extension ClipsViewModel {
    struct ClipSettings {
        let preRollSeconds: Double
        let postRollSeconds: Double
        let cooldownSeconds: Double
    }

    func readClipSettings() -> ClipSettings {
        let defaults = UserDefaults(suiteName: "group.com.cgame.shared")
        let pre = defaults?.double(forKey: "preRollDuration") ?? 5.0
        let post = defaults?.double(forKey: "postRollDuration") ?? 3.0
        let cooldown = defaults?.double(forKey: "killCooldownSeconds") ?? 5.0
        return ClipSettings(preRollSeconds: pre == 0 ? 5.0 : pre,
                            postRollSeconds: post == 0 ? 3.0 : post,
                            cooldownSeconds: cooldown == 0 ? 5.0 : cooldown)
    }

    typealias KillEvent = (Date, Double, String)

    func groupKillsByCooldown(_ kills: [KillEvent], cooldownSeconds: Double) -> [[KillEvent]] {
        guard !kills.isEmpty else { return [] }
        let sorted = kills.sorted { $0.0 < $1.0 }
        var groups: [[KillEvent]] = []
        var current: [KillEvent] = [sorted[0]]
        for i in 1..<sorted.count {
            let prev = sorted[i-1].0
            let cur = sorted[i].0
            if cur.timeIntervalSince(prev) <= cooldownSeconds {
                current.append(sorted[i])
            } else {
                groups.append(current)
                current = [sorted[i]]
            }
        }
        groups.append(current)
        return groups
    }

    func multiKillLabel(for count: Int) -> String {
        switch count {
        case 2: return "Double Kill"
        case 3: return "Triple Kill"
        case 4: return "Quad Kill"
        case 5: return "Penta Kill"
        default:
            return count >= 6 ? "Multi Kill x\(count)" : "Kill"
        }
    }

    func createGroupKillClip(sessionURL: URL, killGroup: [KillEvent], groupIndex: Int, settings: ClipSettings) async -> Bool {
        guard let resolvedURL = resolveAccessibleSessionURL(originalURL: sessionURL) else {
            NSLog("❌ ClipsViewModel: Session file not found at original or fallback locations: \(sessionURL.lastPathComponent)")
            return false
        }
        let asset = AVAsset(url: resolvedURL)
        do {
            let duration = try await asset.load(.duration)
            let sessionDurationSeconds = duration.seconds

            let sessionStartDate = extractSessionStartFromFilename(sessionURL.lastPathComponent)
            guard let first = killGroup.first?.0, let last = killGroup.last?.0 else { return false }
            let firstOffset = first.timeIntervalSince(sessionStartDate)
            let lastOffset = last.timeIntervalSince(sessionStartDate)

            let startTime = max(0, firstOffset - settings.preRollSeconds)
            let endTime = min(sessionDurationSeconds, lastOffset + settings.postRollSeconds)
            let clipStart = CMTime(seconds: startTime, preferredTimescale: 600)
            let clipDuration = CMTime(seconds: endTime - startTime, preferredTimescale: 600)
            let timeRange = CMTimeRange(start: clipStart, duration: clipDuration)

            guard let clipsDir = AppGroupManager.shared.getClipsDirectory() else { return false }
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let timestamp = dateFormatter.string(from: first)
            let suffix = killGroup.count >= 2 ? "_multi_\(killGroup.count)" : ""
            let clipFilename = "killGroup_\(groupIndex)_\(timestamp)\(suffix).mp4"
            let outputURL = clipsDir.appendingPathComponent(clipFilename)

            guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else { return false }
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .mp4
            exportSession.timeRange = timeRange

            // Rotation fix
            do {
                if let videoTrack = try await asset.loadTracks(withMediaType: .video).first {
            let videoComposition = AVMutableVideoComposition()
                    videoComposition.renderSize = CGSize(width: 1920, height: 888)
            videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
            let instruction = AVMutableVideoCompositionInstruction()
                    instruction.timeRange = timeRange
            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
                    let rotateTransform = CGAffineTransform(rotationAngle: -CGFloat.pi/2)
                    let translateTransform = CGAffineTransform(translationX: 0, y: 888)
            let finalTransform = rotateTransform.concatenating(translateTransform)
            layerInstruction.setTransform(finalTransform, at: .zero)
            instruction.layerInstructions = [layerInstruction]
            videoComposition.instructions = [instruction]
            exportSession.videoComposition = videoComposition
                }
            } catch {
                NSLog("⚠️ ClipsViewModel: Could not load video tracks for rotation fix: \(error)")
            }

            await exportSession.export()
            guard exportSession.status == .completed else {
                NSLog("❌ ClipsViewModel: Group clip export failed: \(exportSession.error?.localizedDescription ?? "Unknown")")
                return false
            }
            NSLog("✅ ClipsViewModel: Group clip #\(groupIndex) exported (kills=\(killGroup.count)): \(clipFilename)")

            #if canImport(FirebaseCore)
            if FirebaseApp.app() != nil {
                do {
                    let clipId = clipFilename.replacingOccurrences(of: ".mp4", with: "")
                    let userId = await resolveUserIdForCloud()
                    NSLog("☁️ ClipsViewModel: Preparing cloud upload for userId=\(userId), clipId=\(clipId)")

                    _ = try await StorageService.shared.uploadClip(from: outputURL, clipId: clipId, userId: userId)

                    let thumbGenerator = AVAssetImageGenerator(asset: asset)
                    thumbGenerator.appliesPreferredTrackTransform = true
                    let thumbTime = CMTime(seconds: max(0.5, startTime + 1.0), preferredTimescale: 600)
                    var thumbnailURLString = ""
                    if let cgImage = try? thumbGenerator.copyCGImage(at: thumbTime, actualTime: nil) {
                        let image = UIImage(cgImage: cgImage)
                        if let jpegData = image.jpegData(compressionQuality: 0.8) {
                            thumbnailURLString = try await StorageService.shared.uploadThumbnail(from: jpegData, clipId: clipId, userId: userId)
                        }
                    }

                    #if canImport(FirebaseFirestore)
                    let db = Firestore.firestore()
                    let label = multiKillLabel(for: killGroup.count)
                    try await db.collection("users").document(userId).collection("clips").document(clipId).setData([
                        "game": "Call of Duty",
                        "events": killGroup.count >= 2 ? [label] : ["Kill"],
                        "kills": killGroup.count,
                        "timestamp": Timestamp(date: first),
                        "duration": endTime - startTime,
                        "storagePath": "clips/\(userId)/\(clipId).mp4",
                        "thumbnailURL": thumbnailURLString,
                        "cooldownSeconds": settings.cooldownSeconds
                    ])
                    NSLog("✅ ClipsViewModel: Cloud metadata saved for group clipId=\(clipId), label=\(label)")
                    #endif
                } catch {
                    NSLog("⚠️ ClipsViewModel: Cloud upload failed for group clip #\(groupIndex): \(error.localizedDescription)")
                }
            }
            #endif

            return true
        } catch {
            NSLog("❌ ClipsViewModel: Failed to load asset duration: \(error)")
            return false
        }
    }
}

