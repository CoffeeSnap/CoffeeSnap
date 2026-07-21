import SwiftUI

@available(iOS 17.0, *)
@main
struct CoffeeSnapAIApp: App {
    @StateObject private var coffeeStore = CoffeeStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coffeeStore)
        }
    }
}
