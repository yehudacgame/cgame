import Foundation
import AVFoundation
import UIKit

final class ClipTrimmerService: NSObject {
    static let shared = ClipTrimmerService()
    private let appGroupId = "group.com.cgame.shared"
    private var isProcessing = false
    
    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    func start() {
        // Trigger once on app launch
        processIfPending()
    }
    
    @objc private func handleForeground() {
        processIfPending()
    }
    
    private func processIfPending() {
        guard !isProcessing else { return }
        guard let defaults = UserDefaults(suiteName: appGroupId) else { return }
        guard defaults.bool(forKey: "broadcastFinished") == true else { return }
        
        isProcessing = true
        defaults.set(false, forKey: "broadcastFinished")
        
        guard let pending = AppGroupManager.shared.loadPendingSessionInfo() else {
            isProcessing = false
            return
        }
        
        let sessionURL = pending.sessionURL
        let killEvents = pending.killEvents
        
        // Read pre/post durations (fallbacks if missing)
        let pre: Double = defaults.object(forKey: "preRollDuration") != nil ? defaults.double(forKey: "preRollDuration") : 5.0
        let post: Double = defaults.object(forKey: "postRollDuration") != nil ? defaults.double(forKey: "postRollDuration") : 5.0
        
        trimClips(sessionURL: sessionURL, kills: killEvents, pre: pre, post: post) { [weak self] in
            // Clear pending session info after processing
            AppGroupManager.shared.clearPendingSessionInfo()
            self?.isProcessing = false
        }
    }
    
    private func trimClips(sessionURL: URL, kills: [(Date, Double, String)], pre: Double, post: Double, completion: @escaping () -> Void) {
        let asset = AVAsset(url: sessionURL)
        let duration = asset.duration.seconds
        let group = DispatchGroup()
        
        for (index, kill) in kills.enumerated() {
            let killSeconds = kill.1
            let start = max(0, min(killSeconds - pre, duration))
            let end = min(duration, max(start, killSeconds + post))
            let timeRange = CMTimeRange(
                start: CMTime(seconds: start, preferredTimescale: 600),
                duration: CMTime(seconds: end - start, preferredTimescale: 600)
            )
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let timestamp = dateFormatter.string(from: kill.0)
            let filename = "kill_\(index + 1)_\(timestamp).mp4"
            
            guard let destDir = AppGroupManager.shared.getClipsDirectory() else { continue }
            let outURL = destDir.appendingPathComponent(filename)
            
            // Remove if exists
            try? FileManager.default.removeItem(at: outURL)
            
            group.enter()
            exportPassthrough(asset: asset, timeRange: timeRange, outputURL: outURL) { success in
                if success {
                    NSLog("✅ ClipTrimmerService: Exported clip #\(index + 1) -> \(filename)")
                } else {
                    NSLog("❌ ClipTrimmerService: Failed to export clip #\(index + 1)")
                }
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
        session.exportAsynchronously {
            completion(session.status == .completed)
        }
    }
}
