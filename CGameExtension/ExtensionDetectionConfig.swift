import Foundation
import CoreGraphics

struct ExtensionDetectionConfig {
    let recognitionRegion: CGRect
    
    // Default COD Mobile configuration - Optimized for landscape mode
    // Widened by ~10% to improve resilience across devices/aspect ratios
    static let defaultCODConfig = ExtensionDetectionConfig(
        recognitionRegion: CGRect(
            x: 0.425,  // recentered left after widening
            y: 0.336,  // recentered top after widening
            width: 0.55,  // +10%
            height: 0.308 // +10%
        )
    )
}
