import SwiftUI
import CoreML
import Vision

@main
struct CoffeeSnapAIApp: App {
    @StateObject private var coffeeStore = CoffeeStore()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                ContentView()
                    .environmentObject(coffeeStore)
            } else {
                OnboardingView()
                    .environmentObject(coffeeStore)
            }
        }
    }
}

// MARK: - Coffee Store
class CoffeeStore: ObservableObject {
    @Published var analyzedCoffees: [AnalyzedCoffee] = []
    @Published var favoriteBrewMethods: [String] = []
    @Published var coffeePreferences: CoffeePreferences = CoffeePreferences()
    
    func addAnalyzedCoffee(_ coffee: AnalyzedCoffee) {
        analyzedCoffees.insert(coffee, at: 0)
    }
    
    func toggleFavorite(method: String) {
        if favoriteBrewMethods.contains(method) {
            favoriteBrewMethods.removeAll { $0 == method }
        } else {
            favoriteBrewMethods.append(method)
        }
    }
}

// MARK: - Coffee Preferences
struct CoffeePreferences {
    var preferredStrength: CoffeeStrength = .medium
    var preferredRoast: RoastLevel = .medium
    var dailyCoffeeGoal: Int = 2
    var preferredBrewTime: String = "Morning"
}

enum CoffeeStrength: String, CaseIterable {
    case light = "Light"
    case medium = "Medium"
    case strong = "Strong"
    case extraStrong = "Extra Strong"
}

enum RoastLevel: String, CaseIterable {
    case light = "Light Roast"
    case medium = "Medium Roast"
    case mediumDark = "Medium Dark"
    case dark = "Dark Roast"
}
