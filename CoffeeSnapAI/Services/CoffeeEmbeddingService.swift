import Foundation
import NaturalLanguage

/// Builds a compact, versioned multimodal embedding that remains usable offline.
///
/// The first 12 dimensions are interpretable coffee features. The remaining 20
/// are a deterministic projection of Apple's on-device sentence embedding, with
/// a feature-hashing fallback for devices where that model is unavailable.
struct CoffeeEmbeddingService: Sendable {
    static let modelVersion = "coffeesnap-hybrid-v2"
    static let dimension = 32

    func embed(_ coffee: AnalyzedCoffee) -> [Float] {
        var values = Array(repeating: Float.zero, count: Self.dimension)
        values[0] = Float(coffee.flavorProfile.acidity)
        values[1] = Float(coffee.flavorProfile.body)
        values[2] = Float(coffee.flavorProfile.sweetness)
        values[3] = Float(coffee.flavorProfile.bitterness)
        values[4] = roastPosition(coffee.roastLevel)
        values[5] = Float(coffee.confidence)

        let familyIndex = coffeeFamily(coffee.coffeeType)
        values[6 + familyIndex] = 1

        let semantic = semanticProjection(for: searchableText(for: coffee), dimension: 20)
        for (index, value) in semantic.enumerated() {
            values[12 + index] = value
        }
        return normalized(values)
    }

    func searchableText(for coffee: AnalyzedCoffee) -> String {
        [
            coffee.coffeeType.rawValue,
            coffee.roastLevel.rawValue,
            coffee.brewMethod ?? "",
            coffee.origin ?? "",
            coffee.flavorProfile.flavorNotes.joined(separator: " "),
            coffee.notes
        ]
        .filter { !$0.isEmpty }
        .joined(separator: ". ")
    }

    func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        var dot = Float.zero
        var leftMagnitude = Float.zero
        var rightMagnitude = Float.zero
        for index in lhs.indices {
            dot += lhs[index] * rhs[index]
            leftMagnitude += lhs[index] * lhs[index]
            rightMagnitude += rhs[index] * rhs[index]
        }
        guard leftMagnitude > 0, rightMagnitude > 0 else { return 0 }
        return Double(dot / sqrt(leftMagnitude * rightMagnitude))
    }

    private func semanticProjection(for text: String, dimension: Int) -> [Float] {
        guard !text.isEmpty else { return Array(repeating: 0, count: dimension) }
        let normalizedText = text.lowercased()
        let cacheKey = "\(Self.modelVersion)|\(dimension)|\(normalizedText)"
        return SemanticProjectionCache.shared.value(for: cacheKey) {
            computeSemanticProjection(for: normalizedText, dimension: dimension)
        }
    }

    private func computeSemanticProjection(for normalizedText: String, dimension: Int) -> [Float] {
        if let embedding = NLEmbedding.sentenceEmbedding(for: .english),
           let source = embedding.vector(for: normalizedText) {
            var projection = Array(repeating: Float.zero, count: dimension)
            for (index, value) in source.enumerated() {
                let bucket = (index &* 31 &+ 7) % dimension
                let sign: Float = ((index &* 17 &+ 3) % 2 == 0) ? 1 : -1
                projection[bucket] += Float(value) * sign
            }
            return normalized(projection)
        }

        var projection = Array(repeating: Float.zero, count: dimension)
        let tokens = normalizedText.split { !$0.isLetter && !$0.isNumber }
        for token in tokens {
            let hash = stableHash(String(token))
            let bucket = Int(hash % UInt64(dimension))
            let sign: Float = (hash & 1) == 0 ? 1 : -1
            projection[bucket] += sign
        }
        return normalized(projection)
    }

    private func stableHash(_ value: String) -> UInt64 {
        value.utf8.reduce(1_469_598_103_934_665_603) { hash, byte in
            (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }

    private func normalized(_ vector: [Float]) -> [Float] {
        let magnitude = sqrt(vector.reduce(Float.zero) { $0 + ($1 * $1) })
        guard magnitude > 0 else { return vector }
        return vector.map { $0 / magnitude }
    }

    private func roastPosition(_ roast: RoastLevel) -> Float {
        switch roast {
        case .light: 0
        case .mediumLight: 0.2
        case .medium: 0.4
        case .mediumDark: 0.6
        case .dark: 0.8
        case .extraDark: 1
        }
    }

    private func coffeeFamily(_ type: CoffeeType) -> Int {
        switch type {
        case .espresso, .americano, .redEye, .blackEye: 0
        case .latte, .flatWhite, .cappuccino, .macchiato, .cortado, .gibraltar, .breve: 1
        case .pourOver, .aeropress: 2
        case .frenchPress, .turkish: 3
        case .coldBrew, .nitroColdbrew, .vietnamese: 4
        case .mocha, .affogato, .unknown: 5
        }
    }
}

private final class SemanticProjectionCache: @unchecked Sendable {
    static let shared = SemanticProjectionCache()

    private let cache: NSCache<NSString, ProjectionBox> = {
        let cache = NSCache<NSString, ProjectionBox>()
        cache.countLimit = 512
        return cache
    }()

    func value(for key: String, create: () -> [Float]) -> [Float] {
        let cacheKey = key as NSString
        if let cached = cache.object(forKey: cacheKey) { return cached.values }
        let values = create()
        cache.setObject(ProjectionBox(values), forKey: cacheKey)
        return values
    }
}

private final class ProjectionBox: NSObject {
    let values: [Float]

    init(_ values: [Float]) {
        self.values = values
    }
}
