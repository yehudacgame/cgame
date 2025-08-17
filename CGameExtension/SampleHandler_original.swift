import ReplayKit
import AVFoundation
import AudioToolbox

/// Session metadata for communication between extension and main app
/// Extension records session info, main app processes exports
struct SessionMetadata: Codable {
    let id: String
    let sessionURL: URL
    let killEvents: [KillEvent]
    let sessionStartTime: Date
    let sessionStartCMTime: CMTime
    let sessionEndTime: Date
    
    struct KillEvent: Codable {
        let timestamp: Date
        let cmTimeSeconds: Double // CMTime converted to seconds for JSON serialization
        let eventType: String
        let id: String
        
        init(timestamp: Date, cmTime: CMTime, eventType: String) {
            self.timestamp = timestamp
            self.cmTimeSeconds = cmTime.seconds
            self.eventType = eventType
            self.id = UUID().uuidString
        }
        
        /// Convert back to CMTime when needed
        var cmTime: CMTime {
            return CMTime(seconds: cmTimeSeconds, preferredTimescale: 600)
        }
    }
    
    init(sessionURL: URL, killEvents: [KillEvent], sessionStartTime: Date, sessionStartCMTime: CMTime) {
        self.id = UUID().uuidString
        self.sessionURL = sessionURL
        self.killEvents = killEvents
        self.sessionStartTime = sessionStartTime
        self.sessionStartCMTime = sessionStartCMTime
        self.sessionEndTime = Date()
    }
}

/// Extension for CMTime encoding/decoding
extension CMTime: Codable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(seconds, forKey: .seconds)
        try container.encode(timescale, forKey: .timescale)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let seconds = try container.decode(Double.self, forKey: .seconds)
        let timescale = try container.decode(CMTimeScale.self, forKey: .timescale)
        self = CMTime(seconds: seconds, preferredTimescale: timescale)
    }
    
    private enum CodingKeys: String, CodingKey {
        case seconds
        case timescale
    }
}

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
    
    func endSession(completion: @escaping () -> Void) {
        bufferQueue.async { [weak self] in
            guard let self = self else {
                completion()
                return
            }
            
            NSLog("🏁 SessionBuffer: Ending session with \(self.killEvents.count) kills")
            
            // Finalize recording
            self.finalizeRecording { [weak self] in
                guard let self = self else {
                    completion()
                    return
                }
                
                // Save session metadata for main app to process
                self.saveSessionMetadata()
                completion()
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
    
    private func saveSessionMetadata() {
        guard !killEvents.isEmpty else {
            NSLog("📹 SessionBuffer: No kills to save")
            return
        }
        
        NSLog("📹 SessionBuffer: Saving session info with \(killEvents.count) kills for main app processing")
        
        // Convert kill events to simple tuple format
        let killTimestamps = killEvents.map { killEvent in
            (killEvent.timestamp, killEvent.cmTime.seconds, killEvent.eventType)
        }
        
        AppGroupManager.shared.saveSessionInfo(sessionURL: sessionURL, killTimestamps: killTimestamps)
        NSLog("📹 SessionBuffer: Session info saved - main app will process \(killEvents.count) kill clips")
    }
    
}

@objc(CGameExtensionSampleHandler)
class SampleHandler: RPBroadcastSampleHandler {
    
    private var eventDetector: EventDetector?
    private var sessionBuffer: SessionBuffer?
    private var isRecording = false
    
    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        isRecording = true
        
        NSLog("INFO: Broadcast started.")
        
        let settings = loadUserSettings()
        let selectedProfile = loadSelectedDetectionProfile(from: settings)
        
        // Initialize simple session buffer for continuous recording
        sessionBuffer = SessionBuffer()
        sessionBuffer?.startSession()
        
        eventDetector = EventDetector(activeProfile: selectedProfile)
        eventDetector?.onEventDetected = { [weak self] (timestamp: Date, cmTime: CMTime, event: String) in
            // Format timestamp to show local time clearly
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .medium
            formatter.timeZone = TimeZone.current
            NSLog("🎯 CGAME: KILL DETECTED at \(formatter.string(from: timestamp)) local time (CMTime: \(String(format: "%.3f", cmTime.seconds))s)!")
            
            // Simply add kill event to session buffer - no complex processing
            self?.sessionBuffer?.addKillEvent(at: timestamp, cmTime: cmTime, eventType: event)
            
            // Play sound/vibration notification immediately
            AudioServicesPlaySystemSound(1113) // Achievement sound
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
        
        NSLog("🎮 CGame Highlight Recorder started!")
        NSLog("📺 Monitoring for: \(selectedProfile.name)")
    }
    
    override func broadcastPaused() {
        print("Broadcast paused")
    }
    
    override func broadcastResumed() {
        print("Broadcast resumed")
    }
    
    override func broadcastFinished() {
        isRecording = false
        
        NSLog("🏁 CGAME: Broadcast finished - finalizing any pending sessions...")
        
        // Use a semaphore to wait for the async export to complete
        let semaphore = DispatchSemaphore(value: 0)
        
        sessionBuffer?.endSession { [weak self] in
            NSLog("🏁 CGAME: Session ended - metadata saved for main app processing")
            
            self?.eventDetector = nil
            self?.sessionBuffer = nil
            
            NSLog("🏁 CGAME: Broadcast cleanup completed")
            
            // Signal that we're done
            semaphore.signal()
        }
        
        // Wait briefly for session metadata to save before terminating
        _ = semaphore.wait(timeout: .now() + 2.0)
        NSLog("🏁 CGAME: broadcastFinished is now unblocked.")
    }
    
    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard isRecording else { return }
        
        switch sampleBufferType {
        case .video:
            // Session buffer handles continuous recording
            sessionBuffer?.add(sample: sampleBuffer)
            
            if let detector = eventDetector {
                detector.analyze(sampleBuffer: sampleBuffer)
            } else {
                NSLog("ERROR: EventDetector is nil in processSampleBuffer.")
            }
            
        case .audioApp, .audioMic:
            // Session buffer handles audio too
            sessionBuffer?.add(sample: sampleBuffer)
            break
            
        @unknown default:
            break
        }
    }
    
    private func saveClipList(_ clipFilenames: [String]) {
        // Save list of clip filenames for main app to discover
        guard let appGroupDefaults = UserDefaults(suiteName: "group.com.cgame.shared") else {
            NSLog("❌ CGAME: Failed to access App Groups for clip list")
            return
        }
        
        appGroupDefaults.set(clipFilenames, forKey: "processed_clips")
        appGroupDefaults.set(Date().timeIntervalSince1970, forKey: "clips_updated_at")
        NSLog("📝 CGAME: Saved \(clipFilenames.count) clip filenames to App Groups")
    }
    
    private func loadUserSettings() -> UserSettings {
        guard let appGroupDefaults = UserDefaults(suiteName: "group.com.cgame.shared") else {
            NSLog("CRITICAL: App Group not accessible, using default COD settings.")
            return UserSettings(gameProfileName: "CallOfDuty", videoQuality: .hd1080p, preRollDuration: 5.0, postRollDuration: 3.0)
        }
        
        let gameProfile = appGroupDefaults.string(forKey: "selectedProfile") ?? "CallOfDuty"
        let preRoll = appGroupDefaults.double(forKey: "preRollDuration")
        let postRoll = appGroupDefaults.double(forKey: "postRollDuration")
        let qualityRaw = appGroupDefaults.string(forKey: "videoQuality") ?? UserSettings.VideoQuality.hd1080p.rawValue
        let videoQuality = UserSettings.VideoQuality(rawValue: qualityRaw) ?? .hd1080p
        
        return UserSettings(
            gameProfileName: gameProfile,
            videoQuality: videoQuality,
            preRollDuration: preRoll > 0 ? preRoll : 5.0,
            postRollDuration: postRoll > 0 ? postRoll : 3.0
        )
    }
    
    private func loadSelectedDetectionProfile(from settings: UserSettings) -> DetectionProfile {
        let profileName = settings.gameProfileName
        
        switch profileName {
        case "CallOfDuty":
            return CallOfDutyProfile()
        case "Valorant":
            return ValorantProfile()
        default:
            return FortniteProfile()
        }
    }
}