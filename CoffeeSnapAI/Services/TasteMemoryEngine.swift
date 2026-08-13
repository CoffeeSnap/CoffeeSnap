import Foundation

/// Stateless learning and ranking logic. Keeping policy out of persistence makes
/// it testable and lets a future Pinecone/Weaviate adapter reuse the same model.
struct TasteMemoryEngine: Sendable {
    private let embedding = CoffeeEmbeddingService()
    private let calendar = Calendar(identifier: .gregorian)
    private let preferenceHalfLifeDays = 120.0

    func buildProfile(
        coffees: [AnalyzedCoffee],
        signals: [MemorySignal],
        calibration: TasteCalibration? = nil,
        now: Date = Date()
    ) -> TasteProfile {
        guard !coffees.isEmpty || calibration != nil else { return .empty }
        let signalsByCoffee = Dictionary(grouping: signals, by: \.coffeeID)
        var centroid = Array(repeating: Float.zero, count: CoffeeEmbeddingService.dimension)
        var totalWeight = 0.0
        var axisTotals = [Double](repeating: 0, count: 4)
        var noteWeights: [String: Double] = [:]

        if let calibration {
            let anchor = calibrationCoffee(from: calibration)
            let calibrationWeight = 1.25
            let vector = embedding.embed(anchor)
            for index in centroid.indices {
                centroid[index] += vector[index] * Float(calibrationWeight)
            }
            axisTotals[0] = calibration.acidity * calibrationWeight
            axisTotals[1] = calibration.body * calibrationWeight
            axisTotals[2] = calibration.sweetness * calibrationWeight
            axisTotals[3] = calibration.bitterness * calibrationWeight
            for note in calibration.flavorNotes {
                noteWeights[note, default: 0] += calibrationWeight
            }
            totalWeight = calibrationWeight
        }

        for coffee in coffees {
            let coffeeSignals = signalsByCoffee[coffee.id] ?? []
            let reward = learnedReward(for: coffee, signals: coffeeSignals)
            let age = max(0, now.timeIntervalSince(coffee.analysisDate) / 86_400)
            let recency = pow(0.5, age / preferenceHalfLifeDays)
            let evidence = (0.35 + 0.65 * coffee.confidence) * recency
            // Neutral observations remain weak evidence; explicit feedback dominates.
            let preference = max(0.05, (reward - 0.35) / 0.65)
            let weight = evidence * preference
            let vector = embedding.embed(coffee)
            for index in centroid.indices {
                centroid[index] += vector[index] * Float(weight)
            }
            axisTotals[0] += coffee.flavorProfile.acidity * weight
            axisTotals[1] += coffee.flavorProfile.body * weight
            axisTotals[2] += coffee.flavorProfile.sweetness * weight
            axisTotals[3] += coffee.flavorProfile.bitterness * weight
            for note in coffee.flavorProfile.flavorNotes {
                noteWeights[note.lowercased(), default: 0] += weight
            }
            totalWeight += weight
        }

        guard totalWeight > 0 else { return .empty }
        let topNotes = noteWeights
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }
            .prefix(4)
            .map(\.key)

        return TasteProfile(
            vector: normalized(centroid),
            acidity: axisTotals[0] / totalWeight,
            body: axisTotals[1] / totalWeight,
            sweetness: axisTotals[2] / totalWeight,
            bitterness: axisTotals[3] / totalWeight,
            adventure: calibration?.adventure ?? 0.5,
            confidence: min(1, 1 - exp(-totalWeight / 3.5)),
            observationCount: coffees.count,
            topNotes: topNotes
        )
    }

    func recommendations(
        profile: TasteProfile,
        memories: [AnalyzedCoffee],
        signals: [MemorySignal],
        candidates: [CoffeeCandidate] = CoffeeCatalog.candidates,
        limit: Int = 5,
        samplingSeed: UInt64 = 0
    ) -> [MemoryRecommendation] {
        let exposureSignals = signals.filter {
            $0.kind == .recommendationShown ||
            $0.kind == .recommendationOpened ||
            $0.kind == .recommendationSkipped
        }
        let typeCounts = Dictionary(grouping: memories, by: \.coffeeType).mapValues(\.count)
        let totalExposure = max(1, exposureSignals.count + memories.count)
        let historyVectors = memories.map(embedding.embed)
        let signalsByCandidate = Dictionary(grouping: signals, by: \.coffeeID)
        let sensoryCorrection = learnedSensoryCorrection(memories: memories, candidates: candidates)

        var pool = candidates.map { candidate -> RankedCandidate in
            // Catalog descriptors are a population prior. Once a user adjusts
            // predicted tasting axes, a shrinkage estimate becomes their private
            // sensory lens for all future candidates.
            let vector = embedding.embed(adjustedCoffee(candidate, by: sensoryCorrection))
            let rawMatch = profile.vector.isEmpty ? 0 : embedding.cosineSimilarity(profile.vector, vector)
            let match = profile.vector.isEmpty ? 0.55 : ((rawMatch + 1) / 2).clamped(to: 0...1)
            let closestHistory = historyVectors.map { embedding.cosineSimilarity($0, vector) }.max() ?? 0
            let semanticNovelty = (1 - max(0, closestHistory)).clamped(to: 0...1)
            let triedCount = typeCounts[candidate.coffeeType, default: 0]
            let exploration = sqrt(log(Double(totalExposure) + 2) / Double(triedCount + 1))
            let explorationScore = min(1, exploration / 1.4)
            let noteAffinity = noteOverlap(profile.topNotes, candidate.flavorProfile.flavorNotes)
            let behaviorAffinity = candidateAffinity(signalsByCandidate[candidate.id] ?? [])

            let matchWeight = 0.60 - (0.16 * profile.adventure)
            let noveltyWeight = 0.08 + (0.10 * profile.adventure)
            let explorationWeight = 0.08 + (0.08 * profile.adventure)
            let score = (
                match * matchWeight +
                semanticNovelty * noveltyWeight +
                explorationScore * explorationWeight +
                noteAffinity * 0.10 +
                behaviorAffinity * 0.12 +
                0.04
            ).clamped(to: 0...1)
            let isExploration = triedCount == 0 && semanticNovelty > 0.18
            return RankedCandidate(
                recommendation: MemoryRecommendation(
                    candidate: candidate,
                    match: match,
                    novelty: semanticNovelty,
                    score: score,
                    reason: explanation(for: candidate, profile: profile, isExploration: isExploration),
                    isExploration: isExploration,
                    behaviorAffinity: behaviorAffinity,
                    selectionProbability: 1,
                    policyActions: []
                ),
                vector: vector
            )
        }

        // Sequential epsilon-softmax sampling preserves the MMR diversity
        // objective while assigning every available action a known, non-zero
        // probability. This bounded randomization creates the overlap required
        // for counterfactual evaluation without turning discovery into roulette.
        var selected: [MemoryRecommendation] = []
        var selectedVectors: [[Float]] = []
        var random = SplitMix64(seed: samplingSeed)
        let explorationMass = (0.08 + 0.12 * profile.adventure).clamped(to: 0.08...0.20)
        let temperature = 0.055 + 0.035 * profile.adventure
        while !pool.isEmpty, selected.count < limit {
            let utilities = pool.map {
                diversifiedScore($0.recommendation, vector: $0.vector, selectedVectors: selectedVectors)
            }
            let probabilities = boundedSoftmax(
                utilities,
                temperature: temperature,
                explorationMass: explorationMass
            )
            let actions = zip(zip(pool, utilities), probabilities).map { pair, probability in
                PolicyActionProbability(
                    candidateID: pair.0.recommendation.id,
                    utility: pair.1,
                    probability: probability
                )
            }
            let nextIndex = random.sampleIndex(probabilities)
            let choice = pool.remove(at: nextIndex)
            let recommendation = choice.recommendation
            selected.append(MemoryRecommendation(
                candidate: recommendation.candidate,
                match: recommendation.match,
                novelty: recommendation.novelty,
                score: recommendation.score,
                reason: recommendation.reason,
                isExploration: recommendation.isExploration,
                behaviorAffinity: recommendation.behaviorAffinity,
                selectionProbability: probabilities[nextIndex],
                policyActions: actions
            ))
            selectedVectors.append(choice.vector)
        }
        return selected
    }

    func policyDiagnostics(signals: [MemorySignal]) -> RecommendationPolicyDiagnostics {
        let exposures = signals.filter {
            $0.kind == .recommendationShown &&
            $0.policyProbability != nil &&
            !($0.policyActions ?? []).isEmpty
        }
        guard !exposures.isEmpty else { return .empty }

        let entropies = exposures.compactMap { signal -> Double? in
            guard let actions = signal.policyActions, actions.count > 1 else { return nil }
            let entropy = -actions.reduce(0.0) { partial, action in
                let probability = action.probability.clamped(to: 1e-12...1)
                return partial + probability * log(probability)
            }
            return (entropy / log(Double(actions.count))).clamped(to: 0...1)
        }
        let minimum = exposures.compactMap(\.policyProbability).min() ?? 0
        return RecommendationPolicyDiagnostics(
            auditedSessions: Set(exposures.compactMap(\.sessionID)).count,
            loggedExposures: exposures.count,
            meanNormalizedEntropy: entropies.isEmpty ? 0 : entropies.reduce(0, +) / Double(entropies.count),
            minimumPropensity: minimum
        )
    }

    func reviewCards(for coffee: AnalyzedCoffee, now: Date = Date()) -> [ReviewCard] {
        var cards: [ReviewCard] = []
        if let origin = coffee.origin, !origin.isEmpty {
            cards.append(ReviewCard(
                coffeeID: coffee.id,
                concept: .origin,
                prompt: "Where did this \(coffee.coffeeType.rawValue.lowercased()) most likely originate?",
                answer: origin,
                dueAt: now.addingTimeInterval(2 * 86_400)
            ))
        }
        if let brewMethod = coffee.brewMethod, !brewMethod.isEmpty {
            cards.append(ReviewCard(
                coffeeID: coffee.id,
                concept: .brew,
                prompt: "Which brew method was used for this \(coffee.coffeeType.rawValue.lowercased())?",
                answer: brewMethod,
                dueAt: now.addingTimeInterval(86_400)
            ))
        }
        cards.append(ReviewCard(
            coffeeID: coffee.id,
            concept: .roast,
            prompt: "Recall the roast level of this \(coffee.coffeeType.rawValue.lowercased()).",
            answer: coffee.roastLevel.rawValue,
            dueAt: now.addingTimeInterval(3 * 86_400)
        ))
        if !coffee.flavorProfile.flavorNotes.isEmpty {
            cards.append(ReviewCard(
                coffeeID: coffee.id,
                concept: .flavor,
                prompt: "Name at least one flavor note you noticed in this cup.",
                answer: coffee.flavorProfile.flavorNotes.joined(separator: ", "),
                dueAt: now.addingTimeInterval(20 * 60)
            ))
        }
        return cards
    }

    func applyReview(
        _ grade: ReviewGrade,
        to original: ReviewCard,
        now: Date = Date()
    ) -> ReviewCard {
        var card = original
        let elapsedDays = card.lastReviewedAt.map { max(0, now.timeIntervalSince($0) / 86_400) } ?? 0
        let retrievability = card.lastReviewedAt == nil
            ? 0.9
            : exp(log(0.9) * elapsedDays / max(0.1, card.stability))

        if card.repetitions == 0 {
            card.stability = [0.20, 0.75, 2.5, 5.0][grade.rawValue - 1]
        } else {
            switch grade {
            case .again:
                card.stability = max(0.20, card.stability * (0.35 + 0.10 * retrievability))
                card.difficulty = min(10, card.difficulty + 0.8)
                card.lapses += 1
            case .hard:
                card.stability *= 1.2 + (1 - retrievability) * 0.25
                card.difficulty = min(10, card.difficulty + 0.25)
            case .good:
                card.stability *= 1.7 + (1 - retrievability) * 0.9 + (10 - card.difficulty) / 20
                card.difficulty = max(1, card.difficulty - 0.15)
            case .easy:
                card.stability *= 2.6 + (1 - retrievability) * 1.2 + (10 - card.difficulty) / 15
                card.difficulty = max(1, card.difficulty - 0.5)
            }
        }

        card.repetitions += 1
        card.lastReviewedAt = now
        if grade == .again {
            card.dueAt = now.addingTimeInterval(10 * 60)
        } else {
            card.dueAt = calendar.date(byAdding: .minute, value: Int(max(0.5, card.stability) * 1_440), to: now) ?? now
        }
        return card
    }

    func interleavedDueCards(_ cards: [ReviewCard], now: Date = Date()) -> [ReviewCard] {
        let due = cards.filter { $0.dueAt <= now }.sorted { $0.dueAt < $1.dueAt }
        var queues = Dictionary(grouping: due, by: \.concept)
        var result: [ReviewCard] = []
        var previousConcept: CoffeeConcept?

        while !queues.values.allSatisfy(\.isEmpty) {
            let available = CoffeeConcept.allCases.filter { concept in
                concept != previousConcept && !(queues[concept] ?? []).isEmpty
            }
            let concept = available.first ?? CoffeeConcept.allCases.first { !(queues[$0] ?? []).isEmpty }
            guard let concept, var queue = queues[concept], !queue.isEmpty else { break }
            result.append(queue.removeFirst())
            queues[concept] = queue
            previousConcept = concept
        }
        return result
    }

    func memoryHealth(cards: [ReviewCard], now: Date = Date()) -> Double {
        guard !cards.isEmpty else { return 0 }
        let recall = cards.map { card -> Double in
            guard let lastReview = card.lastReviewedAt else { return card.dueAt > now ? 0.65 : 0.35 }
            let elapsed = max(0, now.timeIntervalSince(lastReview) / 86_400)
            return exp(log(0.9) * elapsed / max(0.1, card.stability))
        }
        return recall.reduce(0, +) / Double(recall.count)
    }

    private func learnedReward(for coffee: AnalyzedCoffee, signals: [MemorySignal]) -> Double {
        var reward = coffee.rating.map { $0 / 5 } ?? 0.55
        for signal in signals.sorted(by: { $0.timestamp < $1.timestamp }) {
            switch signal.kind {
            case .rated: reward = signal.value.clamped(to: 0...1)
            case .favorited: reward = min(1, reward + 0.18)
            case .unfavorited: reward = max(0, reward - 0.12)
            case .recommendationOpened: reward = min(1, reward + 0.04)
            case .recommendationSkipped: reward = max(0, reward - 0.04)
            case .recommendationConverted: reward = signal.value.clamped(to: 0...1)
            case .recommendationShown: break
            case .tasted: break
            }
        }
        return reward
    }

    private func noteOverlap(_ preferred: [String], _ candidate: [String]) -> Double {
        guard !preferred.isEmpty, !candidate.isEmpty else { return 0 }
        let left = Set(preferred.map { $0.lowercased() })
        let right = Set(candidate.map { $0.lowercased() })
        return Double(left.intersection(right).count) / Double(left.union(right).count)
    }

    private func candidateAffinity(_ signals: [MemorySignal]) -> Double {
        var positive = 1.0
        var evidence = 2.0
        for signal in signals {
            switch signal.kind {
            case .recommendationOpened:
                positive += 0.6
                evidence += 1
            case .recommendationSkipped:
                evidence += 1
            case .recommendationConverted:
                positive += 1 + signal.value.clamped(to: 0...1)
                evidence += 2
            case .recommendationShown:
                break
            default:
                break
            }
        }
        return (positive / evidence).clamped(to: 0...1)
    }

    private func learnedSensoryCorrection(
        memories: [AnalyzedCoffee],
        candidates: [CoffeeCandidate],
        now: Date = Date()
    ) -> SensoryCorrection {
        let catalog = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        var totals = [Double](repeating: 0, count: 4)
        var totalWeight = 0.0
        var count = 0

        for memory in memories {
            guard let sourceID = memory.sourceCandidateID,
                  let predicted = catalog[sourceID]?.flavorProfile else { continue }
            let ageDays = max(0, now.timeIntervalSince(memory.analysisDate) / 86_400)
            let recency = pow(0.5, ageDays / preferenceHalfLifeDays)
            let weight = (0.5 + 0.5 * memory.confidence) * recency
            totals[0] += (memory.flavorProfile.acidity - predicted.acidity) * weight
            totals[1] += (memory.flavorProfile.body - predicted.body) * weight
            totals[2] += (memory.flavorProfile.sweetness - predicted.sweetness) * weight
            totals[3] += (memory.flavorProfile.bitterness - predicted.bitterness) * weight
            totalWeight += weight
            count += 1
        }

        // Two pseudo-observations at zero prevent one unusual cup from shifting
        // every recommendation too aggressively.
        let denominator = totalWeight + 2
        guard denominator > 2 else { return .zero }
        return SensoryCorrection(
            acidity: totals[0] / denominator,
            body: totals[1] / denominator,
            sweetness: totals[2] / denominator,
            bitterness: totals[3] / denominator,
            evidenceCount: count
        )
    }

    private func adjustedCoffee(
        _ candidate: CoffeeCandidate,
        by correction: SensoryCorrection
    ) -> AnalyzedCoffee {
        guard correction.evidenceCount > 0 else { return candidate.asAnalyzedCoffee }
        var coffee = candidate.asAnalyzedCoffee
        let profile = candidate.flavorProfile
        coffee.flavorProfile = FlavorProfile(
            acidity: profile.acidity + correction.acidity,
            body: profile.body + correction.body,
            sweetness: profile.sweetness + correction.sweetness,
            bitterness: profile.bitterness + correction.bitterness,
            flavorNotes: profile.flavorNotes
        )
        return coffee
    }

    private func calibrationCoffee(from calibration: TasteCalibration) -> AnalyzedCoffee {
        AnalyzedCoffee(
            imageData: nil,
            coffeeType: .unknown,
            confidence: 0.8,
            analysisDate: calibration.updatedAt,
            roastLevel: .medium,
            notes: "Initial palate calibration",
            flavorProfile: FlavorProfile(
                acidity: calibration.acidity,
                body: calibration.body,
                sweetness: calibration.sweetness,
                bitterness: calibration.bitterness,
                flavorNotes: calibration.flavorNotes
            )
        )
    }

    private func explanation(for candidate: CoffeeCandidate, profile: TasteProfile, isExploration: Bool) -> String {
        let candidateAxes = [
            ("brightness", candidate.flavorProfile.acidity, profile.acidity),
            ("body", candidate.flavorProfile.body, profile.body),
            ("sweetness", candidate.flavorProfile.sweetness, profile.sweetness),
            ("boldness", candidate.flavorProfile.bitterness, profile.bitterness)
        ]
        let closest = candidateAxes.min { abs($0.1 - $0.2) < abs($1.1 - $1.2) }?.0 ?? "balance"
        let sharedNote = candidate.flavorProfile.flavorNotes.first { note in
            profile.topNotes.contains(note.lowercased())
        }
        if isExploration {
            return "A deliberate stretch beyond your usual cups, anchored by familiar \(closest)."
        }
        if let sharedNote {
            return "Matches your \(closest) preference and your affinity for \(sharedNote.lowercased())."
        }
        return "Close to your learned \(profile.signature.lowercased()) profile, especially on \(closest)."
    }

    private func diversifiedScore(
        _ recommendation: MemoryRecommendation,
        vector: [Float],
        selectedVectors: [[Float]]
    ) -> Double {
        guard !selectedVectors.isEmpty else { return recommendation.score }
        let redundancy = selectedVectors
            .map { embedding.cosineSimilarity(vector, $0) }
            .max() ?? 0
        return recommendation.score - max(0, redundancy) * 0.14
    }

    private func boundedSoftmax(
        _ utilities: [Double],
        temperature: Double,
        explorationMass: Double
    ) -> [Double] {
        guard utilities.count > 1 else { return utilities.isEmpty ? [] : [1] }
        let maximum = utilities.max() ?? 0
        let weights = utilities.map { exp(($0 - maximum) / max(0.01, temperature)) }
        let total = weights.reduce(0, +)
        let uniform = 1 / Double(utilities.count)
        let epsilon = explorationMass.clamped(to: 0...1)
        let probabilities = weights.map { weight in
            (1 - epsilon) * (weight / max(total, .leastNonzeroMagnitude)) + epsilon * uniform
        }
        let normalization = probabilities.reduce(0, +)
        return probabilities.map { $0 / normalization }
    }

    private func normalized(_ vector: [Float]) -> [Float] {
        let magnitude = sqrt(vector.reduce(Float.zero) { $0 + ($1 * $1) })
        guard magnitude > 0 else { return vector }
        return vector.map { $0 / magnitude }
    }
}

private struct RankedCandidate {
    let recommendation: MemoryRecommendation
    let vector: [Float]
}

private struct SensoryCorrection {
    static let zero = SensoryCorrection(
        acidity: 0,
        body: 0,
        sweetness: 0,
        bitterness: 0,
        evidenceCount: 0
    )

    let acidity: Double
    let body: Double
    let sweetness: Double
    let bitterness: Double
    let evidenceCount: Int
}

enum CoffeeCatalog {
    static let version = "coffee-catalog-v1"
    static let candidates: [CoffeeCandidate] = [
        CoffeeCandidate(
            id: UUID(uuidString: "C0FFEE00-0000-4000-8000-000000000001")!,
            name: "Ethiopian Natural V60",
            coffeeType: .pourOver,
            roastLevel: .light,
            brewMethod: "V60 pour over",
            origin: "Guji, Ethiopia",
            flavorProfile: FlavorProfile(acidity: 0.88, body: 0.38, sweetness: 0.78, bitterness: 0.12, flavorNotes: ["blueberry", "jasmine", "cocoa"]),
            story: "A fruit-forward natural process cup that rewards a slow, mindful tasting."
        ),
        CoffeeCandidate(
            id: UUID(uuidString: "C0FFEE00-0000-4000-8000-000000000002")!,
            name: "Colombian Honey Flat White",
            coffeeType: .flatWhite,
            roastLevel: .medium,
            brewMethod: "Double ristretto + microfoam",
            origin: "Huila, Colombia",
            flavorProfile: FlavorProfile(acidity: 0.48, body: 0.78, sweetness: 0.82, bitterness: 0.25, flavorNotes: ["caramel", "red apple", "almond"]),
            story: "Silky milk meets a honey-process espresso with a long caramel finish."
        ),
        CoffeeCandidate(
            id: UUID(uuidString: "C0FFEE00-0000-4000-8000-000000000003")!,
            name: "Sumatran French Press",
            coffeeType: .frenchPress,
            roastLevel: .mediumDark,
            brewMethod: "Four-minute French press",
            origin: "Aceh, Indonesia",
            flavorProfile: FlavorProfile(acidity: 0.18, body: 0.95, sweetness: 0.35, bitterness: 0.62, flavorNotes: ["cedar", "dark chocolate", "spice"]),
            story: "A heavy, earthy cup designed for people who enjoy texture and depth."
        ),
        CoffeeCandidate(
            id: UUID(uuidString: "C0FFEE00-0000-4000-8000-000000000004")!,
            name: "Kenyan Flash Cold Brew",
            coffeeType: .coldBrew,
            roastLevel: .light,
            brewMethod: "Flash-chilled pour over",
            origin: "Nyeri, Kenya",
            flavorProfile: FlavorProfile(acidity: 0.78, body: 0.45, sweetness: 0.7, bitterness: 0.16, flavorNotes: ["blackcurrant", "grapefruit", "brown sugar"]),
            story: "Flash chilling preserves sparkling acidity without the heaviness of immersion cold brew."
        ),
        CoffeeCandidate(
            id: UUID(uuidString: "C0FFEE00-0000-4000-8000-000000000005")!,
            name: "Brazilian Cacao Espresso",
            coffeeType: .espresso,
            roastLevel: .mediumDark,
            brewMethod: "1:2 espresso, 28 seconds",
            origin: "Minas Gerais, Brazil",
            flavorProfile: FlavorProfile(acidity: 0.28, body: 0.9, sweetness: 0.64, bitterness: 0.55, flavorNotes: ["dark chocolate", "hazelnut", "molasses"]),
            story: "A forgiving, syrupy espresso with classic chocolate-and-nut comfort."
        ),
        CoffeeCandidate(
            id: UUID(uuidString: "C0FFEE00-0000-4000-8000-000000000006")!,
            name: "Costa Rican AeroPress",
            coffeeType: .aeropress,
            roastLevel: .mediumLight,
            brewMethod: "Inverted AeroPress",
            origin: "Tarrazú, Costa Rica",
            flavorProfile: FlavorProfile(acidity: 0.62, body: 0.58, sweetness: 0.75, bitterness: 0.22, flavorNotes: ["orange", "honey", "pecan"]),
            story: "A compact brew with honey sweetness, clarity, and enough body for balance."
        ),
        CoffeeCandidate(
            id: UUID(uuidString: "C0FFEE00-0000-4000-8000-000000000007")!,
            name: "Vietnamese Iced Coffee",
            coffeeType: .vietnamese,
            roastLevel: .dark,
            brewMethod: "Phin over condensed milk",
            origin: "Đắk Lắk, Vietnam",
            flavorProfile: FlavorProfile(acidity: 0.12, body: 0.92, sweetness: 0.96, bitterness: 0.68, flavorNotes: ["cocoa", "condensed milk", "roasted nuts"]),
            story: "An intense robusta-led brew transformed by ice and condensed milk."
        ),
        CoffeeCandidate(
            id: UUID(uuidString: "C0FFEE00-0000-4000-8000-000000000008")!,
            name: "Panama Gesha Tasting",
            coffeeType: .pourOver,
            roastLevel: .light,
            brewMethod: "Low-agitation conical pour over",
            origin: "Boquete, Panama",
            flavorProfile: FlavorProfile(acidity: 0.84, body: 0.3, sweetness: 0.74, bitterness: 0.08, flavorNotes: ["jasmine", "bergamot", "peach"]),
            story: "A high-novelty floral cup for calibrating aroma and delicate acidity."
        )
    ]
}

enum RecommendationPolicy {
    static let version = "taste-bandit-v4-bounded-softmax"
}

private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func sampleIndex(_ probabilities: [Double]) -> Int {
        guard probabilities.count > 1 else { return 0 }
        let draw = nextUnitInterval()
        var cumulative = 0.0
        for (index, probability) in probabilities.enumerated() {
            cumulative += probability
            if draw < cumulative { return index }
        }
        return probabilities.index(before: probabilities.endIndex)
    }

    private mutating func nextUnitInterval() -> Double {
        Double(next() >> 11) * 0x1.0p-53
    }

    private mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
