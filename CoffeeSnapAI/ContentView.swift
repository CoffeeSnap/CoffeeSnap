import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: CoffeeStore
    @State private var selection: AppSection = .memory

    var body: some View {
        TabView(selection: $selection) {
            MemoryHomeView()
                .tabItem { Label("Memory", systemImage: "sparkles") }
                .tag(AppSection.memory)

            DiscoverView()
                .tabItem { Label("Discover", systemImage: "scope") }
                .tag(AppSection.discover)

            LearningLabView()
                .tabItem { Label("Taste Lab", systemImage: "brain.head.profile") }
                .badge(store.dashboard.dueCards.count)
                .tag(AppSection.learn)

            CoffeeJournalView()
                .tabItem { Label("Journal", systemImage: "books.vertical.fill") }
                .tag(AppSection.journal)
        }
        .tint(CoffeeTheme.caramel)
        .task { await store.start() }
        .fullScreenCover(isPresented: Binding(
            get: { store.needsCalibration },
            set: { _ in }
        )) {
            TasteCalibrationView(isOnboarding: true)
                .interactiveDismissDisabled()
        }
        .alert(
            "Taste memory needs attention",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.clearError() } }
            )
        ) {
            Button("OK") { store.clearError() }
        } message: {
            Text(store.errorMessage ?? "Unknown error")
        }
        .overlay {
            if store.isLoading {
                ZStack {
                    Color.black.opacity(0.12).ignoresSafeArea()
                    ProgressView("Building your taste memory…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                }
            }
        }
    }
}

private enum AppSection: Hashable {
    case memory, discover, learn, journal
}

enum CoffeeTheme {
    static let espresso = Color(red: 0.12, green: 0.075, blue: 0.05)
    static let roast = Color(red: 0.29, green: 0.16, blue: 0.10)
    static let caramel = Color(red: 0.86, green: 0.48, blue: 0.16)
    static let crema = Color(red: 0.96, green: 0.82, blue: 0.61)
    static let sage = Color(red: 0.32, green: 0.53, blue: 0.42)
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
}

#Preview {
    ContentView()
        .environmentObject(CoffeeStore())
}
