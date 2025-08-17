import SwiftUI

struct Diamond: View {
    var size: CGFloat = 8
    
    var body: some View {
        Rectangle()
            .frame(width: size, height: size)
            .rotationEffect(.degrees(45))
    }
}

struct DiamondPattern: View {
    var size: CGFloat = 6
    var spacing: CGFloat = 2
    
    var body: some View {
        VStack(spacing: spacing) {
            HStack(spacing: spacing) {
                Diamond(size: size)
                Diamond(size: size)
            }
            HStack(spacing: spacing) {
                Diamond(size: size)
                Diamond(size: size)
            }
        }
    }
}