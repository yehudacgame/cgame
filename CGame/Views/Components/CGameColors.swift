import SwiftUI

extension Color {
    // CGame Brand Colors based on logo
    static let cgameOrange = Color(red: 1.0, green: 0.6, blue: 0.2)
    static let cgameRed = Color(red: 1.0, green: 0.4, blue: 0.4)
    static let cgameNavy = Color(red: 0.15, green: 0.25, blue: 0.45)
    static let cgameNavyLight = Color(red: 0.25, green: 0.35, blue: 0.55)
    
    // Brand Gradients
    static let cgamePrimaryGradient = LinearGradient(
        gradient: Gradient(colors: [cgameRed, cgameOrange]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let cgameNavyGradient = LinearGradient(
        gradient: Gradient(colors: [cgameNavy, cgameNavyLight]),
        startPoint: .leading,
        endPoint: .trailing
    )
    
    static let cgameActiveGradient = LinearGradient(
        gradient: Gradient(colors: [Color(red: 1.0, green: 0.3, blue: 0.3), Color(red: 0.8, green: 0.2, blue: 0.2)]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let cgameSuccessGradient = LinearGradient(
        gradient: Gradient(colors: [Color(red: 0.3, green: 0.8, blue: 0.3), Color(red: 0.2, green: 0.7, blue: 0.2)]),
        startPoint: .leading,
        endPoint: .trailing
    )
}

// Custom Button Styles
struct CGamePrimaryButtonStyle: ButtonStyle {
    let isActive: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                isActive ? Color.cgameActiveGradient : Color.cgamePrimaryGradient
            )
            .foregroundColor(.white)
            .cornerRadius(15)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct CGameSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .background(Color.cgameNavyGradient)
            .foregroundColor(.white)
            .cornerRadius(10)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// Custom Views
struct CGameLogo: View {
    var size: CGFloat = 100
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.cgamePrimaryGradient)
                .frame(width: size, height: size)
            
            DiamondPattern(size: size * 0.08, spacing: size * 0.02)
                .foregroundColor(.white)
        }
    }
}

struct CGameStatusBadge: View {
    let text: String
    let isActive: Bool
    
    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                isActive ? Color.cgameActiveGradient : Color.cgameSuccessGradient
            )
            .cornerRadius(8)
    }
}