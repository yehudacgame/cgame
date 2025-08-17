import SwiftUI

struct ClipsGalleryView: View {
    @StateObject private var clipsViewModel = ClipsViewModel()
    @State private var showingCompileView = false
    
    private let columns = Array(repeating: GridItem(.flexible()), count: 2)
    
    var body: some View {
        NavigationView {
            VStack {
                if clipsViewModel.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                            .scaleEffect(1.5)
                        
                        Text("Processing videos...")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Creating highlight clips from your gameplay")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else if clipsViewModel.clips.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("No clips yet")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Start recording gameplay to capture highlights")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(clipsViewModel.clips) { clip in
                                ClipGridItemView(clip: clip)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("My Clips")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Compile Highlights") {
                            showingCompileView = true
                        }
                        
                        Button("Refresh") {
                            clipsViewModel.loadClips()
                        }
                        
                        Button("Upload All") {
                            // TODO: Implement upload functionality
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .onAppear {
                clipsViewModel.loadClips()
            }
            .refreshable {
                clipsViewModel.loadClips()
            }
        }
        .sheet(isPresented: $showingCompileView) {
            CompileHighlightsView(clips: clipsViewModel.clips)
        }
    }
}

struct ClipGridItemView: View {
    let clip: Clip
    @State private var showingPlayerView = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(16/9, contentMode: .fit)
                
                if let thumbnailURL = clip.thumbnailURL {
                    AsyncImage(url: URL(string: thumbnailURL)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                    }
                    .clipped()
                    .cornerRadius(12)
                }
                
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("\(Int(clip.duration))s")
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.7))
                            .foregroundColor(.white)
                            .cornerRadius(4)
                            .padding(.trailing, 8)
                            .padding(.bottom, 8)
                    }
                }
                
                Button(action: {
                    showingPlayerView = true
                }) {
                    Image(systemName: "play.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(clip.eventDescription)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                
                Text(clip.game)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text(clip.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .sheet(isPresented: $showingPlayerView) {
            ClipPlayerView(clip: clip)
        }
    }
}