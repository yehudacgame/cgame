import SwiftUI
import AVKit

struct ModernClipsGalleryView: View {
    @StateObject private var viewModel = ClipsViewModel()
    @State private var selectedClip: Clip?
    @State private var showingPlayer = false
    @State private var showingDeleteAlert = false
    @State private var clipToDelete: Clip?
    @State private var gridColumns = 2
    
    let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        ZStack {
            // Background
            Color.gamingBackground
                .ignoresSafeArea()
            
            if viewModel.isLoading {
                loadingView
            } else if viewModel.clips.isEmpty {
                emptyStateView
            } else {
                clipsGrid
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $selectedClip) { clip in
            ClipPlayerSheet(clip: clip)
        }
        .alert("Delete Clip?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let clip = clipToDelete {
                    viewModel.deleteClip(clip)
                }
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }
    
    // MARK: - View Components
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .gamingPrimary))
                .scaleEffect(1.5)
            
            Text("LOADING CLIPS...")
                .font(GamingFonts.body())
                .foregroundColor(.gamingTextSecondary)
                .tracking(2)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 30) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.gamingPrimary.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Image(systemName: GamingIcons.clips)
                    .font(.system(size: 50))
                    .foregroundStyle(GamingGradients.primary)
            }
            
            VStack(spacing: 12) {
                Text("NO CLIPS YET")
                    .font(GamingFonts.heading())
                    .foregroundColor(.gamingTextPrimary)
                    .tracking(1)
                
                Text("Start recording to capture\nyour epic gaming moments!")
                    .font(GamingFonts.body())
                    .foregroundColor(.gamingTextSecondary)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: { }) {
                HStack {
                    Image(systemName: GamingIcons.record)
                    Text("START RECORDING")
                }
                .font(GamingFonts.body())
            }
            .buttonStyle(GamingButtonStyle(color: .gamingPrimary))
        }
    }
    
    private var clipsGrid: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                headerView
                
                // Grid
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(viewModel.clips) { clip in
                        ClipCard(
                            clip: clip,
                            onPlay: {
                                selectedClip = clip
                            },
                            onDelete: {
                                clipToDelete = clip
                                showingDeleteAlert = true
                            }
                        )
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal)
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: viewModel.clips.count)
            }
            .padding(.vertical)
        }
        .refreshable {
            viewModel.refreshClips()
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        // Small CGame logo
                        VStack(spacing: 0.5) {
                            HStack(spacing: 0.5) {
                                RoundedRectangle(cornerRadius: 0.5)
                                    .fill(GamingGradients.cgameBrand)
                                    .frame(width: 3, height: 3)
                                    .rotationEffect(.degrees(45))
                            }
                            HStack(spacing: 0.5) {
                                RoundedRectangle(cornerRadius: 0.5)
                                    .fill(GamingGradients.cgameBrand)
                                    .frame(width: 3, height: 3)
                                    .rotationEffect(.degrees(45))
                                RoundedRectangle(cornerRadius: 0.5)
                                    .fill(GamingGradients.cgameBrand)
                                    .frame(width: 3, height: 3)
                                    .rotationEffect(.degrees(45))
                                RoundedRectangle(cornerRadius: 0.5)
                                    .fill(GamingGradients.cgameBrand)
                                    .frame(width: 3, height: 3)
                                    .rotationEffect(.degrees(45))
                            }
                            HStack(spacing: 0.5) {
                                RoundedRectangle(cornerRadius: 0.5)
                                    .fill(GamingGradients.cgameBrand)
                                    .frame(width: 3, height: 3)
                                    .rotationEffect(.degrees(45))
                                RoundedRectangle(cornerRadius: 0.5)
                                    .fill(GamingGradients.cgameBrand)
                                    .frame(width: 3, height: 3)
                                    .rotationEffect(.degrees(45))
                            }
                        }
                        .padding(.trailing, 8)
                        
                        Text("YOUR HIGHLIGHTS")
                            .font(GamingFonts.title(28))
                            .foregroundStyle(GamingGradients.cgameBrand)
                    }
                    
                    Text("\(viewModel.clips.count) CLIPS CAPTURED")
                        .font(GamingFonts.caption())
                        .foregroundColor(.gamingTextSecondary)
                        .tracking(1)
                }
                
                Spacer()
                
                // Filter/Sort Menu
                Menu {
                    Button("Most Recent", action: { })
                    Button("Longest", action: { })
                    Button("Most Kills", action: { })
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.title2)
                        .foregroundColor(.gamingPrimary)
                }
            }
            .padding(.horizontal)
            
            // Stats Bar
            HStack(spacing: 20) {
                QuickStat(label: "TOTAL", value: "\(viewModel.clips.count)")
                QuickStat(label: "DURATION", value: formatTotalDuration())
                QuickStat(label: "STORAGE", value: formatStorageSize())
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatTotalDuration() -> String {
        let total = viewModel.clips.reduce(0) { $0 + $1.duration }
        let minutes = Int(total) / 60
        return "\(minutes)m"
    }
    
    private func formatStorageSize() -> String {
        // Estimate ~1.5MB per second at 4Mbps
        let total = viewModel.clips.reduce(0) { $0 + $1.duration }
        let mbSize = Int(total * 1.5)
        if mbSize > 1000 {
            return String(format: "%.1fGB", Double(mbSize) / 1000.0)
        }
        return "\(mbSize)MB"
    }
}

// MARK: - Clip Card Component

struct ClipCard: View {
    let clip: Clip
    let onPlay: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail Area
            ZStack {
                // Placeholder Thumbnail
                LinearGradient(
                    colors: [
                        Color.gamingPrimary.opacity(0.3),
                        Color.gamingSecondary.opacity(0.3)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .aspectRatio(16/9, contentMode: .fill)
                
                // Game Icon
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white.opacity(0.3))
                
                // Play Button Overlay
                Button(action: onPlay) {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.6))
                            .frame(width: 50, height: 50)
                        
                        Image(systemName: "play.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                // Duration Badge
                VStack {
                    HStack {
                        Spacer()
                        Text(formatDuration(clip.duration))
                            .font(GamingFonts.caption())
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(6)
                            .padding(8)
                    }
                    Spacer()
                }
            }
            
            // Info Section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    // Event Type
                    Label {
                        Text(clip.events.first ?? "Kill")
                            .font(GamingFonts.body(14))
                            .foregroundColor(.gamingTextPrimary)
                    } icon: {
                        Image(systemName: GamingIcons.kill)
                            .font(.caption)
                            .foregroundColor(.gamingAccent)
                    }
                    
                    Spacer()
                    
                    // Options Menu
                    Menu {
                        Button(action: { }) {
                            Label("Share", systemImage: GamingIcons.share)
                        }
                        Button(action: onDelete, role: .destructive) {
                            Label("Delete", systemImage: GamingIcons.delete)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.caption)
                            .foregroundColor(.gamingTextSecondary)
                    }
                }
                
                // Timestamp
                Text(formatDate(clip.timestamp))
                    .font(GamingFonts.caption())
                    .foregroundColor(.gamingTextTertiary)
            }
            .padding(12)
            .background(Color.gamingCardBackground)
        }
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isHovered ? Color.gamingPrimary.opacity(0.5) : Color.clear,
                    lineWidth: 2
                )
        )
        .shadow(color: Color.black.opacity(0.3), radius: 8, y: 4)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Supporting Views

struct QuickStat: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(GamingFonts.caption())
                .foregroundColor(.gamingTextTertiary)
            
            Text(value)
                .font(GamingFonts.body())
                .foregroundColor(.gamingPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.gamingCardBackground)
        .cornerRadius(8)
    }
}

struct ClipPlayerSheet: View {
    let clip: Clip
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black
                    .ignoresSafeArea()
                
                if let url = clip.localURL {
                    VideoPlayer(player: AVPlayer(url: url))
                        .ignoresSafeArea()
                } else {
                    Text("Video unavailable")
                        .foregroundColor(.white)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.gamingPrimary)
                }
            }
        }
    }
}

#Preview {
    ModernClipsGalleryView()
}