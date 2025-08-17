import Foundation

struct ClipMetadata: Codable {
    let id: String
    let game: String
    let events: [EventInfo]
    let startTime: Date
    let endTime: Date
    var localFilePath: String
    var untrimmedParts: [String] // Array of untrimmed part filenames for smart copy strategy
    var isProcessed: Bool
    
    struct EventInfo: Codable {
        let type: String
        let timestamp: Date
    }
    
    init(
        id: String = UUID().uuidString,
        game: String,
        events: [EventInfo],
        startTime: Date,
        endTime: Date,
        localFilePath: String,
        untrimmedParts: [String] = [],
        isProcessed: Bool = false
    ) {
        self.id = id
        self.game = game
        self.events = events
        self.startTime = startTime
        self.endTime = endTime
        self.localFilePath = localFilePath
        self.untrimmedParts = untrimmedParts
        self.isProcessed = isProcessed
    }
    
    var duration: Double {
        endTime.timeIntervalSince(startTime)
    }
}