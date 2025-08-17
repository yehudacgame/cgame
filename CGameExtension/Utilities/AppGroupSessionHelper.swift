import Foundation

struct AppGroupManager {
	static let shared = AppGroupManager()
	private let appGroupIdentifier = "group.com.cgame.shared"
	
	func saveSessionInfo(sessionURL: URL, killTimestamps: [(Date, Double, String)]) {
		guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
			NSLog("❌ AppGroupManager (Ext): Failed to access App Groups")
			return
		}
		let timestamps = killTimestamps.map { $0.0.timeIntervalSince1970 }
		let cmTimes = killTimestamps.map { $0.1 }
		let eventTypes = killTimestamps.map { $0.2 }
		defaults.set(sessionURL.path, forKey: "pending_session_url")
		defaults.set(timestamps, forKey: "pending_kill_timestamps")
		defaults.set(cmTimes, forKey: "pending_kill_cmtimes")
		defaults.set(eventTypes, forKey: "pending_kill_events")
		defaults.set(Date().timeIntervalSince1970, forKey: "session_updated_at")
		NSLog("📊 AppGroupManager (Ext): Saved session info with \(killTimestamps.count) kills")
	}
}
