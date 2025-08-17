import Foundation
import AVFoundation

struct UserSettings: Codable {
    var gameProfileName: String
    var videoQuality: VideoQuality
    var preRollDuration: Double
    var postRollDuration: Double
    
    enum VideoQuality: String, Codable, CaseIterable {
        case hd720p = "720p"
        case hd1080p = "1080p"
        case hd4K = "4K"
        
        var displayName: String {
            switch self {
            case .hd720p: return "720p HD"
            case .hd1080p: return "1080p Full HD"
            case .hd4K: return "4K Ultra HD"
            }
        }
    }
    
    init(
        gameProfileName: String = "Fortnite",
        videoQuality: VideoQuality = .hd1080p,
        preRollDuration: Double = 5.0,
        postRollDuration: Double = 3.0
    ) {
        self.gameProfileName = gameProfileName
        self.videoQuality = videoQuality
        self.preRollDuration = preRollDuration
        self.postRollDuration = postRollDuration
    }
    
    var videoOutputSettings: [String: Any] {
        let bitRate: Int
        let width: Int
        let height: Int
        
        switch videoQuality {
        case .hd720p:
            bitRate = 5_000_000
            width = 1280
            height = 720
        case .hd1080p:
            bitRate = 10_000_000
            width = 1920
            height = 1080
        case .hd4K:
            bitRate = 35_000_000
            width = 3840
            height = 2160
        }
        
        return [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
    }
}