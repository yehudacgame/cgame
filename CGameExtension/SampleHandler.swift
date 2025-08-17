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
    private let ocrFrameInterval = 10 // Process every 10th frame
    
    // Debug toggle: when true, run preprocessing filters and save 'after' images
    private let debugPreprocessingEnabled: Bool = false
    
    // Track current frame PTS and last recorded kill time to dedupe events
    private var lastVideoPTS: CMTime = .zero
    private var lastKillPTS: CMTime = .negativeInfinity
    private let killCooldownSeconds: Double = 2.5
    
    // Hardcoded orientation for Call of Duty Mobile (landscape)
    private let codOrientation: CGImagePropertyOrientation = .left
    
    // Create a persistent CIContext for memory and performance efficiency
    private let ciContext = CIContext()
    
    override init() {
        super.init()
        NSLog("✅✅✅ THIS IS THE NEW CODE RUNNING - VERSION 2025.08.17.1230 ✅✅✅")
    }

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        self.sessionBuffer = SessionBuffer()
        
        guard let sessionBuffer = self.sessionBuffer else {
            NSLog("❌ CGame AI Recorder: SessionBuffer could not be initialized.")
            let error = NSError(domain: "CGameExtensionError", code: 101, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize SessionBuffer."])
            finishBroadcastWithError(error)
            return
        }
        
        sessionBuffer.startSession()
        NSLog("🎮 CGame AI Recorder: Session-based recording STARTED!")
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
        
        sessionBuffer?.endSession { [weak self] (clipFilenames) in
            guard let self = self else { return }
            
            let message = !clipFilenames.isEmpty ? "Session ended - clips can be processed." : "Session ended - no clips were generated."
            NSLog("📹 CGame AI Recorder: \(message)")

            // Inform the main app that the broadcast has finished
            let userDefaults = UserDefaults(suiteName: "group.com.cgame.shared")
            userDefaults?.set(true, forKey: "broadcastFinished")
        }
    }
    
    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        // Process video frames
        if sampleBufferType == .video {
            frameCount += 1
            lastVideoPTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            
            // Only run OCR on designated frames to save resources
            if frameCount % ocrFrameInterval == 0 {
                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                    return
                }
                
                // Save debug images AND perform OCR
                processFrame(pixelBuffer: pixelBuffer, frameNumber: frameCount)
            }
            
            // Forward the sample buffer to the video recorder
            sessionBuffer?.add(sample: sampleBuffer)
        }
    }
    
    private func processFrame(pixelBuffer: CVPixelBuffer, frameNumber: Int) {
        saveDebugImages(for: pixelBuffer, frameNumber: frameNumber)
        performOCR(on: pixelBuffer, frameNumber: frameNumber)
    }

    private func performOCR(on pixelBuffer: CVPixelBuffer, frameNumber: Int) {
        let rawImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(codOrientation)

        let request = VNRecognizeTextRequest { [weak self] request, error in
            self?.handleOCRResults(request, error: error, frameNumber: frameNumber)
        }

        let roiTopLeft = ExtensionDetectionConfig.defaultCODConfig.recognitionRegion
        let roiVision = CGRect(x: roiTopLeft.origin.x,
                                  y: 1.0 - roiTopLeft.origin.y - roiTopLeft.size.height,
                                  width: roiTopLeft.size.width,
                                  height: roiTopLeft.size.height)
        request.regionOfInterest = roiVision
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        request.customWords = ["ELIMINATED", "KILLED", "KILL", "KILLS"]
        request.minimumTextHeight = 0.01

        let handler = VNImageRequestHandler(ciImage: rawImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            NSLog("❌ SampleHandler: OCR failed: \(error.localizedDescription)")
        }
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
            if upper.contains("ELIMINATED") || upper.contains("KILLED") {
                let nowPTS = lastVideoPTS
                let delta = nowPTS.seconds - lastKillPTS.seconds
                if delta.isNaN || delta > killCooldownSeconds {
                    sessionBuffer?.addKillEvent(at: Date(), cmTime: nowPTS, eventType: upper.contains("ELIMINATED") ? "ELIMINATED" : "KILLED")
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
        
        let orientedImage = sourceImage.oriented(codOrientation)
        
        let config = ExtensionDetectionConfig.defaultCODConfig
        let region = config.recognitionRegion
        
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