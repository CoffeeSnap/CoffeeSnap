import Foundation
import SwiftUI

@available(iOS 17.0, *)
@MainActor
class CoffeeStore: ObservableObject {
    @Published var coffees: [AnalyzedCoffee] = []
    @Published var favorites: Set<UUID> = []
    @Published var searchText = ""
    @Published var selectedFilter: CoffeeType? = nil
    @Published var isLoading = false
    
    private let vectorDBService = VectorDatabaseService.shared
    
    init() {
        loadSampleData()
        Task {
            await vectorDBService.initialize()
        }
    }
    
    var filteredCoffees: [AnalyzedCoffee] {
        var result = coffees
        
        if !searchText.isEmpty {
            result = result.filter { coffee in
                coffee.coffeeType.rawValue.localizedCaseInsensitiveContains(searchText) ||
                coffee.notes.localizedCaseInsensitiveContains(searchText) ||
                coffee.flavorProfile.flavorNotes.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }
        
        if let filter = selectedFilter {
            result = result.filter { $0.coffeeType == filter }
        }
        
        return result.sorted { $0.analysisDate > $1.analysisDate }
    }
    
    var favoriteCoffees: [AnalyzedCoffee] {
        return coffees.filter { favorites.contains($0.id) }
    }
    
    func addCoffee(_ coffee: AnalyzedCoffee) async {
        coffees.insert(coffee, at: 0)
        
        // Store in vector database for similarity search
        await vectorDBService.storeCoffeeVector(coffee)
    }
    
    func searchSimilarCoffees(to coffee: AnalyzedCoffee, limit: Int = 5) async -> [AnalyzedCoffee] {
        let similarIds = await vectorDBService.findSimilarCoffees(
            flavorProfile: coffee.flavorProfile,
            coffeeType: coffee.coffeeType,
            limit: limit
        )
        
        return coffees.filter { similarIds.contains($0.id) }
    }
    
    func getRecommendationsFor(_ coffee: AnalyzedCoffee) async -> [AnalyzedCoffee] {
        return await searchSimilarCoffees(to: coffee, limit: 3)
    }
    
    func toggleFavorite(_ coffeeId: UUID) {
        if favorites.contains(coffeeId) {
            favorites.remove(coffeeId)
        } else {
            favorites.insert(coffeeId)
        }
        
        // Persist favorites to UserDefaults
        let favoriteIds = Array(favorites).map { $0.uuidString }
        UserDefaults.standard.set(favoriteIds, forKey: "favorite_coffees")
    }
    
    func isFavorite(_ coffeeId: UUID) -> Bool {
        favorites.contains(coffeeId)
    }
    
    func deleteCoffee(_ coffee: AnalyzedCoffee) {
        coffees.removeAll { $0.id == coffee.id }
        favorites.remove(coffee.id)
        
        Task {
            await vectorDBService.deleteCoffeeVector(coffee.id)
        }
    }
    
    func getCoffeeStatistics() -> CoffeeStatistics {
        let typeCount = Dictionary(grouping: coffees, by: { $0.coffeeType })
            .mapValues { $0.count }
        
        let averageRating = coffees.compactMap { $0.rating }.reduce(0, +) / Double(coffees.count)
        let totalCoffees = coffees.count
        let favoritesCount = favorites.count
        
        return CoffeeStatistics(
            totalCoffees: totalCoffees,
            favoritesCount: favoritesCount,
            averageRating: averageRating.isNaN ? 0 : averageRating,
            coffeeTypeDistribution: typeCount
        )
    }
    
    private func loadSampleData() {
        let sampleCoffees = [
            AnalyzedCoffee(
                imageData: nil,
                coffeeType: .espresso,
                confidence: 0.95,
                brewMethod: "Traditional Italian",
                roastLevel: .dark,
                notes: "Rich, intense flavor with hints of chocolate",
                recommendations: ["Serve immediately", "Pair with dark chocolate", "Water temp: 92-96°C"],
                flavorProfile: FlavorProfile(
                    acidity: 0.8,
                    body: 0.9,
                    sweetness: 0.3,
                    bitterness: 0.7,
                    flavorNotes: ["chocolate", "caramel", "nutty"]
                ),
                origin: "Ethiopia",
                rating: 4.5
            ),
            AnalyzedCoffee(
                imageData: nil,
                coffeeType: .latte,
                confidence: 0.88,
                brewMethod: "Steamed milk art",
                roastLevel: .medium,
                notes: "Smooth and creamy with perfect milk integration",
                recommendations: ["Milk temp: 60-65°C", "Create latte art", "Use whole milk"],
                flavorProfile: FlavorProfile(
                    acidity: 0.4,
                    body: 0.7,
                    sweetness: 0.8,
                    bitterness: 0.3,
                    flavorNotes: ["vanilla", "caramel", "milk chocolate"]
                ),
                origin: "Brazil",
                rating: 4.2
            ),
            AnalyzedCoffee(
                imageData: nil,
                coffeeType: .pourOver,
                confidence: 0.92,
                brewMethod: "V60 pour over",
                roastLevel: .light,
                notes: "Bright and fruity with floral aromatics",
                recommendations: ["Use paper filter", "Circular pour technique", "Medium-fine grind"],
                flavorProfile: FlavorProfile(
                    acidity: 0.9,
                    body: 0.5,
                    sweetness: 0.6,
                    bitterness: 0.2,
                    flavorNotes: ["citrus", "floral", "berry", "bright"]
                ),
                origin: "Kenya",
                rating: 4.7
            )
        ]
        
        coffees = sampleCoffees
        loadFavorites()
    }
    
    private func loadFavorites() {
        let savedFavorites = UserDefaults.standard.stringArray(forKey: "favorite_coffees") ?? []
        favorites = Set(savedFavorites.compactMap { UUID(uuidString: $0) })
    }
}

// MARK: - Coffee Statistics
struct CoffeeStatistics {
    let totalCoffees: Int
    let favoritesCount: Int
    let averageRating: Double
    let coffeeTypeDistribution: [CoffeeType: Int]
    
    var mostPopularType: CoffeeType? {
        coffeeTypeDistribution.max { $0.value < $1.value }?.key
    }
}
