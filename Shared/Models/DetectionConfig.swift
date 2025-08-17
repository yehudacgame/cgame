import Foundation
import CoreGraphics

struct DetectionConfig: Codable {
    // OCR Processing Settings
    let frameSkipInterval: Int
    let detectionCooldownSeconds: Double
    let ocrConfidenceThreshold: Float
    
    // Detection Region Settings
    let recognitionRegion: RegionConfig
    
    // Game-Specific Settings
    let gameProfile: GameProfileConfig
    
    // Video Processing Settings
    let bufferDurationSeconds: Double
    let preRollDurationSeconds: Double
    let postRollDurationSeconds: Double
    
    // Debug Settings
    let enableDebugLogging: Bool
    let logDetectedTextInterval: Int // Log detected text every N frames
    
    struct RegionConfig: Codable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
        
        var cgRect: CGRect {
            CGRect(x: x, y: y, width: width, height: height)
        }
    }
    
    struct GameProfileConfig: Codable {
        let name: String
        let targetKeywords: [String]
        let avoidKeywords: [String]
        let caseSensitive: Bool
    }
    
    // Default COD Mobile configuration - Optimized for landscape mode
    static let defaultCODConfig = DetectionConfig(
        frameSkipInterval: 2, // Check every 2nd frame to not miss the brief banner
        detectionCooldownSeconds: 2.5,  // OCR cooldown to prevent detecting same ELIMINATED text (appears 1.5-2s)
        ocrConfidenceThreshold: 0.5,  // Balanced confidence for stylized text
        recognitionRegion: RegionConfig(
            x: 0.60,  // Start at 60% from the left
            y: 0.35,  // Start at 35% from the top
            width: 0.35, // Cover 35% of the screen width
            height: 0.25 // Cover 25% of the screen height
        ),
        gameProfile: GameProfileConfig(
            name: "Call of Duty Mobile",
            targetKeywords: ["ELIMINATED"], // Only ELIMINATED as requested
            avoidKeywords: ["KILLED BY", "ELIMINATED BY", "Kill Highlight", "CGAME", "Duration", "Recorded"], // Filter out app UI elements
            caseSensitive: false
        ),
        bufferDurationSeconds: 60.0,
        preRollDurationSeconds: 5.0,
        postRollDurationSeconds: 3.0,
        enableDebugLogging: true,
        logDetectedTextInterval: 300
    )
    
    // Alternative configurations for testing - Landscape mode optimized
    static let sensitiveCODConfig = DetectionConfig(
        frameSkipInterval: 5,
        detectionCooldownSeconds: 2.0,
        ocrConfidenceThreshold: 0.3,
        recognitionRegion: RegionConfig(
            x: 0.4,   // Wider area for sensitive detection
            y: 0.15,  // Cover more vertical area
            width: 0.55, // Even wider to catch all possible text
            height: 0.4  // Good height coverage
        ),
        gameProfile: GameProfileConfig(
            name: "Call of Duty Mobile (Sensitive)",
            targetKeywords: ["ELIMINATED", "KILL", "ELIMINA", "KNOCKED", "DOWN"],
            avoidKeywords: ["KILLED BY", "ELIMINATED BY", "KNOCKED BY"],
            caseSensitive: false
        ),
        bufferDurationSeconds: 60.0,
        preRollDurationSeconds: 7.0,
        postRollDurationSeconds: 4.0,
        enableDebugLogging: true,
        logDetectedTextInterval: 150
    )
    
    static let conservativeCODConfig = DetectionConfig(
        frameSkipInterval: 15,
        detectionCooldownSeconds: 5.0,
        ocrConfidenceThreshold: 0.7,
        recognitionRegion: RegionConfig(
            x: 0.55,  // Focus on the exact area where ELIMINATED appears
            y: 0.25,  // Center area where kill text shows
            width: 0.4,  // Precise width for the kill notification
            height: 0.25 // Focused height
        ),
        gameProfile: GameProfileConfig(
            name: "Call of Duty Mobile (Conservative)",
            targetKeywords: ["ELIMINATED"],
            avoidKeywords: [],
            caseSensitive: false
        ),
        bufferDurationSeconds: 60.0,
        preRollDurationSeconds: 4.0,
        postRollDurationSeconds: 2.0,
        enableDebugLogging: true,
        logDetectedTextInterval: 450
    )
}