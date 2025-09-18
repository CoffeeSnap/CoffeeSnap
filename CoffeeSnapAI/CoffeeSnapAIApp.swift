import SwiftUI

@available(iOS 17.0, *)
@main
struct CoffeeSnapAIApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// Basic structure for eventual expansion
@available(iOS 17.0, *)
struct UserPreferences {
    var preferredStrength: String = "medium"
    var preferredRoast: String = "medium"
    var favoriteOrigins: [String] = []
}
