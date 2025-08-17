import Foundation
import AVFoundation
import CoreMedia

/// Manages exports that need to wait for additional footage to be recorded
class DeferredExportManager {
    private var pendingExports: [DeferredExport] = []
    private let processingQueue = DispatchQueue(label: "com.cgame.deferred-exports", qos: .utility)
    private var processingTimer: Timer?
    private weak var hardwareBuffer: HardwareEncodedBuffer?
    
    struct DeferredExport {
        let clipId: String
        let startTime: Date
        let endTime: Date
        let requiredEndTime: Date  // When we need footage until
        let metadata: ClipMetadata?
        let completion: ([String]) -> Void
        let createdAt: Date
    }
    
    init(hardwareBuffer: HardwareEncodedBuffer) {
        self.hardwareBuffer = hardwareBuffer
        startProcessing()
    }
    
    func addDeferredExport(clipId: String, startTime: Date, endTime: Date, requiredEndTime: Date, metadata: ClipMetadata?, completion: @escaping ([String]) -> Void) {
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            let deferredExport = DeferredExport(
                clipId: clipId,
                startTime: startTime,
                endTime: endTime,
                requiredEndTime: requiredEndTime,
                metadata: metadata,
                completion: completion,
                createdAt: Date()
            )
            
            self.pendingExports.append(deferredExport)
            NSLog("📋 Deferred Export: Added \(clipId) to queue. Waiting for footage until \(requiredEndTime)")
            NSLog("📊 Deferred Export: Queue now has \(self.pendingExports.count) pending exports")
        }
    }
    
    private func startProcessing() {
        // Ensure we're on the main thread for Timer
        DispatchQueue.main.async { [weak self] in
            self?.processingTimer?.invalidate()
            self?.processingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.processPendingExports()
            }
            RunLoop.current.add(self?.processingTimer ?? Timer(), forMode: .common)
            NSLog("🚀 Deferred Export: Processing timer started (1s interval) on main thread")
        }
    }
    
    private func processPendingExports() {
        processingQueue.async { [weak self] in
            guard let self = self, let buffer = self.hardwareBuffer else { 
                NSLog("⚠️ Deferred Export: Timer fired but manager or buffer is nil")
                return 
            }
            
            // Only log state changes, not every check
            if !self.pendingExports.isEmpty {
                let availableUntil = buffer.getAvailableFootageEndTime()
                let readyExports = self.pendingExports.filter { export in
                    return export.requiredEndTime <= availableUntil
                }
                
                // Only log when we have exports ready to process
                if !readyExports.isEmpty {
                    NSLog("✅ Deferred Export: Processing \(readyExports.count) ready exports")
                    
                    for export in readyExports {
                        NSLog("🎬 Deferred Export: Now processing \(export.clipId)")
                        
                        // Process the export immediately now that we have enough footage
                        buffer.performImmediateExport(
                            startTime: export.startTime,
                            endTime: export.endTime,
                            clipId: export.clipId,
                            completion: export.completion
                        )
                        
                        // Remove from pending queue
                        self.pendingExports.removeAll { $0.clipId == export.clipId }
                    }
                }
            }
            
            // Clean up expired exports (older than 10 seconds - buffer cycles every 30s)
            self.cleanupExpiredExports(olderThan: 10.0)
        }
    }
    
    private func cleanupExpiredExports(olderThan seconds: TimeInterval) {
        let cutoffTime = Date().addingTimeInterval(-seconds)
        let expiredExports = pendingExports.filter { $0.createdAt < cutoffTime }
        
        if !expiredExports.isEmpty {
            NSLog("🧹 Deferred Export: Found \(expiredExports.count) expired exports older than \(seconds)s")
        }
        
        for expired in expiredExports {
            NSLog("⚠️ Deferred Export: Timeout for \(expired.clipId) after \(seconds)s, creating partial clip")
            
            // Create partial clip with available footage
            if let buffer = hardwareBuffer {
                let availableUntil = buffer.getAvailableFootageEndTime()
                let adjustedEndTime = min(expired.endTime, availableUntil)
                
                NSLog("📁 Deferred Export: Creating partial clip from \(expired.startTime) to \(adjustedEndTime)")
                
                buffer.performImmediateExport(
                    startTime: expired.startTime,
                    endTime: adjustedEndTime,
                    clipId: expired.clipId,
                    completion: expired.completion
                )
            } else {
                NSLog("❌ Deferred Export: Buffer is nil, calling completion with empty result")
                // If buffer is gone, call completion with empty result
                expired.completion([])
            }
            
            pendingExports.removeAll { $0.clipId == expired.clipId }
        }
    }
    
    func invalidate() {
        processingTimer?.invalidate()
        processingTimer = nil
        
        // Complete any remaining exports with empty results
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            for export in self.pendingExports {
                NSLog("🛑 Deferred Export: Invalidating pending export \(export.clipId)")
                export.completion([])
            }
            
            self.pendingExports.removeAll()
        }
    }
    
    deinit {
        invalidate()
    }
}

/// A cyclic buffer that uses hardware H.264 encoding to maintain 30 seconds of compressed video with minimal memory overhead.
/// This implementation uses a two-file rotation system to ensure a clip can be safely read while the buffer continues to write.
class HardwareEncodedBuffer {
    
    private struct BufferInfo {
        let url: URL
        let startTime: Date
        var endTime: Date?  // Will be set when buffer actually cycles
        let startCMTime: CMTime?
        var endCMTime: CMTime?  // Will be set when buffer actually cycles
    }
    private let maxDurationSeconds: Double = 30.0
    private let bufferQueue = DispatchQueue(label: "com.cgame.hardwarebuffer", qos: .userInitiated)
    
    // Deferred export management
    private lazy var deferredExportManager: DeferredExportManager = {
        NSLog("🎯 Creating DeferredExportManager for HardwareEncodedBuffer")
        return DeferredExportManager(hardwareBuffer: self)
    }()
    
    // Two-file rotation system for safe reading and continuous writing
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var isWriting = false
    
    // URLs for the two rotating buffer files
    private var primaryBufferURL: URL
    private var secondaryBufferURL: URL
    private var currentWriterURL: URL

    // Frame dimensions (will be set on first frame)
    private var videoDimensions: CMVideoDimensions?
    private var videoTransform: CGAffineTransform = .identity
    
    // Timestamp tracking for cycling and smart export
    // THIS IS THE CORE OF THE NEW, RELIABLE SYSTEM
    // We map the start/end of each buffer file to both wall-clock time (Date) and presentation time (CMTime)
    private var primaryBufferInfo: BufferInfo?
    private var secondaryBufferInfo: BufferInfo?
    private var lastWrittenCMTime: CMTime = .zero

    init() {
        // Create URLs in app group container
        let appGroupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.cgame.shared"
        )!
        let bufferDir = appGroupURL.appendingPathComponent("HardwareBuffer")
        try? FileManager.default.createDirectory(at: bufferDir, withIntermediateDirectories: true)
        
        self.primaryBufferURL = bufferDir.appendingPathComponent("buffer_1.mp4")
        self.secondaryBufferURL = bufferDir.appendingPathComponent("buffer_2.mp4")
        self.currentWriterURL = primaryBufferURL
        
        // Clean up any existing files
        try? FileManager.default.removeItem(at: primaryBufferURL)
        try? FileManager.default.removeItem(at: secondaryBufferURL)
    }
    
    func add(sample: CMSampleBuffer) {
        bufferQueue.async { [weak self] in
            self?.processSample(sample)
        }
    }
    
    private func processSample(_ sample: CMSampleBuffer) {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sample) else {
            NSLog("ERROR: No format description for sample")
            return
        }
        let mediaType = CMFormatDescriptionGetMediaType(formatDesc)
        
        // Initialize writer on first video frame OR restart after export
        if !isWriting, mediaType == kCMMediaType_Video {
            setupWriter(with: sample)
        }
        
        guard isWriting, let writer = writer, writer.status == .writing else {
            // Only log drops occasionally to prevent spam
            // These logs can overwhelm the extension if logged every frame
            return
        }
        
        // Check if we need to cycle the buffer
        let presentationTime = sample.presentationTimeStamp
        
        // Use the buffer's own start time for cycling logic
        let currentBufferStartCMTime = (currentWriterURL == primaryBufferURL ? primaryBufferInfo?.startCMTime : secondaryBufferInfo?.startCMTime) ?? .zero
        
        if CMTimeGetSeconds(CMTimeSubtract(presentationTime, currentBufferStartCMTime)) >= maxDurationSeconds {
            cycleBuffer(nextSample: sample)
        }
        
        // Write the sample
        switch mediaType {
        case kCMMediaType_Video:
            if let videoInput = videoInput, videoInput.isReadyForMoreMediaData {
                // Removed frame-by-frame logging to reduce overhead
                // These logs were causing performance issues
                videoInput.append(sample)
                lastWrittenCMTime = presentationTime // Keep track of the most recent timestamp
            }
        case kCMMediaType_Audio:
            if let audioInput = audioInput, audioInput.isReadyForMoreMediaData {
                audioInput.append(sample)
            }
        default:
            break
        }
    }
    
    private func setupWriter(with firstSample: CMSampleBuffer) {
        // Clean up any existing writer first (in case we're restarting after export)
        if let existingWriter = writer, existingWriter.status == .failed || existingWriter.status == .cancelled {
            NSLog("🗑️ CGAME Buffer: Cleaning up failed writer (status: \(existingWriter.status.rawValue))")
            writer = nil
            videoInput = nil
            audioInput = nil
        }
        
        // Get video dimensions from the first frame
        if videoDimensions == nil,
           let formatDesc = CMSampleBufferGetFormatDescription(firstSample),
           CMFormatDescriptionGetMediaType(formatDesc) == kCMMediaType_Video {
            videoDimensions = CMVideoFormatDescriptionGetDimensions(formatDesc)
            
            let width = Int(videoDimensions!.width)
            let height = Int(videoDimensions!.height)
            NSLog("🎥 CGAME Buffer: Original dimensions from ReplayKit: \(width)x\(height)")
            
            if width > height {
                NSLog("🔄 CGAME Buffer: Detected landscape video - will rotate to portrait for mobile viewing")
                videoTransform = CGAffineTransform(rotationAngle: CGFloat.pi / 2)
                videoDimensions = CMVideoDimensions(width: Int32(height), height: Int32(width))
                NSLog("🎥 CGAME Buffer: Transformed dimensions for writer: \(height)x\(width) (portrait)")
            } else {
                videoTransform = .identity
            }
        }
        
        guard let dimensions = videoDimensions else {
            NSLog("ERROR: No video dimensions available for writer setup.")
            return
        }
        
        do {
            writer = try AVAssetWriter(url: currentWriterURL, fileType: .mp4)
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(dimensions.width),
                AVVideoHeightKey: Int(dimensions.height),
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 6_000_000,
                    AVVideoMaxKeyFrameIntervalKey: 60,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                ]
            ]
            
            videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput?.expectsMediaDataInRealTime = true
            if videoTransform != .identity { videoInput?.transform = videoTransform }
            if let videoInput = videoInput, writer?.canAdd(videoInput) == true { writer?.add(videoInput) }
            
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 44100,
                AVEncoderBitRateKey: 128_000,
            ]
            audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput?.expectsMediaDataInRealTime = true
            if let audioInput = audioInput, writer?.canAdd(audioInput) == true { writer?.add(audioInput) }
 
            writer?.startWriting()
            let startTime = firstSample.presentationTimeStamp
            writer?.startSession(atSourceTime: startTime)
            self.isWriting = true
            
            // Track buffer timing for smart export (both Date and CMTime)
            if currentWriterURL == primaryBufferURL {
                primaryBufferInfo = BufferInfo(
                    url: primaryBufferURL,
                    startTime: Date(),
                    endTime: nil,
                    startCMTime: startTime,
                    endCMTime: nil
                )
                NSLog("📊 CGAME Buffer: Primary buffer started at \(Date()) (CMTime: \(String(format: "%.3f", startTime.seconds))s)")
            } else {
                secondaryBufferInfo = BufferInfo(
                    url: secondaryBufferURL,
                    startTime: Date(),
                    endTime: nil,
                    startCMTime: startTime,
                    endCMTime: nil
                )
                NSLog("📊 CGAME Buffer: Secondary buffer started at \(Date()) (CMTime: \(String(format: "%.3f", startTime.seconds))s)")
            }
            
        } catch {
            NSLog("ERROR: Failed to setup AVAssetWriter: \(error.localizedDescription)")
            isWriting = false
        }
    }
    
    private func cycleBuffer(nextSample: CMSampleBuffer) {
        let oldWriter = writer
        let oldURL = currentWriterURL
        let cycleTime = Date()
        let cycleCMTime = nextSample.presentationTimeStamp
        
        NSLog("🔄 Buffer: Cycling \(oldURL.lastPathComponent)")
        
        // Record the actual end time for the buffer that's cycling out
        if oldURL == primaryBufferURL {
            primaryBufferInfo?.endTime = cycleTime
            primaryBufferInfo?.endCMTime = cycleCMTime
            NSLog("📊 Primary buffer ended at \(cycleTime)")
        } else {
            secondaryBufferInfo?.endTime = cycleTime
            secondaryBufferInfo?.endCMTime = cycleCMTime
            NSLog("📊 Secondary buffer ended at \(cycleTime)")
        }
        
        // Switch to the other buffer file
        currentWriterURL = (oldURL == primaryBufferURL) ? secondaryBufferURL : primaryBufferURL
        
        // Finalize the old writer asynchronously
        finalize(writer: oldWriter)
        
        // Setup a new writer for the new file. This will also set the new buffer's info.
        setupWriter(with: nextSample)
    }

    /// Smart Copy Strategy with Deferred Export: Copy entire buffer files needed for the clip range
    /// If required footage doesn't exist yet, defer the export until it's available
    /// Main app will handle stitching and trimming to exact boundaries
    func smartCopyForClip(startTime: Date, endTime: Date, clipId: String, completion: @escaping ([String]) -> Void) {
        bufferQueue.async { [weak self] in
            guard let self = self else {
                completion([])
                return
            }
            
            NSLog("📋 Smart Copy: Analyzing clip range \(startTime) to \(endTime) for \(clipId)")
            
            // Check if we need footage from the currently active buffer
            let needsActiveBuffer = self.requiresActiveBuffer(for: startTime, endTime: endTime)
            
            if needsActiveBuffer {
                let availableUntil = self.getAvailableFootageEndTime()
                
                NSLog("📊 Smart Copy: Clip needs active buffer. Available until: \(availableUntil), need until: \(endTime)")
                
                if endTime > availableUntil {
                    // Need to defer this export - we don't have enough footage yet
                    NSLog("⏳ Smart Copy: Deferring export for \(clipId) - need footage until \(endTime), have until \(availableUntil)")
                    
                    self.deferredExportManager.addDeferredExport(
                        clipId: clipId,
                        startTime: startTime,
                        endTime: endTime,
                        requiredEndTime: endTime,
                        metadata: nil,
                        completion: completion
                    )
                    return
                }
            }
            
            // We have all the footage we need - proceed with immediate export
            NSLog("✅ Smart Copy: All footage available for \(clipId), proceeding with immediate export")
            self.performImmediateExport(
                startTime: startTime,
                endTime: endTime,
                clipId: clipId,
                completion: completion
            )
        }
    }
    
    // Legacy method - kept for compatibility but should not be used with smart copy strategy
    private func legacyExportClip(from startTime: Date, to endTime: Date, to outputURL: URL, completion: @escaping (Bool) -> Void) {
        bufferQueue.async { [weak self] in
            guard let self = self else {
                completion(false)
                return
            }
            
            NSLog("🎬 CGAME Export: Requested clip from \(startTime) to \(endTime)")

            // Add file safety checks before accessing buffers
            guard FileManager.default.fileExists(atPath: self.primaryBufferURL.path) else {
                NSLog("❌ CGAME Export: Primary buffer file does not exist: \(self.primaryBufferURL.path)")
                completion(false)
                return
            }
            
            guard FileManager.default.fileExists(atPath: self.secondaryBufferURL.path) else {
                NSLog("❌ CGAME Export: Secondary buffer file does not exist: \(self.secondaryBufferURL.path)")
                completion(false)
                return
            }
            
            // Check if files are currently being written to (size changes)
            let primaryInitialSize = (try? FileManager.default.attributesOfItem(atPath: self.primaryBufferURL.path)[.size] as? UInt64) ?? 0
            let secondaryInitialSize = (try? FileManager.default.attributesOfItem(atPath: self.secondaryBufferURL.path)[.size] as? UInt64) ?? 0
            
            // Wait briefly and check again to ensure files are stable
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                let primaryCurrentSize = (try? FileManager.default.attributesOfItem(atPath: self.primaryBufferURL.path)[.size] as? UInt64) ?? 0
                let secondaryCurrentSize = (try? FileManager.default.attributesOfItem(atPath: self.secondaryBufferURL.path)[.size] as? UInt64) ?? 0
                
                if primaryCurrentSize != primaryInitialSize || secondaryCurrentSize != secondaryInitialSize {
                    NSLog("⚠️ CGAME Export: Buffer files still being written, waiting additional 200ms...")
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                        self.performSafeExport(startTime: startTime, endTime: endTime, outputURL: outputURL, completion: completion)
                    }
                } else {
                    self.performSafeExport(startTime: startTime, endTime: endTime, outputURL: outputURL, completion: completion)
                }
            }
        }
    }
    
    private func performSafeExport(startTime: Date, endTime: Date, outputURL: URL, completion: @escaping (Bool) -> Void) {
        // Gather information about the current state of the buffers
        let primaryAsset = AVAsset(url: self.primaryBufferURL)
        let secondaryAsset = AVAsset(url: self.secondaryBufferURL)
        
        let composition = AVMutableComposition()
        
        Task {
            var success = true
            do {
                // Sequentially process primary buffer, then secondary, to build the composition
                try await self.add(asset: primaryAsset, url: self.primaryBufferURL, with: self.primaryBufferInfo, to: composition, clipStart: startTime, clipEnd: endTime)
                try await self.add(asset: secondaryAsset, url: self.secondaryBufferURL, with: self.secondaryBufferInfo, to: composition, clipStart: startTime, clipEnd: endTime)

            } catch {
                NSLog("❌ CGAME Export: Failed to build composition: \(error.localizedDescription)")
                success = false
            }
            
            guard success, !composition.tracks.isEmpty else {
                NSLog("❌ CGAME Export: Composition is empty or failed to build. Aborting export.")
                completion(false)
                return
            }
            
            // Export the final composed clip
            self.performExport(composition: composition, outputURL: outputURL, completion: completion)
        }
    }
    
    private func add(asset: AVAsset, url: URL, with info: BufferInfo?, to composition: AVMutableComposition, clipStart: Date, clipEnd: Date) async throws {
        guard let info = info else { return } // If buffer has no info, it's not ready
        
        let assetDuration = try await asset.load(.duration)
        let bufferEndDate = info.endTime ?? info.startTime.addingTimeInterval(assetDuration.seconds)
        
        // Check for overlap between the buffer's time range and the requested clip's time range
        let clipRange = DateInterval(start: clipStart, end: clipEnd)
        let bufferRange = DateInterval(start: info.startTime, end: bufferEndDate)
        
        guard let intersection = clipRange.intersection(with: bufferRange) else {
            return // No overlap, nothing to add from this buffer
        }
        
        let timeOffsetInAsset = intersection.start.timeIntervalSince(info.startTime)
        let durationToCopy = intersection.duration
        
        let timeRangeToCopy = CMTimeRange(
            start: CMTime(seconds: timeOffsetInAsset, preferredTimescale: 600),
            duration: CMTime(seconds: durationToCopy, preferredTimescale: 600)
        )
        
        NSLog("✅ Adding to composition from \(url.lastPathComponent): duration \(durationToCopy)s")
        
        // Add video track
        if let assetVideoTrack = try await asset.loadTracks(withMediaType: .video).first,
           let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try compositionVideoTrack.insertTimeRange(timeRangeToCopy, of: assetVideoTrack, at: .invalid)
            
            // Apply transform to preserve orientation
            if videoTransform != .identity {
                compositionVideoTrack.preferredTransform = videoTransform
            }
        }
        
        // Add audio track
        if let assetAudioTrack = try await asset.loadTracks(withMediaType: .audio).first,
           let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try compositionAudioTrack.insertTimeRange(timeRangeToCopy, of: assetAudioTrack, at: .invalid)
        }
    }
    
    private func performExport(composition: AVComposition, outputURL: URL, completion: @escaping (Bool) -> Void) {
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            completion(false)
            return
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        
        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                switch exportSession.status {
                case .completed:
                    NSLog("✅ Final export completed successfully.")
                    completion(true)
                case .failed:
                    NSLog("❌ Final export failed: \(exportSession.error?.localizedDescription ?? "Unknown")")
                    completion(false)
                default:
                    completion(false)
                }
            }
        }
    }
    
    private func finalize(writer: AVAssetWriter?) {
        guard let writer = writer, writer.status == .writing else { return }
        
        writer.finishWriting {
            if writer.status == .failed {
                NSLog("Buffer writer failed: \(writer.error?.localizedDescription ?? "N/A")")
            }
        }
    }
    
    func clear() {
        bufferQueue.async { [weak self] in
            guard let self = self else { return }
            self.finalize(writer: self.writer)
            try? FileManager.default.removeItem(at: self.primaryBufferURL)
            try? FileManager.default.removeItem(at: self.secondaryBufferURL)
            self.videoDimensions = nil
            self.isWriting = false
            self.primaryBufferInfo = nil
            self.secondaryBufferInfo = nil
            self.deferredExportManager.invalidate()
        }
    }
    
    // MARK: - Deferred Export Support Methods
    
    /// Returns the latest time for which we have complete footage
    func getAvailableFootageEndTime() -> Date {
        // Only consider completed (non-active) buffer files as having reliable footage
        // The currently active buffer is being written to and should not be copied until complete
        
        if currentWriterURL == primaryBufferURL {
            // Primary is active, secondary should be complete (if it exists)
            if let secondaryInfo = secondaryBufferInfo {
                // Use actual end time if available, otherwise estimate
                if let actualEndTime = secondaryInfo.endTime {
                    NSLog("📊 Available Footage: Using actual secondary end time: \(actualEndTime)")
                    return actualEndTime
                } else {
                    // Still recording, estimate based on start time + max duration
                    let estimatedEnd = secondaryInfo.startTime.addingTimeInterval(maxDurationSeconds)
                    NSLog("📊 Available Footage: Estimating secondary end time: \(estimatedEnd)")
                    return estimatedEnd
                }
            } else {
                // No secondary buffer yet, no reliable footage available
                NSLog("📊 Available Footage: No secondary buffer available")
                return Date.distantPast
            }
        } else {
            // Secondary is active, primary should be complete (if it exists)
            if let primaryInfo = primaryBufferInfo {
                // Use actual end time if available, otherwise estimate
                if let actualEndTime = primaryInfo.endTime {
                    NSLog("📊 Available Footage: Using actual primary end time: \(actualEndTime)")
                    return actualEndTime
                } else {
                    // Still recording, estimate based on start time + max duration
                    let estimatedEnd = primaryInfo.startTime.addingTimeInterval(maxDurationSeconds)
                    NSLog("📊 Available Footage: Estimating primary end time: \(estimatedEnd)")
                    return estimatedEnd
                }
            } else {
                // No primary buffer yet, no reliable footage available
                NSLog("📊 Available Footage: No primary buffer available")
                return Date.distantPast
            }
        }
    }
    
    /// Checks if the requested clip requires footage from the currently active buffer
    private func requiresActiveBuffer(for startTime: Date, endTime: Date) -> Bool {
        let currentBufferStartTime = (currentWriterURL == primaryBufferURL ? primaryBufferInfo?.startTime : secondaryBufferInfo?.startTime) ?? Date()
        
        // Check if clip time range overlaps with current active buffer
        let currentBufferEndTime = currentBufferStartTime.addingTimeInterval(maxDurationSeconds)
        let clipRange = DateInterval(start: startTime, end: endTime)
        let activeBufferRange = DateInterval(start: currentBufferStartTime, end: currentBufferEndTime)
        
        return clipRange.intersects(activeBufferRange)
    }
    
    /// Performs immediate export when we know all footage is available
    func performImmediateExport(startTime: Date, endTime: Date, clipId: String, completion: @escaping ([String]) -> Void) {
        bufferQueue.async { [weak self] in
            guard let self = self else {
                completion([])
                return
            }
            
            NSLog("🎬 Immediate Export: Processing \(clipId) from \(startTime) to \(endTime)")
            
            var requiredFiles: [String] = []
            var copiedFiles: [String] = []
            
            // Determine which buffer files are needed based on simple Date overlap
            // Primary buffer coverage
            if let primaryInfo = self.primaryBufferInfo {
                let primaryEndTime = primaryInfo.endTime ?? primaryInfo.startTime.addingTimeInterval(self.maxDurationSeconds)
                let primaryRange = DateInterval(start: primaryInfo.startTime, end: primaryEndTime)
                let clipRange = DateInterval(start: startTime, end: endTime)
                
                if primaryRange.intersects(clipRange) {
                    requiredFiles.append("primary")
                    NSLog("📁 Primary buffer needed: covers \(primaryInfo.startTime) to \(primaryEndTime)")
                }
            }
            
            // Secondary buffer coverage  
            if let secondaryInfo = self.secondaryBufferInfo {
                let secondaryEndTime = secondaryInfo.endTime ?? secondaryInfo.startTime.addingTimeInterval(self.maxDurationSeconds)
                let secondaryRange = DateInterval(start: secondaryInfo.startTime, end: secondaryEndTime)
                let clipRange = DateInterval(start: startTime, end: endTime)
                
                if secondaryRange.intersects(clipRange) {
                    requiredFiles.append("secondary")
                    NSLog("📁 Secondary buffer needed: covers \(secondaryInfo.startTime) to \(secondaryEndTime)")
                }
            }
            
            NSLog("📋 Immediate Export: Need \(requiredFiles.count) buffer files: \(requiredFiles)")
            
            // Copy required files to clips directory
            for (index, bufferType) in requiredFiles.enumerated() {
                let sourceURL = (bufferType == "primary") ? self.primaryBufferURL : self.secondaryBufferURL
                let partNumber = index + 1
                let outputFileName = "untrimmed_\(clipId)_part\(partNumber).mp4"
                
                // Safety check: Don't copy from the currently active buffer
                if sourceURL == self.currentWriterURL {
                    NSLog("⚠️ Immediate Export: Skipping active buffer \(bufferType) - still being written")
                    continue
                }
                
                guard let clipsDir = AppGroupManager.shared.getClipsDirectory(),
                      FileManager.default.fileExists(atPath: sourceURL.path) else {
                    NSLog("❌ Immediate Export: Source file missing or clips directory unavailable")
                    continue
                }
                
                let destinationURL = clipsDir.appendingPathComponent(outputFileName)
                
                do {
                    // Remove existing file if present
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    
                    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                    copiedFiles.append(outputFileName)
                    NSLog("✅ Immediate Export: Copied \(bufferType) buffer to \(outputFileName)")
                    
                } catch {
                    NSLog("❌ Immediate Export: Failed to copy \(bufferType) buffer: \(error.localizedDescription)")
                }
            }
            
            NSLog("📋 Immediate Export: Successfully copied \(copiedFiles.count) files: \(copiedFiles)")
            completion(copiedFiles)
        }
    }
    
    // Legacy method - kept for compatibility
    private func loadAssetDurationWithRetry(asset: AVAsset, name: String) async -> CMTime? {
        for attempt in 1...3 {
            do {
                let duration = try await asset.load(.duration)
                NSLog("✅ Successfully loaded \(name) buffer duration: \(String(format: "%.3f", duration.seconds))s (attempt \(attempt))")
                return duration
            } catch {
                NSLog("⚠️ Attempt \(attempt) failed to load \(name) buffer duration: \(error.localizedDescription)")
                if attempt < 3 {
                    // Wait longer between retries to let the file stabilize
                    try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
                }
            }
        }
        NSLog("❌ Failed to load \(name) buffer duration after 3 attempts")
        return nil
    }
    
    deinit {
        clear()
    }
}