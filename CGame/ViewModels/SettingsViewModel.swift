import Foundation
import UIKit

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var selectedConfigType: ConfigManager.PredefinedConfigType = .`default`
    @Published var videoQuality: UserSettings.VideoQuality = .hd1080p
    @Published var preRollDuration: Double = 5.0
    @Published var postRollDuration: Double = 3.0
    @Published var storageUsed: String = "Calculating..."
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let configManager = ConfigManager.shared
    
    init() {
        loadSettings()
    }
    
    func loadSettings() {
        isLoading = true
        
        // Load from local configuration
        let currentConfig = configManager.getCurrentConfig()
        
        // Determine which predefined config this matches
        if configManager.isCurrentConfigEqualTo(.`default`) {
            selectedConfigType = .`default`
        } else if configManager.isCurrentConfigEqualTo(.sensitive) {
            selectedConfigType = .sensitive
        } else if configManager.isCurrentConfigEqualTo(.conservative) {
            selectedConfigType = .conservative
        } else {
            selectedConfigType = .`default` // Default fallback
        }
        
        isLoading = false
        
        // Load storage usage
        Task {
            updateStorageUsage()
        }
    }
    
    func saveSettings() {
        // Save detection configuration
        configManager.loadPredefinedConfig(selectedConfigType)
        
        // Save user preferences
        let settings = UserSettings(
            gameProfileName: "cod_mobile", // Fixed for COD Mobile
            videoQuality: videoQuality,
            preRollDuration: preRollDuration,
            postRollDuration: postRollDuration
        )
        
        // Save to app group for extension access
        saveSettingsToAppGroup(settings)
    }
    
    private func saveSettingsToAppGroup(_ settings: UserSettings) {
        guard let appGroupDefaults = UserDefaults(suiteName: "group.com.cgame.shared") else { return }
        
        // Save configuration type for extension
        appGroupDefaults.set(selectedConfigType.displayName, forKey: "selectedConfigType")
        
        // Save other settings
        appGroupDefaults.set(preRollDuration, forKey: "preRollDuration")
        appGroupDefaults.set(postRollDuration, forKey: "postRollDuration")
        appGroupDefaults.set(videoQuality.rawValue, forKey: "videoQuality")
        
        appGroupDefaults.synchronize()
    }
    
    private func updateStorageUsage() {
        Task(priority: .background) {
            let urls = AppGroupManager.shared.getAllClipFiles()
            
            let totalSize = urls.reduce(0) { (result, url) -> Int64 in
                let values = try? url.resourceValues(forKeys: [.fileSizeKey])
                return result + Int64(values?.fileSize ?? 0)
            }
            
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useMB, .useGB]
            formatter.countStyle = .file
            
            storageUsed = formatter.string(fromByteCount: totalSize)
        }
    }
    
    func clearLocalStorage() {
        let alert = UIAlertController(
            title: "Clear Local Storage",
            message: "This will delete all local clips. Are you sure?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { [weak self] _ in
            self?.performClearLocalStorage()
        })
        
        // Present alert through the root view controller
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(alert, animated: true)
        }
    }
    
    private func performClearLocalStorage() {
        let localFiles = AppGroupManager.shared.getAllClipFiles()
        
        for fileURL in localFiles {
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        AppGroupManager.shared.clearPendingMetadata()
        
        Task {
            updateStorageUsage()
        }
    }
    
    func clearError() {
        errorMessage = nil
    }
}