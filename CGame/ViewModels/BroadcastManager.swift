import Foundation
import ReplayKit

@MainActor
class BroadcastManager: ObservableObject {
    @Published var isRecording = false
    @Published var statusMessage = "Ready to detect COD Mobile kills"
    @Published var recentClips: [Clip] = []
    @Published var totalKillsDetected = 0
    @Published var sessionDuration: TimeInterval = 0
    @Published var sessionClipCount = 0
    
    private var clipCheckTimer: Timer?
    private var sessionStartTime: Date?
    private var sessionTimer: Timer?
    
    init() {
        startClipMonitoring()
    }
    
    deinit {
        clipCheckTimer?.invalidate()
        sessionTimer?.invalidate()
    }
    
    func broadcastDidStart() {
        isRecording = true
        sessionStartTime = Date()
        statusMessage = "🎯 COD Kill detection active - Play and get kills!"
        
        // Start session timer
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateSessionDuration()
            }
        }
    }
    
    func stopBroadcast() {
        RPScreenRecorder.shared().stopCapture { [weak self] error in
            DispatchQueue.main.async {
                self?.isRecording = false
                self?.sessionTimer?.invalidate()
                
                if let error = error {
                    self?.statusMessage = "❌ Failed to stop recording: \(error.localizedDescription)"
                } else {
                    let kills = self?.totalKillsDetected ?? 0
                    let duration = self?.formatSessionDuration() ?? "0m"
                    self?.statusMessage = "✅ Session ended - \(kills) kills detected in \(duration)"
                    self?.checkForNewClips()
                }
            }
        }
    }
    
    func checkForNewClips() {
        let pendingClips = AppGroupManager.shared.loadPendingClipMetadata()
        
        // Convert metadata to Clip objects for display
        let newClips = pendingClips.compactMap { metadata -> Clip? in
            guard let localURL = AppGroupManager.shared.getClipURL(for: URL(string: metadata.localFilePath)?.lastPathComponent ?? "") else {
                return nil
            }
            
            return Clip(
                id: metadata.id,
                game: metadata.game,
                events: metadata.events.map { $0.type },
                timestamp: metadata.startTime,
                duration: metadata.duration,
                storagePath: metadata.localFilePath,
                localURL: localURL
            )
        }
        
        // Update recent clips, keeping most recent first
        var allClips = newClips + recentClips
        allClips = Array(Set(allClips.map { $0.id }))
            .compactMap { id in allClips.first(where: { $0.id == id }) }
            .sorted { $0.timestamp > $1.timestamp }
        
        let previousCount = recentClips.count
        recentClips = Array(allClips.prefix(10))
        totalKillsDetected = recentClips.count
        sessionClipCount = recentClips.count
        
        // Update status message based on new clips found
        let newClipsFound = recentClips.count - previousCount
        if newClipsFound > 0 {
            statusMessage = "🎯 \(newClipsFound) new kill highlight\(newClipsFound == 1 ? "" : "s") detected!"
        } else if !isRecording && recentClips.isEmpty {
            statusMessage = "Ready to detect COD Mobile kills"
        } else if !isRecording {
            statusMessage = "Session complete - \(totalKillsDetected) total kills detected"
        }
    }
    
    private func startClipMonitoring() {
        clipCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForNewClips()
            }
        }
    }
    
    private func updateSessionDuration() {
        guard let startTime = sessionStartTime else { return }
        sessionDuration = Date().timeIntervalSince(startTime)
    }
    
    private func formatSessionDuration() -> String {
        let minutes = Int(sessionDuration) / 60
        let seconds = Int(sessionDuration) % 60
        
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
    
    func getRecordingStatus() -> String {
        if isRecording {
            return "🎯 DETECTING KILLS"
        } else if !recentClips.isEmpty {
            return "✅ \(recentClips.count) kills detected"
        } else {
            return "⚪ Ready to detect"
        }
    }
    
    func resetSession() {
        totalKillsDetected = 0
        sessionDuration = 0
        sessionClipCount = 0
        sessionStartTime = nil
        sessionTimer?.invalidate()
        statusMessage = "Ready to detect COD Mobile kills"
    }
}