import Foundation
import SQLite
import simd

// MARK: - Vector Database Service
@MainActor
@available(iOS 17.0, macOS 10.15, *)
class VectorDatabaseService: ObservableObject {
    static let shared = VectorDatabaseService()
    
    private var db: Connection?
    private let dbPath: String
    private let vectorDimension = 16 // Flavor profile + metadata dimensions
    
    // Vector similarity thresholds
    private let similarityThreshold: Float = 0.8
    private let maxResults = 100
    
    // SQLite table definitions
    private let coffeeVectors = Table("coffee_vectors")
    private let id = Expression<String>(value: "id")
    private let coffeeType = Expression<String>(value: "coffee_type")
    private let roastLevel = Expression<String>(value: "roast_level")
    private let confidence = Expression<Double>(value: "confidence")
    private let analysisDate = Expression<String>(value: "analysis_date")
    private let origin = Expression<String?>(value: "origin")
    private let rating = Expression<Double?>(value: "rating")
    private let vector = Expression<Data>(value: "vector")
    private let flavorVector = Expression<Data>(value: "flavor_vector")
    private let metadata = Expression<Data?>(value: "metadata")
    private let createdAt = Expression<Date>(value: "created_at")
    
    init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        dbPath = documentsPath.appendingPathComponent("coffee_vectors.db").path
    }
    
    deinit {
        db = nil
    }
    
    // MARK: - Database Initialization
    func initialize() async {
        do {
            db = try Connection(dbPath)
            await createTables()
            await createIndexes()
            print("✅ Vector database initialized successfully")
        } catch {
            print("❌ Unable to open database: \(error)")
        }
    }
    
    private func createTables() async {
        guard let db = db else { return }
        
        do {
            try db.run(coffeeVectors.create(ifNotExists: true) { t in
                t.column(id, primaryKey: true)
                t.column(coffeeType)
                t.column(roastLevel)
                t.column(confidence)
                t.column(analysisDate)
                t.column(origin)
                t.column(rating)
                t.column(vector)
                t.column(flavorVector)
                t.column(metadata)
                t.column(createdAt, defaultValue: Date())
            })
        } catch {
            print("❌ Error creating tables: \(error)")
        }
    }
    
    private func createIndexes() async {
        guard let db = db else { return }
        
        do {
            try db.run("CREATE INDEX IF NOT EXISTS idx_coffee_type ON coffee_vectors(coffee_type)")
            try db.run("CREATE INDEX IF NOT EXISTS idx_roast_level ON coffee_vectors(roast_level)")
            try db.run("CREATE INDEX IF NOT EXISTS idx_confidence ON coffee_vectors(confidence)")
            try db.run("CREATE INDEX IF NOT EXISTS idx_rating ON coffee_vectors(rating)")
            try db.run("CREATE INDEX IF NOT EXISTS idx_analysis_date ON coffee_vectors(analysis_date)")
        } catch {
            print("❌ Error creating indexes: \(error)")
        }
    }
    
    // MARK: - Vector Generation
    private func generateCoffeeVector(from coffee: AnalyzedCoffee) -> [Float] {
        var vector: [Float] = []
        
        // Flavor profile components (4 dimensions)
        vector.append(Float(coffee.flavorProfile.acidity))
        vector.append(Float(coffee.flavorProfile.body))
        vector.append(Float(coffee.flavorProfile.sweetness))
        vector.append(Float(coffee.flavorProfile.bitterness))
        
        // Coffee type encoding (4 dimensions)
        let typeEncoding = encodeCoffeeType(coffee.coffeeType)
        vector.append(contentsOf: typeEncoding)
        
        // Roast level encoding (3 dimensions)
        let roastEncoding = encodeRoastLevel(coffee.roastLevel)
        vector.append(contentsOf: roastEncoding)
        
        // Confidence and rating (2 dimensions)
        vector.append(Float(coffee.confidence))
        vector.append(Float(coffee.rating ?? 0.0))
        
        // Flavor notes embedding (3 dimensions)
        let flavorNotesEncoding = encodeFlavorNotes(coffee.flavorProfile.flavorNotes)
        vector.append(contentsOf: flavorNotesEncoding)
        
        // Normalize vector
        return normalizeVector(vector)
    }
    
    private func generateFlavorVector(from profile: FlavorProfile) -> [Float] {
        var vector: [Float] = []
        
        // Core flavor dimensions
        vector.append(Float(profile.acidity))
        vector.append(Float(profile.body))
        vector.append(Float(profile.sweetness))
        vector.append(Float(profile.bitterness))
        
        // Flavor notes encoding
        let flavorNotesEncoding = encodeFlavorNotes(profile.flavorNotes, dimension: 8)
        vector.append(contentsOf: flavorNotesEncoding)
        
        // Flavor complexity (derived metric)
        let complexity = Float(profile.flavorNotes.count) / 10.0 // Normalize by max expected notes
        vector.append(complexity)
        
        // Flavor balance (derived metric)
        let balance = 1.0 - abs(Float(profile.acidity - profile.bitterness))
        vector.append(balance)
        
        // Intensity (derived metric)
        let intensity = Float((profile.acidity + profile.body + profile.sweetness + profile.bitterness) / 4.0)
        vector.append(intensity)
        
        // Profile signature (derived metric)
        let signature = Float(profile.acidity * profile.sweetness - profile.bitterness * profile.body)
        vector.append(signature)
        
        return normalizeVector(vector)
    }
    
    private func encodeCoffeeType(_ type: CoffeeType) -> [Float] {
        // Use a simple embedding approach for coffee types
        let typeMap: [CoffeeType: [Float]] = [
            .espresso: [1.0, 0.0, 0.0, 0.0],
            .latte: [0.0, 1.0, 0.0, 0.0],
            .cappuccino: [0.0, 0.8, 0.2, 0.0],
            .americano: [0.8, 0.0, 0.0, 0.2],
            .macchiato: [0.7, 0.3, 0.0, 0.0],
            .mocha: [0.0, 0.6, 0.0, 0.4],
            .flatWhite: [0.0, 0.9, 0.1, 0.0],
            .cortado: [0.0, 0.7, 0.3, 0.0],
            .pourOver: [0.0, 0.0, 1.0, 0.0],
            .frenchPress: [0.0, 0.0, 0.8, 0.2],
            .coldBrew: [0.0, 0.0, 0.0, 1.0],
            .aeropress: [0.0, 0.0, 0.7, 0.3]
        ]
        
        return typeMap[type] ?? [0.0, 0.0, 0.0, 0.0]
    }
    
    private func encodeRoastLevel(_ level: RoastLevel) -> [Float] {
        switch level {
        case .light: return [1.0, 0.0, 0.0]
        case .mediumLight: return [0.7, 0.3, 0.0]
        case .medium: return [0.0, 1.0, 0.0]
        case .mediumDark: return [0.0, 0.7, 0.3]
        case .dark: return [0.0, 0.0, 1.0]
        case .extraDark: return [0.0, 0.0, 0.8]
        }
    }
    
    private func encodeFlavorNotes(_ notes: [String], dimension: Int = 3) -> [Float] {
        // Create a simple flavor notes encoding based on common coffee flavor categories
        let flavorCategories = [
            "fruity": ["citrus", "berry", "apple", "cherry", "tropical"],
            "nutty": ["almond", "hazelnut", "walnut", "peanut", "nutty"],
            "chocolate": ["chocolate", "cocoa", "dark chocolate", "milk chocolate"],
            "caramel": ["caramel", "toffee", "brown sugar", "maple"],
            "spicy": ["cinnamon", "nutmeg", "clove", "pepper", "spicy"],
            "floral": ["floral", "jasmine", "rose", "lavender"],
            "earthy": ["earthy", "woody", "tobacco", "leather"],
            "roasted": ["roasted", "smoky", "burnt", "toasted"]
        ]
        
        var encoding = Array(repeating: Float(0.0), count: dimension)
        
        for (index, (_, categoryNotes)) in flavorCategories.enumerated() {
            if index >= dimension { break }
            
            let matchCount = notes.filter { note in
                categoryNotes.contains { categoryNote in
                    note.lowercased().contains(categoryNote.lowercased())
                }
            }.count
            
            encoding[index] = Float(matchCount) / Float(notes.count + 1) // +1 to avoid division by zero
        }
        
        return encoding
    }
    
    private func normalizeVector(_ vector: [Float]) -> [Float] {
        let magnitude = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        guard magnitude > 0 else { return vector }
        return vector.map { $0 / magnitude }
    }
    
    // MARK: - Vector Storage and Retrieval
    func storeCoffeeVector(_ coffee: AnalyzedCoffee) async {
        guard let db = db else { return }
        
        let vectorData = generateCoffeeVector(from: coffee)
        let flavorVectorData = generateFlavorVector(from: coffee.flavorProfile)
        
        let vectorBlob = Data(bytes: vectorData, count: vectorData.count * MemoryLayout<Float>.size)
        let flavorVectorBlob = Data(bytes: flavorVectorData, count: flavorVectorData.count * MemoryLayout<Float>.size)
        
        let metadataDict = [
            "brew_method": coffee.brewMethod ?? "",
            "notes": coffee.notes,
            "recommendations": coffee.recommendations
        ]
        let metadataBlob = try? JSONSerialization.data(withJSONObject: metadataDict)
        
        let formatter = ISO8601DateFormatter()
        
        do {
            try db.run(coffeeVectors.insert(or: .replace,
                self.id <- coffee.id.uuidString,
                self.coffeeType <- coffee.coffeeType.rawValue,
                self.roastLevel <- coffee.roastLevel.rawValue,
                self.confidence <- coffee.confidence,
                self.analysisDate <- formatter.string(from: coffee.analysisDate),
                self.origin <- coffee.origin,
                self.rating <- coffee.rating,
                self.vector <- vectorBlob,
                self.flavorVector <- flavorVectorBlob,
                self.metadata <- metadataBlob,
                self.createdAt <- Date()
            ))
            print("✅ Stored vector for coffee: \(coffee.coffeeType.rawValue)")
        } catch {
            print("❌ Error storing vector: \(error)")
        }
    }
    
    func findSimilarCoffees(flavorProfile: FlavorProfile, coffeeType: CoffeeType? = nil, limit: Int = 5) async -> [UUID] {
        guard let db = db else { return [] }
        
        let queryVector = generateFlavorVector(from: flavorProfile)
        
        do {
            var query = coffeeVectors.select(id, flavorVector, self.coffeeType, confidence, rating)
            
            if let coffeeType = coffeeType {
                query = query.filter(self.coffeeType == coffeeType.rawValue)
            }
            
            query = query.order(createdAt.desc).limit(maxResults)
            
            var similarities: [(UUID, Float)] = []
            
            for row in try db.prepare(query) {
                guard let coffeeId = UUID(uuidString: row[id]) else { continue }
                
                let flavorVectorData = row[flavorVector]
                let storedVector = flavorVectorData.withUnsafeBytes { bytes in
                    Array(bytes.bindMemory(to: Float.self))
                }
                
                let similarity = cosineSimilarity(queryVector, storedVector)
                if similarity >= similarityThreshold {
                    similarities.append((coffeeId, similarity))
                }
            }
            
            // Sort by similarity and return top results
            similarities.sort { $0.1 > $1.1 }
            return Array(similarities.prefix(limit).map { $0.0 })
            
        } catch {
            print("❌ Error finding similar coffees: \(error)")
            return []
        }
    }
    
    func getCoffeeAnalytics() async -> VectorAnalytics {
        guard let db = db else { return VectorAnalytics() }
        
        var analytics = VectorAnalytics()
        
        do {
            // Get total count and averages
            let totalQuery = coffeeVectors.select(
                coffeeVectors.count,
                confidence.average,
                rating.average
            )
            
            if let row = try db.pluck(totalQuery) {
                analytics.totalVectors = row[coffeeVectors.count]
                analytics.averageConfidence = row[confidence.average] ?? 0.0
                analytics.averageRating = row[rating.average] ?? 0.0
            }
            
            // Get type distribution
            let typeQuery = coffeeVectors
                .select(coffeeType, coffeeVectors.count)
                .group(coffeeType)
                .order(coffeeVectors.count.desc)
            
            for row in try db.prepare(typeQuery) {
                analytics.typeDistribution[row[coffeeType]] = row[coffeeVectors.count]
            }
            
        } catch {
            print("❌ Error getting analytics: \(error)")
        }
        
        return analytics
    }
    
    func deleteCoffeeVector(_ coffeeId: UUID) async {
        guard let db = db else { return }
        
        do {
            try db.run(coffeeVectors.filter(id == coffeeId.uuidString).delete())
        } catch {
            print("❌ Error deleting vector: \(error)")
        }
    }
    
    // MARK: - Utility Functions
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0.0 }
        
        let dotProduct = zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
        let magnitudeA = sqrt(a.reduce(0) { $0 + $1 * $1 })
        let magnitudeB = sqrt(b.reduce(0) { $0 + $1 * $1 })
        
        guard magnitudeA > 0 && magnitudeB > 0 else { return 0.0 }
        return dotProduct / (magnitudeA * magnitudeB)
    }
}

// MARK: - Vector Analytics
struct VectorAnalytics {
    var totalVectors: Int = 0
    var averageConfidence: Double = 0.0
    var averageRating: Double = 0.0
    var typeDistribution: [String: Int] = [:]
    var clusterCount: Int = 0
    
    var mostPopularType: String? {
        typeDistribution.max { $0.value < $1.value }?.key
    }
    
    var diversityScore: Double {
        let entropy = typeDistribution.values.map { count in
            let probability = Double(count) / Double(totalVectors)
            return probability > 0 ? -probability * log2(probability) : 0
        }.reduce(0, +)
        
        return entropy / log2(Double(typeDistribution.count))
    }
}
