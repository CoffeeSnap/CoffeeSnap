import Foundation

/// The signals CoffeeSnap can learn from without uploading a user's journal.
enum MemorySignalKind: String, Codable, Sendable {
    case tasted
    case rated
    case favorited
    case unfavorited
    case recommendationOpened
    case recommendationSkipped
    case recommendationShown
    case recommendationConverted
}

struct MemorySignal: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let coffeeID: UUID
    let kind: MemorySignalKind
    let value: Double
    let timestamp: Date
    let position: Int?
    let policyScore: Double?
    /// Exact conditional probability assigned by the logging policy at this
    /// slate position. Products across a session recover the ordered-slate
    /// propensity.
    let policyProbability: Double?
    let policyVersion: String?
    let catalogVersion: String?
    /// The complete distribution over actions that were available at this
    /// position. This makes exploration auditable instead of logging only the
    /// winning item.
    let policyActions: [PolicyActionProbability]?
    let sessionID: UUID?

    init(
        id: UUID = UUID(),
        coffeeID: UUID,
        kind: MemorySignalKind,
        value: Double,
        timestamp: Date = Date(),
        position: Int? = nil,
        policyScore: Double? = nil,
        policyProbability: Double? = nil,
        policyVersion: String? = nil,
        catalogVersion: String? = nil,
        policyActions: [PolicyActionProbability]? = nil,
        sessionID: UUID? = nil
    ) {
        self.id = id
        self.coffeeID = coffeeID
        self.kind = kind
        self.value = value
        self.timestamp = timestamp
        self.position = position
        self.policyScore = policyScore
        self.policyProbability = policyProbability
        self.policyVersion = policyVersion
        self.catalogVersion = catalogVersion
        self.policyActions = policyActions
        self.sessionID = sessionID
    }
}

struct PolicyActionProbability: Codable, Equatable, Sendable {
    let candidateID: UUID
    let utility: Double
    let probability: Double
}

struct TasteCalibration: Codable, Equatable, Sendable {
    let acidity: Double
    let body: Double
    let sweetness: Double
    let bitterness: Double
    let adventure: Double
    let flavorNotes: [String]
    let updatedAt: Date

    init(
        acidity: Double,
        body: Double,
        sweetness: Double,
        bitterness: Double,
        adventure: Double,
        flavorNotes: [String],
        updatedAt: Date = Date()
    ) {
        self.acidity = acidity.clamped(to: 0...1)
        self.body = body.clamped(to: 0...1)
        self.sweetness = sweetness.clamped(to: 0...1)
        self.bitterness = bitterness.clamped(to: 0...1)
        self.adventure = adventure.clamped(to: 0...1)
        self.flavorNotes = Array(Set(flavorNotes.map { $0.lowercased() })).sorted()
        self.updatedAt = updatedAt
    }
}

struct TasteProfile: Codable, Equatable, Sendable {
    static let empty = TasteProfile(
        vector: [],
        acidity: 0.5,
        body: 0.5,
        sweetness: 0.5,
        bitterness: 0.5,
        adventure: 0.5,
        confidence: 0,
        observationCount: 0,
        topNotes: []
    )

    let vector: [Float]
    let acidity: Double
    let body: Double
    let sweetness: Double
    let bitterness: Double
    let adventure: Double
    let confidence: Double
    let observationCount: Int
    let topNotes: [String]

    var isColdStart: Bool { observationCount < 3 }

    var signature: String {
        let dimensions = [
            ("bright", acidity),
            ("full-bodied", body),
            ("sweet", sweetness),
            ("bold", bitterness)
        ]
        let strongest = dimensions.sorted { $0.1 > $1.1 }.prefix(2).map(\.0)
        return strongest.isEmpty ? "Still learning" : strongest.joined(separator: " + ").capitalized
    }
}

struct CoffeeCandidate: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let coffeeType: CoffeeType
    let roastLevel: RoastLevel
    let brewMethod: String
    let origin: String
    let flavorProfile: FlavorProfile
    let story: String

    init(
        id: UUID = UUID(),
        name: String,
        coffeeType: CoffeeType,
        roastLevel: RoastLevel,
        brewMethod: String,
        origin: String,
        flavorProfile: FlavorProfile,
        story: String
    ) {
        self.id = id
        self.name = name
        self.coffeeType = coffeeType
        self.roastLevel = roastLevel
        self.brewMethod = brewMethod
        self.origin = origin
        self.flavorProfile = flavorProfile
        self.story = story
    }

    var asAnalyzedCoffee: AnalyzedCoffee {
        AnalyzedCoffee(
            id: id,
            imageData: nil,
            coffeeType: coffeeType,
            confidence: 1,
            brewMethod: brewMethod,
            roastLevel: roastLevel,
            notes: story,
            flavorProfile: flavorProfile,
            origin: origin,
            sourceCandidateID: id
        )
    }
}

struct MemoryRecommendation: Identifiable, Equatable, Sendable {
    let candidate: CoffeeCandidate
    let match: Double
    let novelty: Double
    let score: Double
    let reason: String
    let isExploration: Bool
    let behaviorAffinity: Double
    let selectionProbability: Double
    let policyActions: [PolicyActionProbability]

    var id: UUID { candidate.id }
}

struct RecommendationPolicyDiagnostics: Equatable, Sendable {
    static let empty = RecommendationPolicyDiagnostics(
        auditedSessions: 0,
        loggedExposures: 0,
        meanNormalizedEntropy: 0,
        minimumPropensity: 0
    )

    let auditedSessions: Int
    let loggedExposures: Int
    /// Zero is effectively deterministic; one is uniform over the available
    /// actions. A bounded non-zero value confirms that counterfactual overlap
    /// exists without requiring reckless random recommendations.
    let meanNormalizedEntropy: Double
    let minimumPropensity: Double
}

enum ReviewGrade: Int, CaseIterable, Codable, Sendable {
    case again = 1
    case hard = 2
    case good = 3
    case easy = 4

    var title: String {
        switch self {
        case .again: "Again"
        case .hard: "Hard"
        case .good: "Good"
        case .easy: "Easy"
        }
    }
}

enum CoffeeConcept: String, Codable, CaseIterable, Sendable {
    case origin
    case flavor
    case brew
    case roast
}

struct ReviewCard: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let coffeeID: UUID
    let concept: CoffeeConcept
    let prompt: String
    let answer: String
    var difficulty: Double
    var stability: Double
    var dueAt: Date
    var lastReviewedAt: Date?
    var repetitions: Int
    var lapses: Int

    init(
        id: UUID = UUID(),
        coffeeID: UUID,
        concept: CoffeeConcept,
        prompt: String,
        answer: String,
        difficulty: Double = 5,
        stability: Double = 1,
        dueAt: Date = Date(),
        lastReviewedAt: Date? = nil,
        repetitions: Int = 0,
        lapses: Int = 0
    ) {
        self.id = id
        self.coffeeID = coffeeID
        self.concept = concept
        self.prompt = prompt
        self.answer = answer
        self.difficulty = difficulty
        self.stability = stability
        self.dueAt = dueAt
        self.lastReviewedAt = lastReviewedAt
        self.repetitions = repetitions
        self.lapses = lapses
    }
}

struct MemoryDashboard: Equatable, Sendable {
    static let empty = MemoryDashboard(
        profile: .empty,
        recommendations: [],
        dueCards: [],
        totalMemories: 0,
        memoryHealth: 0
    )

    let profile: TasteProfile
    let recommendations: [MemoryRecommendation]
    let dueCards: [ReviewCard]
    let totalMemories: Int
    let memoryHealth: Double
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
