import Foundation
import SwiftUI

@MainActor
final class CoffeeStore: ObservableObject {
    @Published private(set) var coffees: [AnalyzedCoffee] = []
    @Published private(set) var favorites: Set<UUID> = []
    @Published private(set) var dashboard = MemoryDashboard.empty
    @Published private(set) var isLoading = false
    @Published private(set) var hasStarted = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var calibration: TasteCalibration?
    @Published private(set) var recommendationExposureID = UUID()
    @Published var searchText = ""

    private let database: any VectorMemoryRepository
    private let engine = TasteMemoryEngine()
    private var signals: [MemorySignal] = []
    private var reviewCards: [ReviewCard] = []
    private var activeRecommendationSessionID = UUID()
    private var lastExposedRecommendationID: UUID?
    private var recommendationSeed = UInt64.random(in: UInt64.min...UInt64.max)
    private var pendingAttributions: [UUID: RecommendationAttribution] = [:]
    private let recommendationPolicyVersion = RecommendationPolicy.version

    init(database: any VectorMemoryRepository = VectorDatabaseService.shared) {
        self.database = database
    }

    var filteredCoffees: [AnalyzedCoffee] {
        guard !searchText.isEmpty else { return coffees }
        return coffees.filter { coffee in
            coffee.coffeeType.rawValue.localizedCaseInsensitiveContains(searchText) ||
            coffee.origin?.localizedCaseInsensitiveContains(searchText) == true ||
            coffee.notes.localizedCaseInsensitiveContains(searchText) ||
            coffee.flavorProfile.flavorNotes.contains {
                $0.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var nextReview: ReviewCard? { dashboard.dueCards.first }
    var needsCalibration: Bool { hasStarted && calibration == nil && coffees.isEmpty && !isLoading }
    var policyDiagnostics: RecommendationPolicyDiagnostics {
        engine.policyDiagnostics(signals: signals)
    }

    func start() async {
        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            hasStarted = true
        }
        do {
            try await database.initialize()
            coffees = try await database.loadCoffees()
            calibration = try await database.loadCalibration()
            try await refreshMemory()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addCoffee(_ coffee: AnalyzedCoffee) async {
        do {
            try await database.upsert(coffee, cards: engine.reviewCards(for: coffee))
            try await database.append(MemorySignal(coffeeID: coffee.id, kind: .tasted, value: 1))
            if let rating = coffee.rating {
                try await database.append(MemorySignal(coffeeID: coffee.id, kind: .rated, value: rating / 5))
            }
            if let candidateID = coffee.sourceCandidateID {
                let attribution = pendingAttributions.removeValue(forKey: candidateID)
                try await database.append(MemorySignal(
                    coffeeID: candidateID,
                    kind: .recommendationConverted,
                    value: (coffee.rating ?? 3.5) / 5,
                    position: attribution?.position,
                    policyScore: attribution?.score,
                    policyProbability: attribution?.probability,
                    policyVersion: recommendationPolicyVersion,
                    catalogVersion: CoffeeCatalog.version,
                    sessionID: attribution?.sessionID ?? activeRecommendationSessionID
                ))
            }
            coffees.removeAll { $0.id == coffee.id }
            coffees.insert(coffee, at: 0)
            try await refreshMemory()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rate(_ coffeeID: UUID, rating: Double) async {
        guard let index = coffees.firstIndex(where: { $0.id == coffeeID }) else { return }
        coffees[index].rating = rating.clamped(to: 0...5)
        do {
            try await database.upsert(coffees[index], cards: engine.reviewCards(for: coffees[index]))
            try await database.append(MemorySignal(
                coffeeID: coffeeID,
                kind: .rated,
                value: rating.clamped(to: 0...5) / 5
            ))
            try await refreshMemory()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleFavorite(_ coffeeID: UUID) async {
        let isRemoving = favorites.contains(coffeeID)
        if isRemoving {
            favorites.remove(coffeeID)
        } else {
            favorites.insert(coffeeID)
        }
        do {
            try await database.append(MemorySignal(
                coffeeID: coffeeID,
                kind: isRemoving ? .unfavorited : .favorited,
                value: isRemoving ? 0 : 1
            ))
            try await refreshMemory()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exposeRecommendations() async {
        guard !dashboard.recommendations.isEmpty,
              lastExposedRecommendationID != recommendationExposureID else { return }
        activeRecommendationSessionID = UUID()
        do {
            for (index, recommendation) in dashboard.recommendations.enumerated() {
                let signal = MemorySignal(
                    coffeeID: recommendation.id,
                    kind: .recommendationShown,
                    value: 1,
                    position: index + 1,
                    policyScore: recommendation.score,
                    policyProbability: recommendation.selectionProbability,
                    policyVersion: recommendationPolicyVersion,
                    catalogVersion: CoffeeCatalog.version,
                    policyActions: recommendation.policyActions,
                    sessionID: activeRecommendationSessionID
                )
                try await database.append(signal)
                signals.append(signal)
            }
            lastExposedRecommendationID = recommendationExposureID
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func recordRecommendation(_ recommendation: MemoryRecommendation, opened: Bool) async {
        let position = dashboard.recommendations.firstIndex { $0.id == recommendation.id }.map { $0 + 1 }
        do {
            let signal = MemorySignal(
                coffeeID: recommendation.id,
                kind: opened ? .recommendationOpened : .recommendationSkipped,
                value: opened ? 1 : 0,
                position: position,
                policyScore: recommendation.score,
                policyProbability: recommendation.selectionProbability,
                policyVersion: recommendationPolicyVersion,
                catalogVersion: CoffeeCatalog.version,
                sessionID: activeRecommendationSessionID
            )
            try await database.append(signal)
            signals.append(signal)
            if opened {
                pendingAttributions[recommendation.id] = RecommendationAttribution(
                    sessionID: activeRecommendationSessionID,
                    position: position,
                    score: recommendation.score,
                    probability: recommendation.selectionProbability
                )
            } else {
                try await refreshMemory()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func gradeNextReview(_ grade: ReviewGrade) async {
        guard let card = nextReview else { return }
        let updated = engine.applyReview(grade, to: card)
        do {
            try await database.update(updated)
            if let index = reviewCards.firstIndex(where: { $0.id == updated.id }) {
                reviewCards[index] = updated
            }
            rebuildDashboard()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ coffeeID: UUID) async {
        do {
            try await database.deleteCoffee(coffeeID)
            coffees.removeAll { $0.id == coffeeID }
            favorites.remove(coffeeID)
            try await refreshMemory()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveCalibration(_ value: TasteCalibration) async {
        do {
            try await database.saveCalibration(value)
            calibration = value
            renewRecommendationPolicy()
            rebuildDashboard()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func visualMatches(for coffee: AnalyzedCoffee, limit: Int = 5) async -> [VisualSearchResult] {
        guard let imageData = coffee.imageData else { return [] }
        do {
            let results = try await database.searchVisually(
                similarTo: imageData,
                limit: limit + 1
            )
            return Array(results.filter { $0.coffee.id != coffee.id }.prefix(limit))
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func refreshMemory() async throws {
        signals = try await database.loadSignals()
        reviewCards = try await database.loadReviewCards()
        calibration = try await database.loadCalibration()
        favorites = replayFavorites(signals)
        renewRecommendationPolicy()
        rebuildDashboard()
    }

    private func rebuildDashboard(now: Date = Date()) {
        let profile = engine.buildProfile(
            coffees: coffees,
            signals: signals,
            calibration: calibration,
            now: now
        )
        dashboard = MemoryDashboard(
            profile: profile,
            recommendations: engine.recommendations(
                profile: profile,
                memories: coffees,
                signals: signals,
                samplingSeed: recommendationSeed
            ),
            dueCards: engine.interleavedDueCards(reviewCards, now: now),
            totalMemories: coffees.count,
            memoryHealth: engine.memoryHealth(cards: reviewCards, now: now)
        )
    }

    private func renewRecommendationPolicy() {
        recommendationSeed = UInt64.random(in: UInt64.min...UInt64.max)
        recommendationExposureID = UUID()
    }

    private func replayFavorites(_ signals: [MemorySignal]) -> Set<UUID> {
        var result: Set<UUID> = []
        for signal in signals.sorted(by: { $0.timestamp < $1.timestamp }) {
            switch signal.kind {
            case .favorited: result.insert(signal.coffeeID)
            case .unfavorited: result.remove(signal.coffeeID)
            default: break
            }
        }
        return result
    }

}

private struct RecommendationAttribution {
    let sessionID: UUID
    let position: Int?
    let score: Double
    let probability: Double
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
