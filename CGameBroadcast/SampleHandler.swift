//
//  SampleHandler.swift
//  CGameBroadcast
//
//  Created by Yehuda Elmaliach on 15/08/2025.
//

import ReplayKit
import AVFoundation
import AudioToolbox
import Vision

class SampleHandler: RPBroadcastSampleHandler {
    
    // Session-based recording components
    private var sessionBuffer: SessionBuffer?
    private var eventDetector: EventDetector?
    private var isSessionActive = false
    private var frameCounter = 0
    
    override init() {
        super.init()
        NSLog("🚀 CGame AI Recorder: Extension initialized successfully!")
    }
    
    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        NSLog("🎮 CGame AI Recorder: broadcastStarted() called!")
        
        // Initialize session-based recording
        sessionBuffer = SessionBuffer()
        
        // Initialize event detector with COD Mobile profile
        eventDetector = EventDetector(activeProfile: CallOfDutyProfile(), config: DetectionConfig.codMobileDefault)
        
        // Setup kill detection callback
        eventDetector?.onEventDetected = { [weak self] timestamp, cmTime, eventType in
            NSLog("🎯 CGame AI Recorder: Kill detected - \(eventType)")
            self?.sessionBuffer?.addKillEvent(at: timestamp, cmTime: cmTime, eventType: eventType)
        }
        
        // Start session recording
        sessionBuffer?.startSession()
        
        isSessionActive = true
        frameCounter = 0
        
        NSLog("🎮 CGame AI Recorder: Session-based recording STARTED!")
        NSLog("📱 Setup info: \(String(describing: setupInfo))")
        
        // Play start sound
        AudioServicesPlaySystemSound(1113)
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        
        NSLog("🎮 CGame AI Recorder: broadcastStarted() completed!")
    }
    
    override func broadcastPaused() {
        NSLog("⏸️ CGame AI Recorder: Broadcast PAUSED")
    }
    
    override func broadcastResumed() {
        NSLog("▶️ CGame AI Recorder: Broadcast RESUMED")
    }
    
    override func broadcastFinished() {
        NSLog("🏁 CGame AI Recorder: Broadcast FINISHED after \(frameCounter) frames")
        
        guard isSessionActive else { return }
        isSessionActive = false
        
        // End session and process kill clips
        sessionBuffer?.endSession { [weak self] processedClips in
            NSLog("📹 CGame AI Recorder: Session ended - \(processedClips.count) clips processed")
            
            // Save session info for main app
            if let sessionURL = self?.sessionBuffer?.getSessionURL() {
                AppGroupManager.shared.savePendingSessionInfo(
                    sessionURL: sessionURL,
                    killEvents: [] // Kill events already processed into clips
                )
            }
            
            // Notify main app of completion
            self?.notifyMainAppOfSessionComplete()
        }
        
        sessionBuffer = nil
        eventDetector = nil
    }
    
    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard isSessionActive else { return }
        
        switch sampleBufferType {
        case .video:
            frameCounter += 1
            
            // Add frame to session recording
            sessionBuffer?.add(sample: sampleBuffer)
            
            // Perform OCR for kill detection (every 10th frame)
            if frameCounter % 10 == 0 {
                eventDetector?.analyze(sampleBuffer: sampleBuffer)
            }
            
            if frameCounter % 30 == 0 {
                NSLog("📹 CGame AI Recorder: Processed \(frameCounter) video frames")
            }
            
        case .audioApp, .audioMic:
            // Add audio to session recording
            sessionBuffer?.add(sample: sampleBuffer)
            
        @unknown default:
            break
        }
    }
    
    private func notifyMainAppOfSessionComplete() {
        // Use UserDefaults to notify main app
        let sharedDefaults = UserDefaults(suiteName: "group.com.cgame.shared")
        sharedDefaults?.set(Date().timeIntervalSince1970, forKey: "lastSessionCompleted")
        sharedDefaults?.synchronize()
        
        NSLog("📱 CGame AI Recorder: Notified main app of session completion")
    }
}

// MARK: - SessionBuffer Implementation
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
    
    func getSessionURL() -> URL {
        return sessionURL
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
        
        // Get clips directory from App Groups
        let appGroupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.cgame.shared"
        )!
        let clipsDir = appGroupURL.appendingPathComponent("Clips")
        try? FileManager.default.createDirectory(at: clipsDir, withIntermediateDirectories: true)
        
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

// MARK: - Simplified EventDetector for ELIMINATED detection
class EventDetector {
    private let activeProfile: DetectionProfile
    var onEventDetected: ((Date, CMTime, String) -> Void)?
    
    private let processQueue = DispatchQueue(label: "com.cgame.eventdetector", qos: .userInitiated)
    private var frameCounter = 0
    private var lastDetectionTime: Date = Date.distantPast
    private let detectionCooldownSeconds: TimeInterval = 3.0
    private let frameSkipInterval = 10
    
    init(activeProfile: DetectionProfile, config: DetectionConfig) {
        self.activeProfile = activeProfile
        
        NSLog("🔍 EventDetector initialized for: \(activeProfile.name)")
    }
    
    func analyze(sampleBuffer: CMSampleBuffer) {
        frameCounter += 1
        
        // Log every frame for debugging like working version
        if frameCounter % 30 == 0 { // Log every 30 frames (once per second at 30fps)
            NSLog("🎬 CGAME: Total frames received: \(frameCounter)")
        }
        
        // Check frame skip interval
        guard frameCounter % frameSkipInterval == 0 else { 
            if frameCounter <= 50 { // Log first 50 frames for debugging
                NSLog("⏭️ CGAME: Skipping frame \(frameCounter), next OCR at frame \((frameCounter / frameSkipInterval + 1) * frameSkipInterval)")
            }
            return 
        }
        
        // Cooldown check
        let now = Date()
        let timeSinceLastDetection = now.timeIntervalSince(lastDetectionTime)
        if timeSinceLastDetection <= detectionCooldownSeconds {
            NSLog("⏰ CGAME: In cooldown, \(String(format: "%.1f", detectionCooldownSeconds - timeSinceLastDetection))s remaining")
            return
        }
        
        // Strong debug logging - ALWAYS log OCR attempts like working version
        NSLog("🔍 CGAME OCR: Processing frame \(frameCounter) for \(activeProfile.name)")
        
        processQueue.async { [weak self] in
            self?.performOCR(on: sampleBuffer)
        }
    }
    
    private func performOCR(on sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Detect if this is landscape game content in portrait video format
        let imageWidth = ciImage.extent.width
        let imageHeight = ciImage.extent.height
        let isPortraitVideo = imageHeight > imageWidth
        
        NSLog("🖥️ CGAME OCR: Image dimensions: \(Int(imageWidth))x\(Int(imageHeight)), isPortrait: \(isPortraitVideo)")
        
        // Use FULL SCREEN detection like the working version - no cropping!
        // The working config uses x=0.0, y=0.0, width=1.0, height=1.0
        let fullImage = ciImage
        
        // For landscape game in portrait video, rotate the ENTIRE image 90 degrees counterclockwise
        let finalImage: CIImage
        if isPortraitVideo {
            let rotatedImage = fullImage.oriented(.left)
            finalImage = rotatedImage
            NSLog("🔄 CGAME OCR: Rotated FULL image 90° counterclockwise for landscape text recognition")
        } else {
            finalImage = fullImage
        }
        
        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let self = self else { return }
            
            if let error = error {
                NSLog("ERROR: OCR analysis failed. Details: \(error.localizedDescription)")
                return
            }
            
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                return
            }
            
            // ALWAYS log detected text for debugging like working version
            if !observations.isEmpty {
                NSLog("📝 CGAME OCR: Found \(observations.count) text observations in frame \(self.frameCounter)")
                for (index, obs) in observations.enumerated().prefix(5) {
                    // Debug the candidate extraction process like working version
                    let candidates = obs.topCandidates(1)
                    NSLog("📝 CGAME OCR: [\(index)] Has \(candidates.count) candidates")
                    
                    if let text = candidates.first?.string,
                       let confidence = candidates.first?.confidence {
                        NSLog("📝 CGAME OCR: [\(index)] '\(text)' (confidence: \(String(format: "%.2f", confidence)))")
                        
                        // Apply working detection logic with confidence threshold
                        let confidenceThreshold: Float = 0.5  // Lower than default 0.8 for testing
                        
                        guard confidence >= confidenceThreshold else {
                            // Log if ELIMINATED was found but confidence too low
                            if text.uppercased().contains("ELIMIN") {
                                NSLog("⚠️ CGAME: Found 'ELIMIN' text but confidence too low: '\(text)' at \(String(format: "%.1f%%", confidence * 100)) (minimum: \(String(format: "%.0f%%", confidenceThreshold * 100)))")
                            }
                            continue
                        }
                        
                        let originalText = text.trimmingCharacters(in: .whitespaces)
                        let textToCheck = originalText.uppercased()
                        
                        // Check avoid keywords first (like working version)
                        let avoidKeywords = ["KILLED BY", "ELIMINATED BY", "Kill Highlight", "CGAME", "Duration", "Recorded"]
                        let shouldAvoid = avoidKeywords.contains { avoidKeyword in
                            return textToCheck.contains(avoidKeyword.uppercased())
                        }
                        
                        if shouldAvoid {
                            NSLog("🚫 CGAME: Skipping text '\(originalText)' - contains avoid keyword")
                            continue
                        }
                        
                        // Check for ELIMINATED with same debug logic as working version
                        let targetKeyword = "ELIMINATED"
                        
                        // Debug logging specifically for ELIMINATED detection attempts
                        if originalText.uppercased().contains("ELIMIN") {
                            NSLog("🔍 CGAME DETECTION DEBUG: Found ELIMIN text: '\(originalText)' checking against '\(targetKeyword)'")
                            NSLog("🔍 CGAME DETECTION DEBUG: textToCheck='\(textToCheck)' contains '\(targetKeyword)'? \(textToCheck.contains(targetKeyword))")
                        }
                        
                        if textToCheck.contains(targetKeyword) {
                            self.lastDetectionTime = Date()
                            
                            NSLog("🎯 COD KILL DETECTED: '\(targetKeyword)' found in '\(originalText)'")
                            NSLog("📍 Detection confidence: \(String(format: "%.1f%%", confidence * 100))")
                            
                            // Play kill notification sound and vibration
                            AudioServicesPlaySystemSound(1113) // Achievement sound
                            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                            NSLog("🔊 Kill notification played!")
                            
                            // Extract CMTime from the sample buffer for precise export
                            let eventCMTime = sampleBuffer.presentationTimeStamp
                            NSLog("🎯 CGAME Kill Detection: Event '\(targetKeyword)' detected at frame CMTime: \(String(format: "%.3f", eventCMTime.seconds))s")
                            self.onEventDetected?(Date(), eventCMTime, "ELIMINATED")
                            return
                        }
                    } else {
                        NSLog("📝 CGAME OCR: [\(index)] Failed to extract text or confidence from candidate")
                        // Try alternative approach
                        let alternativeText = obs.topCandidates(1).first?.string ?? "NO STRING"
                        NSLog("📝 CGAME OCR: [\(index)] Alternative extraction: '\(alternativeText)'")
                    }
                }
            } else {
                NSLog("📝 CGAME OCR: No text found in frame \(self.frameCounter)")
            }
        }
        
        // Use same settings as working version
        request.recognitionLevel = .accurate  // Changed from .fast to .accurate like working version
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        request.minimumTextHeight = 0.01  // Allow smaller text
        
        NSLog("🔧 CGAME OCR: Using accurate recognition level for better text detection")
        
        let handler = VNImageRequestHandler(ciImage: finalImage, options: [:])
        
        do {
            try handler.perform([request])
        } catch {
            NSLog("ERROR: Failed to perform OCR request. Details: \(error.localizedDescription)")
        }
    }
}

// MARK: - Protocol Definitions
protocol DetectionProfile {
    var name: String { get }
    var recognitionRegion: CGRect { get }
    func didDetectEvent(from observations: [VNRecognizedTextObservation]) -> String?
}

struct CallOfDutyProfile: DetectionProfile {
    let name = "Call of Duty Mobile"
    let recognitionRegion = CGRect(x: 0.5, y: 0.1, width: 0.45, height: 0.4)
    
    func didDetectEvent(from observations: [VNRecognizedTextObservation]) -> String? {
        for observation in observations {
            guard let topCandidate = observation.topCandidates(1).first else { continue }
            
            let text = topCandidate.string.uppercased()
            if text.contains("ELIMINATED") {
                return "ELIMINATED"
            }
        }
        return nil
    }
}

struct DetectionConfig {
    let frameSkipInterval: Int
    let detectionCooldownSeconds: TimeInterval
    let ocrConfidenceThreshold: Float
    
    static let codMobileDefault = DetectionConfig(
        frameSkipInterval: 10,
        detectionCooldownSeconds: 3.0,
        ocrConfidenceThreshold: 0.5
    )
}

// MARK: - AppGroup Helper
struct AppGroupManager {
    static let shared = AppGroupManager()
    
    func savePendingSessionInfo(sessionURL: URL, killEvents: [SessionBuffer.KillEvent]) {
        let sharedDefaults = UserDefaults(suiteName: "group.com.cgame.shared")
        sharedDefaults?.set(sessionURL.path, forKey: "lastSessionURL")
        sharedDefaults?.set(killEvents.count, forKey: "lastSessionKillCount")
        sharedDefaults?.synchronize()
        
        NSLog("📱 AppGroupManager: Saved session info - \(killEvents.count) kills")
    }
}