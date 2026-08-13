import CoreGraphics
import Foundation
import ImageIO
import SQLite3
import UniformTypeIdentifiers
import XCTest
@testable import CoffeeSnapAI

final class VectorDatabaseIntegrationTests: XCTestCase {
    private var database: VectorDatabaseService!
    private var databaseURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("coffeesnap-tests-\(UUID().uuidString).sqlite")
        database = VectorDatabaseService(databaseURL: databaseURL)
        try await database.initialize()
    }

    override func tearDown() async throws {
        database = nil
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
        try await super.tearDown()
    }

    func testCoffeeVectorRoundTripAndCounts() async throws {
        let coffee = makeCoffee(
            id: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA",
            type: .flatWhite,
            acidity: 0.4,
            sweetness: 0.8
        )
        let cards = TasteMemoryEngine().reviewCards(for: coffee)

        try await database.upsert(coffee, cards: cards)
        try await database.append(MemorySignal(coffeeID: coffee.id, kind: .rated, value: 0.9))

        let loaded = try await database.loadCoffees()
        let counts = try await database.counts()
        XCTAssertEqual(loaded, [coffee])
        XCTAssertEqual(counts.memories, 1)
        XCTAssertEqual(counts.signals, 1)
        XCTAssertEqual(counts.reviews, cards.count)
    }

    @MainActor
    func testFailedSignalWriteRollsBackTastingAndKeepsVisibleFeedbackTruthful() async throws {
        let existing = makeCoffee(
            id: "A0A0A0A0-A0A0-40A0-80A0-A0A0A0A0A0A0",
            type: .flatWhite,
            acidity: 0.4,
            sweetness: 0.8
        )
        try await database.upsert(existing, cards: [])
        let store = CoffeeStore(database: database)
        await store.start()

        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &connection), SQLITE_OK)
        defer { sqlite3_close(connection) }
        let rejectSignals = """
            CREATE TRIGGER reject_test_signals
            BEFORE INSERT ON memory_signals
            BEGIN
                SELECT RAISE(ABORT, 'intentional test failure');
            END;
            """
        XCTAssertEqual(sqlite3_exec(connection, rejectSignals, nil, nil, nil), SQLITE_OK)

        let didRate = await store.rate(existing.id, rating: 1)
        let didFavorite = await store.toggleFavorite(existing.id)
        XCTAssertFalse(didRate)
        XCTAssertFalse(didFavorite)
        XCTAssertEqual(store.coffees.first?.rating, existing.rating)
        XCTAssertFalse(store.favorites.contains(existing.id))

        let newCoffee = makeCoffee(
            id: "B0B0B0B0-B0B0-40B0-80B0-B0B0B0B0B0B0",
            type: .pourOver,
            acidity: 0.8,
            sweetness: 0.7
        )
        let didSave = await store.addCoffee(newCoffee)
        XCTAssertFalse(didSave)
        XCTAssertFalse(store.coffees.contains(where: { $0.id == newCoffee.id }))

        let stored = try await database.loadCoffees()
        let storedSignals = try await database.loadSignals()
        XCTAssertEqual(stored, [existing])
        XCTAssertTrue(storedSignals.isEmpty)
    }

    func testInitializationCanRetryAfterMigrationFailure() async throws {
        let brokenURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("coffeesnap-broken-\(UUID().uuidString).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: brokenURL.path + suffix)
            }
        }
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(brokenURL.path, &connection), SQLITE_OK)
        XCTAssertEqual(
            sqlite3_exec(connection, "CREATE TABLE coffee_memories (id TEXT PRIMARY KEY)", nil, nil, nil),
            SQLITE_OK
        )
        sqlite3_close(connection)

        let recovering = VectorDatabaseService(databaseURL: brokenURL)
        do {
            try await recovering.initialize()
            XCTFail("A malformed legacy schema should fail initialization")
        } catch {
            // Expected: initialization must close the failed connection so a retry is possible.
        }

        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: brokenURL.path + suffix)
        }
        try await recovering.initialize()
        let counts = try await recovering.counts()
        XCTAssertEqual(counts.memories, 0)
        XCTAssertEqual(counts.signals, 0)
        XCTAssertEqual(counts.reviews, 0)
    }

    @MainActor
    func testStartupFailureShowsRecoveryInsteadOfFalseOnboarding() async {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("coffeesnap-not-a-database-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let store = CoffeeStore(database: VectorDatabaseService(databaseURL: directoryURL))

        await store.start()

        XCTAssertTrue(store.hasStarted)
        XCTAssertTrue(store.startupFailed)
        XCTAssertFalse(store.needsCalibration)
        XCTAssertNotNil(store.errorMessage)
    }

    func testSignalBatchRollsBackWhenOneEventFails() async throws {
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &connection), SQLITE_OK)
        defer { sqlite3_close(connection) }
        let rejectSkip = """
            CREATE TRIGGER reject_skip_signal
            BEFORE INSERT ON memory_signals
            WHEN NEW.kind = 'recommendationSkipped'
            BEGIN
                SELECT RAISE(ABORT, 'intentional batch failure');
            END;
            """
        XCTAssertEqual(sqlite3_exec(connection, rejectSkip, nil, nil, nil), SQLITE_OK)
        let candidateID = UUID()
        let batch = [
            MemorySignal(coffeeID: candidateID, kind: .recommendationShown, value: 1),
            MemorySignal(coffeeID: candidateID, kind: .recommendationSkipped, value: 0)
        ]

        do {
            try await database.append(batch)
            XCTFail("The trigger should reject the second event")
        } catch {
            // Expected. The first event must roll back with the rejected second event.
        }

        let signals = try await database.loadSignals()
        XCTAssertTrue(signals.isEmpty)
    }

    func testExactVectorSearchRanksClosestCoffeeFirst() async throws {
        let query = makeCoffee(
            id: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB",
            type: .pourOver,
            acidity: 0.9,
            sweetness: 0.7
        )
        let similar = makeCoffee(
            id: "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC",
            type: .pourOver,
            acidity: 0.88,
            sweetness: 0.72
        )
        let different = makeCoffee(
            id: "DDDDDDDD-DDDD-4DDD-8DDD-DDDDDDDDDDDD",
            type: .espresso,
            acidity: 0.1,
            sweetness: 0.2
        )
        for coffee in [query, similar, different] {
            try await database.upsert(coffee, cards: [])
        }

        let results = try await database.search(similarTo: query, limit: 2)

        XCTAssertEqual(results.map { $0.coffee.id }, [similar.id, different.id])
        XCTAssertGreaterThan(results[0].similarity, results[1].similarity)
    }

    func testVisionFeaturePrintIsDeterministicAndSeparatesImages() throws {
        let encoder = VisualEmbeddingService()
        let striped = try makeImageData(pattern: .stripes)
        let checkerboard = try makeImageData(pattern: .checkerboard)

        let first = try encoder.embed(striped)
        let repeated = try encoder.embed(striped)
        let different = try encoder.embed(checkerboard)

        XCTAssertGreaterThan(first.count, 100)
        XCTAssertEqual(first.count, repeated.count)
        XCTAssertEqual(first.count, different.count)
        XCTAssertEqual(encoder.similarity(first, repeated), 1, accuracy: 0.000_001)
        XCTAssertLessThan(encoder.similarity(first, different), 1)
    }

    func testVisualSearchRanksTheExactPhotoFirst() async throws {
        let stripedData = try makeImageData(pattern: .stripes)
        let checkerboardData = try makeImageData(pattern: .checkerboard)
        var striped = makeCoffee(
            id: "ABABABAB-ABAB-4BAB-8BAB-ABABABABABAB",
            type: .flatWhite,
            acidity: 0.4,
            sweetness: 0.8
        )
        var checkerboard = makeCoffee(
            id: "CDCDCDCD-CDCD-4DCD-8DCD-CDCDCDCDCDCD",
            type: .espresso,
            acidity: 0.2,
            sweetness: 0.3
        )
        striped.imageData = stripedData
        checkerboard.imageData = checkerboardData
        try await database.upsert(striped, cards: [])
        try await database.upsert(checkerboard, cards: [])

        let results = try await database.searchVisually(similarTo: stripedData, limit: 2)

        XCTAssertEqual(results.map { $0.coffee.id }, [striped.id, checkerboard.id])
        XCTAssertEqual(results[0].similarity, 1, accuracy: 0.000_001)
        XCTAssertGreaterThan(results[0].similarity, results[1].similarity)
    }

    func testRecommendationSignalsCanPrecedeATasting() async throws {
        let candidateID = UUID()
        let sessionID = UUID()
        let signal = MemorySignal(
            coffeeID: candidateID,
            kind: .recommendationOpened,
            value: 1,
            position: 2,
            policyScore: 0.83,
            policyVersion: "taste-bandit-v3",
            sessionID: sessionID
        )

        try await database.append(signal)

        let loadedSignals = try await database.loadSignals()
        let loaded = try XCTUnwrap(loadedSignals.first)
        XCTAssertEqual(loaded.id, signal.id)
        XCTAssertEqual(loaded.coffeeID, signal.coffeeID)
        XCTAssertEqual(loaded.kind, signal.kind)
        XCTAssertEqual(loaded.value, signal.value)
        XCTAssertEqual(loaded.timestamp.timeIntervalSince1970, signal.timestamp.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(loaded.position, 2)
        XCTAssertEqual(loaded.policyScore, 0.83)
        XCTAssertEqual(loaded.policyVersion, "taste-bandit-v3")
        XCTAssertEqual(loaded.sessionID, sessionID)
    }

    @MainActor
    func testConversionKeepsItsOriginalExposureSessionAndRatingDoesNotDuplicateIt() async throws {
        let store = CoffeeStore(database: database)
        await store.start()
        await store.saveCalibration(TasteCalibration(
            acidity: 0.7,
            body: 0.4,
            sweetness: 0.75,
            bitterness: 0.2,
            adventure: 0.65,
            flavorNotes: ["citrus", "jasmine"]
        ))
        let recommendation = try XCTUnwrap(store.dashboard.recommendations.first)

        await store.exposeRecommendations()
        let exposureSignals = try await database.loadSignals()
        let shown = try XCTUnwrap(exposureSignals.first {
            $0.kind == .recommendationShown && $0.coffeeID == recommendation.id
        })
        await store.recordRecommendation(recommendation, opened: true)

        let relaunchedStore = CoffeeStore(database: database)
        await relaunchedStore.start()
        let candidate = recommendation.candidate
        let tasting = AnalyzedCoffee(
            imageData: nil,
            coffeeType: candidate.coffeeType,
            confidence: 1,
            brewMethod: candidate.brewMethod,
            roastLevel: candidate.roastLevel,
            notes: "A real observed tasting",
            flavorProfile: candidate.flavorProfile,
            origin: candidate.origin,
            rating: 4,
            sourceCandidateID: candidate.id
        )
        await relaunchedStore.addCoffee(tasting)

        var conversions = try await database.loadSignals().filter {
            $0.kind == .recommendationConverted && $0.coffeeID == candidate.id
        }
        let conversion = try XCTUnwrap(conversions.first)
        XCTAssertEqual(conversions.count, 1)
        XCTAssertEqual(conversion.sessionID, shown.sessionID)
        XCTAssertEqual(conversion.position, shown.position)
        XCTAssertEqual(conversion.policyProbability, shown.policyProbability)

        await relaunchedStore.rate(tasting.id, rating: 5)
        conversions = try await database.loadSignals().filter {
            $0.kind == .recommendationConverted && $0.coffeeID == candidate.id
        }
        XCTAssertEqual(conversions.count, 1)
    }

    func testReviewStatePersistsAfterScheduling() async throws {
        let coffee = makeCoffee(
            id: "EEEEEEEE-EEEE-4EEE-8EEE-EEEEEEEEEEEE",
            type: .aeropress,
            acidity: 0.6,
            sweetness: 0.6
        )
        let engine = TasteMemoryEngine()
        let original = try XCTUnwrap(engine.reviewCards(for: coffee).first)
        try await database.upsert(coffee, cards: [original])
        let updated = engine.applyReview(.good, to: original)

        try await database.update(updated)

        let loadedCards = try await database.loadReviewCards()
        let loaded = try XCTUnwrap(loadedCards.first)
        XCTAssertEqual(loaded.id, updated.id)
        XCTAssertEqual(loaded.coffeeID, updated.coffeeID)
        XCTAssertEqual(loaded.concept, updated.concept)
        XCTAssertEqual(loaded.prompt, updated.prompt)
        XCTAssertEqual(loaded.answer, updated.answer)
        XCTAssertEqual(loaded.difficulty, updated.difficulty, accuracy: 0.0001)
        XCTAssertEqual(loaded.stability, updated.stability, accuracy: 0.0001)
        XCTAssertEqual(loaded.dueAt.timeIntervalSince1970, updated.dueAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(
            try XCTUnwrap(loaded.lastReviewedAt).timeIntervalSince1970,
            try XCTUnwrap(updated.lastReviewedAt).timeIntervalSince1970,
            accuracy: 0.001
        )
        XCTAssertEqual(loaded.repetitions, updated.repetitions)
        XCTAssertEqual(loaded.lapses, updated.lapses)
    }

    func testCalibrationRoundTripsAndCanBeReplaced() async throws {
        let first = TasteCalibration(
            acidity: 0.8,
            body: 0.3,
            sweetness: 0.7,
            bitterness: 0.2,
            adventure: 0.9,
            flavorNotes: ["citrus", "floral"],
            updatedAt: Date(timeIntervalSince1970: 1_900_000_001)
        )
        let replacement = TasteCalibration(
            acidity: 0.2,
            body: 0.9,
            sweetness: 0.5,
            bitterness: 0.7,
            adventure: 0.25,
            flavorNotes: ["chocolate"],
            updatedAt: Date(timeIntervalSince1970: 1_900_000_002)
        )

        try await database.saveCalibration(first)
        let loadedFirst = try await database.loadCalibration()
        XCTAssertEqual(loadedFirst, first)
        try await database.saveCalibration(replacement)
        let loadedReplacement = try await database.loadCalibration()
        XCTAssertEqual(loadedReplacement, replacement)
    }

    func testTwoTriesOfTheSameRecommendationRemainDistinctMemories() async throws {
        let candidateID = UUID()
        var first = makeCoffee(
            id: "77777777-7777-4777-8777-777777777777",
            type: .pourOver,
            acidity: 0.8,
            sweetness: 0.7
        )
        var second = makeCoffee(
            id: "88888888-8888-4888-8888-888888888888",
            type: .pourOver,
            acidity: 0.75,
            sweetness: 0.8
        )
        first.sourceCandidateID = candidateID
        second.sourceCandidateID = candidateID

        try await database.upsert(first, cards: [])
        try await database.upsert(second, cards: [])

        let loaded = try await database.loadCoffees()
        XCTAssertEqual(Set(loaded.map(\.id)), Set([first.id, second.id]))
        XCTAssertTrue(loaded.allSatisfy { $0.sourceCandidateID == candidateID })
    }

    func testDeletingATastingDoesNotDeleteCatalogFeedback() async throws {
        let coffee = makeCoffee(
            id: "99999999-9999-4999-8999-999999999999",
            type: .espresso,
            acidity: 0.2,
            sweetness: 0.3
        )
        let candidateID = UUID()
        try await database.upsert(coffee, cards: [])
        try await database.append(MemorySignal(coffeeID: coffee.id, kind: .rated, value: 0.8))
        try await database.append(MemorySignal(coffeeID: candidateID, kind: .recommendationSkipped, value: 0))

        try await database.deleteCoffee(coffee.id)

        let remainingCoffees = try await database.loadCoffees()
        XCTAssertTrue(remainingCoffees.isEmpty)
        let remaining = try await database.loadSignals()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.coffeeID, candidateID)
    }

    func testVersionTwoSignalSchemaMigratesWithoutLosingLegacyEvents() async throws {
        let legacyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("coffeesnap-legacy-\(UUID().uuidString).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: legacyURL.path + suffix)
            }
        }
        let legacyID = UUID()
        let candidateID = UUID()
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(legacyURL.path, &connection), SQLITE_OK)
        let create = """
            CREATE TABLE memory_signals (
                id TEXT PRIMARY KEY NOT NULL,
                coffee_id TEXT NOT NULL,
                kind TEXT NOT NULL,
                value REAL NOT NULL,
                created_at REAL NOT NULL
            );
            INSERT INTO memory_signals (id, coffee_id, kind, value, created_at)
            VALUES ('\(legacyID.uuidString)', '\(candidateID.uuidString)', 'recommendationOpened', 1, 1900000000);
            PRAGMA user_version = 2;
            """
        XCTAssertEqual(sqlite3_exec(connection, create, nil, nil, nil), SQLITE_OK)
        sqlite3_close(connection)

        let migrated = VectorDatabaseService(databaseURL: legacyURL)
        try await migrated.initialize()
        let migratedLegacySignals = try await migrated.loadSignals()
        let legacy = try XCTUnwrap(migratedLegacySignals.first)
        XCTAssertEqual(legacy.id, legacyID)
        XCTAssertEqual(legacy.coffeeID, candidateID)
        XCTAssertEqual(legacy.kind, .recommendationOpened)
        XCTAssertNil(legacy.policyVersion)
        XCTAssertNil(legacy.policyProbability)
        XCTAssertNil(legacy.policyActions)

        let actions = [
            PolicyActionProbability(candidateID: candidateID, utility: 0.91, probability: 0.72),
            PolicyActionProbability(candidateID: UUID(), utility: 0.74, probability: 0.28)
        ]
        let rich = MemorySignal(
            coffeeID: candidateID,
            kind: .recommendationShown,
            value: 1,
            position: 1,
            policyScore: 0.91,
            policyProbability: 0.72,
            policyVersion: RecommendationPolicy.version,
            catalogVersion: CoffeeCatalog.version,
            policyActions: actions,
            sessionID: UUID()
        )
        try await migrated.append(rich)
        let migratedSignals = try await migrated.loadSignals()
        let loadedRich = try XCTUnwrap(migratedSignals.first { $0.id == rich.id })
        XCTAssertEqual(loadedRich.id, rich.id)
        XCTAssertEqual(loadedRich.coffeeID, rich.coffeeID)
        XCTAssertEqual(loadedRich.kind, rich.kind)
        XCTAssertEqual(loadedRich.value, rich.value)
        XCTAssertEqual(loadedRich.timestamp.timeIntervalSince1970, rich.timestamp.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(loadedRich.position, rich.position)
        XCTAssertEqual(loadedRich.policyScore, rich.policyScore)
        XCTAssertEqual(loadedRich.policyProbability, rich.policyProbability)
        XCTAssertEqual(loadedRich.policyVersion, rich.policyVersion)
        XCTAssertEqual(loadedRich.catalogVersion, rich.catalogVersion)
        XCTAssertEqual(loadedRich.policyActions, actions)
        XCTAssertEqual(loadedRich.sessionID, rich.sessionID)
    }

    func testVersionThreeMemorySchemaAddsVisualIndexWithoutDataLoss() async throws {
        let legacyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("coffeesnap-v3-\(UUID().uuidString).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: legacyURL.path + suffix)
            }
        }
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(legacyURL.path, &connection), SQLITE_OK)
        let create = """
            CREATE TABLE coffee_memories (
                id TEXT PRIMARY KEY NOT NULL,
                coffee_json BLOB NOT NULL,
                embedding BLOB NOT NULL,
                embedding_model TEXT NOT NULL,
                search_text TEXT NOT NULL,
                created_at REAL NOT NULL,
                rating REAL
            );
            PRAGMA user_version = 3;
            """
        XCTAssertEqual(sqlite3_exec(connection, create, nil, nil, nil), SQLITE_OK)
        sqlite3_close(connection)

        let migrated = VectorDatabaseService(databaseURL: legacyURL)
        try await migrated.initialize()
        var coffee = makeCoffee(
            id: "EFEFEFEF-EFEF-4FEF-8FEF-EFEFEFEFEFEF",
            type: .cappuccino,
            acidity: 0.4,
            sweetness: 0.7
        )
        let imageData = try makeImageData(pattern: .stripes)
        coffee.imageData = imageData
        try await migrated.upsert(coffee, cards: [])

        let memories = try await migrated.loadCoffees()
        let matches = try await migrated.searchVisually(similarTo: imageData, limit: 1)
        XCTAssertEqual(memories, [coffee])
        XCTAssertEqual(matches.first?.coffee.id, coffee.id)
        XCTAssertEqual(matches.first?.similarity ?? 0, 1, accuracy: 0.000_001)

        // Simulate a pre-v4 photo row that has no visual vector yet. Search must
        // generate and persist the index lazily instead of hiding that memory.
        var mutationConnection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(legacyURL.path, &mutationConnection), SQLITE_OK)
        XCTAssertEqual(
            sqlite3_exec(
                mutationConnection,
                "UPDATE coffee_memories SET visual_embedding = NULL, visual_model = NULL, visual_source_hash = NULL",
                nil,
                nil,
                nil
            ),
            SQLITE_OK
        )
        sqlite3_close(mutationConnection)

        let lazilyReindexed = try await migrated.searchVisually(similarTo: imageData, limit: 1)
        XCTAssertEqual(lazilyReindexed.first?.coffee.id, coffee.id)
        XCTAssertEqual(lazilyReindexed.first?.similarity ?? 0, 1, accuracy: 0.000_001)
    }

    private func makeCoffee(
        id: String,
        type: CoffeeType,
        acidity: Double,
        sweetness: Double
    ) -> AnalyzedCoffee {
        AnalyzedCoffee(
            id: UUID(uuidString: id)!,
            imageData: nil,
            coffeeType: type,
            confidence: 0.95,
            analysisDate: Date(timeIntervalSince1970: 1_900_000_000),
            brewMethod: type.rawValue,
            roastLevel: type == .espresso ? .dark : .light,
            notes: "coffee test memory",
            flavorProfile: FlavorProfile(
                acidity: acidity,
                body: type == .espresso ? 0.9 : 0.45,
                sweetness: sweetness,
                bitterness: type == .espresso ? 0.8 : 0.15,
                flavorNotes: type == .espresso ? ["chocolate"] : ["citrus", "floral"]
            ),
            origin: type == .espresso ? "Brazil" : "Ethiopia",
            rating: 4.5
        )
    }

    private enum ImagePattern: Equatable {
        case stripes
        case checkerboard
    }

    private func makeImageData(pattern: ImagePattern) throws -> Data {
        let width = 96
        let height = 96
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let isPrimary: Bool
                switch pattern {
                case .stripes:
                    isPrimary = (x / 12).isMultiple(of: 2)
                case .checkerboard:
                    isPrimary = ((x / 12) + (y / 12)).isMultiple(of: 2)
                }
                if pattern == .stripes {
                    pixels[offset] = isPrimary ? 220 : 245
                    pixels[offset + 1] = isPrimary ? 70 : 210
                    pixels[offset + 2] = isPrimary ? 35 : 80
                } else {
                    pixels[offset] = isPrimary ? 30 : 40
                    pixels[offset + 1] = isPrimary ? 70 : 180
                    pixels[offset + 2] = isPrimary ? 210 : 230
                }
                pixels[offset + 3] = 255
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw VisualEmbeddingError.invalidImage
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw VisualEmbeddingError.invalidImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw VisualEmbeddingError.invalidImage
        }
        return output as Data
    }
}
