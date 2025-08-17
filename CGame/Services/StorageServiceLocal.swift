import Foundation
import FirebaseAuth

// Temporary local-only storage service while Firebase Storage setup is pending
class StorageServiceLocal {
    static let shared = StorageServiceLocal()
    
    // Feature flag - set to true when Firebase Storage is ready
    static let CLOUD_STORAGE_ENABLED = false
    
    private init() {}
    
    func uploadClip(
        from localURL: URL,
        clipId: String,
        userId: String,
        progress: @escaping (Double) -> Void = { _ in }
    ) async throws -> String {
        // For local mode, just return a local reference
        // The clip stays in the App Groups container
        progress(1.0)
        
        // Return local URL as string for Firestore reference
        return "local://\(userId)/\(clipId).mp4"
    }
    
    func uploadThumbnail(
        from imageData: Data,
        clipId: String,
        userId: String
    ) async throws -> String {
        // Save thumbnail locally if needed
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.cgame.shared") else {
            throw StorageError.downloadURLNotFound
        }
        
        let thumbnailsDir = containerURL.appendingPathComponent("Thumbnails")
        try? FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)
        
        let thumbnailURL = thumbnailsDir.appendingPathComponent("\(clipId).jpg")
        try imageData.write(to: thumbnailURL)
        
        return "local://thumbnails/\(clipId).jpg"
    }
    
    func deleteClip(clipId: String, userId: String) async throws {
        // For local mode, delete from App Groups container
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.cgame.shared") else {
            throw StorageError.deleteFailed
        }
        
        let clipsDir = containerURL.appendingPathComponent("Clips")
        let clipFiles = try FileManager.default.contentsOfDirectory(at: clipsDir, includingPropertiesForKeys: nil)
        
        for file in clipFiles where file.lastPathComponent.contains(clipId) {
            try FileManager.default.removeItem(at: file)
        }
    }
    
    func getDownloadURL(for clipId: String, userId: String) async throws -> URL {
        // Return local file URL
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.cgame.shared") else {
            throw StorageError.downloadURLNotFound
        }
        
        let clipsDir = containerURL.appendingPathComponent("Clips")
        let clipFiles = try FileManager.default.contentsOfDirectory(at: clipsDir, includingPropertiesForKeys: nil)
        
        if let clipFile = clipFiles.first(where: { $0.lastPathComponent.contains(clipId) }) {
            return clipFile
        }
        
        throw StorageError.downloadURLNotFound
    }
}

// Extension to make it compatible with existing code
extension StorageServiceLocal {
    func uploadMultipleClips(
        clips: [(localURL: URL, clipId: String)],
        userId: String,
        progressHandler: @escaping (Int, Int) -> Void = { _, _ in }
    ) async throws -> [String] {
        
        var downloadURLs: [String] = []
        
        for (index, clipData) in clips.enumerated() {
            let downloadURL = try await uploadClip(
                from: clipData.localURL,
                clipId: clipData.clipId,
                userId: userId
            )
            downloadURLs.append(downloadURL)
            progressHandler(index + 1, clips.count)
        }
        
        return downloadURLs
    }
}