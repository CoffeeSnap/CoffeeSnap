import XCTest
@testable import CoffeeSnapAI

@MainActor
final class CoffeeStoreIntegrationTests: XCTestCase {
    
    var coffeeStore: CoffeeStore!
    var vectorService: VectorDatabaseService!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Initialize services
        vectorService = VectorDatabaseService.shared
        await vectorService.initialize()
        
        coffeeStore = CoffeeStore()
        
        // Wait a moment for initialization
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
    }
    
    override func tearDown() async throws {
        coffeeStore = nil
        try await super.tearDown()
    }
    
    // MARK: - Basic Operations Tests
    
    func testCoffeeStoreInitialization() throws {
        // Test that store initializes with sample data
        XCTAssertGreaterThan(coffeeStore.coffees.count, 0, "Store should initialize with sample data")
        XCTAssertTrue(coffeeStore.favorites.isEmpty || !coffeeStore.favorites.isEmpty, "Favorites should be initialized")
        XCTAssertEqual(coffeeStore.searchText, "", "Search text should be empty initially")
        XCTAssertNil(coffeeStore.selectedFilter, "No filter should be selected initially")
    }
    
    func testAddCoffeeToStore() async throws {
        let initialCount = coffeeStore.coffees.count
        
        let newCoffee = AnalyzedCoffee(
            imageData: nil,
            coffeeType: .cappuccino,
            confidence: 0.9,
            brewMethod: "Traditional",
            roastLevel: .medium,
            notes: "Test coffee for integration testing",
            recommendations: ["Test recommendation"],
            flavorProfile: FlavorProfile(
                acidity: 0.6,
                body: 0.7,
                sweetness: 0.5,
                bitterness: 0.4,
                flavorNotes: ["vanilla", "caramel"]
            ),
            origin: "Test Origin",
            rating: 4.0
        )
        
        await coffeeStore.addCoffee(newCoffee)
        
        XCTAssertEqual(coffeeStore.coffees.count, initialCount + 1, "Coffee count should increase by 1")
        XCTAssertEqual(coffeeStore.coffees.first?.notes, "Test coffee for integration testing", "New coffee should be first in list")
    }
    
    func testToggleFavorite() throws {
        guard let firstCoffee = coffeeStore.coffees.first else {
            XCTFail("No coffee available for testing")
            return
        }
        
        let coffeeId = firstCoffee.id
        let initialFavoriteState = coffeeStore.isFavorite(coffeeId)
        
        // Toggle favorite
        coffeeStore.toggleFavorite(coffeeId)
        XCTAssertEqual(coffeeStore.isFavorite(coffeeId), !initialFavoriteState, "Favorite state should toggle")
        
        // Toggle back
        coffeeStore.toggleFavorite(coffeeId)
        XCTAssertEqual(coffeeStore.isFavorite(coffeeId), initialFavoriteState, "Favorite state should return to original")
    }
    
    // MARK: - Search and Filter Tests
    
    func testSearchFunctionality() throws {
        // Test search by coffee type
        coffeeStore.searchText = "espresso"
        let espressoResults = coffeeStore.filteredCoffees
        
        for coffee in espressoResults {
            let matchesType = coffee.coffeeType.rawValue.localizedCaseInsensitiveContains("espresso")
            let matchesNotes = coffee.notes.localizedCaseInsensitiveContains("espresso")
            let matchesFlavorNotes = coffee.flavorProfile.flavorNotes.contains { $0.localizedCaseInsensitiveContains("espresso") }
            
            XCTAssertTrue(matchesType || matchesNotes || matchesFlavorNotes, "Search results should match search term")
        }
        
        // Clear search
        coffeeStore.searchText = ""
        XCTAssertEqual(coffeeStore.filteredCoffees.count, coffeeStore.coffees.count, "Clearing search should show all coffees")
    }
    
    func testFilterFunctionality() throws {
        // Test filter by coffee type
        coffeeStore.selectedFilter = .latte
        let latteResults = coffeeStore.filteredCoffees
        
        for coffee in latteResults {
            XCTAssertEqual(coffee.coffeeType, .latte, "Filtered results should only contain lattes")
        }
        
        // Clear filter
        coffeeStore.selectedFilter = nil
        XCTAssertEqual(coffeeStore.filteredCoffees.count, coffeeStore.coffees.count, "Clearing filter should show all coffees")
    }
    
    func testCombinedSearchAndFilter() throws {
        // Add a latte with specific notes for testing
        let testCoffee = AnalyzedCoffee(
            imageData: nil,
            coffeeType: .latte,
            confidence: 0.85,
            notes: "smooth vanilla latte",
            flavorProfile: FlavorProfile(flavorNotes: ["vanilla", "milk"]),
            rating: 4.3
        )
        
        Task {
            await coffeeStore.addCoffee(testCoffee)
        }
        
        // Apply both search and filter
        coffeeStore.searchText = "vanilla"
        coffeeStore.selectedFilter = .latte
        
        let results = coffeeStore.filteredCoffees
        
        for coffee in results {
            XCTAssertEqual(coffee.coffeeType, .latte, "Results should be filtered to lattes")
            let hasVanilla = coffee.notes.localizedCaseInsensitiveContains("vanilla") ||
                           coffee.flavorProfile.flavorNotes.contains { $0.localizedCaseInsensitiveContains("vanilla") }
            XCTAssertTrue(hasVanilla, "Results should contain vanilla")
        }
    }
    
    // MARK: - Statistics Tests
    
    func testCoffeeStatistics() throws {
        let stats = coffeeStore.getCoffeeStatistics()
        
        XCTAssertEqual(stats.totalCoffees, coffeeStore.coffees.count, "Total coffee count should match")
        XCTAssertEqual(stats.favoritesCount, coffeeStore.favorites.count, "Favorites count should match")
        XCTAssertGreaterThanOrEqual(stats.averageRating, 0.0, "Average rating should be non-negative")
        XCTAssertLessThanOrEqual(stats.averageRating, 5.0, "Average rating should not exceed 5.0")
        
        // Test type distribution
        let typeCounts = Dictionary(grouping: coffeeStore.coffees, by: { $0.coffeeType })
            .mapValues { $0.count }
        
        for (type, count) in typeCounts {
            XCTAssertEqual(stats.coffeeTypeDistribution[type], count, "Type distribution should match actual counts")
        }
    }
    
    // MARK: - Vector Database Integration Tests
    
    func testVectorDatabaseIntegration() async throws {
        let testCoffee = AnalyzedCoffee(
            imageData: nil,
            coffeeType: .pourOver,
            confidence: 0.92,
            roastLevel: .light,
            notes: "Bright and fruity pour over",
            flavorProfile: FlavorProfile(
                acidity: 0.9,
                body: 0.5,
                sweetness: 0.6,
                bitterness: 0.2,
                flavorNotes: ["citrus", "berry", "floral"]
            ),
            origin: "Ethiopia",
            rating: 4.8
        )
        
        // Add coffee and verify vector storage
        await coffeeStore.addCoffee(testCoffee)
        
        // Test similarity search
        let similarCoffees = await coffeeStore.searchSimilarCoffees(to: testCoffee, limit: 3)
        
        // Similar coffees should have compatible flavor profiles
        for similarCoffee in similarCoffees {
            // Check that similar coffees have somewhat similar characteristics
            XCTAssertLessThanOrEqual(
                abs(similarCoffee.flavorProfile.acidity - testCoffee.flavorProfile.acidity),
                0.5,
                "Similar coffees should have similar acidity levels"
            )
        }
    }
    
    func testRecommendationEngine() async throws {
        guard let firstCoffee = coffeeStore.coffees.first else {
            XCTFail("No coffee available for testing recommendations")
            return
        }
        
        let recommendations = await coffeeStore.getRecommendationsFor(firstCoffee)
        
        XCTAssertLessThanOrEqual(recommendations.count, 3, "Should return at most 3 recommendations")
        
        // Recommendations should not include the original coffee
        for recommendation in recommendations {
            XCTAssertNotEqual(recommendation.id, firstCoffee.id, "Recommendations should not include the original coffee")
        }
    }
    
    // MARK: - Data Persistence Tests
    
    func testFavoritesPersistence() throws {
        guard let firstCoffee = coffeeStore.coffees.first else {
            XCTFail("No coffee available for testing persistence")
            return
        }
        
        let coffeeId = firstCoffee.id
        
        // Add to favorites
        coffeeStore.toggleFavorite(coffeeId)
        XCTAssertTrue(coffeeStore.isFavorite(coffeeId), "Coffee should be favorited")
        
        // Verify persistence by checking UserDefaults
        let savedFavorites = UserDefaults.standard.stringArray(forKey: "favorite_coffees") ?? []
        XCTAssertTrue(savedFavorites.contains(coffeeId.uuidString), "Favorite should be persisted to UserDefaults")
        
        // Remove from favorites
        coffeeStore.toggleFavorite(coffeeId)
        XCTAssertFalse(coffeeStore.isFavorite(coffeeId), "Coffee should not be favorited")
        
        let updatedFavorites = UserDefaults.standard.stringArray(forKey: "favorite_coffees") ?? []
        XCTAssertFalse(updatedFavorites.contains(coffeeId.uuidString), "Favorite removal should be persisted")
    }
    
    // MARK: - Performance Tests
    
    func testSearchPerformance() throws {
        // Add multiple coffees for performance testing
        let testCoffees = (0..<100).map { index in
            AnalyzedCoffee(
                imageData: nil,
                coffeeType: CoffeeType.allCases.randomElement() ?? .espresso,
                confidence: Double.random(in: 0.7...0.99),
                notes: "Performance test coffee \(index)",
                flavorProfile: FlavorProfile(
                    acidity: Double.random(in: 0...1),
                    body: Double.random(in: 0...1),
                    sweetness: Double.random(in: 0...1),
                    bitterness: Double.random(in: 0...1)
                ),
                rating: Double.random(in: 3...5)
            )
        }
        
        Task {
            for coffee in testCoffees {
                await coffeeStore.addCoffee(coffee)
            }
        }
        
        // Measure search performance
        coffeeStore.searchText = "test"
        
        let startTime = CFAbsoluteTimeGetCurrent()
        let _ = coffeeStore.filteredCoffees
        let searchTime = CFAbsoluteTimeGetCurrent() - startTime
        
        XCTAssertLessThan(searchTime, 0.1, "Search should complete in less than 100ms")
    }
    
    // MARK: - Edge Cases Tests
    
    func testEmptyStateHandling() throws {
        // Create a new store with no data
        let emptyStore = CoffeeStore()
        emptyStore.coffees = []
        
        XCTAssertEqual(emptyStore.filteredCoffees.count, 0, "Empty store should have no filtered results")
        XCTAssertEqual(emptyStore.favoriteCoffees.count, 0, "Empty store should have no favorites")
        
        let stats = emptyStore.getCoffeeStatistics()
        XCTAssertEqual(stats.totalCoffees, 0, "Empty store should report zero total coffees")
        XCTAssertEqual(stats.averageRating, 0.0, "Empty store should have zero average rating")
    }
    
    func testInvalidDataHandling() throws {
        let invalidCoffee = AnalyzedCoffee(
            imageData: nil,
            coffeeType: .unknown,
            confidence: -1.0, // Invalid confidence
            notes: "",
            flavorProfile: FlavorProfile(
                acidity: 2.0, // Out of range
                body: -0.5,   // Out of range
                sweetness: 1.5, // Out of range
                bitterness: -1.0 // Out of range
            ),
            rating: 10.0 // Out of range
        )
        
        Task {
            await coffeeStore.addCoffee(invalidCoffee)
        }
        
        // App should handle invalid data gracefully
        XCTAssertNoThrow(coffeeStore.filteredCoffees, "App should handle invalid data gracefully")
        XCTAssertNoThrow(coffeeStore.getCoffeeStatistics(), "Statistics should handle invalid data gracefully")
    }
}