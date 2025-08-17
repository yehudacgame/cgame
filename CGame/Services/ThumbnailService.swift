import Foundation
import AVFoundation
import UIKit

final class ThumbnailService {
    static let shared = ThumbnailService()
    private let cache = NSCache<NSString, UIImage>()
    private let queue = DispatchQueue(label: "com.cgame.thumbnail", qos: .userInitiated)
    
    private init() {}
    
    func thumbnail(for url: URL, at seconds: Double = 1.0, size: CGSize = CGSize(width: 640, height: 360), completion: @escaping (UIImage?) -> Void) {
        let key = NSString(string: url.absoluteString)
        if let cached = cache.object(forKey: key) {
            completion(cached)
            return
        }
        
        queue.async {
            let asset = AVAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.maximumSize = size
            generator.appliesPreferredTrackTransform = true
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            do {
                let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
                let image = UIImage(cgImage: cgImage)
                self.cache.setObject(image, forKey: key)
                DispatchQueue.main.async { completion(image) }
            } catch {
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }
}
