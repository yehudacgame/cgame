import SwiftUI
import AVKit
import AVFoundation
import UIKit

struct LocalClipsGalleryView: View {
    @StateObject private var clipsViewModel = ClipsViewModel()
    @State private var selectedClip: Clip?
    @State private var contextMenuClip: Clip?
    
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    var body: some View {
        NavigationView {
            VStack {
                if clipsViewModel.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading kill highlights...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                } else if clipsViewModel.clips.isEmpty {
                    EmptyClipsView()
                    
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(clipsViewModel.clips) { clip in
                                CODClipGridItem(clip: clip, onTap: { selectedClip = clip })
                                    .contextMenu {
                                        Button {
                                            share(clip)
                                        } label: {
                                            Label("Share", systemImage: "square.and.arrow.up")
                                        }
                                        Divider()
                                        Button(role: .destructive) {
                                            clipsViewModel.deleteClip(clip)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                        .padding(12)
                    }
                    .refreshable { clipsViewModel.refreshClips() }
                }
            }
            .navigationTitle("Kill Highlights")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Refresh Clips") { clipsViewModel.refreshClips() }
                        Divider()
                        Button("Clear All Clips", role: .destructive) { clearAllClips() }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .onAppear { NSLog("📱 LocalClipsGalleryView: onAppear - ClipsViewModel will handle pending clips processing") }
        }
        .fullScreenCover(item: $selectedClip) { clip in
            CODClipPlayerView(clip: clip)
        }
    }
    
    private func share(_ clip: Clip) {
        guard let url = clip.localURL else { return }
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first,
           let root = window.rootViewController {
            root.present(av, animated: true)
        }
    }
    
    private func clearAllClips() {
        let localFiles = AppGroupManager.shared.getAllClipFiles()
        for fileURL in localFiles { try? FileManager.default.removeItem(at: fileURL) }
        AppGroupManager.shared.clearPendingMetadata()
        clipsViewModel.refreshClips()
    }
}

struct EmptyClipsView: View {
    var body: some View {
        VStack(spacing: 20) {
            CGameLogo(size: 80).opacity(0.6)
            Text("No Kill Highlights Yet").font(.title2).fontWeight(.semibold)
            VStack(spacing: 8) {
                Text("Start recording COD Mobile gameplay").font(.body).foregroundColor(.secondary)
                Text("Your epic kills will appear here automatically!").font(.subheadline).foregroundColor(.secondary)
            }.multilineTextAlignment(.center)
            Button(action: {}) {
                HStack { Image(systemName: "play.circle.fill"); Text("Start Detection") }
                    .buttonStyle(CGamePrimaryButtonStyle(isActive: false))
            }
        }.padding()
    }
}

struct CODClipGridItem: View {
    let clip: Clip
    let onTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onTap) {
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                        .aspectRatio(16/9, contentMode: .fit)
                        .overlay(ClipThumbnail(url: clip.localURL))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    HStack(spacing: 8) {
                        Label("KILL", systemImage: "scope")
                            .font(.caption2).foregroundColor(.white)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color.red.opacity(0.8)).cornerRadius(4)
                        
                        Text("\(Int(clip.duration))s")
                            .font(.caption2).fontWeight(.bold).foregroundColor(.white)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color.black.opacity(0.7)).cornerRadius(4)
                    }
                    .padding(8)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(clip.eventDescription).font(.subheadline).fontWeight(.semibold).lineLimit(1)
                HStack {
                    Text("COD Mobile").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Text(formatRelativeTime(clip.timestamp)).font(.caption).foregroundColor(.orange)
                }
            }
        }
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let now = Date(); let diff = now.timeIntervalSince(date)
        if diff < 60 { return "Just now" }
        if diff < 3600 { return "\(Int(diff / 60))m ago" }
        if diff < 86400 { return "\(Int(diff / 3600))h ago" }
        return "\(Int(diff / 86400))d ago"
    }
}

struct ClipThumbnail: View {
    let url: URL?
    @State private var image: UIImage?
    
    var body: some View {
        ZStack {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(gradient: Gradient(colors: [.gray.opacity(0.3), .gray.opacity(0.5)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(Image(systemName: "video").font(.largeTitle).foregroundColor(.white.opacity(0.6)))
                    .task { await load() }
            }
        }
        .clipped()
    }
    
    private func load() async {
        guard let url else { return }
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let asset = AVAsset(url: url)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 800, height: 450)
                let time = CMTime(seconds: 1.0, preferredTimescale: 600)
                let result: UIImage?
                do {
                    let cg = try generator.copyCGImage(at: time, actualTime: nil)
                    result = UIImage(cgImage: cg)
                } catch {
                    result = nil
                }
                DispatchQueue.main.async {
                    self.image = result
                    continuation.resume()
                }
            }
        }
    }
}

struct CODClipPlayerView: View {
    let clip: Clip
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var showControls = true
    @State private var controlsTimer: Timer?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Full screen black background
                Color.black
                    .ignoresSafeArea(.all)
                
                // Video Player - Full Screen with proper aspect ratio
                if let player = player {
                    VideoPlayer(player: player)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .ignoresSafeArea(.all)
                        .onAppear {
                            NSLog("🎬 COD Player: VideoPlayer onAppear - Starting playback")
                            player.play()
                            // Auto-hide controls after 3 seconds
                            startControlsTimer()
                        }
                        .onDisappear {
                            player.pause()
                            controlsTimer?.invalidate()
                            // Clean up notification observers
                            NotificationCenter.default.removeObserver(self)
                        }
                        .onTapGesture {
                            // Toggle controls on tap
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showControls.toggle()
                            }
                            if showControls {
                                startControlsTimer()
                            }
                        }
                } else {
                    // Loading state
                    VStack {
                        ProgressView("Loading video...")
                            .tint(.white)
                        Text("Preparing your kill highlight")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .onAppear {
                        NSLog("🔄 COD Player: Showing loading state - player is nil")
                    }
                }
                
                // Controls overlay - close button always visible, share button auto-hides
                VStack {
                    // Top bar with always-visible close button and conditional share button
                    HStack {
                        // Close button - ALWAYS VISIBLE
                        Button(action: { 
                            NSLog("🎬 COD Player: Close button tapped")
                            dismiss() 
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                                .foregroundColor(.white)
                                .background(Color.black.opacity(0.7))
                                .clipShape(Circle())
                                .scaleEffect(1.1)
                        }
                        .padding()
                        .accessibilityLabel("Close video player")
                        
                        Spacer()
                        
                        // Share button - only shows with other controls
                        if showControls {
                            Button(action: { shareClip() }) {
                                Image(systemName: "square.and.arrow.up.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Circle())
                            }
                            .padding()
                            .transition(.opacity)
                        }
                    }
                    
                    Spacer()
                    
                    // Debug overlay to show controls state
                    if showControls {
                        Text("Controls visible - will hide in 3s")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .padding()
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(8)
                            .transition(.opacity)
                    }
                }
            }
        }
        .ignoresSafeArea(.all)
        .statusBarHidden() // Always hide status bar for full immersion
        .persistentSystemOverlays(.hidden) // Hide system overlays for full screen
        .onAppear {
            NSLog("🎬 COD Player View: onAppear called - Setting up player for clip \(clip.id)")
            NSLog("🎬 COD Player: Initial showControls state: \(showControls)")
            setupPlayer()
            // Don't force orientation - let user control it naturally
        }
        .onDisappear {
            // Don't force orientation change on disappear
        }
    }
    
    private func startControlsTimer() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                showControls = false
            }
        }
    }
    
    private func setupPlayer() {
        NSLog("🎬 COD Player: Starting setup for clip \(clip.id)")
        
        guard let localURL = clip.localURL else {
            NSLog("❌ COD Player: No local URL for clip \(clip.id)")
            return
        }
        
        NSLog("🎬 COD Player: Video file path: \(localURL.path)")
        
        // Check if file exists and is valid
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            NSLog("❌ COD Player: Video file doesn't exist at \(localURL.path)")
            return
        }
        
        // Get file size and detailed attributes
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: localURL.path)
            if let fileSize = attributes[.size] as? NSNumber,
               let modificationDate = attributes[.modificationDate] as? Date {
                NSLog("🎥 COD Player: Video file details - Size: \(fileSize) bytes, Modified: \(modificationDate)")
                
                if fileSize.intValue < 1000 {
                    NSLog("🚨 COD Player: CRITICAL - Video file is \(fileSize) bytes, likely corrupted!")
                    return
                } else if fileSize.intValue < 100000 {
                    NSLog("⚠️ COD Player: WARNING - Video file is only \(fileSize) bytes, might be corrupted")
                }
            }
        } catch {
            NSLog("❌ COD Player: Error checking video file attributes: \(error)")
            return
        }
        
        NSLog("🎬 COD Player: Creating AVAsset and AVPlayer...")
        let asset = AVAsset(url: localURL)
        let playerItem = AVPlayerItem(asset: asset)
        
        // Monitor player item status changes
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { notification in
            if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
                NSLog("❌ COD Player: Failed to play to end: \(error.localizedDescription)")
            }
        }
        
        player = AVPlayer(playerItem: playerItem)
        NSLog("🎬 COD Player: AVPlayer created")
        
        // Monitor asset loading in detail
        Task {
            do {
                NSLog("🔄 COD Player: Loading asset properties...")
                
                // Load all essential properties
                let duration = try await asset.load(.duration)
                let isPlayable = try await asset.load(.isPlayable)
                let hasProtectedContent = try await asset.load(.hasProtectedContent)
                let tracks = try await asset.load(.tracks)
                
                await MainActor.run {
                    NSLog("🔍 COD Player: Asset loaded - Duration: \(String(format: "%.2f", duration.seconds))s, Playable: \(isPlayable), Protected: \(hasProtectedContent), Tracks: \(tracks.count)")
                    
                    if !isPlayable {
                        NSLog("🚨 COD Player: CRITICAL - Asset is NOT playable!")
                    }
                    
                    if duration.seconds <= 0 {
                        NSLog("🚨 COD Player: CRITICAL - Asset has zero or negative duration!")
                    }
                    
                    if tracks.isEmpty {
                        NSLog("🚨 COD Player: CRITICAL - Asset has no tracks!")
                    } else {
                        for (index, track) in tracks.enumerated() {
                            NSLog("🎥 COD Player: Track \(index): \(track.mediaType.rawValue)")
                        }
                    }
                }
            } catch {
                NSLog("❌ COD Player: CRITICAL ERROR loading asset properties: \(error)")
            }
        }
        
        // Loop the video
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { _ in
            self.player?.seek(to: .zero)
            self.player?.play()
        }
        
        NSLog("✅ COD Player: Setup completed for clip \(clip.id)")
    }
    
    
    private func shareClip() {
        // TODO: Implement sharing functionality
        print("Sharing COD kill clip: \(clip.id)")
    }
    
    // Removed forced orientation methods - let user control orientation naturally
}