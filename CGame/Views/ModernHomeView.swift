import SwiftUI
import ReplayKit

struct ModernHomeView: View {
    @StateObject private var broadcastManager = BroadcastManager()
    @State private var isRecording = false
    @State private var showingBroadcastPicker = false
    @State private var recordingDuration: TimeInterval = 0
    @State private var timer: Timer?
    @State private var killCount = 0
    @State private var showKillAnimation = false
    
    var body: some View {
        ZStack {
            // Gaming Background
            backgroundGradient
            
            VStack(spacing: 30) {
                // Header
                headerView
                
                Spacer()
                
                // Main Recording Interface
                recordingInterface
                
                // Stats Row
                if isRecording {
                    statsRow
                        .transition(.scale.combined(with: .opacity))
                }
                
                Spacer()
                
                // Action Buttons
                actionButtons
            }
            .padding()
            
            // Kill Animation Overlay
            if showKillAnimation {
                KillAnimationView()
                    .zIndex(100)
            }
        }
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            stopRecordingIfNeeded()
        }
    }
    
    // MARK: - View Components
    
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color.gamingBackground,
                Color.gamingBackground.opacity(0.9),
                Color.gamingPrimary.opacity(0.1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
    
    private var headerView: some View {
        VStack(spacing: 12) {
            // CGame Logo Header
            HStack {
                // CGame diamond logo pattern
                VStack(spacing: 1) {
                    HStack(spacing: 1) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(LinearGradient(
                                colors: [Color.orange, Color.red],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 6, height: 6)
                            .rotationEffect(.degrees(45))
                    }
                    HStack(spacing: 1) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(LinearGradient(
                                colors: [Color.orange, Color.red],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 6, height: 6)
                            .rotationEffect(.degrees(45))
                        RoundedRectangle(cornerRadius: 1)
                            .fill(LinearGradient(
                                colors: [Color.orange, Color.red],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 6, height: 6)
                            .rotationEffect(.degrees(45))
                        RoundedRectangle(cornerRadius: 1)
                            .fill(LinearGradient(
                                colors: [Color.orange, Color.red],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 6, height: 6)
                            .rotationEffect(.degrees(45))
                    }
                    HStack(spacing: 1) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(LinearGradient(
                                colors: [Color.orange, Color.red],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 6, height: 6)
                            .rotationEffect(.degrees(45))
                        RoundedRectangle(cornerRadius: 1)
                            .fill(LinearGradient(
                                colors: [Color.orange, Color.red],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 6, height: 6)
                            .rotationEffect(.degrees(45))
                    }
                }
                .padding(.trailing, 8)
                
                Text("CGAME")
                    .font(GamingFonts.title(32))
                    .foregroundStyle(LinearGradient(
                        colors: [Color.orange, Color.red],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
            }
            
            Text("COD KILL DETECTION")
                .font(GamingFonts.caption(14))
                .foregroundColor(.gamingTextSecondary)
                .tracking(3)
        }
        .padding(.top, 20)
    }
    
    private var recordingInterface: some View {
        VStack(spacing: 25) {
            // Recording Status Circle
            ZStack {
                // Outer Ring
                Circle()
                    .stroke(
                        isRecording ? Color.gamingDanger : Color.gamingPrimary.opacity(0.3),
                        lineWidth: 4
                    )
                    .frame(width: 200, height: 200)
                
                // Animated Pulse Ring
                if isRecording {
                    Circle()
                        .stroke(Color.gamingDanger.opacity(0.5), lineWidth: 2)
                        .frame(width: 200, height: 200)
                        .scaleEffect(1.2)
                        .opacity(0)
                        .animation(
                            Animation.easeOut(duration: 1.5)
                                .repeatForever(autoreverses: false),
                            value: isRecording
                        )
                }
                
                // Center Button
                Button(action: toggleRecording) {
                    ZStack {
                        // Gradient background circle
                        Circle()
                            .fill(
                                isRecording ? 
                                GamingGradients.danger :
                                GamingGradients.primary
                            )
                            .frame(width: 160, height: 160)
                        
                        VStack(spacing: 8) {
                            // CGame Logo-inspired diamond pattern or simple icon
                            if isRecording {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.white)
                            } else {
                                // Diamond pattern inspired by CGame logo
                                VStack(spacing: 2) {
                                    HStack(spacing: 2) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(.white)
                                            .frame(width: 8, height: 8)
                                            .rotationEffect(.degrees(45))
                                    }
                                    HStack(spacing: 2) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(.white)
                                            .frame(width: 8, height: 8)
                                            .rotationEffect(.degrees(45))
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(.white)
                                            .frame(width: 8, height: 8)
                                            .rotationEffect(.degrees(45))
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(.white)
                                            .frame(width: 8, height: 8)
                                            .rotationEffect(.degrees(45))
                                    }
                                    HStack(spacing: 2) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(.white)
                                            .frame(width: 8, height: 8)
                                            .rotationEffect(.degrees(45))
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(.white)
                                            .frame(width: 8, height: 8)
                                            .rotationEffect(.degrees(45))
                                    }
                                }
                                .scaleEffect(1.5)
                            }
                            
                            Text(isRecording ? "RECORDING" : "START DETECTION")
                                .font(GamingFonts.body(12))
                                .foregroundColor(.white)
                                .tracking(1)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .scaleEffect(isRecording ? 1.0 : 1.0)
                .animation(.spring(response: 0.5, dampingFraction: 0.6), value: isRecording)
            }
            .glowEffect(
                color: isRecording ? .gamingDanger : .gamingPrimary,
                radius: isRecording ? 20 : 10
            )
            
            // Recording Timer
            if isRecording {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.gamingDanger)
                        .frame(width: 10, height: 10)
                        .opacity(recordingDuration.truncatingRemainder(dividingBy: 2) < 1 ? 1 : 0.3)
                        .animation(.easeInOut(duration: 0.5).repeatForever(), value: recordingDuration)
                    
                    Text(formatDuration(recordingDuration))
                        .font(GamingFonts.heading())
                        .foregroundColor(.gamingTextPrimary)
                        .monospacedDigit()
                }
            }
        }
    }
    
    private var statsRow: some View {
        HStack(spacing: 30) {
            StatCard(
                icon: GamingIcons.kill,
                value: "\(killCount)",
                label: "KILLS",
                color: .gamingAccent
            )
            
            StatCard(
                icon: GamingIcons.clips,
                value: "\(broadcastManager.sessionClipCount)",
                label: "CLIPS",
                color: .gamingPrimary
            )
            
            StatCard(
                icon: GamingIcons.trophy,
                value: "2.5",
                label: "K/D",
                color: .gamingWarning
            )
        }
        .padding(.horizontal)
    }
    
    private var actionButtons: some View {
        HStack(spacing: 20) {
            // Game Launch Button
            Button(action: launchGame) {
                HStack {
                    Image(systemName: "gamecontroller.fill")
                    Text("LAUNCH COD")
                }
                .font(GamingFonts.body())
            }
            .buttonStyle(GamingOutlineButtonStyle(color: .gamingPrimary))
            
            // Settings Button
            Button(action: openSettings) {
                HStack {
                    Image(systemName: GamingIcons.settings)
                    Text("SETTINGS")
                }
                .font(GamingFonts.body())
            }
            .buttonStyle(GamingOutlineButtonStyle(color: .gamingTextSecondary))
        }
        .padding(.bottom, 30)
    }
    
    // MARK: - Actions
    
    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        showingBroadcastPicker = true
        
        // Start the broadcast picker
        let picker = RPSystemBroadcastPickerView(frame: .zero)
        picker.preferredExtension = "com.cgameapp.app.extension"
        picker.showsMicrophoneButton = false
        
        // Trigger the picker programmatically
        for subview in picker.subviews {
            if let button = subview as? UIButton {
                button.sendActions(for: .allTouchEvents)
            }
        }
        
        isRecording = true
        recordingDuration = 0
        killCount = 0
        
        // Start timer
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            recordingDuration += 1
        }
    }
    
    private func stopRecording() {
        isRecording = false
        timer?.invalidate()
        timer = nil
        broadcastManager.stopBroadcast()
    }
    
    private func stopRecordingIfNeeded() {
        if isRecording {
            stopRecording()
        }
    }
    
    private func launchGame() {
        // Try to open Call of Duty Mobile
        if let url = URL(string: "codmobile://") {
            UIApplication.shared.open(url) { success in
                if !success {
                    // Fallback to App Store
                    if let appStoreURL = URL(string: "https://apps.apple.com/app/call-of-duty-mobile/id1287282214") {
                        UIApplication.shared.open(appStoreURL)
                    }
                }
            }
        }
    }
    
    private func openSettings() {
        // Navigation to settings will be handled by parent view
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)
            
            Text(value)
                .font(GamingFonts.heading())
                .foregroundColor(.gamingTextPrimary)
            
            Text(label)
                .font(GamingFonts.caption())
                .foregroundColor(.gamingTextSecondary)
                .tracking(1)
        }
        .frame(width: 80)
        .padding(.vertical, 12)
        .gamingCard()
    }
}

struct KillAnimationView: View {
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 1.0
    
    var body: some View {
        VStack {
            Image(systemName: "flame.fill")
                .font(.system(size: 80))
                .foregroundStyle(GamingGradients.accent)
            
            Text("ELIMINATED!")
                .font(GamingFonts.title())
                .foregroundStyle(GamingGradients.accent)
                .tracking(2)
        }
        .scaleEffect(scale)
        .opacity(opacity)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                scale = 1.2
            }
            
            withAnimation(.easeOut(duration: 0.8).delay(0.5)) {
                opacity = 0
                scale = 1.5
            }
        }
    }
}

#Preview {
    ModernHomeView()
}