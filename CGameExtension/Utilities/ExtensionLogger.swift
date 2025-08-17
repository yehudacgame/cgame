import Foundation

/// Lightweight logger for the broadcast extension to minimize memory overhead
/// Only logs critical events to prevent extension crashes from excessive logging
final class ExtensionLogger {
    
    // MARK: - Debug Flags
    // Set these to false in production to reduce logging overhead
    #if DEBUG
    static let enableVerboseLogging = false  // Frame-by-frame logs
    static let enableBufferLogging = true    // Buffer cycling events
    static let enableDetectionLogging = true // Kill detection events
    static let enableExportLogging = true    // Export and file operations
    static let enableErrorLogging = true     // Always log errors
    #else
    static let enableVerboseLogging = false
    static let enableBufferLogging = false
    static let enableDetectionLogging = true // Keep detection in production
    static let enableExportLogging = false
    static let enableErrorLogging = true
    #endif
    
    // MARK: - Log Throttling
    private static var lastLogTimes: [String: Date] = [:]
    private static let throttleInterval: TimeInterval = 1.0 // Minimum seconds between similar logs
    
    // MARK: - Logging Methods
    
    /// Log verbose frame-by-frame events (disabled by default)
    static func verbose(_ message: String) {
        guard enableVerboseLogging else { return }
        NSLog("[VERBOSE] \(message)")
    }
    
    /// Log buffer-related events
    static func buffer(_ message: String) {
        guard enableBufferLogging else { return }
        NSLog("📊 \(message)")
    }
    
    /// Log detection events (kills, etc.)
    static func detection(_ message: String) {
        guard enableDetectionLogging else { return }
        NSLog("🎯 \(message)")
    }
    
    /// Log export and file operations
    static func export(_ message: String) {
        guard enableExportLogging else { return }
        NSLog("📁 \(message)")
    }
    
    /// Always log errors
    static func error(_ message: String) {
        guard enableErrorLogging else { return }
        NSLog("❌ \(message)")
    }
    
    /// Log with throttling - prevents the same message from logging too frequently
    static func throttled(_ key: String, message: String, minInterval: TimeInterval = 1.0) {
        let now = Date()
        
        if let lastTime = lastLogTimes[key] {
            guard now.timeIntervalSince(lastTime) >= minInterval else { return }
        }
        
        lastLogTimes[key] = now
        NSLog(message)
    }
    
    /// Log only every Nth occurrence
    private static var logCounters: [String: Int] = [:]
    static func everyN(_ key: String, n: Int, message: String) {
        let count = (logCounters[key] ?? 0) + 1
        logCounters[key] = count
        
        if count % n == 0 {
            NSLog("\(message) [occurrence #\(count)]")
        }
    }
}