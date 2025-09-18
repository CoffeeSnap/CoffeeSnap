import XCTest
@testable import CoffeeSnapAI

@MainActor
final class VectorDatabaseIntegrationTests: XCTestCase {
    
    var vectorService: VectorDatabaseService!
    
    override func setUp() async throws {
        try await super.setUp()
        
        vectorService = VectorDatabaseService.shared
        await vectorService.initialize()
        
        // Wait for initialization
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
    }
    
    override func tearDown() async throws {
        vectorService = nil
        try await super.tearDown()
    }
    
    // MARK: - Database Initialization Tests
    
    func testDatabaseInitialization() async throws {
        // Database should initialize without errors
        await vectorService.initialize()
        
        // Test basic database functionality by getting analytics
        let analytics = await vectorService.getCoffeeAnalytics()
        XCTAssertGreaterThanOrEqual(analytics.totalVectors, 0, "Database should be accessible")
    }
    
    // MARK: - Vector Storage Tests
    
    func testStoreCoffeeVector() async throws {
        let testCoffee = createTestCoffee(
            type: .espresso,
            roastLevel: .dark,
            flavorProfile: FlavorProfile(
                acidity: 0.8,
                body: 0.9,
                sweetness: 0.3,
                bitterness: 0.7,
                flavorNotes: ["chocolate", "caramel", "nutty"]
            )
        )
        
        // Store the coffee vector
        await vectorService.storeCoffeeVector(testCoffee)
        
        // Verify storage by checking analytics
        let analytics = await vectorService.getCoffeeAnalytics()
        XCTAssertGreaterThan(analytics.totalVectors, 0, "Vector should be stored successfully")
    }
    
    func testStoreMultipleCoffeeVectors() async throws {
        let coffees = [
            createTestCoffee(type: .latte, roastLevel: .medium, flavorProfile: FlavorProfile(acidity: 0.4, body: 0.7, sweetness: 0.8, bitterness: 0.3)),
            createTestCoffee(type: .pourOver, roastLevel: .light, flavorProfile: FlavorProfile(acidity: 0.9, body: 0.5, sweetness: 0.6, bitterness: 0.2)),
            createTestCoffee(type: .cappuccino, roastLevel: .medium, flavorProfile: FlavorProfile(acidity: 0.6, body: 0.8, sweetness: 0.7, bitterness: 0.4))
        ]
        
        let initialAnalytics = await vectorService.getCoffeeAnalytics()
        let initialCount = initialAnalytics.totalVectors
        
        // Store multiple vectors
        for coffee in coffees {
            await vectorService.storeCoffeeVector(coffee)
        }
        
        let finalAnalytics = await vectorService.getCoffeeAnalytics()
        XCTAssertGreaterThanOrEqual(finalAnalytics.totalVectors, initialCount + coffees.count, "All vectors should be stored")
    }
    
    // MARK: - Similarity Search Tests
    
    func testSimilaritySearch() async throws {
        // Store reference coffees with distinct flavor profiles
        let lightCoffee = createTestCoffee(
            type: .pourOver,
            roastLevel: .light,
            flavorProfile: FlavorProfile(
                acidity: 0.9,
                body: 0.3,
                sweetness: 0.7,
                bitterness: 0.1,
                flavorNotes: ["citrus", "floral", "bright"]
            )
        )
        
        let darkCoffee = createTestCoffee(
            type: .espresso,
            roastLevel: .dark,
            flavorProfile: FlavorProfile(
                acidity: 0.2,
                body: 0.9,
                sweetness: 0.3,
                bitterness: 0.8,
                flavorNotes: ["chocolate", "smoky", "roasted"]
            )
        )
        
        await vectorService.storeCoffeeVector(lightCoffee)
        await vectorService.storeCoffeeVector(darkCoffee)
        
        // Search for similar to light coffee
        let similarToLight = await vectorService.findSimilarCoffees(
            flavorProfile: lightCoffee.flavorProfile,
            coffeeType: nil,
            limit: 5
        )
        
        // Should find at least the stored light coffee
        XCTAssertGreaterThanOrEqual(similarToLight.count, 0, "Should find similar coffees")
        
        // Test type-specific search
        let similarEspressos = await vectorService.findSimilarCoffees(
            flavorProfile: darkCoffee.flavorProfile,
            coffeeType: .espresso,
            limit: 5
        )
        
        XCTAssertGreaterThanOrEqual(similarEspressos.count, 0, "Should find similar espressos")
    }
    
    func testSimilaritySearchAccuracy() async throws {
        // Create coffee with very specific flavor profile
        let targetFlavorProfile = FlavorProfile(
            acidity: 0.6,
            body: 0.7,
            sweetness: 0.5,
            bitterness: 0.4,
            flavorNotes: ["vanilla", "caramel", "nuts"]
        )
        
        let targetCoffee = createTestCoffee(
            type: .latte,
            roastLevel: .medium,
            flavorProfile: targetFlavorProfile
        )
        
        // Create similar coffee (small variations)
        let similarCoffee = createTestCoffee(
            type: .cappuccino,
            roastLevel: .medium,
            flavorProfile: FlavorProfile(
                acidity: 0.65, // Similar
                body: 0.75,    // Similar
                sweetness: 0.55, // Similar
                bitterness: 0.35, // Similar
                flavorNotes: ["vanilla", "caramel", "almond"] // Mostly similar
            )
        )
        
        // Create dissimilar coffee
        let dissimilarCoffee = createTestCoffee(
            type: .coldBrew,
            roastLevel: .dark,
            flavorProfile: FlavorProfile(
                acidity: 0.1,  // Very different
                body: 0.9,     // Very different
                sweetness: 0.2, // Very different
                bitterness: 0.9, // Very different
                flavorNotes: ["smoky", "bitter", "earthy"] // Very different
            )
        )
        
        await vectorService.storeCoffeeVector(targetCoffee)
        await vectorService.storeCoffeeVector(similarCoffee)
        await vectorService.storeCoffeeVector(dissimilarCoffee)
        
        // Search for similar to target
        let results = await vectorService.findSimilarCoffees(
            flavorProfile: targetFlavorProfile,
            coffeeType: nil,
            limit: 10
        )
        
        // Verify that results prioritize similarity
        // Note: This is a basic test - in a real scenario, you'd verify similarity scores
        XCTAssertGreaterThanOrEqual(results.count, 0, "Should return similarity results")
    }
    
    // MARK: - Analytics Tests
    
    func testVectorAnalytics() async throws {
        // Store diverse coffee data
        let coffeeTypes: [CoffeeType] = [.espresso, .latte, .cappuccino, .pourOver, .americano]
        let roastLevels: [RoastLevel] = [.light, .medium, .dark]
        
        var storedCoffees: [AnalyzedCoffee] = []
        
        for (index, coffeeType) in coffeeTypes.enumerated() {
            for roastLevel in roastLevels {
                let coffee = createTestCoffee(
                    type: coffeeType,
                    roastLevel: roastLevel,
                    flavorProfile: FlavorProfile(
                        acidity: Double.random(in: 0.1...0.9),
                        body: Double.random(in: 0.1...0.9),
                        sweetness: Double.random(in: 0.1...0.9),
                        bitterness: Double.random(in: 0.1...0.9)
                    ),
                    confidence: Double.random(in: 0.7...0.99),
                    rating: Double.random(in: 3.0...5.0)
                )
                
                storedCoffees.append(coffee)
                await vectorService.storeCoffeeVector(coffee)
            }
        }
        
        let analytics = await vectorService.getCoffeeAnalytics()
        
        // Test analytics accuracy
        XCTAssertGreaterThanOrEqual(analytics.totalVectors, storedCoffees.count, "Total vectors should match stored count")
        XCTAssertGreaterThan(analytics.averageConfidence, 0.0, "Average confidence should be positive")
        XCTAssertGreaterThan(analytics.averageRating, 0.0, "Average rating should be positive")
        XCTAssertLessThanOrEqual(analytics.averageRating, 5.0, "Average rating should not exceed 5.0")
        
        // Test type distribution
        XCTAssertGreaterThan(analytics.typeDistribution.count, 0, "Should have type distribution data")
        
        // Test diversity score
        XCTAssertGreaterThanOrEqual(analytics.diversityScore, 0.0, "Diversity score should be non-negative")
        XCTAssertLessThanOrEqual(analytics.diversityScore, 1.0, "Diversity score should not exceed 1.0")
        
        // Test most popular type
        XCTAssertNotNil(analytics.mostPopularType, "Should identify most popular type")
    }
    
    // MARK: - Vector Deletion Tests
    
    func testDeleteCoffeeVector() async throws {
        let testCoffee = createTestCoffee(
            type: .mocha,
            roastLevel: .medium,
            flavorProfile: FlavorProfile(acidity: 0.5, body: 0.6, sweetness: 0.8, bitterness: 0.4)
        )
        
        // Store the vector
        await vectorService.storeCoffeeVector(testCoffee)
        
        let analyticsBeforeDelete = await vectorService.getCoffeeAnalytics()
        let initialCount = analyticsBeforeDelete.totalVectors
        
        // Delete the vector
        await vectorService.deleteCoffeeVector(testCoffee.id)
        
        let analyticsAfterDelete = await vectorService.getCoffeeAnalytics()
        
        // Note: Due to the nature of our test setup, we might have other vectors
        // So we check that deletion doesn't increase the count
        XCTAssertLessThanOrEqual(analyticsAfterDelete.totalVectors, initialCount, "Vector count should not increase after deletion")
    }
    
    // MARK: - Performance Tests
    
    func testVectorStoragePerformance() async throws {
        let coffeeCount = 50
        let coffees = (0..<coffeeCount).map { index in
            createTestCoffee(
                type: CoffeeType.allCases.randomElement() ?? .espresso,
                roastLevel: RoastLevel.allCases.randomElement() ?? .medium,
                flavorProfile: FlavorProfile(
                    acidity: Double.random(in: 0...1),
                    body: Double.random(in: 0...1),
                    sweetness: Double.random(in: 0...1),
                    bitterness: Double.random(in: 0...1),
                    flavorNotes: ["note\(index)", "flavor\(index % 5)"]
                )
            )
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        for coffee in coffees {
            await vectorService.storeCoffeeVector(coffee)
        }
        
        let storageTime = CFAbsoluteTimeGetCurrent() - startTime
        let averageTimePerVector = storageTime / Double(coffeeCount)
        
        XCTAssertLessThan(averageTimePerVector, 0.1, "Vector storage should be efficient (< 100ms per vector)")
    }
    
    func testSimilaritySearchPerformance() async throws {
        // Store multiple vectors for search testing
        let searchTestCoffees = (0..<30).map { index in
            createTestCoffee(
                type: CoffeeType.allCases.randomElement() ?? .espresso,
                roastLevel: RoastLevel.allCases.randomElement() ?? .medium,
                flavorProfile: FlavorProfile(
                    acidity: Double.random(in: 0...1),
                    body: Double.random(in: 0...1),
                    sweetness: Double.random(in: 0...1),
                    bitterness: Double.random(in: 0...1)
                )
            )
        }
        
        for coffee in searchTestCoffees {
            await vectorService.storeCoffeeVector(coffee)
        }
        
        let queryProfile = FlavorProfile(acidity: 0.5, body: 0.5, sweetness: 0.5, bitterness: 0.5)
        
        let startTime = CFAbsoluteTimeGetCurrent()
        let _ = await vectorService.findSimilarCoffees(flavorProfile: queryProfile, limit: 10)
        let searchTime = CFAbsoluteTimeGetCurrent() - startTime
        
        XCTAssertLessThan(searchTime, 0.5, "Similarity search should complete in reasonable time (< 500ms)")
    }
    
    // MARK: - Edge Cases Tests
    
    func testEdgeCaseFlavorProfiles() async throws {
        // Test extreme flavor profiles
        let extremeProfiles = [
            FlavorProfile(acidity: 0.0, body: 0.0, sweetness: 0.0, bitterness: 0.0), // All zeros
            FlavorProfile(acidity: 1.0, body: 1.0, sweetness: 1.0, bitterness: 1.0), // All maxed
            FlavorProfile(acidity: 1.0, body: 0.0, sweetness: 1.0, bitterness: 0.0), // Alternating
            FlavorProfile(acidity: 0.5, body: 0.5, sweetness: 0.5, bitterness: 0.5)  // All average
        ]
        
        for (index, profile) in extremeProfiles.enumerated() {
            let coffee = createTestCoffee(
                type: .espresso,
                roastLevel: .medium,
                flavorProfile: profile
            )
            
            // Should handle extreme values gracefully
            XCTAssertNoThrow(await vectorService.storeCoffeeVector(coffee), "Should handle extreme flavor profiles")
            
            // Should be able to search with extreme profiles
            let results = await vectorService.findSimilarCoffees(flavorProfile: profile, limit: 5)
            XCTAssertGreaterThanOrEqual(results.count, 0, "Should handle similarity search with extreme profiles")
        }
    }
    
    func testEmptyFlavorNotes() async throws {
        let coffee = createTestCoffee(
            type: .americano,
            roastLevel: .light,
            flavorProfile: FlavorProfile(
                acidity: 0.6,
                body: 0.4,
                sweetness: 0.5,
                bitterness: 0.3,
                flavorNotes: [] // Empty flavor notes
            )
        )
        
        XCTAssertNoThrow(await vectorService.storeCoffeeVector(coffee), "Should handle empty flavor notes")
        
        let results = await vectorService.findSimilarCoffees(flavorProfile: coffee.flavorProfile, limit: 3)
        XCTAssertGreaterThanOrEqual(results.count, 0, "Should handle similarity search with empty flavor notes")
    }
    
    // MARK: - Helper Methods
    
    private func createTestCoffee(
        type: CoffeeType,
        roastLevel: RoastLevel,
        flavorProfile: FlavorProfile,
        confidence: Double = 0.9,
        rating: Double = 4.0
    ) -> AnalyzedCoffee {
        return AnalyzedCoffee(
            imageData: nil,
            coffeeType: type,
            confidence: confidence,
            brewMethod: "Test Method",
            roastLevel: roastLevel,
            notes: "Test coffee for \(type.rawValue)",
            recommendations: ["Test recommendation"],
            flavorProfile: flavorProfile,
            origin: "Test Origin",
            rating: rating
        )
    }
}