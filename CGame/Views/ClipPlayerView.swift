import SwiftUI
import AVKit

struct ClipPlayerView: View {
    let clip: Clip
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    
    var body: some View {
        NavigationView {
            VStack {
                if let player = player {
                    VideoPlayer(player: player)
                        .onAppear {
                            player.play()
                        }
                        .onDisappear {
                            player.pause()
                        }
                } else {
                    VStack {
                        ProgressView("Loading video...")
                        Text("Preparing your highlight")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(clip.eventDescription)
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Text(clip.game)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text("\(Int(clip.duration))s")
                            .font(.headline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(8)
                    }
                    
                    Text("Captured \(clip.timestamp.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if !clip.events.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Events")
                                .font(.headline)
                            
                            ForEach(clip.events.indices, id: \.self) { index in
                                HStack {
                                    Image(systemName: "target")
                                        .foregroundColor(.red)
                                    Text(clip.events[index])
                                    Spacer()
                                }
                                .font(.subheadline)
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.systemGroupedBackground))
                
                Spacer()
            }
            .navigationTitle("Clip Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Share") {
                        shareClip()
                    }
                }
            }
        }
        .onAppear {
            setupPlayer()
        }
    }
    
    private func setupPlayer() {
        if let localURL = clip.localURL {
            player = AVPlayer(url: localURL)
        } else if let storageURL = URL(string: clip.storagePath) {
            player = AVPlayer(url: storageURL)
        }
    }
    
    private func shareClip() {
        // TODO: Implement sharing functionality
        print("Sharing clip: \(clip.id)")
    }
}