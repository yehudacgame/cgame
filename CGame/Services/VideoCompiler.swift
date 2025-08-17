import Foundation
import AVFoundation
import Photos
import UIKit

class VideoCompiler {
    
    enum CompilationStyle {
        case simple              // Just concatenate clips
        case withTransitions     // Add fade transitions between clips
        case highlight          // Add intro/outro with music
    }
    
    struct CompilationSettings {
        let style: CompilationStyle
        let outputQuality: VideoQuality
        let includeAudio: Bool
        let transitionDuration: Double
        let maxDuration: Double?
        
        enum VideoQuality {
            case sd480p, hd720p, hd1080p
            
            var dimensions: CGSize {
                switch self {
                case .sd480p: return CGSize(width: 854, height: 480)
                case .hd720p: return CGSize(width: 1280, height: 720)
                case .hd1080p: return CGSize(width: 1920, height: 1080)
                }
            }
            
            var bitRate: Int {
                switch self {
                case .sd480p: return 2_500_000
                case .hd720p: return 5_000_000
                case .hd1080p: return 10_000_000
                }
            }
        }
        
        static let `default` = CompilationSettings(
            style: .withTransitions,
            outputQuality: .hd1080p,
            includeAudio: true,
            transitionDuration: 0.5,
            maxDuration: 300 // 5 minutes max
        )
    }
    
    func compileClips(
        _ clips: [Clip],
        settings: CompilationSettings = .default,
        progress: @escaping (Double) -> Void = { _ in }
    ) async throws -> URL {
        
        guard !clips.isEmpty else {
            throw VideoCompilerError.noClipsProvided
        }
        
        // Sort clips by timestamp
        let sortedClips = clips.sorted { $0.timestamp < $1.timestamp }
        
        // Create composition
        let composition = AVMutableComposition()
        let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let audioTrack = settings.includeAudio ? composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) : nil
        
        var currentTime = CMTime.zero
        let transitionTime = CMTime(seconds: settings.transitionDuration, preferredTimescale: 600)
        
        // Process each clip
        for (index, clip) in sortedClips.enumerated() {
            progress(Double(index) / Double(sortedClips.count) * 0.7) // 70% for processing clips
            
            guard let clipURL = getClipURL(for: clip) else {
                print("Warning: Could not find URL for clip \(clip.id)")
                continue
            }
            
            let asset = AVAsset(url: clipURL)
            
            // Get video and audio tracks
            guard let assetVideoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                continue
            }
            
            let assetAudioTrack = try? await asset.loadTracks(withMediaType: .audio).first
            
            // Calculate clip duration
            let clipDuration = try await asset.load(.duration)
            let maxClipDuration = settings.maxDuration.map { CMTime(seconds: $0 / Double(sortedClips.count), preferredTimescale: 600) }
            let finalClipDuration = maxClipDuration != nil ? min(clipDuration, maxClipDuration!) : clipDuration
            
            // Insert video track
            try videoTrack?.insertTimeRange(
                CMTimeRange(start: .zero, duration: finalClipDuration),
                of: assetVideoTrack,
                at: currentTime
            )
            
            // Insert audio track if available
            if let audioTrack = audioTrack, let assetAudioTrack = assetAudioTrack {
                try audioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: finalClipDuration),
                    of: assetAudioTrack,
                    at: currentTime
                )
            }
            
            currentTime = CMTimeAdd(currentTime, finalClipDuration)
            
            // Add transition time (except for last clip)
            if index < sortedClips.count - 1 && settings.style == .withTransitions {
                currentTime = CMTimeSubtract(currentTime, transitionTime)
            }
        }
        
        progress(0.8) // 80% complete - starting export
        
        // Create output URL
        let outputURL = createOutputURL()
        
        // Remove existing file if it exists
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        
        // Export the composition
        try await exportComposition(
            composition,
            to: outputURL,
            settings: settings,
            progress: { exportProgress in
                progress(0.8 + (exportProgress * 0.2)) // Final 20% for export
            }
        )
        
        progress(1.0)
        return outputURL
    }
    
    private func getClipURL(for clip: Clip) -> URL? {
        // Try local URL first
        if let localURL = clip.localURL, FileManager.default.fileExists(atPath: localURL.path) {
            return localURL
        }
        
        // Try app group URL
        if let fileName = URL(string: clip.storagePath)?.lastPathComponent,
           let appGroupURL = AppGroupManager.shared.getClipURL(for: fileName),
           FileManager.default.fileExists(atPath: appGroupURL.path) {
            return appGroupURL
        }
        
        // Try cloud URL (would need to download first)
        if let cloudURL = URL(string: clip.storagePath), cloudURL.scheme == "https" {
            // TODO: Download from cloud if needed
            return nil
        }
        
        return nil
    }
    
    private func exportComposition(
        _ composition: AVMutableComposition,
        to outputURL: URL,
        settings: CompilationSettings,
        progress: @escaping (Double) -> Void
    ) async throws {
        
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw VideoCompilerError.exportSessionCreationFailed
        }
        
        // Configure export session
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        
        // Set video composition for transitions if needed
        if settings.style == .withTransitions {
            let videoComposition = createVideoComposition(for: composition, settings: settings)
            exportSession.videoComposition = videoComposition
        }
        
        // Start export with progress monitoring
        try await withCheckedThrowingContinuation { continuation in
            exportSession.exportAsynchronously {
                switch exportSession.status {
                case .completed:
                    continuation.resume()
                case .failed:
                    continuation.resume(throwing: exportSession.error ?? VideoCompilerError.exportFailed)
                case .cancelled:
                    continuation.resume(throwing: VideoCompilerError.exportCancelled)
                default:
                    break
                }
            }
            
            // Monitor progress on the main thread
            Task { @MainActor in
                while exportSession.status == .exporting {
                    progress(Double(exportSession.progress))
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                }
            }
        }
    }
    
    private func createVideoComposition(
        for composition: AVMutableComposition,
        settings: CompilationSettings
    ) -> AVMutableVideoComposition {
        
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = settings.outputQuality.dimensions
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30) // 30 FPS
        
        // For now, return basic composition without transitions
        // TODO: Implement fade transitions between clips
        
        return videoComposition
    }
    
    private func createOutputURL() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        
        return documentsPath.appendingPathComponent("highlight_compilation_\(timestamp).mp4")
    }
    
    func saveToPhotoLibrary(_ videoURL: URL) async throws {
        if PHPhotoLibrary.authorizationStatus(for: .addOnly) != .authorized {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized else {
                throw VideoCompilerError.photoLibraryAccessDenied
            }
        }
        
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
        }
    }
    
    func generateThumbnail(for videoURL: URL, at time: CMTime = .zero) async throws -> UIImage {
        let asset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        let cgImage = try await imageGenerator.image(at: time).image
        return UIImage(cgImage: cgImage)
    }
}

enum VideoCompilerError: Error, LocalizedError {
    case noClipsProvided
    case exportSessionCreationFailed
    case exportFailed
    case exportCancelled
    case photoLibraryAccessDenied
    
    var errorDescription: String? {
        switch self {
        case .noClipsProvided:
            return "No clips provided for compilation"
        case .exportSessionCreationFailed:
            return "Failed to create export session"
        case .exportFailed:
            return "Video export failed"
        case .exportCancelled:
            return "Video export was cancelled"
        case .photoLibraryAccessDenied:
            return "Photo library access denied"
        }
    }
}