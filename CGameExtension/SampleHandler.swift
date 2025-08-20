//
//  SampleHandler.swift
//  CGameExtension
//
//  Created by Yehuda Elmaliach on 17/08/2025.
//

import ReplayKit
import Vision
import CoreImage
import Photos
import AVFoundation
import CoreMedia
import UserNotifications
import AudioToolbox

class SampleHandler: RPBroadcastSampleHandler {
    
    private var sessionBuffer: SessionBuffer?
    private var frameCount: Int = 0
    private let ocrFrameInterval = 2 // Process every 2nd frame to reliably catch brief banners
    // Time-based OCR throttle: run at most 3 times per second
    private let ocrMinInterval: TimeInterval = 1.0 / 3.0
    private var lastOCRRunAt: Date = .distantPast
    
    // Debug toggle: when true, run preprocessing filters and save 'after' images
    private let debugPreprocessingEnabled: Bool = false
    
    // Track current frame PTS and last recorded kill time to dedupe events
    private var lastVideoPTS: CMTime = .zero
    private var lastKillPTS: CMTime = .negativeInfinity
    private var lastGameOverPTS: CMTime = .negativeInfinity
    private var lastStartPTS: CMTime = .negativeInfinity
    private let killCooldownSeconds: Double = 2.5
    private let startCooldownSeconds: Double = 30.0
    private let gameOverCooldownSeconds: Double = 10.0
    // Recording control
    private var recordingActive: Bool = false
    private var recordingFinalized: Bool = false
    
    // Orientation handling: ReplayKit provides portrait buffers while COD is landscape.
    // We resolve whether content is landscape-left (.left) or landscape-right (.right),
    // and mirror ROIs accordingly.
    private var imageOrientation: CGImagePropertyOrientation = .left
    private var mirrorHorizontally: Bool = false
    private var orientationResolved: Bool = false
    // Serialize OCR state changes to avoid races
    private let ocrProcessingQueue = DispatchQueue(label: "com.cgameapp.extension.ocrprocessing")
    
    // Create a persistent CIContext for memory and performance efficiency
    private let ciContext = CIContext()
    
    override init() {
        super.init()
        NSLog("✅✅✅ THIS IS THE NEW CODE RUNNING - VERSION 2025.08.17.1230 ✅✅✅")
    }

    // Lightweight file logger to App Group for post-run analysis
    private func logToShared(_ message: String) {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.cgame.shared") else { return }
        let dir = container.appendingPathComponent("Debug", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let url = dir.appendingPathComponent("error.log")
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[EXT] \(ts) \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path) {
                if let h = try? FileHandle(forWritingTo: url) {
                    h.seekToEndOfFile()
                    h.write(data)
                    try? h.close()
                }
            } else {
                try? data.write(to: url)
            }
        }
    }
    
    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        self.sessionBuffer = SessionBuffer()
        logToShared("broadcastStarted() - initializing session buffer")
        
        guard let sessionBuffer = self.sessionBuffer else {
            NSLog("❌ CGame AI Recorder: SessionBuffer could not be initialized.")
            let error = NSError(domain: "CGameExtensionError", code: 101, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize SessionBuffer."])
            finishBroadcastWithError(error)
            return
        }
        // Start continuous recording immediately; detection only marks events
        sessionBuffer.startSession()
        recordingActive = true
        logToShared("recording started")
        NSLog("📱 Setup info: \(setupInfo ?? [:])")
        NSLog("🎮 CGame AI Recorder: broadcastStarted() completed!")
    }
    
    override func broadcastPaused() {
        // User has paused the broadcast. The video recorder will automatically pause.
        NSLog("⏸️ CGame AI Recorder: Broadcast PAUSED!")
    }
    
    override func broadcastResumed() {
        NSLog("▶️ CGame AI Recorder: Broadcast RESUMED!")
        // sessionBuffer?.resume() // Method does not exist, safe to remove
    }
    
    override func broadcastFinished() {
        // User has finished the broadcast.
        NSLog("🏁 CGame AI Recorder: Broadcast FINISHED after \(frameCount) frames")
        logToShared("broadcastFinished() after frames=\(frameCount)")
        // Mark as finished immediately so the main app can start processing even if the extension exits early
        let userDefaults = UserDefaults(suiteName: "group.com.cgame.shared")
        userDefaults?.set(true, forKey: "broadcastFinished")

        let finalizeSemaphore = DispatchSemaphore(value: 0)
        sessionBuffer?.endSession { [weak self] (clipFilenames) in
            guard let self = self else { return }
            
            let message = !clipFilenames.isEmpty ? "Session ended - clips can be processed." : "Session ended - no clips were generated."
            NSLog("📹 CGame AI Recorder: \(message)")
            logToShared("endSession completed, clips=\(clipFilenames.count)")
            finalizeSemaphore.signal()
        }
        // Allow sufficient time for writer to finalize before the extension is torn down
        let waitResult = finalizeSemaphore.wait(timeout: .now() + 6.0)
        if waitResult == .timedOut {
            logToShared("finalize wait timed out; extension may terminate before writer finishes")
        } else {
            logToShared("finalize wait completed")
        }
    }
    
    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        // Process video frames
        if sampleBufferType == .video {
            frameCount += 1
            lastVideoPTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            
            // Time-based OCR throttle: constant 3 Hz
            let now = Date()
            if now.timeIntervalSince(lastOCRRunAt) >= ocrMinInterval {
                lastOCRRunAt = now
                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
                processFrame(pixelBuffer: pixelBuffer, frameNumber: frameCount)
            }
            
            // Forward the sample buffer only when recording is active
            if recordingActive && !recordingFinalized {
                sessionBuffer?.add(sample: sampleBuffer)
            }
            if frameCount % (ocrFrameInterval * 10) == 0 { logToShared("video frame appended fc=\(frameCount)") }
        }
    }
    
    private func processFrame(pixelBuffer: CVPixelBuffer, frameNumber: Int) {
        saveDebugImages(for: pixelBuffer, frameNumber: frameNumber)
        performOCR(on: pixelBuffer, frameNumber: frameNumber)
    }

    private func performOCR(on pixelBuffer: CVPixelBuffer, frameNumber: Int) {
        if !orientationResolved {
            resolveOrientationIfNeeded(pixelBuffer: pixelBuffer, frameNumber: frameNumber)
        }
        let config = ExtensionDetectionConfig.defaultCODConfig
        func baseRegionForOrientation(_ region: CGRect) -> CGRect {
            // If the device/game is in the opposite landscape, mirror X
            if mirrorHorizontally {
                return CGRect(x: 1.0 - region.origin.x - region.size.width,
                              y: region.origin.y,
                              width: region.size.width,
                              height: region.size.height)
            }
            return region
        }
        func visionROI(from region: CGRect) -> CGRect {
            // Convert normalized top-left origin rect to Vision's bottom-left origin
            let r = baseRegionForOrientation(region)
            return CGRect(x: r.origin.x,
                          y: 1.0 - r.origin.y - r.size.height,
                          width: r.size.width,
                          height: r.size.height)
        }
        func clampNormalizedRect(_ rect: CGRect, label: String) -> CGRect {
            var x = max(0.0, min(rect.origin.x, 1.0))
            var y = max(0.0, min(rect.origin.y, 1.0))
            var w = max(0.0, min(rect.size.width, 1.0 - x))
            var h = max(0.0, min(rect.size.height, 1.0 - y))
            let clamped = CGRect(x: x, y: y, width: w, height: h)
            if clamped != rect {
                logToShared("ROI clamped for \(label): from [\(String(format: "%.2f", rect.origin.x)), \(String(format: "%.2f", rect.origin.y)), \(String(format: "%.2f", rect.size.width)), \(String(format: "%.2f", rect.size.height))] to [\(String(format: "%.2f", clamped.origin.x)), \(String(format: "%.2f", clamped.origin.y)), \(String(format: "%.2f", clamped.size.width)), \(String(format: "%.2f", clamped.size.height))]")
            }
            return clamped
        }

        // Kill detection request
        let killRequest = VNRecognizeTextRequest { [weak self] request, error in
            self?.ocrProcessingQueue.async { self?.handleOCRResults(request, error: error, frameNumber: frameNumber) }
        }
        killRequest.regionOfInterest = clampNormalizedRect(visionROI(from: config.killRegion), label: "kill")
        killRequest.recognitionLevel = .accurate
        killRequest.usesLanguageCorrection = false
        killRequest.recognitionLanguages = ["en-US"]
        killRequest.customWords = ["ELIMINATED"]
        killRequest.minimumTextHeight = 0.015

        // START button detection request
        let startRequest = VNRecognizeTextRequest { [weak self] request, error in
            self?.ocrProcessingQueue.async { self?.handleStartDetection(request, error: error, frameNumber: frameNumber) }
        }
        startRequest.regionOfInterest = clampNormalizedRect(visionROI(from: config.startRegion), label: "start")
        startRequest.recognitionLevel = .accurate
        startRequest.usesLanguageCorrection = false
        startRequest.recognitionLanguages = ["en-US"]
        startRequest.customWords = ["START"]
        startRequest.minimumTextHeight = 0.022

        // GAME OVER detection request (full screen)
        let gameOverRequest = VNRecognizeTextRequest { [weak self] request, error in
            self?.ocrProcessingQueue.async { self?.handleGameOverDetection(request, error: error, frameNumber: frameNumber) }
        }
        gameOverRequest.regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1) // Full screen
        gameOverRequest.recognitionLevel = .accurate
        gameOverRequest.usesLanguageCorrection = false
        gameOverRequest.recognitionLanguages = ["en-US"]
        gameOverRequest.customWords = ["GAME", "OVER", "KILLCAM"]
        gameOverRequest.minimumTextHeight = 0.02

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: imageOrientation, options: [:])
        do {
            try handler.perform([killRequest, startRequest, gameOverRequest])
            logToShared("OCR performed on frame=\(frameNumber)")
        } catch {
            NSLog("❌ SampleHandler: OCR failed: \(error.localizedDescription)")
            logToShared("OCR error frame=\(frameNumber) msg=\(error.localizedDescription)")
        }
    }

    // Determine whether content is landscape-left or landscape-right.
    // Try both orientations quickly on the START region and pick the one with more text hits.
    private func resolveOrientationIfNeeded(pixelBuffer: CVPixelBuffer, frameNumber: Int) {
        guard !orientationResolved else { return }
        let config = ExtensionDetectionConfig.defaultCODConfig
        func roiFor(region: CGRect, mirror: Bool) -> CGRect {
            let base = mirror ? CGRect(x: 1.0 - region.origin.x - region.size.width,
                                       y: region.origin.y,
                                       width: region.size.width,
                                       height: region.size.height) : region
            // top-left -> bottom-left
            return CGRect(x: base.origin.x,
                          y: 1.0 - base.origin.y - base.size.height,
                          width: base.size.width,
                          height: base.size.height)
        }
        func score(orientation: CGImagePropertyOrientation, mirror: Bool) -> Int {
            let request = VNRecognizeTextRequest(completionHandler: nil)
            request.regionOfInterest = roiFor(region: config.startRegion, mirror: mirror)
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US"]
            request.minimumTextHeight = 0.02
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
            do {
                try handler.perform([request])
                let results = request.results as? [VNRecognizedTextObservation] ?? []
                return results.count
            } catch {
                return 0
            }
        }
        let leftScore = score(orientation: .left, mirror: false)
        let rightScoreMirrored = score(orientation: .right, mirror: true)
        if rightScoreMirrored > leftScore {
            imageOrientation = .right
            mirrorHorizontally = true
        } else {
            imageOrientation = .left
            mirrorHorizontally = false
        }
        orientationResolved = true
        logToShared("orientation resolved: orientation=\(imageOrientation == .left ? "left" : "right"), mirrorX=\(mirrorHorizontally)")
    }

    private func handleOCRResults(_ request: VNRequest, error: Error?, frameNumber: Int) {
        if let error = error {
            NSLog("❌ SampleHandler: OCR error on frame \(frameNumber): \(error.localizedDescription)")
            return
        }
        
        guard let observations = request.results as? [VNRecognizedTextObservation], !observations.isEmpty else {
            NSLog("ℹ️ SampleHandler: No text found in frame \(frameNumber).")
            return
        }
        
        let recognizedStrings = observations.compactMap { observation in
            observation.topCandidates(1).first?.string
        }
        
        NSLog("✅ SampleHandler: OCR Frame \(frameNumber) found text: \(recognizedStrings.joined(separator: ", "))")

        // Decide if a kill was detected and record it with cooldown to avoid duplicates
        for text in recognizedStrings {
            let upper = text.uppercased()
            if upper.contains("ELIMINATED") {
                let nowPTS = lastVideoPTS
                let delta = nowPTS.seconds - lastKillPTS.seconds
                if delta.isNaN || delta > killCooldownSeconds {
                    sessionBuffer?.addKillEvent(at: Date(), cmTime: nowPTS, eventType: "ELIMINATED")
                    logToShared("KILL detected frame=\(frameNumber) PTS=\(String(format: "%.3f", nowPTS.seconds))s")
                    lastKillPTS = nowPTS
                    NSLog("🚨🚨🚨 KILL DETECTED on frame \(frameNumber)! Text: \(text) at PTS \(String(format: "%.3f", nowPTS.seconds))s 🚨🚨🚨")
                    scheduleKillNotification(body: text)
                    vibrateDevice()
                } else {
                    NSLog("🧊 SampleHandler: Kill suppressed by cooldown (\(String(format: "%.2f", delta))s since last)")
                }
                break // Stop after first relevant match
            }
        }
    }

    private func handleStartDetection(_ request: VNRequest, error: Error?, frameNumber: Int) {
        if let error = error {
            NSLog("❌ SampleHandler: START OCR error on frame \(frameNumber): \(error.localizedDescription)")
            return
        }
        
        guard let observations = request.results as? [VNRecognizedTextObservation], !observations.isEmpty else {
            return
        }

        let recognizedStrings = observations.compactMap { observation in
            observation.topCandidates(1).first?.string
        }

        for text in recognizedStrings {
            let upper = text.uppercased().replacingOccurrences(of: "[^A-Z]", with: "", options: .regularExpression)
            if upper == "START" {
                let nowPTS = lastVideoPTS
                let delta = nowPTS.seconds - lastStartPTS.seconds
                if delta.isNaN || delta > startCooldownSeconds {
                    NSLog("🎬 START DETECTED on frame \(frameNumber)! Text: \(text)")
                    logToShared("START detected frame=\(frameNumber)")
                    playStartSound()
                    lastStartPTS = nowPTS
                    // Keep only audio cue; recording is already active continuously
                } else {
                    logToShared(String(format: "START suppressed by cooldown (%.2fs since last)", delta))
                }
                break
            }
        }
    }

    private func handleGameOverDetection(_ request: VNRequest, error: Error?, frameNumber: Int) {
        if let error = error {
            NSLog("❌ SampleHandler: GAME OVER OCR error on frame \(frameNumber): \(error.localizedDescription)")
            return
        }

        guard let observations = request.results as? [VNRecognizedTextObservation], !observations.isEmpty else {
            return 
        }
        
        let recognizedStrings = observations.compactMap { observation in
            observation.topCandidates(1).first?.string
        }
        
        // Check for GAME OVER or KILLCAM text
        let allText = recognizedStrings.joined(separator: " ").uppercased()
        let hasGameOver = allText.contains("GAME OVER") || allText.replacingOccurrences(of: " ", with: "").contains("GAMEOVER")
        let hasKillcam = allText.contains("KILLCAM")
        
        if hasGameOver || hasKillcam {
            NSLog("🏁 GAME OVER DETECTED on frame \(frameNumber)! Texts: \(recognizedStrings.joined(separator: ", "))")
            logToShared("GAME OVER detected frame=\(frameNumber)")
            // Apply cooldown to avoid consecutive detections/sounds
            let nowPTS = lastVideoPTS
            let delta = nowPTS.seconds - lastGameOverPTS.seconds
            if delta.isNaN || delta > gameOverCooldownSeconds {
                playGameOverSound()
                // Record a synthetic event so the main app trims a clip even if no kills happened
                sessionBuffer?.addKillEvent(at: Date(), cmTime: nowPTS, eventType: "GAME_OVER")
                lastGameOverPTS = nowPTS
                logToShared("GAME OVER event recorded at PTS=\(String(format: "%.3f", nowPTS.seconds))s")
                // Do not finalize automatically; main app will handle trimming/export
            } else {
                logToShared("GAME OVER event suppressed by cooldown (\(String(format: "%.2f", delta))s since last)")
            }
        }
    }

    private func scheduleKillNotification(body: String) {
        let content = UNMutableNotificationContent()
        content.title = "Kill detected"
        content.body = body
        if #available(iOS 12.0, *) {
            // Critical sound (requires Critical Alerts entitlement in the main app to fully take effect)
            content.sound = UNNotificationSound.defaultCriticalSound(withAudioVolume: 1.0)
        } else {
            content.sound = .default
        }
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
            content.relevanceScore = 0.9
        }
        let request = UNNotificationRequest(
            identifier: "kill_\(UUID().uuidString)",
            content: content,
            trigger: nil // deliver immediately
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                NSLog("❌ SampleHandler: Failed to schedule notification: \(error.localizedDescription)")
            } else {
                NSLog("🔔 SampleHandler: Kill notification scheduled")
            }
        }
    }

    private func vibrateDevice() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }

    // MARK: - Audio cues
    private func playStartSound() {
        // Distinct short tone for START
        // 1110 is a common system "Tink" style tone
        AudioServicesPlaySystemSound(1110)
    }

    private func playGameOverSound() {
        // Distinct different tone for GAME OVER
        // 1016 is a common "Tock"/Alert tone
        AudioServicesPlaySystemSound(1016)
    }

    // Optional very light preprocessing used only for debug image
    private func lightPreprocess(_ image: CIImage) -> CIImage {
        var img = image
        if let gray = CIFilter(name: "CIColorControls") {
            gray.setValue(img, forKey: kCIInputImageKey)
            gray.setValue(0.0, forKey: kCIInputSaturationKey)
            gray.setValue(1.08, forKey: kCIInputContrastKey)
            img = gray.outputImage ?? img
        }
        return img
    }
    
    // MARK: - Debug Image Saving (Memory Efficient)
    
    private func saveDebugImages(for pixelBuffer: CVPixelBuffer, frameNumber: Int) {
        NSLog("📸 DEBUG: Preparing to save images for frame \(frameNumber).")
        let sourceImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        let orientedImage = sourceImage.oriented(imageOrientation)
        
        let config = ExtensionDetectionConfig.defaultCODConfig
        let region = config.killRegion
        
        let imageWidth = orientedImage.extent.width
        let imageHeight = orientedImage.extent.height
        
        let cropRect = CGRect(x: imageWidth * region.origin.x,
                              y: imageHeight * (1 - region.origin.y - region.height), // Y is flipped in Core Image
                              width: imageWidth * region.width,
                              height: imageHeight * region.height)
        
        let croppedImage = orientedImage.cropped(to: cropRect)
        
        // Save the 'before' image (oriented and cropped)
        saveImage(croppedImage, withName: "debug_frame_\(frameNumber)_before.png")
        
        // Save an optional light-processed variant for reference (no inversion)
        if debugPreprocessingEnabled {
            let lightVariant = lightPreprocess(croppedImage)
            saveImage(lightVariant, withName: "debug_frame_\(frameNumber)_after_light.png")
        }
    }

    private func preprocessImage(_ image: CIImage) -> CIImage {
        // Legacy path: use light preprocessing only
        return lightPreprocess(image)
    }
    
    private func saveImage(_ image: CIImage, withName fileName: String) {
        guard let debugDir = getDebugDirectory() else {
            NSLog("❌ SampleHandler: Cannot save image, debug directory URL is nil.")
            return
        }
        
        let fileURL = debugDir.appendingPathComponent(fileName)
        
        NSLog("➡️ SampleHandler: Attempting to write PNG to \(fileURL.path)")
        
        do {
            try ciContext.writePNGRepresentation(of: image,
                                                 to: fileURL,
                                                 format: .RGBA8,
                                                 colorSpace: image.colorSpace ?? CGColorSpaceCreateDeviceRGB())
            NSLog("✅ SampleHandler: SUCCESS - Image write completed for \(fileName).")
        } catch {
            NSLog("❌ SampleHandler: FAILED to write image \(fileName). Error: \(error.localizedDescription)")
        }
    }
    
    private func getDebugDirectory() -> URL? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.cgame.shared") else {
            NSLog("❌ SampleHandler: Could not get App Group container URL.")
            return nil
        }
        let debugDir = containerURL.appendingPathComponent("Debug", isDirectory: true)
        
        // This check is important because the directory might be deleted or permissions change.
        if !FileManager.default.fileExists(atPath: debugDir.path) {
            do {
                try FileManager.default.createDirectory(at: debugDir, withIntermediateDirectories: true, attributes: nil)
                NSLog("✅ SampleHandler: Created debug directory at \(debugDir.path)")
            } catch {
                NSLog("❌ SampleHandler: Could not create debug directory: \(error.localizedDescription)")
                return nil
            }
        }
        return debugDir
    }
}

// MARK: - Date Extension for file naming
extension Date {
    var fileNameFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: self)
    }
}