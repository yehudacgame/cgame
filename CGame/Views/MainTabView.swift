import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var authService: AuthService
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Image(systemName: "target")
                    Text("Detector")
                }
                .tag(0)
            
            LocalClipsGalleryView()
                .tabItem {
                    Image(systemName: "video.fill")
                    Text("Clips")
                }
                .tag(1)
            
            CODSettingsView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }
                .tag(2)
        }
        .preferredColorScheme(.dark)
        .accentColor(.blue) // Use standard blue for now
    }
}