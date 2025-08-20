import Foundation
import AVFoundation
import CoreMedia
import CoreGraphics
import VideoToolbox

// Minimal App Group helper local to the extension target
private struct ExtAppGroupSession {
	static let shared = ExtAppGroupSession()
	private let appGroupIdentifier = "group.com.cgame.shared"

	func saveSessionInfo(sessionURL: URL, killTimestamps: [(Date, Double, String)]) {
		guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
			NSLog("❌ ExtAppGroupSession: Failed to access App Groups")
			return
		}
		let timestamps = killTimestamps.map { $0.0.timeIntervalSince1970 }
		let cmTimes = killTimestamps.map { $0.1 }
		let eventTypes = killTimestamps.map { $0.2 }
		defaults.set(sessionURL.path, forKey: "pending_session_url")
		defaults.set(timestamps, forKey: "pending_kill_timestamps")
		defaults.set(cmTimes, forKey: "pending_kill_cmtimes")
		defaults.set(eventTypes, forKey: "pending_kill_events")
		defaults.set(Date().timeIntervalSince1970, forKey: "session_updated_at")
		NSLog("📊 ExtAppGroupSession: Saved session info with \(killTimestamps.count) kills")
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
    
    // Simple helper to mirror diagnostics into App Group error.log
    private func writeSharedLog(_ message: String) {
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.cgame.shared") {
            let dir = container.appendingPathComponent("Debug", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("error.log")
            let ts = ISO8601DateFormatter().string(from: Date())
            let line = "[EXT] \(ts) \(message)\n"
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: url.path) {
                    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(data); try? h.close() }
                } else {
                    try? data.write(to: url)
                }
            }
        }
    }
    
    // Single continuous recording
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var compressionSession: VTCompressionSession?
    private var isRecording = false
    private var baseVideoPTS: CMTime = .invalid
    private var forcedKeyframeSent: Bool = false
    // Append counters for diagnostics
    private var videoSamplesAppended: Int = 0
    private var videoSamplesFailed: Int = 0
    private var audioSamplesAppended: Int = 0
    private var audioSamplesFailed: Int = 0
    
    // Session data
    private var sessionStartTime: Date?
    private var sessionStartCMTime: CMTime = .zero
    private var killEvents: [KillEvent] = []
    private var sessionURL: URL
    
    // Frame info
    private var videoDimensions: CMVideoDimensions?
    
    init() {
        // Create session file URL
        guard let appGroupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.cgame.shared"
        ) else {
            NSLog("❌ SessionBuffer: Failed to access App Group container")
            // Fallback to tmp directory to prevent crash
            let tmpDir = FileManager.default.temporaryDirectory
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let timestamp = dateFormatter.string(from: Date())
            self.sessionURL = tmpDir.appendingPathComponent("session_\(timestamp).mp4")
            return
        }
        
        let sessionDir = appGroupURL.appendingPathComponent("Sessions")
        do {
            try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        } catch {
            NSLog("❌ SessionBuffer: Failed to create Sessions directory: \(error)")
        }
        
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
            
            // Persist updated session info so the main app knows about the session file
            let killTriples: [(Date, Double, String)] = self.killEvents.map { evt in
                (evt.timestamp, evt.cmTime.seconds, evt.eventType)
            }
            ExtAppGroupSession.shared.saveSessionInfo(sessionURL: self.sessionURL, killTimestamps: killTriples)
        }
    }
    
    func endSession(completion: @escaping ([String]) -> Void) {
        bufferQueue.async { [weak self] in
            guard let self = self else {
                completion([])
                return
            }
            
            NSLog("🏁 SessionBuffer: Ending session with \(self.killEvents.count) kills")
            
            // Persist latest session info immediately before finalizing
            let preFinalizeTriples: [(Date, Double, String)] = self.killEvents.map { evt in
                (evt.timestamp, evt.cmTime.seconds, evt.eventType)
            }
            ExtAppGroupSession.shared.saveSessionInfo(sessionURL: self.sessionURL, killTimestamps: preFinalizeTriples)
            
            // Finalize recording
            self.finalizeRecording { [weak self] in
                guard let self = self else {
                    completion([])
                    return
                }
                
                // NEW: Persist session + kill metadata for main app to trim without re-encoding
                let killTriples: [(Date, Double, String)] = self.killEvents.map { evt in
                    (evt.timestamp, evt.cmTime.seconds, evt.eventType)
                }
                ExtAppGroupSession.shared.saveSessionInfo(sessionURL: self.sessionURL, killTimestamps: killTriples)
                NSLog("📊 SessionBuffer: Saved session info for main app (\(killTriples.count) kills)")
                
                // Do NOT export clips in the extension anymore
                completion([])
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
            
            // Persist initial session info early so the main app knows about the session file
            let killTriples: [(Date, Double, String)] = self.killEvents.map { evt in
                (evt.timestamp, evt.cmTime.seconds, evt.eventType)
            }
            ExtAppGroupSession.shared.saveSessionInfo(sessionURL: self.sessionURL, killTimestamps: killTriples)
            
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
            if let session = compressionSession {
                if let pixelBuffer = CMSampleBufferGetImageBuffer(sample) {
                    var pts = CMSampleBufferGetPresentationTimeStamp(sample)
                    if CMTIME_IS_INVALID(baseVideoPTS) { baseVideoPTS = pts }
                    pts = CMTimeSubtract(pts, baseVideoPTS)
                    var frameProps: CFDictionary?
                    if !forcedKeyframeSent {
                        let dict: [NSString: Any] = [kVTEncodeFrameOptionKey_ForceKeyFrame: true]
                        frameProps = dict as CFDictionary
                        forcedKeyframeSent = true
                    }
                    let status = VTCompressionSessionEncodeFrame(session,
                        imageBuffer: pixelBuffer,
                        presentationTimeStamp: pts,
                        duration: .invalid,
                        frameProperties: frameProps,
                        sourceFrameRefcon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                        infoFlagsOut: nil)
                    if status != noErr {
                        NSLog("❌ SessionBuffer: VTCompressionSessionEncodeFrame error=\(status)")
                    } else {
                        // Compressed sample will be appended in the output callback
                    }
                } else if let videoInput = videoInput {
                    // Fallback: ReplayKit provided an already-compressed sample (no CVImageBuffer)
                    // Remap timing to zero-based and append directly
                    var timingCount: CMItemCount = 0
                    CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: 0, arrayToFill: nil, entriesNeededOut: &timingCount)
                    var timingInfo = Array(repeating: CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .invalid, decodeTimeStamp: .invalid), count: timingCount)
                    CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: timingCount, arrayToFill: &timingInfo, entriesNeededOut: &timingCount)
                    if CMTIME_IS_INVALID(baseVideoPTS) { baseVideoPTS = timingInfo.first?.presentationTimeStamp ?? .zero }
                    for i in 0..<timingInfo.count {
                        if CMTIME_IS_VALID(timingInfo[i].presentationTimeStamp) {
                            timingInfo[i].presentationTimeStamp = CMTimeSubtract(timingInfo[i].presentationTimeStamp, baseVideoPTS)
                        }
                        if CMTIME_IS_VALID(timingInfo[i].decodeTimeStamp) {
                            timingInfo[i].decodeTimeStamp = CMTimeSubtract(timingInfo[i].decodeTimeStamp, baseVideoPTS)
                        }
                    }
                    var remappedSample: CMSampleBuffer?
                    CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: sample, sampleTimingEntryCount: timingCount, sampleTimingArray: &timingInfo, sampleBufferOut: &remappedSample)
                    let sampleToAppend = remappedSample ?? sample
                    if videoInput.append(sampleToAppend) {
                        videoSamplesAppended += 1
                    } else {
                        videoSamplesFailed += 1
                        let ready = videoInput.isReadyForMoreMediaData
                        let msg = "SessionBuffer: videoInput.append(compressed-fallback) returned false (ready=\(ready) status=\(writer.status.rawValue) err=\(writer.error?.localizedDescription ?? "nil"))"
                        NSLog("❌ \(msg)")
                        writeSharedLog("❌ \(msg)")
                    }
                }
            } else if let videoInput = videoInput {
                // Remap PTS/DTS to start from zero for writer stability
                var timingCount: CMItemCount = 0
                CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: 0, arrayToFill: nil, entriesNeededOut: &timingCount)
                var timingInfo = Array(repeating: CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .invalid, decodeTimeStamp: .invalid), count: timingCount)
                CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: timingCount, arrayToFill: &timingInfo, entriesNeededOut: &timingCount)
                if CMTIME_IS_INVALID(baseVideoPTS) { baseVideoPTS = timingInfo.first?.presentationTimeStamp ?? .zero }
                for i in 0..<timingInfo.count {
                    if CMTIME_IS_VALID(timingInfo[i].presentationTimeStamp) {
                        timingInfo[i].presentationTimeStamp = CMTimeSubtract(timingInfo[i].presentationTimeStamp, baseVideoPTS)
                    }
                    if CMTIME_IS_VALID(timingInfo[i].decodeTimeStamp) {
                        timingInfo[i].decodeTimeStamp = CMTimeSubtract(timingInfo[i].decodeTimeStamp, baseVideoPTS)
                    }
                }
                var remappedSample: CMSampleBuffer?
                CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: sample, sampleTimingEntryCount: timingCount, sampleTimingArray: &timingInfo, sampleBufferOut: &remappedSample)
                let sampleToAppend = remappedSample ?? sample
                if videoInput.append(sampleToAppend) {
                    videoSamplesAppended += 1
                } else {
                    videoSamplesFailed += 1
                    let ready = videoInput.isReadyForMoreMediaData
                    let msg = "SessionBuffer: videoInput.append returned false (ready=\(ready) status=\(writer.status.rawValue) err=\(writer.error?.localizedDescription ?? "nil"))"
                    NSLog("❌ \(msg)")
                    writeSharedLog("❌ \(msg)")
                }
            } else if videoInput == nil {
                // If no VT session and we don't have a videoInput yet, create one with sourceFormatHint from this compressed sample
                if let fmt = CMSampleBufferGetFormatDescription(sample) {
                    let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: fmt)
                    input.expectsMediaDataInRealTime = true
                    input.transform = CGAffineTransform(rotationAngle: -.pi/2)
                    if writer.canAdd(input) { writer.add(input); videoInput = input }
                }
            }
        case kCMMediaType_Audio:
            if let audioInput = audioInput {
                // Remap audio PTS/DTS to match zero-based timeline
                var timingCount: CMItemCount = 0
                CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: 0, arrayToFill: nil, entriesNeededOut: &timingCount)
                var timingInfo = Array(repeating: CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .invalid, decodeTimeStamp: .invalid), count: timingCount)
                CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: timingCount, arrayToFill: &timingInfo, entriesNeededOut: &timingCount)
                if CMTIME_IS_INVALID(baseVideoPTS), let firstPTS = timingInfo.first?.presentationTimeStamp { baseVideoPTS = firstPTS }
                for i in 0..<timingInfo.count {
                    if CMTIME_IS_VALID(timingInfo[i].presentationTimeStamp) {
                        timingInfo[i].presentationTimeStamp = CMTimeSubtract(timingInfo[i].presentationTimeStamp, baseVideoPTS)
                    }
                    if CMTIME_IS_VALID(timingInfo[i].decodeTimeStamp) {
                        timingInfo[i].decodeTimeStamp = CMTimeSubtract(timingInfo[i].decodeTimeStamp, baseVideoPTS)
                    }
                }
                var remappedSample: CMSampleBuffer?
                CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: sample, sampleTimingEntryCount: timingCount, sampleTimingArray: &timingInfo, sampleBufferOut: &remappedSample)
                let sampleToAppend = remappedSample ?? sample
                if audioInput.append(sampleToAppend) {
                    audioSamplesAppended += 1
                } else {
                    audioSamplesFailed += 1
                    let ready = audioInput.isReadyForMoreMediaData
                    let msg = "SessionBuffer: audioInput.append returned false (ready=\(ready) status=\(writer.status.rawValue) err=\(writer.error?.localizedDescription ?? "nil"))"
                    NSLog("❌ \(msg)")
                    writeSharedLog("❌ \(msg)")
                }
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
        
        // Read target FPS from settings (default 30)
        let defaults = UserDefaults(suiteName: "group.com.cgame.shared")
        let configuredFPS = defaults?.integer(forKey: "targetFrameRate") ?? 30
        let targetFPS = (configuredFPS == 60) ? 60 : 30

        // Decide path based on input: if compressed (H.264/HEVC) or no pixel buffer, use passthrough.
        let subType = CMFormatDescriptionGetMediaSubType(formatDesc)
        let hasPixelBuffer = CMSampleBufferGetImageBuffer(firstSample) != nil
        let isCompressedInput = (subType == kCMVideoCodecType_H264 || subType == kCMVideoCodecType_HEVC) || !hasPixelBuffer
        
        if isCompressedInput {
            // Passthrough compressed input; create input with sourceFormatHint now
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: formatDesc)
            input.expectsMediaDataInRealTime = true
            input.transform = CGAffineTransform(rotationAngle: -.pi/2)
            if writer.canAdd(input) { writer.add(input); videoInput = input }
            compressionSession = nil
        } else {
            // Raw frames path:
            // 1) Create a writer input up-front in passthrough mode (expects compressed samples)
            //    We will feed it compressed H.264 CMSampleBuffers from VTCompressionSession
            let upfrontInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil)
            upfrontInput.expectsMediaDataInRealTime = true
            upfrontInput.transform = CGAffineTransform(rotationAngle: -.pi/2)
            if writer.canAdd(upfrontInput) { writer.add(upfrontInput); videoInput = upfrontInput }

            // 2) Create a VT encoder to compress CVImageBuffer -> H.264 in real time
            var encoderSpec: CFDictionary?
            if #available(iOSApplicationExtension 17.4, *) {
                let spec: [NSString: Any] = [
                    kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true
                ]
                encoderSpec = spec as CFDictionary
            } else {
                encoderSpec = nil
            }
            var session: VTCompressionSession?
            let status = VTCompressionSessionCreate(
                allocator: kCFAllocatorDefault,
                width: Int32(width),
                height: Int32(height),
                codecType: kCMVideoCodecType_H264,
                encoderSpecification: encoderSpec,
                imageBufferAttributes: nil,
                compressedDataAllocator: nil,
                outputCallback: { refcon, _, status, infoFlags, sampleBuffer in
                    guard status == noErr, let sampleBuffer = sampleBuffer, let refcon = refcon else { return }
                    let unmanaged = Unmanaged<SessionBuffer>.fromOpaque(refcon)
                    let strongSelf = unmanaged.takeUnretainedValue()
                    if let input = strongSelf.videoInput {
                        if input.append(sampleBuffer) {
                            strongSelf.videoSamplesAppended += 1
                        } else {
                            strongSelf.videoSamplesFailed += 1
                            let ready = input.isReadyForMoreMediaData
                            let msg = "SessionBuffer: append(compressed) returned false (ready=\(ready) status=\(strongSelf.writer?.status.rawValue ?? -1) err=\(strongSelf.writer?.error?.localizedDescription ?? "nil"))"
                            NSLog("❌ \(msg)")
                            strongSelf.writeSharedLog("❌ \(msg)")
                        }
                    }
                },
                refcon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                compressionSessionOut: &session
            )
            if status != noErr {
                NSLog("❌ SessionBuffer: VTCompressionSessionCreate error=\(status)")
            } else if let session = session {
                compressionSession = session
                VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
                VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_AutoLevel)
                let fpsNum = NSNumber(value: targetFPS)
                VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: fpsNum)
                let bpsNum = NSNumber(value: bitRate)
                VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bpsNum)
                let keyInt = NSNumber(value: targetFPS)
                VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: keyInt)
                VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanTrue)
                VTCompressionSessionPrepareToEncodeFrames(session)
            }
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
        
        // Start writing with zero-based timeline and remember base PTS
        writer.startWriting()
        let firstPTS = firstSample.presentationTimeStamp
        if CMTIME_IS_INVALID(firstPTS) || !firstPTS.isNumeric {
            baseVideoPTS = .zero
        } else {
            baseVideoPTS = firstPTS
        }
        writer.startSession(atSourceTime: .zero)
        
        sessionStartCMTime = .zero
        isRecording = true
        
        NSLog("📹 SessionBuffer: Started session basePTS=\(String(format: "%.3f", firstPTS.seconds))s zero-based timeline")
    }
    
    private func finalizeRecording(completion: @escaping () -> Void) {
        // Finalize even if isRecording flipped; writer may still need finishing
        guard let writer = writer else {
            completion()
            return
        }
        
        // Stop accepting more data
        isRecording = false
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        
        // Flush any pending frames from VTCompressionSession
        if let session = compressionSession {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(session)
            compressionSession = nil
        }
        
        let finishSem = DispatchSemaphore(value: 0)
        writer.finishWriting {
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: self.sessionURL.path)[.size] as? UInt64) ?? 0
            let sizeInMB = Double(fileSize) / (1024 * 1024)
            let status = writer.status.rawValue
            let err = writer.error?.localizedDescription ?? "nil"
            NSLog("📹 SessionBuffer: Recording finalized - Size: \(String(format: "%.1f", sizeInMB))MB status=\(status) error=\(err) vOK=\(self.videoSamplesAppended) vFail=\(self.videoSamplesFailed) aOK=\(self.audioSamplesAppended) aFail=\(self.audioSamplesFailed)")
            // Mirror finalize into App Group error.log
            if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.cgame.shared") {
                let dir = container.appendingPathComponent("Debug", isDirectory: true)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let url = dir.appendingPathComponent("error.log")
                let ts = ISO8601DateFormatter().string(from: Date())
                let line = "[EXT] \(ts) Recording finalized size=\(String(format: "%.1f", sizeInMB))MB status=\(status) error=\(err) file=\(self.sessionURL.lastPathComponent) vOK=\(self.videoSamplesAppended) vFail=\(self.videoSamplesFailed) aOK=\(self.audioSamplesAppended) aFail=\(self.audioSamplesFailed)\n"
                if let data = line.data(using: .utf8) {
                    if FileManager.default.fileExists(atPath: url.path) {
                        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(data); try? h.close() }
                    } else {
                        try? data.write(to: url)
                    }
                }
            }
            // Tear down inputs and writer
            self.videoInput = nil
            self.audioInput = nil
            self.writer = nil
            finishSem.signal()
            completion()
        }
        // Wait up to 5s for finishWriting closure; if it doesn't arrive, log timeout to App Group log
        if finishSem.wait(timeout: .now() + 5.0) == .timedOut {
            if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.cgame.shared") {
                let dir = container.appendingPathComponent("Debug", isDirectory: true)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let url = dir.appendingPathComponent("error.log")
                let ts = ISO8601DateFormatter().string(from: Date())
                let line = "[EXT] \(ts) Recording finalize timeout status=\(writer.status.rawValue) err=\(writer.error?.localizedDescription ?? "nil") file=\(self.sessionURL.lastPathComponent)\n"
                if let data = line.data(using: .utf8) {
                    if FileManager.default.fileExists(atPath: url.path) {
                        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(data); try? h.close() }
                    } else {
                        try? data.write(to: url)
                    }
                }
            }
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
		let defaults = UserDefaults(suiteName: "group.com.cgame.shared")
		let preRollKey = "preRollDuration"
		let postRollKey = "postRollDuration"
		let hasPre = defaults?.object(forKey: preRollKey) != nil
		let hasPost = defaults?.object(forKey: postRollKey) != nil
		let preRoll: Double = hasPre ? (defaults?.double(forKey: preRollKey) ?? 5.0) : 5.0
		let postRoll: Double = hasPost ? (defaults?.double(forKey: postRollKey) ?? 5.0) : 5.0
        
        let killTimeOffset = killEvent.cmTime.seconds - sessionStartCMTime.seconds
        let startTime = killTimeOffset - preRoll
        let endTime = killTimeOffset + postRoll
        
        // Clamp to asset duration
        let durationSeconds = asset.duration.seconds
        let startTimeClamped = max(0, min(startTime, durationSeconds))
        let endTimeClamped = min(durationSeconds, max(startTimeClamped, endTime))
        
        let clipStart = CMTime(seconds: startTimeClamped, preferredTimescale: 600)
        let clipDuration = CMTime(seconds: endTimeClamped - startTimeClamped, preferredTimescale: 600)
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
            
            // Do NOT delete the session file here. The main app trims clips from it and will delete it
            // after successful processing. Leaving it ensures the Clips tab can process even if the
            // extension is terminated right after broadcast ends.
            NSLog("📹 SessionBuffer: Session cleanup finished (session file retained)")
        }
    }
    
    deinit {
        cleanup()
    }
}