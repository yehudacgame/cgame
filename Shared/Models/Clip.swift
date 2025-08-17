import Foundation

struct Clip: Codable, Identifiable {
    let id: String
    let game: String
    let events: [String]
    let timestamp: Date
    let duration: Double
    let storagePath: String
    var thumbnailURL: String?
    var localURL: URL?
    
    init(
        id: String = UUID().uuidString,
        game: String,
        events: [String],
        timestamp: Date = Date(),
        duration: Double,
        storagePath: String,
        thumbnailURL: String? = nil,
        localURL: URL? = nil
    ) {
        self.id = id
        self.game = game
        self.events = events
        self.timestamp = timestamp
        self.duration = duration
        self.storagePath = storagePath
        self.thumbnailURL = thumbnailURL
        self.localURL = localURL
    }
    
    var eventDescription: String {
        if events.isEmpty {
            return "No events"
        } else if events.count == 1 {
            return displayName(for: events[0])
        } else {
            let eventCounts = Dictionary(grouping: events, by: { $0 })
                .mapValues { $0.count }
            
            return eventCounts.map { event, count in
                let displayEvent = displayName(for: event)
                return count > 1 ? "\(count)x \(displayEvent)" : displayEvent
            }.joined(separator: ", ")
        }
    }
    
    private func displayName(for event: String) -> String {
        // Convert detection event names to user-friendly display names
        switch event.uppercased() {
        case "ELIMINATED":
            return "KILL"
        case "KNOCKED":
            return "KNOCKDOWN"
        case "DOWN":
            return "TAKEDOWN"
        default:
            return event
        }
    }
}