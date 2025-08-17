import Foundation
import AVFoundation
import CoreMedia

class CompressedCyclicBuffer {
    private let maxDurationSeconds: Double
    private let segmentDuration: Double = 1.0 // Internal segment size for efficient memory management
    private var segments: [(url: URL, startTime: Date, duration: Double)] = []
    private let segmentQueue = DispatchQueue(label: "com.cgame.compressedbuffer", qos: .userInitiated)
    
    // The buffer maintains 30 seconds of compressed video using 1-second segments
    // This allows efficient memory usage while keeping 30 seconds of history
    
    private var currentWriter: AVAssetWriter?
    private var currentVideoInput: AVAssetWriterInput?
    private var currentAudioInput: AVAssetWriterInput?
    private var currentSegmentURL: URL?
    private var currentSegmentStartTime: Date?
    private var firstSampleTime: CMTime?
    private var segmentFrameCount = 0
    
    private let containerURL: URL
    
    init(maxDurationSeconds: Double = 30.0) {
        self.maxDurationSeconds = maxDurationSeconds
        
        // Create container directory in app group
        let appGroupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.cgame.shared"
        )!
        self.containerURL = appGroupURL.appendingPathComponent("CyclicBuffer")
        
        // Create directory if needed
        try? FileManager.default.createDirectory(
            at: containerURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        
        // Clean up old segments on init
        cleanupAllSegments()
    }
    
    func add(sample: CMSampleBuffer) {
        segmentQueue.async { [weak self] in
            self?.addSampleSync(sample)
        }
    }
    
    private func addSampleSync(_ sample: CMSampleBuffer) {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sample) else { return }
        let mediaType = CMFormatDescriptionGetMediaType(formatDesc)
        
        // Check if we need to start a new segment
        if shouldStartNewSegment() {
            finalizeCurrentSegment()
            startNewSegment(with: sample)
        }
        
        // Ensure writer is ready
        if currentWriter == nil {
            startNewSegment(with: sample)
        }
        
        // Write the sample
        guard let writer = currentWriter,
              writer.status == .writing else { return }
        
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sample)
        
        switch mediaType {
        case kCMMediaType_Video:
            if let videoInput = currentVideoInput,
               videoInput.isReadyForMoreMediaData {
                videoInput.append(sample)
                segmentFrameCount += 1
            }
            
        case kCMMediaType_Audio:
            if let audioInput = currentAudioInput,
               audioInput.isReadyForMoreMediaData {
                audioInput.append(sample)
            }
            
        default:
            break
        }
    }
    
    private func shouldStartNewSegment() -> Bool {
        guard let startTime = currentSegmentStartTime else { return true }
        return Date().timeIntervalSince(startTime) >= segmentDuration
    }
    
    private func startNewSegment(with sample: CMSampleBuffer) {
        let segmentURL = containerURL.appendingPathComponent("segment_\(Date().timeIntervalSince1970).mp4")
        
        do {
            let writer = try AVAssetWriter(url: segmentURL, fileType: .mp4)
            
            // Configure video input with compression
            if let formatDesc = CMSampleBufferGetFormatDescription(sample),
               CMFormatDescriptionGetMediaType(formatDesc) == kCMMediaType_Video {
                
                let videoInput = createVideoInput(from: formatDesc)
                if writer.canAdd(videoInput) {
                    writer.add(videoInput)
                    currentVideoInput = videoInput
                }
                
                // Add audio input configuration
                let audioInput = createAudioInput()
                if writer.canAdd(audioInput) {
                    writer.add(audioInput)
                    currentAudioInput = audioInput
                }
            }
            
            // Start writing
            writer.startWriting()
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sample)
            writer.startSession(atSourceTime: presentationTime)
            
            currentWriter = writer
            currentSegmentURL = segmentURL
            currentSegmentStartTime = Date()
            firstSampleTime = presentationTime
            segmentFrameCount = 0
            
            NSLog("Started new segment at \(segmentURL.lastPathComponent)")
            
        } catch {
            NSLog("Failed to create segment writer: \(error)")
        }
    }
    
    private func createVideoInput(from formatDesc: CMFormatDescription) -> AVAssetWriterInput {
        // Get video dimensions
        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDesc)
        
        // Configure compression settings for low memory usage
        let compressionSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: dimensions.width,
            AVVideoHeightKey: dimensions.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 2_000_000, // 2 Mbps for good quality
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCABAC,
                AVVideoMaxKeyFrameIntervalKey: 30, // Keyframe every second at 30fps
                AVVideoAllowFrameReorderingKey: false,
                AVVideoExpectedSourceFrameRateKey: 30
            ]
        ]
        
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: compressionSettings
        )
        videoInput.expectsMediaDataInRealTime = true
        
        return videoInput
    }
    
    private func createAudioInput() -> AVAssetWriterInput {
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128000
        ]
        
        let audioInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: audioSettings
        )
        audioInput.expectsMediaDataInRealTime = true
        
        return audioInput
    }
    
    private func finalizeCurrentSegment() {
        guard let writer = currentWriter,
              let segmentURL = currentSegmentURL,
              let startTime = currentSegmentStartTime else { return }
        
        // Mark inputs as finished
        currentVideoInput?.markAsFinished()
        currentAudioInput?.markAsFinished()
        
        // Finish writing
        writer.finishWriting { [weak self] in
            if writer.status == .completed {
                let duration = Date().timeIntervalSince(startTime)
                self?.segments.append((url: segmentURL, startTime: startTime, duration: duration))
                self?.trimOldSegments()
                
                NSLog("Finalized segment: \(segmentURL.lastPathComponent), frames: \(self?.segmentFrameCount ?? 0), duration: \(duration)s")
            } else if let error = writer.error {
                NSLog("Failed to finalize segment: \(error)")
            }
        }
        
        // Clear current writer
        currentWriter = nil
        currentVideoInput = nil
        currentAudioInput = nil
        currentSegmentURL = nil
        currentSegmentStartTime = nil
        firstSampleTime = nil
    }
    
    private func trimOldSegments() {
        let cutoffTime = Date().addingTimeInterval(-maxDurationSeconds)
        
        // Remove old segments
        let segmentsToRemove = segments.filter { $0.startTime < cutoffTime }
        for segment in segmentsToRemove {
            try? FileManager.default.removeItem(at: segment.url)
            NSLog("Removed old segment: \(segment.url.lastPathComponent)")
        }
        
        // Keep only recent segments
        segments = segments.filter { $0.startTime >= cutoffTime }
    }
    
    func exportClip(from startTime: Date, to endTime: Date, outputURL: URL, completion: @escaping (Bool) -> Void) {
        segmentQueue.async { [weak self] in
            guard let self = self else {
                completion(false)
                return
            }
            
            // Finalize current segment if needed
            self.finalizeCurrentSegment()
            
            // Find relevant segments
            let relevantSegments = self.segments.filter { segment in
                let segmentEnd = segment.startTime.addingTimeInterval(segment.duration)
                return (segment.startTime <= endTime && segmentEnd >= startTime)
            }
            
            if relevantSegments.isEmpty {
                NSLog("No segments found for time range")
                completion(false)
                return
            }
            
            // Merge segments using AVMutableComposition
            self.mergeSegments(relevantSegments, outputURL: outputURL, completion: completion)
        }
    }
    
    private func mergeSegments(_ segments: [(url: URL, startTime: Date, duration: Double)], outputURL: URL, completion: @escaping (Bool) -> Void) {
        let composition = AVMutableComposition()
        
        var currentTime = CMTime.zero
        
        for segment in segments {
            do {
                let asset = AVAsset(url: segment.url)
                let timeRange = CMTimeRange(start: .zero, duration: asset.duration)
                
                try composition.insertTimeRange(
                    timeRange,
                    of: asset,
                    at: currentTime
                )
                
                currentTime = CMTimeAdd(currentTime, asset.duration)
                
            } catch {
                NSLog("Failed to add segment to composition: \(error)")
            }
        }
        
        // Export the composition
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            completion(false)
            return
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        
        exportSession.exportAsynchronously {
            completion(exportSession.status == .completed)
            
            if exportSession.status == .failed {
                NSLog("Export failed: \(exportSession.error?.localizedDescription ?? "Unknown error")")
            }
        }
    }
    
    func clear() {
        segmentQueue.async { [weak self] in
            self?.finalizeCurrentSegment()
            self?.cleanupAllSegments()
        }
    }
    
    private func cleanupAllSegments() {
        // Remove all segment files
        for segment in segments {
            try? FileManager.default.removeItem(at: segment.url)
        }
        segments.removeAll()
        
        // Clean up any orphaned files
        if let files = try? FileManager.default.contentsOfDirectory(at: containerURL, includingPropertiesForKeys: nil) {
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
    
    deinit {
        clear()
    }
}