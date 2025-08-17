import Foundation
import AVFoundation
import CoreMedia

@MainActor
class ClipsViewModel: ObservableObject {
    @Published var clips: [Clip] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
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
            // Debug: First check App Groups container access
            if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.cgame.shared") {
                NSLog("🎬 ClipsViewModel: App Groups container: \(containerURL.path)")
                let clipsDir = containerURL.appendingPathComponent("Clips")
                NSLog("🎬 ClipsViewModel: Clips directory path: \(clipsDir.path)")
                
                let dirExists = FileManager.default.fileExists(atPath: clipsDir.path)
                NSLog("🎬 ClipsViewModel: Clips directory exists: \(dirExists)")
                
                if !dirExists {
                    NSLog("🎬 ClipsViewModel: Creating clips directory")
                    try? FileManager.default.createDirectory(at: clipsDir, withIntermediateDirectories: true)
                }
                
                // List all files in clips directory
                do {
                    let allFiles = try FileManager.default.contentsOfDirectory(at: clipsDir, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey], options: [])
                    NSLog("🎬 ClipsViewModel: All files in clips directory: \(allFiles.count)")
                    for file in allFiles {
                        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                        NSLog("🎬 ClipsViewModel: File: \(file.lastPathComponent), Size: \(size) bytes")
                    }
                } catch {
                    NSLog("❌ ClipsViewModel: Failed to list clips directory: \(error)")
                }
            } else {
                NSLog("❌ ClipsViewModel: Cannot access App Groups container!")
            }
            
            let urls = AppGroupManager.shared.getAllClipFiles()
            NSLog("🎬 ClipsViewModel: Found \(urls.count) clip URLs from AppGroupManager")
            var loadedClips: [Clip] = []
            
            for url in urls {
                NSLog("🎬 ClipsViewModel: Processing clip: \(url.lastPathComponent)")
                NSLog("🎬 ClipsViewModel: Full path: \(url.path)")
                
                // Check if file exists and get its size
                let fileExists = FileManager.default.fileExists(atPath: url.path)
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
                NSLog("🎬 ClipsViewModel: File exists: \(fileExists), Size: \(fileSize) bytes")
                
                // Get file creation date for debugging
                if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let creationDate = attrs[.creationDate] as? Date {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .short
                    formatter.timeStyle = .medium
                    NSLog("🎬 ClipsViewModel: File created: \(formatter.string(from: creationDate))")
                }
                
                guard fileExists && fileSize > 0 else {
                    NSLog("❌ ClipsViewModel: Skipping invalid file: \(url.lastPathComponent)")
                    continue
                }
                
                // Try to check if the file is a valid video before creating AVAsset
                let pathExtension = url.pathExtension.lowercased()
                guard pathExtension == "mp4" || pathExtension == "mov" else {
                    NSLog("❌ ClipsViewModel: Skipping non-video file: \(url.lastPathComponent)")
                    continue
                }
                
                do {
                    NSLog("🎬 ClipsViewModel: Creating AVAsset for: \(url.lastPathComponent)")
                    let asset = AVAsset(url: url)
                    NSLog("🎬 ClipsViewModel: AVAsset created, loading duration...")
                    let duration = try await asset.load(.duration).seconds
                    NSLog("🎬 ClipsViewModel: Successfully loaded duration: \(String(format: "%.2f", duration))s")
                    
                    // Try to get actual creation date from filename or file attributes
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
                    NSLog("✅ ClipsViewModel: Successfully created clip: \(url.lastPathComponent)")
                } catch {
                    NSLog("❌ ClipsViewModel: Failed to load AVAsset for \(url.lastPathComponent): \(error)")
                    NSLog("❌ ClipsViewModel: Error type: \(type(of: error))")
                    if let nsError = error as NSError? {
                        NSLog("❌ ClipsViewModel: Error domain: \(nsError.domain), code: \(nsError.code)")
                        NSLog("❌ ClipsViewModel: Error description: \(nsError.localizedDescription)")
                        NSLog("❌ ClipsViewModel: Error userInfo: \(nsError.userInfo)")
                    }
                    
                    // Still create clip entry but with 0 duration so user can see it exists
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
                    NSLog("⚠️ ClipsViewModel: Created clip with 0 duration: \(url.lastPathComponent)")
                }
            }
            
            NSLog("🎬 ClipsViewModel: Total clips loaded: \(loadedClips.count)")
            self.clips = loadedClips.sorted(by: { $0.timestamp > $1.timestamp })
            
            if loadedClips.isEmpty {
                self.errorMessage = "No clips found in directory"
            }
            
            isLoading = false
        }
    }
    
    func deleteClip(_ clip: Clip) {
        // Remove from local storage
        if let localURL = clip.localURL {
            do {
                try FileManager.default.removeItem(at: localURL)
                // Remove from the list in the UI
                if let index = clips.firstIndex(where: { $0.id == clip.id }) {
                    clips.remove(at: index)
                }
            } catch {
                let errorMsg = "Failed to delete clip: \(error.localizedDescription)"
                NSLog("ERROR: \(errorMsg)")
                self.errorMessage = errorMsg
            }
        }
    }

    func refreshClips() {
        loadClips()
    }
    
    func clearError() {
        errorMessage = nil
    }
    
    // MARK: - Smart Copy & Stitch Processing
    
    private func startProcessingPendingClips() {
        // Monitor for new session metadata from extension every 2 seconds
        NSLog("🚀 ClipsViewModel: Starting session metadata monitoring timer")
        
        processingTimer?.cancel() // Clean up any existing timer
        
        let timer = DispatchSource.makeTimerSource(queue: processingQueue)
        timer.schedule(deadline: .now(), repeating: 2.0)
        timer.setEventHandler { [weak self] in
            Task {
                await self?.checkForNewSessions()
            }
        }
        
        processingTimer = timer
        timer.resume()
        
        // Also run immediately once
        Task {
            NSLog("🔄 ClipsViewModel: Running initial session metadata check")
            await checkForNewSessions()
        }
    }
    
    private func checkForNewSessions() async {
        // Check App Groups for new session info from extension
        guard let sessionInfo = AppGroupManager.shared.loadPendingSessionInfo() else {
            return
        }
        
        let sessionUpdatedAt = UserDefaults(suiteName: "group.com.cgame.shared")?.double(forKey: "session_updated_at") ?? 0
        let lastProcessedAt = UserDefaults.standard.double(forKey: "last_processed_session_at")
        
        // Only process if this is a new session
        guard sessionUpdatedAt > lastProcessedAt else {
            return
        }
        
        NSLog("📊 ClipsViewModel: Found pending session with \(sessionInfo.killEvents.count) kill events")
        
        // Update last processed timestamp
        UserDefaults.standard.set(sessionUpdatedAt, forKey: "last_processed_session_at")
        
        // Process the session
        await processSessionInfo(sessionInfo)
    }
    
    private func processSessionInfo(_ sessionInfo: (sessionURL: URL, killEvents: [(Date, Double, String)])) async {
        NSLog("🎬 ClipsViewModel: Processing session with \(sessionInfo.killEvents.count) kills")
        
        // Show loading state during processing
        await MainActor.run {
            self.isLoading = true
        }
        
        // Process all kill clips from this session
        var processedClipCount = 0
        
        for (index, killEvent) in sessionInfo.killEvents.enumerated() {
            if await createKillClipFromSessionInfo(sessionURL: sessionInfo.sessionURL, killEvent: killEvent, index: index + 1) {
                processedClipCount += 1
            }
        }
        
        NSLog("🎬 ClipsViewModel: Session processing complete - \(processedClipCount)/\(sessionInfo.killEvents.count) clips created")
        
        // Clean up processed session info
        AppGroupManager.shared.clearPendingSessionInfo()
        
        // Clean up session file if all clips were processed successfully
        if processedClipCount == sessionInfo.killEvents.count {
            try? FileManager.default.removeItem(at: sessionInfo.sessionURL)
            NSLog("🗑️ ClipsViewModel: Cleaned up session file: \(sessionInfo.sessionURL.lastPathComponent)")
        }
        
        // Refresh clips list to show new clips
        await MainActor.run {
            self.loadClips()
        }
        
        // Local mode - skip cloud upload for now
        print("📁 ClipsViewModel: Running in local mode - clips saved locally")
    }
    
    private func createKillClipFromSessionInfo(sessionURL: URL, killEvent: (Date, Double, String), index: Int) async -> Bool {
        let asset = AVAsset(url: sessionURL)
        
        // Get session duration to validate timing
        do {
            let duration = try await asset.load(.duration)
            let sessionDurationSeconds = duration.seconds
            
            NSLog("📹 ClipsViewModel: Session duration: \(String(format: "%.1f", sessionDurationSeconds))s, Kill CMTime: \(String(format: "%.1f", killEvent.1))s")
            
            // Calculate clip timing - killEvent.1 should be relative offset within session
            let preRoll: Double = 5.0  // 5 seconds before kill
            let postRoll: Double = 3.0 // 3 seconds after kill
            
            // For session-based recording, we need to find when the kill occurred within the session
            // Since we don't have session start time here, let's try a simpler approach
            // The kill timestamp should be relative to session start
            let sessionStartDate = extractSessionStartFromFilename(sessionURL.lastPathComponent)
            let killDate = killEvent.0
            let killOffsetInSession = killDate.timeIntervalSince(sessionStartDate)
            
            NSLog("📹 ClipsViewModel: Session started at: \(sessionStartDate), Kill at: \(killDate)")  
            NSLog("📹 ClipsViewModel: Calculated kill offset in session: \(String(format: "%.1f", killOffsetInSession))s")
            
            let startTime = max(0, killOffsetInSession - preRoll)
            let endTime = min(sessionDurationSeconds, killOffsetInSession + postRoll)
            
            let clipStart = CMTime(seconds: startTime, preferredTimescale: 600)
            let clipDuration = CMTime(seconds: endTime - startTime, preferredTimescale: 600)
            let timeRange = CMTimeRange(start: clipStart, duration: clipDuration)
            
            // Output filename
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let timestamp = dateFormatter.string(from: killEvent.0)
            let clipFilename = "kill_\(index)_\(timestamp).mp4"
            
            guard let clipsDir = AppGroupManager.shared.getClipsDirectory() else {
                NSLog("❌ ClipsViewModel: Clips directory unavailable")
                return false
            }
            
            let outputURL = clipsDir.appendingPathComponent(clipFilename)
            
            // Create export session
            guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
                NSLog("❌ ClipsViewModel: Failed to create export session for kill #\(index)")
                return false
            }
            
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .mp4
            exportSession.timeRange = timeRange
        
        // Apply COD Mobile rotation fix
        do {
            if let videoTrack = try await asset.loadTracks(withMediaType: .video).first {
                let videoComposition = AVMutableVideoComposition()
                videoComposition.renderSize = CGSize(width: 1920, height: 888) // Landscape for COD Mobile
                videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
                
                let instruction = AVMutableVideoCompositionInstruction()
                instruction.timeRange = timeRange
                
                let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
                
                // 90° CCW rotation for COD Mobile
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
        
        NSLog("✂️ ClipsViewModel: Exporting kill #\(index) from \(String(format: "%.1f", startTime))s to \(String(format: "%.1f", endTime))s")
        
        // Export clip
        await exportSession.export()
        
            switch exportSession.status {
            case .completed:
                NSLog("✅ ClipsViewModel: Kill clip #\(index) exported: \(clipFilename)")
                return true
            case .failed:
                NSLog("❌ ClipsViewModel: Kill clip #\(index) export failed: \(exportSession.error?.localizedDescription ?? "Unknown")")
                return false
            default:
                NSLog("❌ ClipsViewModel: Kill clip #\(index) export cancelled or unknown status")
                return false
            }
            
        } catch {
            NSLog("❌ ClipsViewModel: Failed to load asset duration: \(error)")
            return false
        }
    }
    
    private func extractSessionStartFromFilename(_ filename: String) -> Date {
        // Parse filename like "session_2025-08-13_16-01-53.mp4"
        let components = filename.replacingOccurrences(of: "session_", with: "").replacingOccurrences(of: ".mp4", with: "")
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        dateFormatter.timeZone = TimeZone.current
        
        return dateFormatter.date(from: components) ?? Date()
    }
    
    private func processClipMetadata(_ metadata: ClipMetadata) async throws -> URL {
        guard let clipsDir = AppGroupManager.shared.getClipsDirectory() else {
            throw ProcessingError.clipsDirectoryUnavailable
        }
        
        let finalClipURL = clipsDir.appendingPathComponent(metadata.localFilePath)
        
        if metadata.untrimmedParts.count == 1 {
            // Single part - just trim to keyframes
            let untrimmedURL = clipsDir.appendingPathComponent(metadata.untrimmedParts[0])
            try await trimToKeyframes(untrimmedURL, outputURL: finalClipURL, clipStart: metadata.startTime, clipEnd: metadata.endTime)
            
        } else if metadata.untrimmedParts.count == 2 {
            // Two parts - stitch then trim
            let part1URL = clipsDir.appendingPathComponent(metadata.untrimmedParts[0])
            let part2URL = clipsDir.appendingPathComponent(metadata.untrimmedParts[1])
            
            let stitchedURL = clipsDir.appendingPathComponent("temp_stitched_\(metadata.id).mp4")
            try await stitchParts(part1URL: part1URL, part2URL: part2URL, outputURL: stitchedURL)
            
            try await trimToKeyframes(stitchedURL, outputURL: finalClipURL, clipStart: metadata.startTime, clipEnd: metadata.endTime)
            
            // Clean up temp stitched file
            try? FileManager.default.removeItem(at: stitchedURL)
            
        } else {
            throw ProcessingError.invalidPartCount(metadata.untrimmedParts.count)
        }
        
        return finalClipURL
    }
    
    private func stitchParts(part1URL: URL, part2URL: URL, outputURL: URL) async throws {
        NSLog("🧩 Stitching parts: \(part1URL.lastPathComponent) + \(part2URL.lastPathComponent)")
        
        let composition = AVMutableComposition()
        
        let asset1 = AVAsset(url: part1URL)
        let asset2 = AVAsset(url: part2URL)
        
        // Add video tracks
        if let videoTrack1 = try await asset1.loadTracks(withMediaType: .video).first,
           let videoTrack2 = try await asset2.loadTracks(withMediaType: .video).first,
           let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
            
            let duration1 = try await asset1.load(.duration)
            let duration2 = try await asset2.load(.duration)
            
            try compositionVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration1), of: videoTrack1, at: .zero)
            try compositionVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration2), of: videoTrack2, at: duration1)
            
            // Preserve original video orientation from the first track
            let originalTransform = try await videoTrack1.load(.preferredTransform)
            compositionVideoTrack.preferredTransform = originalTransform
            NSLog("🔄 Applied transform to stitched video track: \(originalTransform)")
        }
        
        // Add audio tracks
        if let audioTrack1 = try await asset1.loadTracks(withMediaType: .audio).first,
           let audioTrack2 = try await asset2.loadTracks(withMediaType: .audio).first,
           let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            
            let duration1 = try await asset1.load(.duration)
            let duration2 = try await asset2.load(.duration)
            
            try compositionAudioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration1), of: audioTrack1, at: .zero)
            try compositionAudioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration2), of: audioTrack2, at: duration2)
        }
        
        // Export stitched composition with proper video composition for orientation
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ProcessingError.exportSessionCreationFailed
        }
        
        // Create video composition to fix COD Mobile orientation in stitched video
        if let videoTrack = composition.tracks(withMediaType: .video).first {
            let videoComposition = AVMutableVideoComposition()
            // COD Mobile landscape game in portrait recording - rotate to landscape output
            videoComposition.renderSize = CGSize(width: 1920, height: 888) // Landscape dimensions
            videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
            
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
            
            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
            
            // Apply 90-degree counter-clockwise rotation to fix COD Mobile orientation
            // COD Mobile is landscape game recorded in portrait - need to rotate 90° CCW
            let rotateTransform = CGAffineTransform(rotationAngle: -CGFloat.pi/2) // -90 degrees
            let translateTransform = CGAffineTransform(translationX: 0, y: 888) // Move to correct position
            let finalTransform = rotateTransform.concatenating(translateTransform)
            
            layerInstruction.setTransform(finalTransform, at: .zero)
            instruction.layerInstructions = [layerInstruction]
            
            videoComposition.instructions = [instruction]
            exportSession.videoComposition = videoComposition
            
            NSLog("📐 Applied video composition with landscape orientation (1920x888) and 90° CCW rotation for stitched COD Mobile video")
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        
        await exportSession.export()
        
        if exportSession.status != .completed {
            throw ProcessingError.stitchingFailed(exportSession.error?.localizedDescription ?? "Unknown error")
        }
        
        NSLog("✅ Stitching completed: \(outputURL.lastPathComponent)")
    }
    
    private func trimToKeyframes(_ inputURL: URL, outputURL: URL, clipStart: Date, clipEnd: Date) async throws {
        NSLog("✂️ Trimming to keyframes: \(inputURL.lastPathComponent)")
        
        let asset = AVAsset(url: inputURL)
        
        // For now, use simple time-based trimming
        // TODO: Implement actual keyframe detection for more precise trimming
        let composition = AVMutableComposition()
        
        if let videoTrack = try await asset.loadTracks(withMediaType: .video).first,
           let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
            
            let assetDuration = try await asset.load(.duration)
            let trimDuration = min(CMTime(seconds: clipEnd.timeIntervalSince(clipStart), preferredTimescale: 600), assetDuration)
            
            try compositionVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: trimDuration), of: videoTrack, at: .zero)
            
            // Preserve original video orientation
            let originalTransform = try await videoTrack.load(.preferredTransform)
            compositionVideoTrack.preferredTransform = originalTransform
            NSLog("🔄 Applied transform to trimmed video track: \(originalTransform)")
        }
        
        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first,
           let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            
            let assetDuration = try await asset.load(.duration)
            let trimDuration = min(CMTime(seconds: clipEnd.timeIntervalSince(clipStart), preferredTimescale: 600), assetDuration)
            
            try compositionAudioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: trimDuration), of: audioTrack, at: .zero)
        }
        
        // Export trimmed composition with proper video composition for orientation
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ProcessingError.exportSessionCreationFailed
        }
        
        // Create video composition to fix COD Mobile orientation
        if let videoTrack = composition.tracks(withMediaType: .video).first {
            let videoComposition = AVMutableVideoComposition()
            // COD Mobile landscape game in portrait recording - rotate to landscape output
            videoComposition.renderSize = CGSize(width: 1920, height: 888) // Landscape dimensions
            videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
            
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
            
            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
            
            // Apply 90-degree counter-clockwise rotation to fix COD Mobile orientation
            // COD Mobile is landscape game recorded in portrait - need to rotate 90° CCW
            let rotateTransform = CGAffineTransform(rotationAngle: -CGFloat.pi/2) // -90 degrees
            let translateTransform = CGAffineTransform(translationX: 0, y: 888) // Move to correct position
            let finalTransform = rotateTransform.concatenating(translateTransform)
            
            layerInstruction.setTransform(finalTransform, at: .zero)
            instruction.layerInstructions = [layerInstruction]
            
            videoComposition.instructions = [instruction]
            exportSession.videoComposition = videoComposition
            
            NSLog("📐 Applied video composition with landscape orientation (1920x888) and 90° CCW rotation for COD Mobile")
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        
        await exportSession.export()
        
        if exportSession.status != .completed {
            throw ProcessingError.trimmingFailed(exportSession.error?.localizedDescription ?? "Unknown error")
        }
        
        NSLog("✅ Trimming completed: \(outputURL.lastPathComponent)")
    }
    
    // MARK: - Local Mode Only (Cloud features disabled for now)
    
    private func cleanupUntrimmedParts(_ parts: [String]) async {
        guard let clipsDir = AppGroupManager.shared.getClipsDirectory() else { return }
        
        for part in parts {
            let partURL = clipsDir.appendingPathComponent(part)
            try? FileManager.default.removeItem(at: partURL)
            NSLog("🗑️ Cleaned up untrimmed part: \(part)")
        }
    }
}

enum ProcessingError: Error {
    case clipsDirectoryUnavailable
    case invalidPartCount(Int)
    case exportSessionCreationFailed
    case stitchingFailed(String)
    case trimmingFailed(String)
    
    var localizedDescription: String {
        switch self {
        case .clipsDirectoryUnavailable:
            return "Clips directory is unavailable"
        case .invalidPartCount(let count):
            return "Invalid number of untrimmed parts: \(count)"
        case .exportSessionCreationFailed:
            return "Failed to create export session"
        case .stitchingFailed(let error):
            return "Stitching failed: \(error)"
        case .trimmingFailed(let error):
            return "Trimming failed: \(error)"
        }
    }
}