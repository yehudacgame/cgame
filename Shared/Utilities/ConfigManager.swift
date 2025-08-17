import Foundation

class ConfigManager {
    static let shared = ConfigManager()
    
    private let configFileName = "detection_config.json"
    private let appGroupIdentifier = "group.com.cgame.shared"
    
    private var cachedConfig: DetectionConfig?
    
    private init() {}
    
    // MARK: - Local File Management
    
    private var configFileURL: URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            print("❌ ConfigManager: Could not access app group container")
            return nil
        }
        
        return containerURL.appendingPathComponent(configFileName)
    }
    
    func getCurrentConfig() -> DetectionConfig {
        // Force refresh from default for development
        // TODO: Remove this in production
        let defaultConfig = DetectionConfig.defaultCODConfig
        cachedConfig = defaultConfig
        saveConfigToFile(defaultConfig)
        print("🔄 ConfigManager: Force-refreshed to latest default config")
        print("🔄 ConfigManager: Detection region: x=\(defaultConfig.recognitionRegion.x), y=\(defaultConfig.recognitionRegion.y), w=\(defaultConfig.recognitionRegion.width), h=\(defaultConfig.recognitionRegion.height)")
        return defaultConfig
        
        /*
        if let cached = cachedConfig {
            return cached
        }
        
        // Try to load from file first
        if let loadedConfig = loadConfigFromFile() {
            cachedConfig = loadedConfig
            print("📄 ConfigManager: Loaded config from file")
            return loadedConfig
        }
        
        // Fall back to default
        let defaultConfig = DetectionConfig.defaultCODConfig
        saveConfigToFile(defaultConfig)
        cachedConfig = defaultConfig
        print("🆕 ConfigManager: Using default COD config")
        return defaultConfig
        */
    }
    
    func updateConfig(_ config: DetectionConfig) {
        cachedConfig = config
        saveConfigToFile(config)
        print("💾 ConfigManager: Config updated and saved")
        
        // Notify app group that config changed
        notifyConfigChange()
    }
    
    func resetToDefault() {
        let defaultConfig = DetectionConfig.defaultCODConfig
        updateConfig(defaultConfig)
        print("🔄 ConfigManager: Reset to default configuration")
    }
    
    // MARK: - Predefined Configs
    
    func loadPredefinedConfig(_ configType: PredefinedConfigType) {
        let config: DetectionConfig
        
        switch configType {
        case .`default`:
            config = DetectionConfig.defaultCODConfig
        case .sensitive:
            config = DetectionConfig.sensitiveCODConfig
        case .conservative:
            config = DetectionConfig.conservativeCODConfig
        }
        
        updateConfig(config)
        print("📋 ConfigManager: Loaded \(configType.displayName) configuration")
    }
    
    enum PredefinedConfigType: CaseIterable {
        case `default`, sensitive, conservative
        
        var displayName: String {
            switch self {
            case .`default`: return "Balanced"
            case .sensitive: return "Sensitive (More Detections)"
            case .conservative: return "Conservative (Fewer False Positives)"
            }
        }
        
        var description: String {
            switch self {
            case .`default`:
                return "10 frame skip, 3s cooldown - Recommended for most users"
            case .sensitive:
                return "5 frame skip, 2s cooldown - Catches more kills but uses more resources"
            case .conservative:
                return "15 frame skip, 5s cooldown - Battery friendly, very reliable"
            }
        }
    }
    
    // MARK: - File Operations
    
    private func loadConfigFromFile() -> DetectionConfig? {
        guard let fileURL = configFileURL else { return nil }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            return try decoder.decode(DetectionConfig.self, from: data)
        } catch {
            print("⚠️ ConfigManager: Failed to load config from file: \(error)")
            return nil
        }
    }
    
    private func saveConfigToFile(_ config: DetectionConfig) {
        guard let fileURL = configFileURL else { return }
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(config)
            try data.write(to: fileURL)
            print("💾 ConfigManager: Config saved to \(fileURL.lastPathComponent)")
        } catch {
            print("❌ ConfigManager: Failed to save config: \(error)")
        }
    }
    
    private func notifyConfigChange() {
        // Notify extension that config has changed
        guard let appGroupDefaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
        
        appGroupDefaults.set(Date().timeIntervalSince1970, forKey: "configLastUpdated")
        appGroupDefaults.synchronize()
    }
    
    // MARK: - Debug & Export
    
    func exportConfigAsJSON() -> String? {
        let config = getCurrentConfig()
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(config)
            return String(data: data, encoding: .utf8)
        } catch {
            print("❌ ConfigManager: Failed to export config as JSON: \(error)")
            return nil
        }
    }
    
    func importConfigFromJSON(_ jsonString: String) -> Bool {
        guard let data = jsonString.data(using: .utf8) else {
            print("❌ ConfigManager: Invalid JSON string")
            return false
        }
        
        do {
            let decoder = JSONDecoder()
            let config = try decoder.decode(DetectionConfig.self, from: data)
            updateConfig(config)
            return true
        } catch {
            print("❌ ConfigManager: Failed to import config from JSON: \(error)")
            return false
        }
    }
    
    // MARK: - Config Comparison
    
    func isCurrentConfigEqualTo(_ configType: PredefinedConfigType) -> Bool {
        let currentConfig = getCurrentConfig()
        let predefinedConfig: DetectionConfig
        
        switch configType {
        case .`default`:
            predefinedConfig = DetectionConfig.defaultCODConfig
        case .sensitive:
            predefinedConfig = DetectionConfig.sensitiveCODConfig
        case .conservative:
            predefinedConfig = DetectionConfig.conservativeCODConfig
        }
        
        return currentConfig.frameSkipInterval == predefinedConfig.frameSkipInterval &&
               currentConfig.detectionCooldownSeconds == predefinedConfig.detectionCooldownSeconds &&
               currentConfig.ocrConfidenceThreshold == predefinedConfig.ocrConfidenceThreshold
    }
    
    // MARK: - Future Firebase Integration Placeholder
    
    func syncWithFirebase() async {
        // TODO: Implement Firebase sync when ready
        print("🔄 ConfigManager: Firebase sync not implemented yet")
    }
}