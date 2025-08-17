import SwiftUI

// MARK: - Gaming Color Palette
extension Color {
    // Primary Gaming Colors - CGame branding
    static let gamingPrimary = Color.orange                               // CGame orange
    static let gamingSecondary = Color(red: 1.0, green: 0.2, blue: 0.4)   // Red/Pink  
    static let gamingAccent = Color(red: 0.4, green: 1.0, blue: 0.6)      // Green
    static let cgameOrange = Color.orange                                 // CGame brand color
    
    // Background Colors
    static let gamingBackground = Color(red: 0.05, green: 0.05, blue: 0.1)
    static let gamingCardBackground = Color(red: 0.1, green: 0.1, blue: 0.15)
    static let gamingCardHighlight = Color(red: 0.15, green: 0.15, blue: 0.2)
    
    // Status Colors
    static let gamingSuccess = Color(red: 0.2, green: 1.0, blue: 0.4)
    static let gamingWarning = Color(red: 1.0, green: 0.8, blue: 0.2)
    static let gamingDanger = Color(red: 1.0, green: 0.3, blue: 0.3)
    
    // Text Colors
    static let gamingTextPrimary = Color.white
    static let gamingTextSecondary = Color.white.opacity(0.7)
    static let gamingTextTertiary = Color.white.opacity(0.5)
}

// MARK: - Gaming Gradients
struct GamingGradients {
    static let primary = LinearGradient(
        colors: [Color.orange, Color.red],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let cgameBrand = LinearGradient(
        colors: [Color.orange, Color.red],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let accent = LinearGradient(
        colors: [Color.gamingAccent, Color.gamingPrimary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let danger = LinearGradient(
        colors: [Color.gamingDanger, Color.gamingSecondary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let card = LinearGradient(
        colors: [Color.gamingCardHighlight, Color.gamingCardBackground],
        startPoint: .top,
        endPoint: .bottom
    )
    
    static let shimmer = LinearGradient(
        colors: [
            Color.white.opacity(0.0),
            Color.white.opacity(0.1),
            Color.white.opacity(0.0)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
}

// MARK: - Gaming Fonts
struct GamingFonts {
    static func title(_ size: CGFloat = 34) -> Font {
        Font.system(size: size, weight: .black, design: .rounded)
    }
    
    static func heading(_ size: CGFloat = 24) -> Font {
        Font.system(size: size, weight: .bold, design: .rounded)
    }
    
    static func body(_ size: CGFloat = 16) -> Font {
        Font.system(size: size, weight: .medium, design: .rounded)
    }
    
    static func caption(_ size: CGFloat = 12) -> Font {
        Font.system(size: size, weight: .regular, design: .rounded)
    }
}

// MARK: - Gaming Visual Effects
struct GlowEffect: ViewModifier {
    let color: Color
    let radius: CGFloat
    
    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.6), radius: radius)
            .shadow(color: color.opacity(0.4), radius: radius * 2)
            .shadow(color: color.opacity(0.2), radius: radius * 3)
    }
}

struct NeonBorder: ViewModifier {
    let color: Color
    let width: CGFloat
    
    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(color, lineWidth: width)
                    .shadow(color: color, radius: 5)
            )
    }
}

struct PulseAnimation: ViewModifier {
    @State private var scale: CGFloat = 1.0
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onAppear {
                withAnimation(
                    Animation.easeInOut(duration: 1.0)
                        .repeatForever(autoreverses: true)
                ) {
                    scale = 1.05
                }
            }
    }
}

// MARK: - View Extensions
extension View {
    func glowEffect(color: Color = .gamingPrimary, radius: CGFloat = 10) -> some View {
        modifier(GlowEffect(color: color, radius: radius))
    }
    
    func neonBorder(color: Color = .gamingPrimary, width: CGFloat = 2) -> some View {
        modifier(NeonBorder(color: color, width: width))
    }
    
    func pulseAnimation() -> some View {
        modifier(PulseAnimation())
    }
    
    func gamingCard() -> some View {
        self
            .background(GamingGradients.card)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Gaming Button Styles
struct GamingButtonStyle: ButtonStyle {
    let color: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: configuration.isPressed ? 
                        [color.opacity(0.8), color.opacity(0.6)] :
                        [color, color.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .foregroundColor(.white)
            .cornerRadius(12)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .shadow(
                color: color.opacity(configuration.isPressed ? 0.3 : 0.5),
                radius: configuration.isPressed ? 5 : 10,
                y: configuration.isPressed ? 2 : 5
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct GamingOutlineButtonStyle: ButtonStyle {
    let color: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color.clear)
            .foregroundColor(color)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(color, lineWidth: 2)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Gaming Icons
struct GamingIcons {
    static let record = "record.circle.fill"
    static let stop = "stop.circle.fill"
    static let play = "play.circle.fill"
    static let pause = "pause.circle.fill"
    static let clips = "film.stack"
    static let settings = "gearshape.fill"
    static let trophy = "trophy.fill"
    static let target = "scope"
    static let kill = "flame.fill"
    static let stats = "chart.bar.fill"
    static let share = "square.and.arrow.up"
    static let delete = "trash.fill"
}