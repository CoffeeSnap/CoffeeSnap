import Foundation
import SwiftUI

@MainActor
final class CoffeeStore: ObservableObject {
    @Published private(set) var coffees: [AnalyzedCoffee] = []
    @Published private(set) var favorites: Set<UUID> = []
    @Published private(set) var dashboard = MemoryDashboard.empty
    @Published private(set) var isLoading = false
    @Published private(set) var hasStarted = false
    @Published private(set) var startupFailed = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var calibration: TasteCalibration?
    @Published private(set) var recommendationExposureID = UUID()
    @Published private(set) var isExposingRecommendations = false
    @Published private(set) var isSavingCalibration = false
    @Published private(set) var isGradingReview = false
    @Published private(set) var busyCoffeeIDs: Set<UUID> = []
    @Published private(set) var busyRecommendationIDs: Set<UUID> = []
    @Published var searchText = ""

    private let database: any VectorMemoryRepository
    private let engine = TasteMemoryEngine()
    private var signals: [MemorySignal] = []
    private var reviewCards: [ReviewCard] = []
    private var activeRecommendationSessionID: UUID?
    private var lastExposedRecommendationID: UUID?
    private var recommendationSeed = UInt64.random(in: UInt64.min...UInt64.max)
    private var dashboardRevision = 0
    private var pendingAttributions: [UUID: RecommendationAttribution] = [:]
    private let recommendationPolicyVersion = RecommendationPolicy.version

    init(database: any VectorMemoryRepository = VectorDatabaseService.shared) {
        self.database = database
    }

    var filteredCoffees: [AnalyzedCoffee] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return coffees }
        return coffees.filter { coffee in
            coffee.coffeeType.rawValue.localizedCaseInsensitiveContains(query) ||
            coffee.origin?.localizedCaseInsensitiveContains(query) == true ||
            coffee.brewMethod?.localizedCaseInsensitiveContains(query) == true ||
            coffee.notes.localizedCaseInsensitiveContains(query) ||
            coffee.flavorProfile.flavorNotes.contains {
                $0.localizedCaseInsensitiveContains(query)
            }
        }
    }

    var nextReview: ReviewCard? { dashboard.dueCards.first }
    var needsCalibration: Bool {
        hasStarted && !startupFailed && calibration == nil && coffees.isEmpty && !isLoading
    }
    var policyDiagnostics: RecommendationPolicyDiagnostics {
        engine.policyDiagnostics(signals: signals)
    }

    func start() async {
        guard !isLoading, !hasStarted || startupFailed else { return }
        isLoading = true
        startupFailed = false
        errorMessage = nil
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
            startupFailed = true
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func addCoffee(_ coffee: AnalyzedCoffee) async -> Bool {
        guard busyCoffeeIDs.insert(coffee.id).inserted else { return false }
        defer { busyCoffeeIDs.remove(coffee.id) }
        errorMessage = nil
        let cards = engine.reviewCards(for: coffee)
        var newSignals = [MemorySignal(coffeeID: coffee.id, kind: .tasted, value: 1)]
        if let rating = coffee.rating {
            newSignals.append(MemorySignal(coffeeID: coffee.id, kind: .rated, value: rating / 5))
        }
        let attribution = coffee.sourceCandidateID.flatMap { pendingAttributions[$0] }
        if let candidateID = coffee.sourceCandidateID {
            newSignals.append(MemorySignal(
                coffeeID: candidateID,
                kind: .recommendationConverted,
                value: (coffee.rating ?? 3.5) / 5,
                position: attribution?.position,
                policyScore: attribution?.score,
                policyProbability: attribution?.probability,
                policyVersion: attribution?.policyVersion,
                catalogVersion: attribution?.catalogVersion,
                sessionID: attribution?.sessionID
            ))
        }
        do {
            try await database.saveTasting(coffee, cards: cards, signals: newSignals)
            if let candidateID = coffee.sourceCandidateID {
                pendingAttributions.removeValue(forKey: candidateID)
            }
            coffees.removeAll { $0.id == coffee.id }
            coffees.insert(coffee, at: 0)
            signals.append(contentsOf: newSignals)
            mergeNewCards(cards)
            renewRecommendationPolicy()
            await rebuildDashboard()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func rate(_ coffeeID: UUID, rating: Double) async -> Bool {
        guard let index = coffees.firstIndex(where: { $0.id == coffeeID }),
              busyCoffeeIDs.insert(coffeeID).inserted else { return false }
        defer { busyCoffeeIDs.remove(coffeeID) }
        errorMessage = nil
        var updatedCoffee = coffees[index]
        updatedCoffee.rating = rating.clamped(to: 0...5)
        let cards = engine.reviewCards(for: updatedCoffee)
        let signal = MemorySignal(
            coffeeID: coffeeID,
            kind: .rated,
            value: rating.clamped(to: 0...5) / 5
        )
        do {
            try await database.saveTasting(updatedCoffee, cards: cards, signals: [signal])
            coffees[index] = updatedCoffee
            signals.append(signal)
            mergeNewCards(cards)
            renewRecommendationPolicy()
            await rebuildDashboard()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func toggleFavorite(_ coffeeID: UUID) async -> Bool {
        guard busyCoffeeIDs.insert(coffeeID).inserted else { return false }
        defer { busyCoffeeIDs.remove(coffeeID) }
        errorMessage = nil
        let isRemoving = favorites.contains(coffeeID)
        let signal = MemorySignal(
            coffeeID: coffeeID,
            kind: isRemoving ? .unfavorited : .favorited,
            value: isRemoving ? 0 : 1
        )
        do {
            try await database.append(signal)
            if isRemoving {
                favorites.remove(coffeeID)
            } else {
                favorites.insert(coffeeID)
            }
            signals.append(signal)
            renewRecommendationPolicy()
            await rebuildDashboard()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func exposeRecommendations() async {
        guard !dashboard.recommendations.isEmpty,
              lastExposedRecommendationID != recommendationExposureID,
              !isExposingRecommendations else { return }
        isExposingRecommendations = true
        defer { isExposingRecommendations = false }
        let exposureID = recommendationExposureID
        let sessionID = UUID()
        let recommendations = dashboard.recommendations
        let exposureSignals = recommendations.enumerated().map { index, recommendation in
            MemorySignal(
                coffeeID: recommendation.id,
                kind: .recommendationShown,
                value: 1,
                position: index + 1,
                policyScore: recommendation.score,
                policyProbability: recommendation.selectionProbability,
                policyVersion: recommendationPolicyVersion,
                catalogVersion: CoffeeCatalog.version,
                policyActions: recommendation.policyActions,
                sessionID: sessionID
            )
        }
        do {
            try await database.append(exposureSignals)
            signals.append(contentsOf: exposureSignals)
            if recommendationExposureID == exposureID {
                activeRecommendationSessionID = sessionID
                lastExposedRecommendationID = exposureID
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func recordRecommendation(_ recommendation: MemoryRecommendation, opened: Bool) async -> Bool {
        guard busyRecommendationIDs.insert(recommendation.id).inserted else { return false }
        defer { busyRecommendationIDs.remove(recommendation.id) }
        errorMessage = nil
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
            if opened, let sessionID = activeRecommendationSessionID {
                pendingAttributions[recommendation.id] = RecommendationAttribution(
                    sessionID: sessionID,
                    position: position,
                    score: recommendation.score,
                    probability: recommendation.selectionProbability,
                    policyVersion: recommendationPolicyVersion,
                    catalogVersion: CoffeeCatalog.version
                )
            } else {
                pendingAttributions.removeValue(forKey: recommendation.id)
                renewRecommendationPolicy()
                await rebuildDashboard()
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func gradeNextReview(_ grade: ReviewGrade) async -> Bool {
        guard let card = nextReview, !isGradingReview else { return false }
        isGradingReview = true
        defer { isGradingReview = false }
        errorMessage = nil
        let updated = engine.applyReview(grade, to: card)
        do {
            try await database.update(updated)
            if let index = reviewCards.firstIndex(where: { $0.id == updated.id }) {
                reviewCards[index] = updated
            }
            await rebuildDashboard()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func delete(_ coffeeID: UUID) async -> Bool {
        guard busyCoffeeIDs.insert(coffeeID).inserted else { return false }
        defer { busyCoffeeIDs.remove(coffeeID) }
        errorMessage = nil
        do {
            try await database.deleteCoffee(coffeeID)
            coffees.removeAll { $0.id == coffeeID }
            favorites.remove(coffeeID)
            signals.removeAll { $0.coffeeID == coffeeID }
            reviewCards.removeAll { $0.coffeeID == coffeeID }
            renewRecommendationPolicy()
            await rebuildDashboard()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func saveCalibration(_ value: TasteCalibration) async -> Bool {
        guard !isSavingCalibration else { return false }
        isSavingCalibration = true
        defer { isSavingCalibration = false }
        errorMessage = nil
        do {
            try await database.saveCalibration(value)
            calibration = value
            renewRecommendationPolicy()
            await rebuildDashboard()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
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
        pendingAttributions = replayPendingAttributions(signals)
        renewRecommendationPolicy()
        await rebuildDashboard()
    }

    private func rebuildDashboard(now: Date = Date()) async {
        dashboardRevision += 1
        let revision = dashboardRevision
        let engine = self.engine
        let coffees = self.coffees
        let signals = self.signals
        let calibration = self.calibration
        let reviewCards = self.reviewCards
        let seed = recommendationSeed
        let updated = await Task.detached(priority: .userInitiated) {
            let profile = engine.buildProfile(
                coffees: coffees,
                signals: signals,
                calibration: calibration,
                now: now
            )
            return MemoryDashboard(
                profile: profile,
                recommendations: engine.recommendations(
                    profile: profile,
                    memories: coffees,
                    signals: signals,
                    samplingSeed: seed
                ),
                dueCards: engine.interleavedDueCards(reviewCards, now: now),
                totalMemories: coffees.count,
                memoryHealth: engine.memoryHealth(cards: reviewCards, now: now)
            )
        }.value
        guard dashboardRevision == revision else { return }
        dashboard = updated
    }

    private func renewRecommendationPolicy() {
        recommendationSeed = UInt64.random(in: UInt64.min...UInt64.max)
        recommendationExposureID = UUID()
        activeRecommendationSessionID = nil
    }

    private func mergeNewCards(_ cards: [ReviewCard]) {
        for card in cards where !reviewCards.contains(where: {
            $0.coffeeID == card.coffeeID && $0.concept == card.concept
        }) {
            reviewCards.append(card)
        }
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

    private func replayPendingAttributions(_ signals: [MemorySignal]) -> [UUID: RecommendationAttribution] {
        var result: [UUID: RecommendationAttribution] = [:]
        for signal in signals.sorted(by: { $0.timestamp < $1.timestamp }) {
            switch signal.kind {
            case .recommendationOpened:
                guard let sessionID = signal.sessionID,
                      let score = signal.policyScore,
                      let probability = signal.policyProbability else { continue }
                result[signal.coffeeID] = RecommendationAttribution(
                    sessionID: sessionID,
                    position: signal.position,
                    score: score,
                    probability: probability,
                    policyVersion: signal.policyVersion,
                    catalogVersion: signal.catalogVersion
                )
            case .recommendationConverted:
                result.removeValue(forKey: signal.coffeeID)
            case .recommendationSkipped:
                result.removeValue(forKey: signal.coffeeID)
            default:
                break
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
    let policyVersion: String?
    let catalogVersion: String?
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
