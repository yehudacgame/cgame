import Foundation
import FirebaseStorage
import FirebaseAuth

class StorageService {
    static let shared = StorageService()
    
    // ✅ Firebase Storage is now enabled!
    private let STORAGE_ENABLED = true
    
    // Using the default Firebase Storage bucket
    // You can change this to a custom bucket if needed
    private let CUSTOM_BUCKET_URL: String? = nil // Use default bucket
    
    private var storage: Storage? {
        guard STORAGE_ENABLED else { 
            print("⚠️ StorageService: Cloud storage disabled, using local storage")
            return nil 
        }
        
        if let customBucket = CUSTOM_BUCKET_URL {
            print("☁️ StorageService: Using custom bucket: \(customBucket)")
            return Storage.storage(url: customBucket)
        } else {
            return Storage.storage()
        }
    }
    
    private init() {}
    
    func uploadClip(
        from localURL: URL,
        clipId: String,
        userId: String,
        progress: @escaping (Double) -> Void = { _ in }
    ) async throws -> String {
        
        // Check if Storage is enabled
        guard STORAGE_ENABLED, let storage = storage else {
            // Return local URL as fallback
            progress(1.0)
            print("📁 StorageService: Using local storage for clip \(clipId)")
            return "local://\(userId)/\(clipId).mp4"
        }
        
        let storageRef = storage.reference()
        let clipRef = storageRef.child("clips/\(userId)/\(clipId).mp4")
        
        // Create upload metadata
        let metadata = StorageMetadata()
        metadata.contentType = "video/mp4"
        metadata.customMetadata = [
            "userId": userId,
            "clipId": clipId,
            "uploadedAt": ISO8601DateFormatter().string(from: Date())
        ]
        
        // Perform upload with progress tracking
        return try await withUnsafeThrowingContinuation { continuation in
            let uploadTask = clipRef.putFile(from: localURL, metadata: metadata) { metadata, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    clipRef.downloadURL { url, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else if let url = url {
                            continuation.resume(returning: url.absoluteString)
                        } else {
                            continuation.resume(throwing: StorageError.downloadURLNotFound)
                        }
                    }
                }
            }
            
            // Track upload progress
            uploadTask.observe(.progress) { snapshot in
                guard let progress = snapshot.progress else { return }
                let percentComplete = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
                progress(percentComplete)
            }
        }
    }
    
    func uploadThumbnail(
        from imageData: Data,
        clipId: String,
        userId: String
    ) async throws -> String {
        
        guard STORAGE_ENABLED, let storage = storage else {
            print("📁 StorageService: Using local storage for thumbnail \(clipId)")
            return "local://thumbnails/\(userId)/\(clipId).jpg"
        }
        
        let storageRef = storage.reference()
        let thumbnailRef = storageRef.child("thumbnails/\(userId)/\(clipId).jpg")
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        metadata.customMetadata = [
            "userId": userId,
            "clipId": clipId,
            "uploadedAt": ISO8601DateFormatter().string(from: Date())
        ]
        
        return try await withUnsafeThrowingContinuation { continuation in
            thumbnailRef.putData(imageData, metadata: metadata) { metadata, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    thumbnailRef.downloadURL { url, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else if let url = url {
                            continuation.resume(returning: url.absoluteString)
                        } else {
                            continuation.resume(throwing: StorageError.downloadURLNotFound)
                        }
                    }
                }
            }
        }
    }
    
    func deleteClip(clipId: String, userId: String) async throws {
        guard STORAGE_ENABLED, let storage = storage else {
            print("📁 StorageService: Local storage - no deletion needed")
            return
        }
        
        let storageRef = storage.reference()
        let clipRef = storageRef.child("clips/\(userId)/\(clipId).mp4")
        let thumbnailRef = storageRef.child("thumbnails/\(userId)/\(clipId).jpg")
        
        // Delete both video and thumbnail
        try await clipRef.delete()
        try? await thumbnailRef.delete() // Don't fail if thumbnail doesn't exist
    }
    
    func getDownloadURL(for clipId: String, userId: String) async throws -> URL {
        guard STORAGE_ENABLED, let storage = storage else {
            // Return local file URL from App Groups container
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
        
        let storageRef = storage.reference()
        let clipRef = storageRef.child("clips/\(userId)/\(clipId).mp4")
        
        return try await clipRef.downloadURL()
    }
    
    func getStorageUsage(for userId: String) async throws -> Int64 {
        let storageRef = storage.reference()
        let userClipsRef = storageRef.child("clips/\(userId)")
        
        // Note: Firebase Storage doesn't provide direct folder size calculation
        // This would require listing all files and summing their sizes
        // For now, return 0 - implement based on your needs
        return 0
    }
    
    // MARK: - Batch Operations
    
    func uploadMultipleClips(
        clips: [(localURL: URL, clipId: String)],
        userId: String,
        progressHandler: @escaping (Int, Int) -> Void = { _, _ in }
    ) async throws -> [String] {
        
        var downloadURLs: [String] = []
        
        for (index, clipData) in clips.enumerated() {
            do {
                let downloadURL = try await uploadClip(
                    from: clipData.localURL,
                    clipId: clipData.clipId,
                    userId: userId
                )
                downloadURLs.append(downloadURL)
                progressHandler(index + 1, clips.count)
            } catch {
                print("Failed to upload clip \(clipData.clipId): \(error)")
                throw error
            }
        }
        
        return downloadURLs
    }
}

enum StorageError: Error, LocalizedError {
    case downloadURLNotFound
    case uploadFailed
    case deleteFailed
    
    var errorDescription: String? {
        switch self {
        case .downloadURLNotFound:
            return "Download URL not found"
        case .uploadFailed:
            return "Upload failed"
        case .deleteFailed:
            return "Delete operation failed"
        }
    }
}