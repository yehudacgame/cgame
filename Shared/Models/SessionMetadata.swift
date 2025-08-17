import Foundation
import CoreMedia

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