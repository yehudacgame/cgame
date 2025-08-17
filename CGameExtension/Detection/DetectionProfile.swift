import Foundation
import Vision
import CoreGraphics

protocol DetectionProfile {
    var name: String { get }
    var recognitionRegion: CGRect { get }
    func didDetectEvent(from observations: [VNRecognizedTextObservation]) -> String?
}

struct FortniteProfile: DetectionProfile {
    let name = "Fortnite"
    let recognitionRegion = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.3)
    
    func didDetectEvent(from observations: [VNRecognizedTextObservation]) -> String? {
        let killKeywords = ["eliminated", "knocked", "elimination"]
        
        for observation in observations {
            guard let topCandidate = observation.topCandidates(1).first else { continue }
            
            let text = topCandidate.string.lowercased()
            
            if let keyword = killKeywords.first(where: { text.contains($0) }) {
                print("Fortnite kill detected: \(text)")
                return keyword
            }
        }
        
        return nil
    }
}

struct CallOfDutyProfile: DetectionProfile {
    let name: String
    let recognitionRegion: CGRect
    private let config: DetectionConfig
    
    init() {
        self.config = ConfigManager.shared.getCurrentConfig()
        self.name = config.gameProfile.name
        self.recognitionRegion = config.recognitionRegion.cgRect
    }
    
    func didDetectEvent(from observations: [VNRecognizedTextObservation]) -> String? {
        for observation in observations {
            guard let topCandidate = observation.topCandidates(1).first else { continue }
            
            // Check confidence threshold
            guard topCandidate.confidence >= config.ocrConfidenceThreshold else { 
                // Log if ELIMINATED was found but confidence too low
                if topCandidate.string.uppercased().contains("ELIMIN") {
                    NSLog("⚠️ CGAME: Found 'ELIMIN' text but confidence too low: '\(topCandidate.string)' at \(String(format: "%.1f%%", topCandidate.confidence * 100)) (minimum: \(String(format: "%.0f%%", config.ocrConfidenceThreshold * 100)))")
                }
                continue 
            }
            
            let originalText = topCandidate.string.trimmingCharacters(in: .whitespaces)
            let textToCheck = config.gameProfile.caseSensitive ? originalText : originalText.uppercased()
            
            // Check avoid keywords first
            let shouldAvoid = config.gameProfile.avoidKeywords.contains { avoidKeyword in
                let keywordToCheck = config.gameProfile.caseSensitive ? avoidKeyword : avoidKeyword.uppercased()
                return textToCheck.contains(keywordToCheck)
            }
            
            if shouldAvoid {
                continue
            }
            
            // Check target keywords
            for keyword in config.gameProfile.targetKeywords {
                let keywordToCheck = config.gameProfile.caseSensitive ? keyword : keyword.uppercased()
                
                // Debug logging specifically for ELIMINATED detection attempts
                if originalText.uppercased().contains("ELIMIN") {
                    NSLog("🔍 CGAME DETECTION DEBUG: Found ELIMIN text: '\(originalText)' checking against '\(keywordToCheck)'")
                    NSLog("🔍 CGAME DETECTION DEBUG: textToCheck='\(textToCheck)' contains '\(keywordToCheck)'? \(textToCheck.contains(keywordToCheck))")
                }
                
                if textToCheck.contains(keywordToCheck) {
                    NSLog("🎯 COD KILL DETECTED: '\(keyword)' found in '\(originalText)'")
                    NSLog("📍 Detection confidence: \(String(format: "%.1f%%", topCandidate.confidence * 100))")
                    return keyword
                }
            }
        }
        
        return nil
    }
}

struct ValorantProfile: DetectionProfile {
    let name = "Valorant"
    let recognitionRegion = CGRect(x: 0.0, y: 0.8, width: 1.0, height: 0.2)
    
    func didDetectEvent(from observations: [VNRecognizedTextObservation]) -> String? {
        let killKeywords = ["killed", "eliminated", "headshot", "ace"]
        
        for observation in observations {
            guard let topCandidate = observation.topCandidates(1).first else { continue }
            
            let text = topCandidate.string.lowercased()
            
            if let keyword = killKeywords.first(where: { text.contains($0) }) {
                print("Valorant kill detected: \(text)")
                return keyword
            }
        }
        
        return nil
    }
}

enum GameProfile: String, CaseIterable {
    case fortnite = "Fortnite"
    case callOfDuty = "CallOfDuty"
    case valorant = "Valorant"
    
    var profile: DetectionProfile {
        switch self {
        case .fortnite:
            return FortniteProfile()
        case .callOfDuty:
            return CallOfDutyProfile()
        case .valorant:
            return ValorantProfile()
        }
    }
    
    var displayName: String {
        switch self {
        case .fortnite:
            return "Fortnite"
        case .callOfDuty:
            return "Call of Duty Mobile"
        case .valorant:
            return "Valorant"
        }
    }
}