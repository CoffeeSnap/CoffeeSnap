import XCTest
@testable import CoffeeSnapAI

final class TasteMemoryEngineTests: XCTestCase {
    private let engine = TasteMemoryEngine()

    func testCalibrationCreatesAnHonestColdStartProfile() {
        let calibration = TasteCalibration(
            acidity: 0.85,
            body: 0.25,
            sweetness: 0.75,
            bitterness: 0.15,
            adventure: 0.9,
            flavorNotes: ["Jasmine", "Citrus", "jasmine"],
            updatedAt: Date(timeIntervalSince1970: 2_000_000_000)
        )

        let profile = engine.buildProfile(
            coffees: [],
            signals: [],
            calibration: calibration,
            now: calibration.updatedAt
        )

        XCTAssertFalse(profile.vector.isEmpty)
        XCTAssertEqual(profile.observationCount, 0)
        XCTAssertEqual(profile.acidity, calibration.acidity, accuracy: 0.0001)
        XCTAssertEqual(profile.body, calibration.body, accuracy: 0.0001)
        XCTAssertEqual(profile.adventure, calibration.adventure, accuracy: 0.0001)
        XCTAssertEqual(Set(profile.topNotes), Set(["citrus", "jasmine"]))
        XCTAssertGreaterThan(profile.confidence, 0)
        XCTAssertTrue(profile.isColdStart)
    }

    func testProfileLearnsFromExplicitFeedbackInsteadOfRawFrequency() {
        let sweet = coffee(
            id: "11111111-1111-4111-8111-111111111111",
            type: .flatWhite,
            profile: FlavorProfile(acidity: 0.3, body: 0.7, sweetness: 0.95, bitterness: 0.1),
            rating: 5
        )
        let bitter = coffee(
            id: "22222222-2222-4222-8222-222222222222",
            type: .espresso,
            profile: FlavorProfile(acidity: 0.4, body: 0.9, sweetness: 0.1, bitterness: 0.95),
            rating: 1
        )

        let profile = engine.buildProfile(coffees: [sweet, bitter], signals: [])

        XCTAssertGreaterThan(profile.sweetness, 0.8)
        XCTAssertLessThan(profile.bitterness, 0.25)
        XCTAssertEqual(profile.observationCount, 2)
    }

    func testNewFeedbackOutweighsStalePreferenceEvidence() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let stale = coffee(
            id: "33333333-3333-4333-8333-333333333333",
            type: .pourOver,
            profile: FlavorProfile(acidity: 1, body: 0.1, sweetness: 0.5, bitterness: 0),
            rating: 5,
            date: now.addingTimeInterval(-365 * 86_400)
        )
        let recent = coffee(
            id: "44444444-4444-4444-8444-444444444444",
            type: .espresso,
            profile: FlavorProfile(acidity: 0.1, body: 1, sweetness: 0.5, bitterness: 0.7),
            rating: 5,
            date: now
        )

        let profile = engine.buildProfile(coffees: [stale, recent], signals: [], now: now)

        XCTAssertGreaterThan(profile.body, profile.acidity)
    }

    func testRecommendationsBalanceFitExplorationAndDiversity() {
        let liked = coffee(
            id: "55555555-5555-4555-8555-555555555555",
            type: .flatWhite,
            profile: FlavorProfile(acidity: 0.4, body: 0.8, sweetness: 0.85, bitterness: 0.2, flavorNotes: ["caramel", "almond"]),
            rating: 5
        )
        let profile = engine.buildProfile(coffees: [liked], signals: [])

        let recommendations = engine.recommendations(
            profile: profile,
            memories: [liked],
            signals: [],
            limit: 5
        )

        XCTAssertEqual(recommendations.count, 5)
        XCTAssertGreaterThan(Set(recommendations.map { $0.candidate.coffeeType }).count, 2)
        XCTAssertTrue(recommendations.contains(where: \.isExploration))
        XCTAssertTrue(recommendations.allSatisfy { (0...1).contains($0.score) })
    }

    func testBoundedSlatePolicyIsReproducibleAndLogsExactConditionalProbabilities() throws {
        let calibration = TasteCalibration(
            acidity: 0.72,
            body: 0.42,
            sweetness: 0.76,
            bitterness: 0.18,
            adventure: 0.65,
            flavorNotes: ["jasmine", "citrus"]
        )
        let profile = engine.buildProfile(coffees: [], signals: [], calibration: calibration)

        let first = engine.recommendations(
            profile: profile,
            memories: [],
            signals: [],
            limit: 5,
            samplingSeed: 42
        )
        let replay = engine.recommendations(
            profile: profile,
            memories: [],
            signals: [],
            limit: 5,
            samplingSeed: 42
        )

        XCTAssertEqual(first.map(\.id), replay.map(\.id))
        XCTAssertEqual(first.map(\.selectionProbability), replay.map(\.selectionProbability))
        XCTAssertGreaterThan(first.map(\.selectionProbability).reduce(1, *), 0)

        for recommendation in first {
            let distribution = recommendation.policyActions
            XCTAssertFalse(distribution.isEmpty)
            XCTAssertEqual(distribution.map(\.probability).reduce(0, +), 1, accuracy: 0.000_000_1)
            XCTAssertTrue(distribution.allSatisfy { $0.probability > 0 && $0.probability <= 1 })
            let loggedChoice = try XCTUnwrap(distribution.first { $0.candidateID == recommendation.id })
            XCTAssertEqual(loggedChoice.probability, recommendation.selectionProbability, accuracy: 0.000_000_1)
        }
    }

    func testBoundedSlatePolicyExploresAcrossSeedsWithoutAbandoningUtility() throws {
        let calibration = TasteCalibration(
            acidity: 0.75,
            body: 0.35,
            sweetness: 0.7,
            bitterness: 0.15,
            adventure: 0.5,
            flavorNotes: ["jasmine", "citrus"]
        )
        let profile = engine.buildProfile(coffees: [], signals: [], calibration: calibration)
        let candidates = Array(CoffeeCatalog.candidates.prefix(3))
        let scored = engine.recommendations(
            profile: profile,
            memories: [],
            signals: [],
            candidates: candidates,
            limit: candidates.count,
            samplingSeed: 0
        )
        let scoreByID = Dictionary(uniqueKeysWithValues: scored.map { ($0.id, $0.score) })
        let bestID = try XCTUnwrap(scoreByID.max(by: { $0.value < $1.value })?.key)
        let weakestID = try XCTUnwrap(scoreByID.min(by: { $0.value < $1.value })?.key)
        var firstChoiceCounts: [UUID: Int] = [:]
        var sampledUtility = 0.0

        let sampleCount = 64
        for seed in UInt64(0)..<UInt64(sampleCount) {
            let choice = try XCTUnwrap(engine.recommendations(
                profile: profile,
                memories: [],
                signals: [],
                candidates: candidates,
                limit: 1,
                samplingSeed: seed
            ).first)
            firstChoiceCounts[choice.id, default: 0] += 1
            sampledUtility += choice.score
        }

        let uniformUtility = scoreByID.values.reduce(0, +) / Double(scoreByID.count)
        XCTAssertEqual(firstChoiceCounts.count, candidates.count)
        XCTAssertGreaterThan(firstChoiceCounts[bestID, default: 0], firstChoiceCounts[weakestID, default: 0])
        XCTAssertGreaterThan(sampledUtility / Double(sampleCount), uniformUtility)
    }

    func testPolicyDiagnosticsRequireAuditableExposureDistributions() throws {
        let profile = engine.buildProfile(
            coffees: [],
            signals: [],
            calibration: TasteCalibration(
                acidity: 0.5,
                body: 0.5,
                sweetness: 0.7,
                bitterness: 0.2,
                adventure: 0.7,
                flavorNotes: ["caramel"]
            )
        )
        let recommendations = engine.recommendations(
            profile: profile,
            memories: [],
            signals: [],
            limit: 3,
            samplingSeed: 9
        )
        let sessionID = UUID()
        let exposures = recommendations.enumerated().map { index, recommendation in
            MemorySignal(
                coffeeID: recommendation.id,
                kind: .recommendationShown,
                value: 1,
                position: index + 1,
                policyScore: recommendation.score,
                policyProbability: recommendation.selectionProbability,
                policyVersion: RecommendationPolicy.version,
                catalogVersion: CoffeeCatalog.version,
                policyActions: recommendation.policyActions,
                sessionID: sessionID
            )
        }

        let diagnostics = engine.policyDiagnostics(signals: exposures)

        XCTAssertEqual(diagnostics.auditedSessions, 1)
        XCTAssertEqual(diagnostics.loggedExposures, 3)
        XCTAssertGreaterThan(diagnostics.meanNormalizedEntropy, 0)
        XCTAssertLessThanOrEqual(diagnostics.meanNormalizedEntropy, 1)
        XCTAssertGreaterThan(diagnostics.minimumPropensity, 0)
    }

    func testCandidateSpecificSkipsReduceItsRankWithoutPenalizingTheSlate() throws {
        let calibration = TasteCalibration(
            acidity: 0.6,
            body: 0.5,
            sweetness: 0.7,
            bitterness: 0.2,
            adventure: 0.5,
            flavorNotes: ["citrus"]
        )
        let profile = engine.buildProfile(coffees: [], signals: [], calibration: calibration)
        let candidates = Array(CoffeeCatalog.candidates.prefix(2))
        let target = try XCTUnwrap(candidates.first)
        let baseline = engine.recommendations(
            profile: profile,
            memories: [],
            signals: [],
            candidates: candidates,
            limit: candidates.count
        )
        let skips = (0..<4).map { offset in
            MemorySignal(
                coffeeID: target.id,
                kind: .recommendationSkipped,
                value: 0,
                timestamp: Date().addingTimeInterval(Double(offset))
            )
        }
        let learned = engine.recommendations(
            profile: profile,
            memories: [],
            signals: skips,
            candidates: candidates,
            limit: candidates.count
        )
        let baselineTarget = try XCTUnwrap(baseline.first { $0.id == target.id })
        let learnedTarget = try XCTUnwrap(learned.first { $0.id == target.id })
        let untouched = try XCTUnwrap(candidates.dropFirst().first)
        let learnedUntouched = try XCTUnwrap(learned.first { $0.id == untouched.id })

        XCTAssertLessThan(learnedTarget.behaviorAffinity, baselineTarget.behaviorAffinity)
        XCTAssertLessThan(learnedTarget.score, baselineTarget.score)
        XCTAssertGreaterThan(learnedUntouched.behaviorAffinity, learnedTarget.behaviorAffinity)
    }

    func testObservedPredictionErrorsCalibrateFutureVectorMatches() throws {
        let target = try XCTUnwrap(CoffeeCatalog.candidates.first)
        let calibration = TasteCalibration(
            acidity: 0.2,
            body: 0.85,
            sweetness: 0.45,
            bitterness: 0.55,
            adventure: 0.5,
            flavorNotes: []
        )
        let profile = engine.buildProfile(coffees: [], signals: [], calibration: calibration)
        let baseline = try XCTUnwrap(engine.recommendations(
            profile: profile,
            memories: [],
            signals: [],
            candidates: [target],
            limit: 1
        ).first)
        let observations = (0..<5).map { offset in
            AnalyzedCoffee(
                imageData: nil,
                coffeeType: target.coffeeType,
                confidence: 1,
                analysisDate: Date().addingTimeInterval(Double(-offset)),
                brewMethod: target.brewMethod,
                roastLevel: target.roastLevel,
                flavorProfile: FlavorProfile(
                    acidity: 0.2,
                    body: 0.85,
                    sweetness: 0.45,
                    bitterness: 0.55
                ),
                origin: target.origin,
                rating: 4,
                sourceCandidateID: target.id
            )
        }
        let calibrated = try XCTUnwrap(engine.recommendations(
            profile: profile,
            memories: observations,
            signals: [],
            candidates: [target],
            limit: 1
        ).first)

        XCTAssertGreaterThan(calibrated.match, baseline.match)
    }

    func testNewReviewCardsUseStagedRetrievalInsteadOfImmediateQuizzing() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let tasted = coffee(
            id: "66666666-6666-4666-8666-666666666666",
            type: .pourOver,
            profile: FlavorProfile(
                acidity: 0.8,
                body: 0.4,
                sweetness: 0.7,
                bitterness: 0.1,
                flavorNotes: ["jasmine"]
            ),
            rating: 4,
            date: now
        )

        let cards = engine.reviewCards(for: tasted, now: now)
        let dueByConcept = Dictionary(uniqueKeysWithValues: cards.map { ($0.concept, $0.dueAt) })

        XCTAssertTrue(engine.interleavedDueCards(cards, now: now).isEmpty)
        XCTAssertEqual(try XCTUnwrap(dueByConcept[.flavor]).timeIntervalSince(now), 20 * 60, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(dueByConcept[.brew]).timeIntervalSince(now), 86_400, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(dueByConcept[.origin]).timeIntervalSince(now), 2 * 86_400, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(dueByConcept[.roast]).timeIntervalSince(now), 3 * 86_400, accuracy: 1)
    }

    func testAdaptiveReviewUsesRecallGradeAndSpacing() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let card = ReviewCard(
            coffeeID: UUID(),
            concept: .origin,
            prompt: "Origin?",
            answer: "Ethiopia",
            dueAt: now
        )

        let again = engine.applyReview(.again, to: card, now: now)
        let good = engine.applyReview(.good, to: card, now: now)
        let easy = engine.applyReview(.easy, to: card, now: now)

        XCTAssertEqual(again.dueAt.timeIntervalSince(now), 600, accuracy: 1)
        XCTAssertGreaterThan(good.dueAt, again.dueAt)
        XCTAssertGreaterThan(easy.dueAt, good.dueAt)
        XCTAssertGreaterThan(easy.stability, good.stability)
    }

    func testDueCardsAreInterleavedAcrossConcepts() {
        let now = Date()
        let coffeeID = UUID()
        let cards = [
            ReviewCard(coffeeID: coffeeID, concept: .flavor, prompt: "1", answer: "1", dueAt: now),
            ReviewCard(coffeeID: coffeeID, concept: .flavor, prompt: "2", answer: "2", dueAt: now),
            ReviewCard(coffeeID: coffeeID, concept: .origin, prompt: "3", answer: "3", dueAt: now),
            ReviewCard(coffeeID: coffeeID, concept: .brew, prompt: "4", answer: "4", dueAt: now)
        ]

        let ordered = engine.interleavedDueCards(cards, now: now)

        XCTAssertEqual(ordered.count, cards.count)
        for pair in zip(ordered, ordered.dropFirst()) {
            XCTAssertNotEqual(pair.0.concept, pair.1.concept)
        }
    }

    private func coffee(
        id: String,
        type: CoffeeType,
        profile: FlavorProfile,
        rating: Double,
        date: Date = Date()
    ) -> AnalyzedCoffee {
        AnalyzedCoffee(
            id: UUID(uuidString: id)!,
            imageData: nil,
            coffeeType: type,
            confidence: 1,
            analysisDate: date,
            brewMethod: "Test brew",
            roastLevel: .medium,
            flavorProfile: profile,
            origin: "Test origin",
            rating: rating
        )
    }
}
