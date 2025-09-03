import SwiftUI

struct AppColor {
    // Primary brand colors
    static let primary = Color("PrimaryColor")
    static let secondary = Color("SecondaryColor")
    static let accent = Color("AccentColor")
    
    // Coffee-themed colors
    static let coffeeBean = Color(red: 0.4, green: 0.2, blue: 0.1)
    static let espresso = Color(red: 0.2, green: 0.1, blue: 0.05)
    static let latte = Color(red: 0.8, green: 0.7, blue: 0.6)
    static let cappuccino = Color(red: 0.7, green: 0.5, blue: 0.3)
    static let caramel = Color(red: 0.9, green: 0.6, blue: 0.2)
    static let cream = Color(red: 0.95, green: 0.93, blue: 0.87)
    
    // Semantic colors
    static let success = Color.green
    static let warning = Color.orange
    static let error = Color.red
    static let info = Color.blue
    
    // Background colors
    static let background = Color(UIColor.systemBackground)
    static let secondaryBackground = Color(UIColor.secondarySystemBackground)
    static let tertiaryBackground = Color(UIColor.tertiarySystemBackground)
    
    // Text colors
    static let primaryText = Color(UIColor.label)
    static let secondaryText = Color(UIColor.secondaryLabel)
    static let tertiaryText = Color(UIColor.tertiaryLabel)
    
    // Component colors
    static let cardBackground = Color(UIColor.systemBackground)
    static let cardBorder = Color(UIColor.separator)
    static let buttonBackground = coffeeBean
    static let buttonText = Color.white
    
    // Gradients
    static let primaryGradient = LinearGradient(
        colors: [coffeeBean, espresso],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let warmGradient = LinearGradient(
        colors: [caramel, cappuccino],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let creamGradient = LinearGradient(
        colors: [cream, latte],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // Coffee strength colors
    static func strengthColor(for strength: CoffeeStrength) -> Color {
        switch strength {
        case .light:
            return latte
        case .medium:
            return cappuccino
        case .strong:
            return coffeeBean
        case .extraStrong:
            return espresso
        }
    }
    
    // Roast level colors
    static func roastColor(for roast: RoastLevel) -> Color {
        switch roast {
        case .light:
            return caramel
        case .medium:
            return cappuccino
        case .mediumDark:
            return coffeeBean
        case .dark:
            return espresso
        }
    }
}

// MARK: - Color Extensions
extension Color {
    // Custom color initializers
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    // Adaptive colors for light/dark mode
    static let adaptiveBackground = Color(UIColor { traitCollection in
        return traitCollection.userInterfaceStyle == .dark ? 
            UIColor.systemBackground : UIColor.systemBackground
    })
    
    static let adaptiveCardBackground = Color(UIColor { traitCollection in
        return traitCollection.userInterfaceStyle == .dark ? 
            UIColor.secondarySystemBackground : UIColor.systemBackground
    })
    
    // Shadow colors
    static let shadowColor = Color.black.opacity(0.1)
    static let darkShadowColor = Color.black.opacity(0.3)
}

// MARK: - Gradient Styles
struct GradientStyle {
    static let card = LinearGradient(
        colors: [AppColor.cardBackground, AppColor.secondaryBackground],
        startPoint: .top,
        endPoint: .bottom
    )
    
    static let button = LinearGradient(
        colors: [AppColor.coffeeBean, AppColor.espresso],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let header = LinearGradient(
        colors: [AppColor.caramel.opacity(0.8), AppColor.cappuccino.opacity(0.6)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let confidence = LinearGradient(
        colors: [AppColor.success, AppColor.caramel],
        startPoint: .leading,
        endPoint: .trailing
    )
}
