import SwiftUI
import ReplayKit

struct BroadcastPickerView: UIViewRepresentable {
    let completion: (Bool) -> Void
    
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        
        // Filter to show only the new CGame broadcast extension
        picker.preferredExtension = "com.cgameapp.app.CGameExtension"
        picker.showsMicrophoneButton = false
        
        // Don't hide the button - let it show normally for testing
        // hideSystemButton(in: picker)
        
        return picker
    }
    
    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {
        // Don't hide the button for testing
        // hideSystemButton(in: uiView)
    }
    
    private func hideSystemButton(in picker: RPSystemBroadcastPickerView) {
        for subview in picker.subviews {
            if let button = subview as? UIButton {
                // Hide only the visual appearance, not the button itself
                button.setImage(UIImage(), for: .normal)
                button.setTitle("", for: .normal)
                button.backgroundColor = .clear
                button.tintColor = .clear
                
                // Hide any image views within the button
                for buttonSubview in button.subviews {
                    if let imageView = buttonSubview as? UIImageView {
                        imageView.isHidden = true
                    }
                }
            }
        }
    }
}

// MARK: - Extension Selection Helper View
struct ExtensionSelectionGuide: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(.blue)
                .font(.title2)
            
            Text("Select CGame AI Recorder")
                .font(.headline)
                .fontWeight(.semibold)
            
            Text("If multiple options appear, make sure to select 'CGame AI Recorder' for kill detection to work properly.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}