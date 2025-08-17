import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var settingsViewModel = SettingsViewModel()
    
    var body: some View {
        NavigationView {
            Form {
                Section("Detection Configuration") {
                    Picker("Detection Sensitivity", selection: $settingsViewModel.selectedConfigType) {
                        ForEach(ConfigManager.PredefinedConfigType.allCases, id: \.self) { configType in
                            Text(configType.displayName).tag(configType)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    
                    Text(settingsViewModel.selectedConfigType.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Video Quality") {
                    Picker("Quality", selection: $settingsViewModel.videoQuality) {
                        ForEach(UserSettings.VideoQuality.allCases, id: \.self) { quality in
                            Text(quality.displayName).tag(quality)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                
                Section("Clip Settings") {
                    HStack {
                        Text("Pre-roll Duration")
                        Spacer()
                        Text("\(Int(settingsViewModel.preRollDuration))s")
                            .foregroundColor(.secondary)
                    }
                    Slider(
                        value: $settingsViewModel.preRollDuration,
                        in: 0...15,
                        step: 1
                    )
                    
                    HStack {
                        Text("Post-roll Duration")
                        Spacer()
                        Text("\(Int(settingsViewModel.postRollDuration))s")
                            .foregroundColor(.secondary)
                    }
                    Slider(
                        value: $settingsViewModel.postRollDuration,
                        in: 0...15,
                        step: 1
                    )
                }
                
                Section("Storage") {
                    HStack {
                        Text("Local Storage Used")
                        Spacer()
                        Text(settingsViewModel.storageUsed)
                            .foregroundColor(.secondary)
                    }
                    
                    Button("Clear Local Clips") {
                        settingsViewModel.clearLocalStorage()
                    }
                    .foregroundColor(.red)
                }
                
                Section("Account") {
                    HStack {
                        Text("Email")
                        Spacer()
                        Text(authViewModel.user?.email ?? "")
                            .foregroundColor(.secondary)
                    }
                    
                    Button("Sign Out") {
                        authViewModel.signOut()
                    }
                    .foregroundColor(.red)
                }
                
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    Link("Privacy Policy", destination: URL(string: "https://cgame.app/privacy")!)
                    Link("Terms of Service", destination: URL(string: "https://cgame.app/terms")!)
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                settingsViewModel.loadSettings()
            }
            .onChange(of: settingsViewModel.selectedConfigType) { _ in
                settingsViewModel.saveSettings()
            }
            .onChange(of: settingsViewModel.videoQuality) { _ in
                settingsViewModel.saveSettings()
            }
            .onChange(of: settingsViewModel.preRollDuration) { _ in
                settingsViewModel.saveSettings()
            }
            .onChange(of: settingsViewModel.postRollDuration) { _ in
                settingsViewModel.saveSettings()
            }
        }
    }
}

struct CompileHighlightsView: View {
    let clips: [Clip]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedClips: Set<String> = []
    @State private var isCompiling = false
    
    var body: some View {
        NavigationView {
            VStack {
                if clips.isEmpty {
                    VStack {
                        Image(systemName: "video.slash")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                        Text("No clips available")
                            .font(.title2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(clips) { clip in
                            HStack {
                                Button(action: {
                                    if selectedClips.contains(clip.id) {
                                        selectedClips.remove(clip.id)
                                    } else {
                                        selectedClips.insert(clip.id)
                                    }
                                }) {
                                    Image(systemName: selectedClips.contains(clip.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedClips.contains(clip.id) ? .blue : .gray)
                                }
                                
                                VStack(alignment: .leading) {
                                    Text(clip.eventDescription)
                                        .font(.headline)
                                    Text("\(clip.game) • \(Int(clip.duration))s")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                            }
                        }
                    }
                    
                    if !selectedClips.isEmpty {
                        Button(action: compileHighlights) {
                            HStack {
                                if isCompiling {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                }
                                Text("Compile \(selectedClips.count) Clips")
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .disabled(isCompiling)
                        .padding()
                    }
                }
            }
            .navigationTitle("Compile Highlights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func compileHighlights() {
        isCompiling = true
        
        // TODO: Implement VideoCompiler integration
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isCompiling = false
            dismiss()
        }
    }
}