import SwiftUI
import Photos

struct HomeView: View {
    @StateObject private var broadcastManager = BroadcastManager()
    @State private var showCopyStatusAlert = false
    @State private var copyStatusMessage = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header Section
                VStack(spacing: 16) {
                    CGameLogo(size: 100)
                    
                    Text("CGame")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.cgameNavyGradient)
                    
                    Text(broadcastManager.isRecording ? "🎯 Hunting for kills..." : "Kill Detection Ready")
                        .font(.headline)
                        .foregroundColor(broadcastManager.isRecording ? .cgameRed : .secondary)
                }
                
                // Status Card
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "gamecontroller.fill")
                            .foregroundColor(.cgameOrange)
                        Text("Call of Duty Mobile")
                            .font(.headline)
                        Spacer()
                        CGameStatusBadge(
                            text: broadcastManager.isRecording ? "ACTIVE" : "READY",
                            isActive: broadcastManager.isRecording
                        )
                    }
                    
                    Text(broadcastManager.statusMessage)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
                .background(Color(.systemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // Main Action Button
                if broadcastManager.isRecording {
                    // Stop button when recording
                    Button(action: {
                        broadcastManager.stopBroadcast()
                    }) {
                        HStack(spacing: 16) {
                            Image(systemName: "stop.circle.fill")
                                .font(.title)
                            Text("Stop Detection")
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 80)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.cgameRed, Color.cgameRed.opacity(0.8)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(20)
                        .shadow(color: Color.cgameRed.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .padding(.horizontal, 32)
                } else {
                    // Start button with hidden broadcast picker
                    ZStack {
                        // Visual button
                        HStack(spacing: 16) {
                            Image(systemName: "play.circle.fill")
                                .font(.title)
                                .foregroundColor(.white)
                            Text("Start COD Detection")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 80)
                        .background(Color.cgamePrimaryGradient)
                        .cornerRadius(20)
                        .shadow(color: Color.cgameRed.opacity(0.3), radius: 8, x: 0, y: 4)
                        
                        // Hidden broadcast picker on top
                        BroadcastPickerView { success in
                            if success {
                                broadcastManager.broadcastDidStart()
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.clear)
                    }
                    .padding(.horizontal, 32)
                }
                
                // Instructions
                if !broadcastManager.isRecording {
                    VStack(spacing: 8) {
                        Text("📱 Select 'CGame Extension' from the broadcast picker")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Text("🎮 Start COD Mobile and get some kills!")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        // Debug button to view preview images
                        Button("📸 View OCR Preview Images") {
                            self.copyStatusMessage = "Copying..."
                            self.showCopyStatusAlert = true
                            AppGroupManager.shared.copyDebugImagesToPhotoLibrary { count in
                                if count > 0 {
                                    self.copyStatusMessage = "Copied \(count) debug images to Photos!"
                                } else {
                                    self.copyStatusMessage = "No debug images found to copy. Record a session first."
                                }
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.cgameOrange)
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 32)
                }
                
                Spacer()
                
                // Recent Clips Section
                if !broadcastManager.recentClips.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("🏆 Recent Kill Highlights")
                                .font(.headline)
                            Spacer()
                            Text("\(broadcastManager.recentClips.count)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.cgamePrimaryGradient)
                                .cornerRadius(8)
                        }
                        .padding(.horizontal, 32)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(broadcastManager.recentClips.prefix(5), id: \.id) { clip in
                                    CODClipThumbnailView(clip: clip)
                                }
                            }
                            .padding(.horizontal, 32)
                        }
                    }
                }
            }
            .navigationTitle("CGame AI Recorder")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                broadcastManager.checkForNewClips()
            }
            .alert(isPresented: $showCopyStatusAlert) {
                Alert(title: Text("Debug Images"), message: Text(copyStatusMessage), dismissButton: .default(Text("OK")))
            }
        }
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
    }
}

struct CODClipThumbnailView: View {
    let clip: Clip
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.cgameRed.opacity(0.3), Color.cgameOrange.opacity(0.4)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 140, height: 78)
                
                VStack(spacing: 4) {
                    DiamondPattern(size: 8, spacing: 2)
                        .foregroundColor(.white)
                    
                    Text("KILL")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                
                // Duration badge
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("\(Int(clip.duration))s")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(4)
                            .padding(.trailing, 6)
                            .padding(.bottom, 6)
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(clip.eventDescription)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text("COD Mobile")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text(formatRelativeTime(clip.timestamp))
                    .font(.caption2)
                    .foregroundColor(.cgameOrange)
            }
        }
        .frame(width: 140)
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let now = Date()
        let diff = now.timeIntervalSince(date)
        
        if diff < 60 {
            return "Just now"
        } else if diff < 3600 {
            return "\(Int(diff / 60))m ago"
        } else if diff < 86400 {
            return "\(Int(diff / 3600))h ago"
        } else {
            return "\(Int(diff / 86400))d ago"
        }
    }
}