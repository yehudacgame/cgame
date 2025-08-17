import Foundation
import CoreImage
import UIKit
import Photos

class AppGroupManager {
    static let shared = AppGroupManager()
    
    private let appGroupIdentifier = "group.com.cgame.shared"
    private let metadataFileName = "pending_clips.json"
    
    var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }
    
    private var metadataFileURL: URL? {
        containerURL?.appendingPathComponent(metadataFileName)
    }
    
    
    private var clipsDirectory: URL? {
        containerURL?.appendingPathComponent("Clips", isDirectory: true)
    }
    
    private var debugDirectory: URL? {
        containerURL?.appendingPathComponent("Debug", isDirectory: true)
    }
    
    // A persistent CIContext is more efficient than creating a new one each time.
    private let ciContext = CIContext()

    private init() {
        createClipsDirectoryIfNeeded()
        createDebugDirectoryIfNeeded()
        // Clear old metadata files that use ISO8601 encoding to fix timezone issues
        clearLegacyMetadataFiles()
    }
    
    private func createClipsDirectoryIfNeeded() {
        guard let clipsDir = clipsDirectory else { return }
        
        if !FileManager.default.fileExists(atPath: clipsDir.path) {
            try? FileManager.default.createDirectory(
                at: clipsDir,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }
    
    private func createDebugDirectoryIfNeeded() {
        guard let debugDir = debugDirectory else {
            NSLog("❌ AppGroupManager: Could not construct debug directory URL.")
            return
        }
        
        NSLog("➡️ AppGroupManager: Debug directory path is: \(debugDir.path)")
        
        if !FileManager.default.fileExists(atPath: debugDir.path) {
            NSLog("⚠️ AppGroupManager: Debug directory does not exist. Attempting to create it...")
            do {
                try FileManager.default.createDirectory(at: debugDir, withIntermediateDirectories: true, attributes: nil)
                NSLog("✅ AppGroupManager: Successfully created debug directory.")
            } catch {
                NSLog("❌ AppGroupManager: FAILED to create debug directory: \(error.localizedDescription)")
            }
        }
    }
    
    func saveDebugImage(_ image: CIImage, withName name: String) {
        guard let debugDir = debugDirectory else {
            NSLog("❌ AppGroupManager: Cannot save image, debug directory URL is nil.")
            return
        }
        
        let fileURL = debugDir.appendingPathComponent(name)
        
        do {
            NSLog("➡️ AppGroupManager: Attempting to write PNG to \(fileURL.path)")
            let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
            try ciContext.writePNGRepresentation(of: image, to: fileURL, format: .RGBA8, colorSpace: colorSpace)
            NSLog("✅ AppGroupManager: SUCCESS - Image write completed for \(name).")
        } catch {
            NSLog("❌ AppGroupManager: FAILED to write PNG data for \(name): \(error.localizedDescription)")
        }
    }
    
    func calculatePixelRect(for normalizedRect: CGRect, in imageExtent: CGRect) -> CGRect {
        let imageWidth = imageExtent.width
        let imageHeight = imageExtent.height
        
        let x = normalizedRect.origin.x * imageWidth
        let y = (1 - normalizedRect.origin.y - normalizedRect.size.height) * imageHeight // Correct for Core Image's coordinate system
        let width = normalizedRect.size.width * imageWidth
        let height = normalizedRect.size.height * imageHeight
        
        return CGRect(x: x, y: y, width: width, height: height)
    }
    
    func copyDebugImagesToPhotoLibrary(completion: @escaping (Int) -> Void) {
        guard let debugDir = debugDirectory else {
            NSLog("❌ AppGroupManager: Could not construct debug directory URL for copying.")
            completion(0)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let fileURLs = try FileManager.default.contentsOfDirectory(at: debugDir, includingPropertiesForKeys: nil)
                let imageFiles = fileURLs.filter { $0.pathExtension.lowercased() == "png" }
                
                guard !imageFiles.isEmpty else {
                    NSLog("ℹ️ AppGroupManager: No debug images found to copy.")
                    DispatchQueue.main.async { completion(0) }
                    return
                }

                PHPhotoLibrary.requestAuthorization { status in
                    guard status == .authorized else {
                        NSLog("❌ AppGroup-Manager: Photo Library access denied.")
                        DispatchQueue.main.async { completion(0) }
                        return
                    }

                    let group = DispatchGroup()
                    var successCount = 0

                    for fileURL in imageFiles {
                        group.enter()
                        PHPhotoLibrary.shared().performChanges({
                            PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
                        }, completionHandler: { success, error in
                            if success {
                                successCount += 1
                                NSLog("✅ AppGroupManager: Copied \(fileURL.lastPathComponent) to Photo Library.")
                            } else if let error = error {
                                NSLog("❌ AppGroupManager: FAILED to copy \(fileURL.lastPathComponent) to Photo Library: \(error.localizedDescription)")
                            }
                            group.leave()
                        })
                    }

                    group.notify(queue: .main) {
                        completion(successCount)
                    }
                }
            } catch {
                NSLog("❌ AppGroupManager: FAILED to read contents of debug directory: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(0) }
            }
        }
    }

    func saveClipMetadata(_ metadata: ClipMetadata) {
        var allMetadata = loadPendingClipMetadata()
        allMetadata.append(metadata)
        
        guard let url = metadataFileURL else { return }
        
        do {
            let encoder = JSONEncoder()
            // Use milliseconds since 1970 to preserve exact timestamp including timezone
            encoder.dateEncodingStrategy = .millisecondsSince1970
            let data = try encoder.encode(allMetadata)
            try data.write(to: url)
        } catch {
            print("Failed to save clip metadata: \(error)")
        }
    }
    
    func loadPendingClipMetadata() -> [ClipMetadata] {
        guard let url = metadataFileURL,
              FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            // Use milliseconds since 1970 to preserve exact timestamp including timezone
            decoder.dateDecodingStrategy = .millisecondsSince1970
            return try decoder.decode([ClipMetadata].self, from: data)
        } catch {
            print("Failed to load clip metadata: \(error)")
            return []
        }
    }
    
    func moveClipToPermanentLocation(from localURL: URL) -> URL? {
        guard let clipsDir = clipsDirectory else { return nil }
        
        let fileName = localURL.lastPathComponent
        let destinationURL = clipsDir.appendingPathComponent(fileName)
        
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: localURL, to: destinationURL)
            return destinationURL
        } catch {
            print("Failed to move clip: \(error)")
            return nil
        }
    }
    
    func clearPendingMetadata() {
        guard let url = metadataFileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
    
    func markMetadataAsProcessed(clipId: String) {
        var allMetadata = loadPendingClipMetadata()
        
        if let index = allMetadata.firstIndex(where: { $0.id == clipId }) {
            allMetadata[index].isProcessed = true
        }
        
        guard let url = metadataFileURL else { return }
        
        do {
            let encoder = JSONEncoder()
            // Use milliseconds since 1970 to preserve exact timestamp including timezone
            encoder.dateEncodingStrategy = .millisecondsSince1970
            let data = try encoder.encode(allMetadata)
            try data.write(to: url)
        } catch {
            print("Failed to update metadata: \(error)")
        }
    }
    
    func getClipURL(for filename: String) -> URL? {
        clipsDirectory?.appendingPathComponent(filename)
    }
    
    private func clearLegacyMetadataFiles() {
        guard let url = metadataFileURL,
              FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        
        do {
            // Try to detect if this is a legacy file by attempting to decode with new format
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            
            // If this fails, it's likely an old ISO8601 file - remove it
            let _ = try decoder.decode([ClipMetadata].self, from: data)
            NSLog("📅 Metadata file is compatible with new format")
            
        } catch {
            // This is likely an old ISO8601 format file - remove it
            NSLog("⚠️ Detected legacy metadata file with ISO8601 timestamps - clearing to fix timezone issues")
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    func getClipsDirectory() -> URL? {
        return clipsDirectory
    }
    
    func getAllClipFiles() -> [URL] {
        guard let clipsDir = clipsDirectory else { 
            NSLog("📁 AppGroupManager: No clips directory available")
            return [] 
        }
        
        NSLog("📁 AppGroupManager: Looking for clips in: \(clipsDir.path)")
        
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: clipsDir,
                includingPropertiesForKeys: [.creationDateKey],
                options: .skipsHiddenFiles
            )
            let clipFiles = files.filter { $0.pathExtension == "mp4" || $0.pathExtension == "mov" }
            NSLog("📁 AppGroupManager: Found \(files.count) total files, \(clipFiles.count) clip files")
            for file in clipFiles {
                NSLog("📁 AppGroupManager: Found clip: \(file.lastPathComponent)")
            }
            return clipFiles
        } catch {
            print("Failed to get clip files: \(error)")
            return []
        }
    }
    
    // MARK: - Session Communication (Simple UserDefaults approach)
    
    func saveSessionInfo(sessionURL: URL, killTimestamps: [(Date, Double, String)]) {
        guard let appGroupDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            NSLog("❌ AppGroupManager: Failed to access App Groups for session info")
            return
        }
        
        // Convert kill data to simple arrays for UserDefaults
        let timestamps = killTimestamps.map { $0.0.timeIntervalSince1970 }
        let cmTimes = killTimestamps.map { $0.1 }
        let eventTypes = killTimestamps.map { $0.2 }
        
        appGroupDefaults.set(sessionURL.path, forKey: "pending_session_url")
        appGroupDefaults.set(timestamps, forKey: "pending_kill_timestamps")
        appGroupDefaults.set(cmTimes, forKey: "pending_kill_cmtimes")
        appGroupDefaults.set(eventTypes, forKey: "pending_kill_events")
        appGroupDefaults.set(Date().timeIntervalSince1970, forKey: "session_updated_at")
        
        NSLog("📊 AppGroupManager: Saved session info with \(killTimestamps.count) kills")
    }
    
    func loadPendingSessionInfo() -> (sessionURL: URL, killEvents: [(Date, Double, String)])? {
        guard let appGroupDefaults = UserDefaults(suiteName: appGroupIdentifier),
              let sessionPath = appGroupDefaults.string(forKey: "pending_session_url"),
              let timestamps = appGroupDefaults.array(forKey: "pending_kill_timestamps") as? [Double],
              let cmTimes = appGroupDefaults.array(forKey: "pending_kill_cmtimes") as? [Double],
              let eventTypes = appGroupDefaults.array(forKey: "pending_kill_events") as? [String],
              timestamps.count == cmTimes.count && cmTimes.count == eventTypes.count else {
            return nil
        }
        
        let sessionURL = URL(fileURLWithPath: sessionPath)
        let killEvents = zip(zip(timestamps, cmTimes), eventTypes).map { (timestampCmTime, eventType) in
            (Date(timeIntervalSince1970: timestampCmTime.0), timestampCmTime.1, eventType)
        }
        
        return (sessionURL, killEvents)
    }
    
    func clearPendingSessionInfo() {
        guard let appGroupDefaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
        
        appGroupDefaults.removeObject(forKey: "pending_session_url")
        appGroupDefaults.removeObject(forKey: "pending_kill_timestamps")
        appGroupDefaults.removeObject(forKey: "pending_kill_cmtimes")
        appGroupDefaults.removeObject(forKey: "pending_kill_events")
        appGroupDefaults.removeObject(forKey: "session_updated_at")
        
        NSLog("📊 AppGroupManager: Cleared pending session info")
    }
}