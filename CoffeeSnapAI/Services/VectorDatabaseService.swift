import CryptoKit
import Foundation
import SQLite3

enum VectorDatabaseError: Error, LocalizedError {
    case open(String)
    case execute(String)
    case encode(String)
    case decode(String)

    var errorDescription: String? {
        switch self {
        case .open(let message): "Could not open taste memory: \(message)"
        case .execute(let message): "Taste memory query failed: \(message)"
        case .encode(let message): "Could not encode taste memory: \(message)"
        case .decode(let message): "Could not decode taste memory: \(message)"
        }
    }
}

struct VectorSearchResult: Equatable, Sendable {
    let coffee: AnalyzedCoffee
    let similarity: Double
}

struct VisualSearchResult: Equatable, Sendable {
    let coffee: AnalyzedCoffee
    let similarity: Double
}

protocol VectorMemoryRepository: Sendable {
    func initialize() async throws
    func upsert(_ coffee: AnalyzedCoffee, cards: [ReviewCard]) async throws
    func saveTasting(_ coffee: AnalyzedCoffee, cards: [ReviewCard], signals: [MemorySignal]) async throws
    func loadCoffees() async throws -> [AnalyzedCoffee]
    func append(_ signal: MemorySignal) async throws
    func append(_ signals: [MemorySignal]) async throws
    func loadSignals() async throws -> [MemorySignal]
    func loadReviewCards() async throws -> [ReviewCard]
    func update(_ card: ReviewCard) async throws
    func deleteCoffee(_ id: UUID) async throws
    func saveCalibration(_ calibration: TasteCalibration) async throws
    func loadCalibration() async throws -> TasteCalibration?
    func searchVisually(similarTo imageData: Data, limit: Int) async throws -> [VisualSearchResult]
}

extension VectorMemoryRepository {
    func saveTasting(
        _ coffee: AnalyzedCoffee,
        cards: [ReviewCard],
        signals: [MemorySignal]
    ) async throws {
        try await upsert(coffee, cards: cards)
        try await append(signals)
    }

    func append(_ signals: [MemorySignal]) async throws {
        for signal in signals {
            try await append(signal)
        }
    }
}

/// A private, local-first vector database backed by SQLite WAL.
///
/// Exact cosine search is intentional: a personal coffee journal is normally
/// small enough that scanning normalized vectors is faster and safer than
/// shipping an experimental mobile ANN index. The public boundary can later be
/// implemented by Pinecone or Weaviate without changing ranking policy.
actor VectorDatabaseService: VectorMemoryRepository {
    static let shared = VectorDatabaseService()

    private let databaseURL: URL
    private let embedding = CoffeeEmbeddingService()
    private let visualEmbedding = VisualEmbeddingService()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var database: OpaquePointer?

    init(databaseURL: URL? = nil) {
        self.databaseURL = databaseURL ?? Self.defaultDatabaseURL()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        self.decoder = decoder
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    func initialize() async throws {
        guard database == nil else { return }
        let databaseDirectory = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: databaseDirectory,
            withIntermediateDirectories: true
        )
        #if os(iOS)
        try? (databaseDirectory as NSURL).setResourceValue(
            FileProtectionType.completeUntilFirstUserAuthentication,
            forKey: .fileProtectionKey
        )
        var protectedDirectory = databaseDirectory
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? protectedDirectory.setResourceValues(resourceValues)
        #endif

        var connection: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &connection, flags, nil) == SQLITE_OK,
              let connection else {
            let message = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error"
            if let connection { sqlite3_close(connection) }
            throw VectorDatabaseError.open(message)
        }
        database = connection

        do {
            try execute("PRAGMA journal_mode = WAL")
            try execute("PRAGMA synchronous = NORMAL")
            try execute("PRAGMA foreign_keys = ON")
            try execute("PRAGMA busy_timeout = 3000")
            try execute(
            """
            CREATE TABLE IF NOT EXISTS coffee_memories (
                id TEXT PRIMARY KEY NOT NULL,
                coffee_json BLOB NOT NULL,
                embedding BLOB NOT NULL,
                embedding_model TEXT NOT NULL,
                search_text TEXT NOT NULL,
                created_at REAL NOT NULL,
                rating REAL,
                visual_embedding BLOB,
                visual_model TEXT,
                visual_source_hash TEXT
            )
            """
        )
        if try !columnExists("visual_embedding", in: "coffee_memories") {
            try execute("ALTER TABLE coffee_memories ADD COLUMN visual_embedding BLOB")
        }
        if try !columnExists("visual_model", in: "coffee_memories") {
            try execute("ALTER TABLE coffee_memories ADD COLUMN visual_model TEXT")
        }
        if try !columnExists("visual_source_hash", in: "coffee_memories") {
            try execute("ALTER TABLE coffee_memories ADD COLUMN visual_source_hash TEXT")
        }
        try execute(
            """
            CREATE TABLE IF NOT EXISTS memory_signals (
                id TEXT PRIMARY KEY NOT NULL,
                coffee_id TEXT NOT NULL,
                kind TEXT NOT NULL,
                value REAL NOT NULL,
                created_at REAL NOT NULL,
                signal_json BLOB
            )
            """
        )
        if try !columnExists("signal_json", in: "memory_signals") {
            try execute("ALTER TABLE memory_signals ADD COLUMN signal_json BLOB")
        }
        try execute(
            """
            CREATE TABLE IF NOT EXISTS review_cards (
                id TEXT PRIMARY KEY NOT NULL,
                coffee_id TEXT NOT NULL,
                concept TEXT NOT NULL,
                card_json BLOB NOT NULL,
                due_at REAL NOT NULL,
                FOREIGN KEY(coffee_id) REFERENCES coffee_memories(id) ON DELETE CASCADE,
                UNIQUE(coffee_id, concept)
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS profile_state (
                key TEXT PRIMARY KEY NOT NULL,
                value BLOB NOT NULL,
                updated_at REAL NOT NULL
            )
            """
        )
        try execute("CREATE INDEX IF NOT EXISTS idx_memory_created ON coffee_memories(created_at DESC)")
        try execute("CREATE INDEX IF NOT EXISTS idx_signal_coffee ON memory_signals(coffee_id, created_at)")
        try execute("CREATE INDEX IF NOT EXISTS idx_review_due ON review_cards(due_at)")
            try execute("PRAGMA user_version = 4")
        } catch {
            sqlite3_close(connection)
            database = nil
            throw error
        }
    }

    func upsert(_ coffee: AnalyzedCoffee, cards: [ReviewCard]) async throws {
        try await ensureInitialized()
        let prepared = try prepareCoffeeWrite(coffee)
        try transaction {
            try writeCoffee(prepared, cards: cards)
        }
    }

    func saveTasting(
        _ coffee: AnalyzedCoffee,
        cards: [ReviewCard],
        signals: [MemorySignal]
    ) async throws {
        try await ensureInitialized()
        let prepared = try prepareCoffeeWrite(coffee)
        try transaction {
            try writeCoffee(prepared, cards: cards)
            for signal in signals {
                try writeSignal(signal)
            }
        }
    }

    private func prepareCoffeeWrite(_ coffee: AnalyzedCoffee) throws -> PreparedCoffeeWrite {
        let coffeeData: Data
        do {
            coffeeData = try encoder.encode(coffee)
        } catch {
            throw VectorDatabaseError.encode(error.localizedDescription)
        }
        let vectorData = data(from: embedding.embed(coffee))
        let visualSourceHash = coffee.imageData.map(sourceHash)
        let visualVector: [Float]?
        if let visualSourceHash,
           let existing = try existingVisualVector(for: coffee.id, sourceHash: visualSourceHash) {
            visualVector = existing
        } else {
            visualVector = coffee.imageData.flatMap { try? visualEmbedding.embed($0) }
        }
        let visualData = visualVector.map(data(from:))
        return PreparedCoffeeWrite(
            coffee: coffee,
            coffeeData: coffeeData,
            vectorData: vectorData,
            visualData: visualData,
            visualSourceHash: visualSourceHash
        )
    }

    private func writeCoffee(_ prepared: PreparedCoffeeWrite, cards: [ReviewCard]) throws {
        let coffee = prepared.coffee
        let sql = """
            INSERT INTO coffee_memories
                (id, coffee_json, embedding, embedding_model, search_text, created_at, rating, visual_embedding, visual_model, visual_source_hash)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                coffee_json = excluded.coffee_json,
                embedding = excluded.embedding,
                embedding_model = excluded.embedding_model,
                search_text = excluded.search_text,
                rating = excluded.rating,
                visual_embedding = excluded.visual_embedding,
                visual_model = excluded.visual_model,
                visual_source_hash = excluded.visual_source_hash
            """

        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bind(coffee.id.uuidString, to: 1, in: statement)
        bind(prepared.coffeeData, to: 2, in: statement)
        bind(prepared.vectorData, to: 3, in: statement)
        bind(CoffeeEmbeddingService.modelVersion, to: 4, in: statement)
        bind(embedding.searchableText(for: coffee), to: 5, in: statement)
        sqlite3_bind_double(statement, 6, coffee.analysisDate.timeIntervalSince1970)
        if let rating = coffee.rating {
            sqlite3_bind_double(statement, 7, rating)
        } else {
            sqlite3_bind_null(statement, 7)
        }
        if let visualData = prepared.visualData {
            bind(visualData, to: 8, in: statement)
            bind(VisualEmbeddingService.modelVersion, to: 9, in: statement)
        } else {
            sqlite3_bind_null(statement, 8)
            sqlite3_bind_null(statement, 9)
        }
        if let visualSourceHash = prepared.visualSourceHash {
            bind(visualSourceHash, to: 10, in: statement)
        } else {
            sqlite3_bind_null(statement, 10)
        }
        try step(statement)

        for card in cards {
            try insertCardIfNeeded(card)
        }
    }

    func loadCoffees() async throws -> [AnalyzedCoffee] {
        try await ensureInitialized()
        let statement = try prepare("SELECT coffee_json FROM coffee_memories ORDER BY created_at DESC")
        defer { sqlite3_finalize(statement) }
        var coffees: [AnalyzedCoffee] = []
        while try nextRow(statement) {
            let payload = blob(at: 0, in: statement)
            do {
                coffees.append(try decoder.decode(AnalyzedCoffee.self, from: payload))
            } catch {
                throw VectorDatabaseError.decode(error.localizedDescription)
            }
        }
        return coffees
    }

    func append(_ signal: MemorySignal) async throws {
        try await ensureInitialized()
        try writeSignal(signal)
    }

    func append(_ signals: [MemorySignal]) async throws {
        try await ensureInitialized()
        try transaction {
            for signal in signals {
                try writeSignal(signal)
            }
        }
    }

    private func writeSignal(_ signal: MemorySignal) throws {
        let payload: Data
        do {
            payload = try encoder.encode(signal)
        } catch {
            throw VectorDatabaseError.encode(error.localizedDescription)
        }
        let statement = try prepare(
            "INSERT OR REPLACE INTO memory_signals (id, coffee_id, kind, value, created_at, signal_json) VALUES (?, ?, ?, ?, ?, ?)"
        )
        defer { sqlite3_finalize(statement) }
        bind(signal.id.uuidString, to: 1, in: statement)
        bind(signal.coffeeID.uuidString, to: 2, in: statement)
        bind(signal.kind.rawValue, to: 3, in: statement)
        sqlite3_bind_double(statement, 4, signal.value)
        sqlite3_bind_double(statement, 5, signal.timestamp.timeIntervalSince1970)
        bind(payload, to: 6, in: statement)
        try step(statement)
    }

    func loadSignals() async throws -> [MemorySignal] {
        try await ensureInitialized()
        let statement = try prepare(
            "SELECT id, coffee_id, kind, value, created_at, signal_json FROM memory_signals ORDER BY created_at ASC"
        )
        defer { sqlite3_finalize(statement) }
        var signals: [MemorySignal] = []
        while try nextRow(statement) {
            if sqlite3_column_type(statement, 5) != SQLITE_NULL,
               let decoded = try? decoder.decode(MemorySignal.self, from: blob(at: 5, in: statement)) {
                signals.append(decoded)
                continue
            }
            guard let id = UUID(uuidString: text(at: 0, in: statement)),
                  let coffeeID = UUID(uuidString: text(at: 1, in: statement)),
                  let kind = MemorySignalKind(rawValue: text(at: 2, in: statement)) else { continue }
            signals.append(MemorySignal(
                id: id,
                coffeeID: coffeeID,
                kind: kind,
                value: sqlite3_column_double(statement, 3),
                timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
            ))
        }
        return signals
    }

    func loadReviewCards() async throws -> [ReviewCard] {
        try await ensureInitialized()
        let statement = try prepare("SELECT card_json FROM review_cards ORDER BY due_at ASC")
        defer { sqlite3_finalize(statement) }
        var cards: [ReviewCard] = []
        while try nextRow(statement) {
            do {
                cards.append(try decoder.decode(ReviewCard.self, from: blob(at: 0, in: statement)))
            } catch {
                throw VectorDatabaseError.decode(error.localizedDescription)
            }
        }
        return cards
    }

    func update(_ card: ReviewCard) async throws {
        try await ensureInitialized()
        let payload: Data
        do {
            payload = try encoder.encode(card)
        } catch {
            throw VectorDatabaseError.encode(error.localizedDescription)
        }
        let statement = try prepare(
            "UPDATE review_cards SET card_json = ?, due_at = ? WHERE id = ?"
        )
        defer { sqlite3_finalize(statement) }
        bind(payload, to: 1, in: statement)
        sqlite3_bind_double(statement, 2, card.dueAt.timeIntervalSince1970)
        bind(card.id.uuidString, to: 3, in: statement)
        try step(statement)
    }

    func deleteCoffee(_ id: UUID) async throws {
        try await ensureInitialized()
        try transaction {
            let signalStatement = try prepare("DELETE FROM memory_signals WHERE coffee_id = ?")
            bind(id.uuidString, to: 1, in: signalStatement)
            defer { sqlite3_finalize(signalStatement) }
            try step(signalStatement)

            let memoryStatement = try prepare("DELETE FROM coffee_memories WHERE id = ?")
            bind(id.uuidString, to: 1, in: memoryStatement)
            defer { sqlite3_finalize(memoryStatement) }
            try step(memoryStatement)
        }
    }

    func saveCalibration(_ calibration: TasteCalibration) async throws {
        try await ensureInitialized()
        let payload: Data
        do {
            payload = try encoder.encode(calibration)
        } catch {
            throw VectorDatabaseError.encode(error.localizedDescription)
        }
        let statement = try prepare(
            """
            INSERT INTO profile_state (key, value, updated_at) VALUES ('calibration', ?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
            """
        )
        defer { sqlite3_finalize(statement) }
        bind(payload, to: 1, in: statement)
        sqlite3_bind_double(statement, 2, calibration.updatedAt.timeIntervalSince1970)
        try step(statement)
    }

    func loadCalibration() async throws -> TasteCalibration? {
        try await ensureInitialized()
        let statement = try prepare("SELECT value FROM profile_state WHERE key = 'calibration'")
        defer { sqlite3_finalize(statement) }
        guard try nextRow(statement) else { return nil }
        do {
            return try decoder.decode(TasteCalibration.self, from: blob(at: 0, in: statement))
        } catch {
            throw VectorDatabaseError.decode(error.localizedDescription)
        }
    }

    func search(
        similarTo coffee: AnalyzedCoffee,
        type: CoffeeType? = nil,
        limit: Int = 5
    ) async throws -> [VectorSearchResult] {
        try await ensureInitialized()
        let statement = try prepare(
            "SELECT id, embedding, embedding_model FROM coffee_memories WHERE id != ?"
        )
        defer { sqlite3_finalize(statement) }
        bind(coffee.id.uuidString, to: 1, in: statement)
        let query = embedding.embed(coffee)
        var ranked: [(id: UUID, similarity: Double)] = []
        while try nextRow(statement) {
            guard let id = UUID(uuidString: text(at: 0, in: statement)) else { continue }
            let version = text(at: 2, in: statement)
            let storedCoffee: AnalyzedCoffee?
            let storedVector: [Float]
            if version == CoffeeEmbeddingService.modelVersion {
                storedVector = vector(from: blob(at: 1, in: statement))
                storedCoffee = type == nil ? nil : try loadCoffee(id: id)
            } else {
                let decoded = try loadCoffee(id: id)
                storedCoffee = decoded
                storedVector = embedding.embed(decoded)
            }
            guard type == nil || storedCoffee?.coffeeType == type else { continue }
            ranked.append((id, embedding.cosineSimilarity(query, storedVector)))
        }
        var results: [VectorSearchResult] = []
        for item in ranked.sorted(by: { $0.similarity > $1.similarity }).prefix(max(0, limit)) {
            results.append(VectorSearchResult(
                coffee: try loadCoffee(id: item.id),
                similarity: item.similarity
            ))
        }
        return results
    }

    func searchVisually(
        similarTo imageData: Data,
        limit: Int = 5
    ) async throws -> [VisualSearchResult] {
        try await ensureInitialized()
        let query = try visualEmbedding.embed(imageData)
        let statement = try prepare(
            "SELECT id, visual_embedding, visual_model FROM coffee_memories"
        )
        defer { sqlite3_finalize(statement) }
        var ranked: [(id: UUID, similarity: Double)] = []
        var pendingReindex: [(id: UUID, vector: [Float], sourceHash: String)] = []
        while try nextRow(statement) {
            guard let id = UUID(uuidString: text(at: 0, in: statement)) else { continue }
            let version = text(at: 2, in: statement)
            let storedVector: [Float]
            if sqlite3_column_type(statement, 1) != SQLITE_NULL,
               version == VisualEmbeddingService.modelVersion {
                storedVector = vector(from: blob(at: 1, in: statement))
            } else if let storedImage = try loadCoffee(id: id).imageData,
                      let generatedVector = try? visualEmbedding.embed(storedImage) {
                storedVector = generatedVector
                pendingReindex.append((
                    id: id,
                    vector: storedVector,
                    sourceHash: sourceHash(storedImage)
                ))
            } else {
                continue
            }
            ranked.append((id, visualEmbedding.similarity(query, storedVector)))
        }
        for item in pendingReindex {
            try updateVisualIndex(item.vector, for: item.id, sourceHash: item.sourceHash)
        }
        var results: [VisualSearchResult] = []
        for item in ranked.sorted(by: { $0.similarity > $1.similarity }).prefix(max(0, limit)) {
            results.append(VisualSearchResult(
                coffee: try loadCoffee(id: item.id),
                similarity: item.similarity
            ))
        }
        return results
    }

    func counts() async throws -> (memories: Int, signals: Int, reviews: Int) {
        try await ensureInitialized()
        return (
            try scalarInt("SELECT COUNT(*) FROM coffee_memories"),
            try scalarInt("SELECT COUNT(*) FROM memory_signals"),
            try scalarInt("SELECT COUNT(*) FROM review_cards")
        )
    }

    private func insertCardIfNeeded(_ card: ReviewCard) throws {
        let payload: Data
        do {
            payload = try encoder.encode(card)
        } catch {
            throw VectorDatabaseError.encode(error.localizedDescription)
        }
        let statement = try prepare(
            "INSERT OR IGNORE INTO review_cards (id, coffee_id, concept, card_json, due_at) VALUES (?, ?, ?, ?, ?)"
        )
        defer { sqlite3_finalize(statement) }
        bind(card.id.uuidString, to: 1, in: statement)
        bind(card.coffeeID.uuidString, to: 2, in: statement)
        bind(card.concept.rawValue, to: 3, in: statement)
        bind(payload, to: 4, in: statement)
        sqlite3_bind_double(statement, 5, card.dueAt.timeIntervalSince1970)
        try step(statement)
    }

    private func ensureInitialized() async throws {
        if database == nil { try await initialize() }
    }

    private func transaction(_ work: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try work()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func execute(_ sql: String) throws {
        guard let database else { throw VectorDatabaseError.open("database is not initialized") }
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorMessage)
            throw VectorDatabaseError.execute(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let database else { throw VectorDatabaseError.open("database is not initialized") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw VectorDatabaseError.execute(String(cString: sqlite3_errmsg(database)))
        }
        return statement
    }

    private func step(_ statement: OpaquePointer) throws {
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite step failed"
            throw VectorDatabaseError.execute(message)
        }
    }

    private func nextRow(_ statement: OpaquePointer) throws -> Bool {
        let result = sqlite3_step(statement)
        switch result {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        default:
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite read failed"
            throw VectorDatabaseError.execute(message)
        }
    }

    private func scalarInt(_ sql: String) throws -> Int {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        guard try nextRow(statement) else { return 0 }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func existingVisualVector(for id: UUID, sourceHash: String) throws -> [Float]? {
        let statement = try prepare(
            "SELECT visual_embedding FROM coffee_memories WHERE id = ? AND visual_model = ? AND visual_source_hash = ?"
        )
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, to: 1, in: statement)
        bind(VisualEmbeddingService.modelVersion, to: 2, in: statement)
        bind(sourceHash, to: 3, in: statement)
        guard try nextRow(statement),
              sqlite3_column_type(statement, 0) != SQLITE_NULL else { return nil }
        return vector(from: blob(at: 0, in: statement))
    }

    private func loadCoffee(id: UUID) throws -> AnalyzedCoffee {
        let statement = try prepare("SELECT coffee_json FROM coffee_memories WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, to: 1, in: statement)
        guard try nextRow(statement) else {
            throw VectorDatabaseError.decode("A referenced coffee memory is missing.")
        }
        do {
            return try decoder.decode(AnalyzedCoffee.self, from: blob(at: 0, in: statement))
        } catch {
            throw VectorDatabaseError.decode(error.localizedDescription)
        }
    }

    private func updateVisualIndex(_ vector: [Float], for id: UUID, sourceHash: String) throws {
        let statement = try prepare(
            "UPDATE coffee_memories SET visual_embedding = ?, visual_model = ?, visual_source_hash = ? WHERE id = ?"
        )
        defer { sqlite3_finalize(statement) }
        bind(data(from: vector), to: 1, in: statement)
        bind(VisualEmbeddingService.modelVersion, to: 2, in: statement)
        bind(sourceHash, to: 3, in: statement)
        bind(id.uuidString, to: 4, in: statement)
        try step(statement)
    }

    private func sourceHash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func columnExists(_ column: String, in table: String) throws -> Bool {
        let statement = try prepare("PRAGMA table_info(\(table))")
        defer { sqlite3_finalize(statement) }
        while try nextRow(statement) {
            if text(at: 1, in: statement) == column { return true }
        }
        return false
    }

    private func bind(_ value: String, to index: Int32, in statement: OpaquePointer) {
        sqlite3_bind_text(statement, index, value, -1, Self.sqliteTransient)
    }

    private func bind(_ value: Data, to index: Int32, in statement: OpaquePointer) {
        _ = value.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(bytes.count), Self.sqliteTransient)
        }
    }

    private func text(at index: Int32, in statement: OpaquePointer) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }

    private func blob(at index: Int32, in statement: OpaquePointer) -> Data {
        let count = Int(sqlite3_column_bytes(statement, index))
        guard count > 0, let bytes = sqlite3_column_blob(statement, index) else { return Data() }
        return Data(bytes: bytes, count: count)
    }

    private func data(from vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private func vector(from data: Data) -> [Float] {
        data.withUnsafeBytes { bytes in
            Array(bytes.bindMemory(to: Float.self))
        }
    }

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func defaultDatabaseURL() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root
            .appendingPathComponent("CoffeeSnapAI", isDirectory: true)
            .appendingPathComponent("taste-memory-v2.sqlite")
    }
}

private struct PreparedCoffeeWrite {
    let coffee: AnalyzedCoffee
    let coffeeData: Data
    let vectorData: Data
    let visualData: Data?
    let visualSourceHash: String?
}
