import SwiftUI
import UIKit

struct CODSettingsView: View {
    @State private var preRollDuration: Double = 5.0
    @State private var postRollDuration: Double = 3.0
    @State private var killCooldownSeconds: Double = 5.0
    @State private var targetFrameRateIs60: Bool = false
    @State private var detectionSensitivity: DetectionSensitivity = .balanced
    @State private var storageUsed: String = "Calculating..."
    @State private var showDebugInfo: Bool = false
    @State private var selectedConfigPreset: ConfigManager.PredefinedConfigType = .default
    @State private var currentConfig: DetectionConfig = ConfigManager.shared.getCurrentConfig()
    struct ShareItem: Identifiable { let id = UUID(); let url: URL }
    @State private var shareItem: ShareItem?
    @State private var exportError: String?
    
    enum DetectionSensitivity: String, CaseIterable {
        case low = "Low"
        case balanced = "Balanced"
        case high = "High"
        
        var description: String {
            switch self {
            case .low: return "Less sensitive - reduces false positives"
            case .balanced: return "Recommended for most gameplay"
            case .high: return "More sensitive - catches more kills"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                // Game Profile Section
                Section {
                    HStack {
                        Image(systemName: "gamecontroller.fill")
                            .foregroundColor(.orange)
                            .font(.title2)
                        
                        VStack(alignment: .leading) {
                            Text("Call of Duty Mobile")
                                .font(.headline)
                            Text("Kill Detection Profile")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text("ACTIVE")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green)
                            .cornerRadius(6)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Game Profile")
                }
                
                // Detection Settings
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Detection Sensitivity")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Picker("Sensitivity", selection: $detectionSensitivity) {
                            ForEach(DetectionSensitivity.allCases, id: \.self) { sensitivity in
                                Text(sensitivity.rawValue).tag(sensitivity)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        
                        Text(detectionSensitivity.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Kill Detection")
                }

                // Encoding / Frame Rate
                Section {
                    Toggle(isOn: $targetFrameRateIs60) {
                        VStack(alignment: .leading) {
                            Text("Record at 60 FPS")
                            Text("If off, records at 30 FPS. Hardware encoder is required on iOS 17.4+ for raw input.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Recording Frame Rate")
                }
                
                // Clip Duration Settings
                Section {
                    VStack(spacing: 16) {
                        HStack {
                            Text("Pre-roll Duration")
                            Spacer()
                            Text("\(Int(preRollDuration))s")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $preRollDuration, in: 2...15, step: 1)
                            .accentColor(.cgameOrange)
                        
                        HStack {
                            Text("Post-roll Duration")
                            Spacer()
                            Text("\(Int(postRollDuration))s")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $postRollDuration, in: 1...10, step: 1)
                            .accentColor(.cgameOrange)
                        
                        Divider()

                        HStack {
                            Text("Multi-kill Cooldown")
                            Spacer()
                            Text("\(Int(killCooldownSeconds))s")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $killCooldownSeconds, in: 1...15, step: 1)
                            .accentColor(.cgameOrange)

                        Text("Total clip length: ~\(Int(preRollDuration + postRollDuration + 2))s per kill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Clip Settings")
                } footer: {
                    Text("Pre-roll captures gameplay before the kill. Post-roll captures the aftermath. Cooldown groups multiple kills into a single clip.")
                }
                
                // Storage Section
                Section {
                    HStack {
                        Text("Local Storage Used")
                        Spacer()
                        Text(storageUsed)
                            .foregroundColor(.secondary)
                    }
                    
                    Button("View All Clips") {
                        // Navigate to clips view
                    }
                    .foregroundColor(.blue)
                    
                    Button("Clear All Local Clips") {
                        clearLocalClips()
                    }
                    .foregroundColor(.red)
                } header: {
                    Text("Storage Management")
                }
                
                // Detection Configuration Section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Detection Preset")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Picker("Config Preset", selection: $selectedConfigPreset) {
                            ForEach(ConfigManager.PredefinedConfigType.allCases, id: \.self) { preset in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.displayName)
                                        .font(.headline)
                                    Text(preset.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .tag(preset)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        
                        Button("Apply Configuration") {
                            applyConfigPreset()
                        }
                        .buttonStyle(CGameSecondaryButtonStyle())
                    }
                } header: {
                    Text("Detection Configuration")
                } footer: {
                    Text("Choose a preset that matches your playstyle and device performance needs.")
                }
                
                // Advanced Configuration Section  
                Section {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Frame Skip Interval")
                            Spacer()
                            Text("\(currentConfig.frameSkipInterval)")
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Detection Cooldown")
                            Spacer()
                            Text("\(Int(currentConfig.detectionCooldownSeconds))s")
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("OCR Confidence")
                            Spacer()
                            Text("\(Int(currentConfig.ocrConfidenceThreshold * 100))%")
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Detection Region")
                            Spacer()
                            Text("\(Int(currentConfig.recognitionRegion.width * 100))% x \(Int(currentConfig.recognitionRegion.height * 100))%")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Current Configuration")
                }
                
                // Debug Section
                Section {
                    Toggle("Show Debug Info", isOn: $showDebugInfo)
                    
                    if showDebugInfo {
                        VStack(alignment: .leading, spacing: 8) {
                            DebugInfoRow(title: "Target Keywords", value: currentConfig.gameProfile.targetKeywords.joined(separator: ", "))
                            DebugInfoRow(title: "Avoid Keywords", value: currentConfig.gameProfile.avoidKeywords.isEmpty ? "None" : currentConfig.gameProfile.avoidKeywords.joined(separator: ", "))
                            DebugInfoRow(title: "Case Sensitive", value: currentConfig.gameProfile.caseSensitive ? "Yes" : "No")
                            DebugInfoRow(title: "Debug Logging", value: currentConfig.enableDebugLogging ? "Enabled" : "Disabled")
                            DebugInfoRow(title: "App Group ID", value: "group.com.cgame.shared")
                        }
                        .font(.caption)
                    }
                    
                    Button("Export Config JSON") {
                        exportConfig()
                    }
                    
                    Button("Test Kill Detection") {
                        testKillDetection()
                    }

                    Button("Export error.log to Files…") {
                        exportErrorLog()
                    }
                } header: {
                    Text("Debug & Testing")
                }
                
                // Info Section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0 (COD Test Build)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Build Mode")
                        Spacer()
                        Text("Local Testing")
                            .foregroundColor(.orange)
                            .fontWeight(.medium)
                    }
                } header: {
                    Text("App Info")
                }
            }
            .navigationTitle("COD Settings")
            .onAppear {
                loadSettings()
                calculateStorageUsage()
            }
            .onChange(of: preRollDuration) { _ in saveSettings() }
            .onChange(of: postRollDuration) { _ in saveSettings() }
            .onChange(of: killCooldownSeconds) { _ in saveSettings() }
            .onChange(of: detectionSensitivity) { _ in saveSettings() }
            .onChange(of: targetFrameRateIs60) { _ in saveSettings() }
        }
        .sheet(item: $shareItem) { item in
            ActivityViewController(activityItems: [item.url])
        }
        .alert("Export Failed", isPresented: Binding(get: { exportError != nil }, set: { _ in exportError = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "Unknown error")
        }
    }
    
    private func loadSettings() {
        guard let appGroupDefaults = UserDefaults(suiteName: "group.com.cgame.shared") else { return }
        
        preRollDuration = appGroupDefaults.double(forKey: "preRollDuration")
        if preRollDuration == 0 { preRollDuration = 5.0 }
        
        postRollDuration = appGroupDefaults.double(forKey: "postRollDuration")
        if postRollDuration == 0 { postRollDuration = 3.0 }

        killCooldownSeconds = appGroupDefaults.double(forKey: "killCooldownSeconds")
        if killCooldownSeconds == 0 { killCooldownSeconds = 5.0 }
        let fps = appGroupDefaults.integer(forKey: "targetFrameRate")
        targetFrameRateIs60 = (fps == 60)
        
        if let sensitivityString = appGroupDefaults.string(forKey: "detectionSensitivity"),
           let sensitivity = DetectionSensitivity(rawValue: sensitivityString) {
            detectionSensitivity = sensitivity
        }
    }
    
    private func saveSettings() {
        guard let appGroupDefaults = UserDefaults(suiteName: "group.com.cgame.shared") else { return }
        
        appGroupDefaults.set("CallOfDuty", forKey: "selectedProfile")
        appGroupDefaults.set(preRollDuration, forKey: "preRollDuration")
        appGroupDefaults.set(postRollDuration, forKey: "postRollDuration")
        appGroupDefaults.set(killCooldownSeconds, forKey: "killCooldownSeconds")
        appGroupDefaults.set(targetFrameRateIs60 ? 60 : 30, forKey: "targetFrameRate")
        appGroupDefaults.set(detectionSensitivity.rawValue, forKey: "detectionSensitivity")
        appGroupDefaults.synchronize()
        
        print("⚙️ Settings saved: Pre-roll: \(preRollDuration)s, Post-roll: \(postRollDuration)s, Cooldown: \(killCooldownSeconds)s")
    }
    
    private func calculateStorageUsage() {
        let localFiles = AppGroupManager.shared.getAllClipFiles()
        var totalSize: Int64 = 0
        
        for fileURL in localFiles {
            if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
               let fileSize = attributes[.size] as? Int64 {
                totalSize += fileSize
            }
        }
        
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        
        storageUsed = "\(formatter.string(fromByteCount: totalSize)) (\(localFiles.count) clips)"
    }
    
    private func clearLocalClips() {
        let localFiles = AppGroupManager.shared.getAllClipFiles()
        
        for fileURL in localFiles {
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        AppGroupManager.shared.clearPendingMetadata()
        calculateStorageUsage()
    }
    
    private func applyConfigPreset() {
        ConfigManager.shared.loadPredefinedConfig(selectedConfigPreset)
        currentConfig = ConfigManager.shared.getCurrentConfig()
        print("🔧 Applied \(selectedConfigPreset.displayName) configuration")
    }
    
    private func exportConfig() {
        if let jsonString = ConfigManager.shared.exportConfigAsJSON() {
            print("📤 Configuration exported:")
            print(jsonString)
            // TODO: Add share sheet or copy to clipboard
        }
    }
    
    private func testKillDetection() {
        print("🧪 Testing COD kill detection patterns...")
        print("Current config: \(selectedConfigPreset.displayName)")
        
        // Test with current config keywords
        let testPhrases = currentConfig.gameProfile.targetKeywords + [
            "KILL",
            "You got a kill", 
            "Enemy KILL",
            "KILL +100",
            "Double KILL!"
        ]
        
        for phrase in testPhrases {
            let shouldDetect = currentConfig.gameProfile.targetKeywords.contains { keyword in
                phrase.uppercased().contains(keyword.uppercased())
            }
            print("Testing '\(phrase)' → \(shouldDetect ? "✅ DETECTED" : "❌ Not detected")")
        }
    }

    private func exportErrorLog() {
        // Locate the App Group error.log written by the extension
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.cgame.shared") else {
            exportError = "App Group container unavailable."
            return
        }
        let debugDir = container.appendingPathComponent("Debug")
        var logURL = debugDir.appendingPathComponent("error.log")
        if !FileManager.default.fileExists(atPath: logURL.path) {
            // Fallback: pick the newest error_*.log
            do {
                let files = try FileManager.default.contentsOfDirectory(at: debugDir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
                let errorLogs = files.filter { $0.lastPathComponent.hasPrefix("error_") && $0.pathExtension == "log" }
                if let newest = errorLogs.sorted(by: { (a, b) -> Bool in
                    let aDate = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                    let bDate = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                    return aDate > bDate
                }).first {
                    logURL = newest
                } else {
                    exportError = "No error logs found yet. Run a session first."
                    return
                }
            } catch {
                exportError = "Failed to locate logs: \(error.localizedDescription)"
                return
            }
        }
        // Copy to a temporary location with a friendly name for sharing
        let tmp = FileManager.default.temporaryDirectory
        let dateStr = makeDateString()
        let exportURL = tmp.appendingPathComponent("cgame_error_\(dateStr).log")
        do {
            if FileManager.default.fileExists(atPath: exportURL.path) {
                try FileManager.default.removeItem(at: exportURL)
            }
            try FileManager.default.copyItem(at: logURL, to: exportURL)
            self.shareItem = ShareItem(url: exportURL)
        } catch {
            exportError = "Failed to prepare export: \(error.localizedDescription)"
        }
    }
    
    private func makeDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: Date())
    }
}

struct DebugInfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

// Lightweight UIActivityViewController wrapper local to this file
struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}