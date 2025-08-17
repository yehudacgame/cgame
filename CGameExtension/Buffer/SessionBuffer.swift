import Foundation
import AVFoundation
import CoreMedia

/// Simple session-based recording that captures entire gameplay to a single file
/// Tracks kill timestamps for end-of-session batch processing
class SessionBuffer {
    
    struct KillEvent {
        let timestamp: Date
        let cmTime: CMTime
        let eventType: String
        let id: String
        
        init(timestamp: Date, cmTime: CMTime, eventType: String) {
            self.timestamp = timestamp
            self.cmTime = cmTime
            self.eventType = eventType
            self.id = UUID().uuidString
        }
    }
    
    private let bufferQueue = DispatchQueue(label: "com.cgame.sessionbuffer", qos: .userInitiated)
    private let bitRate: Int = 4_000_000 // 4Mbps - good balance of quality and file size
    
    // Single continuous recording
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var isRecording = false
    
    // Session data
    private var sessionStartTime: Date?
    private var sessionStartCMTime: CMTime = .zero
    private var killEvents: [KillEvent] = []
    private var sessionURL: URL
    
    // Frame info
    private var videoDimensions: CMVideoDimensions?
    
    init() {
        // Create session file URL
        let appGroupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.cgame.shared"
        )!
        let sessionDir = appGroupURL.appendingPathComponent("Sessions")
        try? FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        
        // Unique session file
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        self.sessionURL = sessionDir.appendingPathComponent("session_\(timestamp).mp4")
        
        NSLog("📹 SessionBuffer: Initialized for session: \(sessionURL.lastPathComponent)")
    }
    
    func startSession() {
        bufferQueue.async { [weak self] in
            self?.initializeRecording()
        }
    }
    
    func add(sample: CMSampleBuffer) {
        bufferQueue.async { [weak self] in
            self?.processSample(sample)
        }
    }
    
    func addKillEvent(at timestamp: Date, cmTime: CMTime, eventType: String) {
        bufferQueue.async { [weak self] in
            guard let self = self else { return }
            
            let killEvent = KillEvent(timestamp: timestamp, cmTime: cmTime, eventType: eventType)
            self.killEvents.append(killEvent)
            
            NSLog("🎯 SessionBuffer: Recorded kill #\(self.killEvents.count) at CMTime: \(String(format: "%.3f", cmTime.seconds))s")
            NSLog("📊 SessionBuffer: Total kills in session: \(self.killEvents.count)")
        }
    }
    
    func endSession(completion: @escaping ([String]) -> Void) {
        bufferQueue.async { [weak self] in
            guard let self = self else {
                completion([])
                return
            }
            
            NSLog("🏁 SessionBuffer: Ending session with \(self.killEvents.count) kills")
            
            // Finalize recording
            self.finalizeRecording { [weak self] in
                guard let self = self else {
                    completion([])
                    return
                }
                
                // Process all kills
                self.processKillClips(completion: completion)
            }
        }
    }
    
    private func initializeRecording() {
        guard !isRecording else { return }
        
        do {
            // Remove existing file if present
            try? FileManager.default.removeItem(at: sessionURL)
            
            writer = try AVAssetWriter(url: sessionURL, fileType: .mp4)
            sessionStartTime = Date()
            
            NSLog("📹 SessionBuffer: Recording started to \(sessionURL.lastPathComponent)")
            
        } catch {
            NSLog("❌ SessionBuffer: Failed to initialize recording: \(error)")
        }
    }
    
    private func processSample(_ sample: CMSampleBuffer) {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sample) else { return }
        let mediaType = CMFormatDescriptionGetMediaType(formatDesc)
        
        // Setup writer inputs on first video frame
        if !isRecording && mediaType == kCMMediaType_Video {
            setupInputs(with: sample)
        }
        
        guard isRecording,
              let writer = writer,
              writer.status == .writing else { return }
        
        // Write sample to appropriate input
        switch mediaType {
        case kCMMediaType_Video:
            if let videoInput = videoInput, videoInput.isReadyForMoreMediaData {
                videoInput.append(sample)
            }
        case kCMMediaType_Audio:
            if let audioInput = audioInput, audioInput.isReadyForMoreMediaData {
                audioInput.append(sample)
            }
        default:
            break
        }
    }
    
    private func setupInputs(with firstSample: CMSampleBuffer) {
        guard let writer = writer,
              let formatDesc = CMSampleBufferGetFormatDescription(firstSample) else { return }
        
        // Get video dimensions
        videoDimensions = CMVideoFormatDescriptionGetDimensions(formatDesc)
        guard let dimensions = videoDimensions else { return }
        
        let width = Int(dimensions.width)
        let height = Int(dimensions.height)
        NSLog("📹 SessionBuffer: Video dimensions: \(width)x\(height)")
        
        // Setup video input - 4Mbps bitrate
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoMaxKeyFrameIntervalKey: 60,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ]
        ]
        
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput?.expectsMediaDataInRealTime = true
        
        if let videoInput = videoInput, writer.canAdd(videoInput) {
            writer.add(videoInput)
        }
        
        // Setup audio input
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44100,
            AVEncoderBitRateKey: 128_000,
        ]
        
        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput?.expectsMediaDataInRealTime = true
        
        if let audioInput = audioInput, writer.canAdd(audioInput) {
            writer.add(audioInput)
        }
        
        // Start writing
        writer.startWriting()
        let startTime = firstSample.presentationTimeStamp
        writer.startSession(atSourceTime: startTime)
        
        sessionStartCMTime = startTime
        isRecording = true
        
        NSLog("📹 SessionBuffer: Started recording session at CMTime: \(String(format: "%.3f", startTime.seconds))s")
    }
    
    private func finalizeRecording(completion: @escaping () -> Void) {
        guard let writer = writer, isRecording else {
            completion()
            return
        }
        
        isRecording = false
        
        writer.finishWriting {
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: self.sessionURL.path)[.size] as? UInt64) ?? 0
            let sizeInMB = Double(fileSize) / (1024 * 1024)
            
            NSLog("📹 SessionBuffer: Recording finalized - Size: \(String(format: "%.1f", sizeInMB))MB")
            completion()
        }
    }
    
    private func processKillClips(completion: @escaping ([String]) -> Void) {
        guard !killEvents.isEmpty else {
            NSLog("📹 SessionBuffer: No kills to process")
            completion([])
            return
        }
        
        NSLog("📹 SessionBuffer: Processing \(killEvents.count) kill clips...")
        
        let dispatchGroup = DispatchGroup()
        var processedClips: [String] = []
        let clipQueue = DispatchQueue(label: "com.cgame.clipprocessing", qos: .userInitiated)
        
        for (index, killEvent) in killEvents.enumerated() {
            dispatchGroup.enter()
            
            clipQueue.async { [weak self] in
                self?.createKillClip(
                    killEvent: killEvent,
                    index: index + 1
                ) { clipFilename in
                    if let filename = clipFilename {
                        processedClips.append(filename)
                    }
                    dispatchGroup.leave()
                }
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            NSLog("📹 SessionBuffer: Processed \(processedClips.count)/\(self.killEvents.count) kill clips")
            completion(processedClips)
        }
    }
    
    private func createKillClip(killEvent: KillEvent, index: Int, completion: @escaping (String?) -> Void) {
        let asset = AVAsset(url: sessionURL)
        
        // Calculate clip timing
        let preRoll: Double = 5.0  // 5 seconds before kill
        let postRoll: Double = 3.0 // 3 seconds after kill
        
        let killTimeOffset = killEvent.cmTime.seconds - sessionStartCMTime.seconds
        let startTime = max(0, killTimeOffset - preRoll)
        let endTime = killTimeOffset + postRoll
        
        let clipStart = CMTime(seconds: startTime, preferredTimescale: 600)
        let clipDuration = CMTime(seconds: endTime - startTime, preferredTimescale: 600)
        let timeRange = CMTimeRange(start: clipStart, duration: clipDuration)
        
        // Output filename
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: killEvent.timestamp)
        let clipFilename = "kill_\(index)_\(timestamp).mp4"
        
        guard let clipsDir = getClipsDirectory() else {
            NSLog("❌ SessionBuffer: Clips directory unavailable")
            completion(nil)
            return
        }
        
        let outputURL = clipsDir.appendingPathComponent(clipFilename)
        
        // Create export session
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            NSLog("❌ SessionBuffer: Failed to create export session")
            completion(nil)
            return
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.timeRange = timeRange
        
        // Apply COD Mobile rotation fix
        if let videoTrack = asset.tracks(withMediaType: .video).first {
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
        
        NSLog("✂️ SessionBuffer: Trimming kill #\(index) from \(String(format: "%.1f", startTime))s to \(String(format: "%.1f", endTime))s")
        
        exportSession.exportAsynchronously {
            switch exportSession.status {
            case .completed:
                NSLog("✅ SessionBuffer: Kill clip #\(index) exported: \(clipFilename)")
                completion(clipFilename)
            case .failed:
                NSLog("❌ SessionBuffer: Kill clip #\(index) export failed: \(exportSession.error?.localizedDescription ?? "Unknown")")
                completion(nil)
            default:
                NSLog("❌ SessionBuffer: Kill clip #\(index) export cancelled or unknown status")
                completion(nil)
            }
        }
    }
    
    private func getClipsDirectory() -> URL? {
        guard let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.cgame.shared") else {
            return nil
        }
        let clipsDir = appGroupURL.appendingPathComponent("Clips", isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: clipsDir.path) {
            do {
                try FileManager.default.createDirectory(at: clipsDir, withIntermediateDirectories: true, attributes: nil)
            } catch {
                NSLog("❌ SessionBuffer: Failed to create Clips directory: \(error.localizedDescription)")
                return nil
            }
        }
        return clipsDir
    }
    
    func cleanup() {
        bufferQueue.async { [weak self] in
            guard let self = self else { return }
            
            if self.isRecording {
                self.finalizeRecording {}
            }
            
            // Clean up session file
            try? FileManager.default.removeItem(at: self.sessionURL)
            NSLog("📹 SessionBuffer: Session cleaned up")
        }
    }
    
    deinit {
        cleanup()
    }
}