import Foundation
import CoreGraphics

struct ExtensionDetectionConfig {
    let killRegion: CGRect
    let startRegion: CGRect
    let gameOverRegion: CGRect
    
    // Default COD Mobile configuration - Optimized for landscape mode
    static let defaultCODConfig = ExtensionDetectionConfig(
        // Kill feed area - same as working recognitionRegion
        killRegion: CGRect(
            x: 0.425,  // recentered left after widening
            y: 0.336,  // recentered top after widening
            width: 0.55,  // +10%
            height: 0.308 // +10%
        ),
        // START button region - bottom right
        // Ensure region stays within [0,1] after Vision's bottom-left conversion
        startRegion: CGRect(
            x: 0.76,
            y: 0.80,
            width: 0.20,
            height: 0.18
        ),
        // GAME OVER region - full screen to catch it anywhere
        gameOverRegion: CGRect(
            x: 0.0,
            y: 0.0,
            width: 1.0,
            height: 1.0
        )
    )
}
