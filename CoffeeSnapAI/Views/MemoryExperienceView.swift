import PhotosUI
import SwiftUI
import UIKit

struct MemoryHomeView: View {
    @EnvironmentObject private var store: CoffeeStore
    @State private var showingArchitecture = false
    @State private var showingLog = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 18) {
                    memoryHero
                    tasteFingerprint
                    nextBestCup
                    learningPulse
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(CoffeeTheme.canvas)
            .navigationTitle("CoffeeSnap")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingArchitecture = true } label: {
                        Image(systemName: "lock.shield.fill")
                    }
                    .accessibilityLabel("How taste memory works")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingLog = true } label: {
                        Label("Log cup", systemImage: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showingArchitecture) { MemoryArchitectureView() }
            .sheet(isPresented: $showingLog) { LogTastingView() }
        }
    }

    private var memoryHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("YOUR LIVING TASTE MODEL")
                        .font(.caption2.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(CoffeeTheme.crema.opacity(0.82))
                    Text(store.dashboard.profile.signature)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                    Text(heroMessage)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.76))
                }
                Spacer()
                ConfidenceRing(value: store.dashboard.profile.confidence)
            }

            HStack(spacing: 10) {
                HeroMetric(value: "\(store.dashboard.totalMemories)", label: "taste memories")
                HeroMetric(value: "\(Int(store.dashboard.memoryHealth * 100))%", label: "recall health")
                HeroMetric(value: "\(store.dashboard.dueCards.count)", label: "due today")
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [CoffeeTheme.espresso, CoffeeTheme.roast, CoffeeTheme.caramel.opacity(0.86)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: 150)
                .offset(x: 55, y: -70)
                .allowsHitTesting(false)
        }
    }

    private var heroMessage: String {
        let profile = store.dashboard.profile
        if profile.isColdStart {
            return "A few honest ratings will sharpen this private, on-device model."
        }
        if profile.topNotes.isEmpty {
            return "Your profile adapts as your palate changes—not just as your history grows."
        }
        return "You repeatedly respond to \(profile.topNotes.prefix(3).joined(separator: ", "))."
    }

    private var tasteFingerprint: some View {
        MemoryCard(
            title: "Taste fingerprint",
            eyebrow: store.coffees.isEmpty ? "CALIBRATED START" : "CALIBRATED + LEARNED"
        ) {
            VStack(spacing: 13) {
                TasteAxis(label: "Bright", value: store.dashboard.profile.acidity, tint: .yellow)
                TasteAxis(label: "Full body", value: store.dashboard.profile.body, tint: CoffeeTheme.roast)
                TasteAxis(label: "Sweet", value: store.dashboard.profile.sweetness, tint: CoffeeTheme.caramel)
                TasteAxis(label: "Bold", value: store.dashboard.profile.bitterness, tint: .brown)
            }
        }
    }

    @ViewBuilder
    private var nextBestCup: some View {
        if let recommendation = store.dashboard.recommendations.first {
            MemoryCard(title: "Your next best cup", eyebrow: recommendation.isExploration ? "SMART EXPLORATION" : "PERSONALISED MATCH") {
                HStack(spacing: 14) {
                    CoffeeGlyph(type: recommendation.candidate.coffeeType, size: 56)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(recommendation.candidate.name)
                            .font(.headline)
                        Text(recommendation.reason)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Text("\(Int(recommendation.match * 100))")
                        .font(.title2.monospacedDigit().bold())
                        .foregroundStyle(CoffeeTheme.caramel)
                }
            }
        }
    }

    private var learningPulse: some View {
        MemoryCard(title: "Learning pulse", eyebrow: "RETRIEVAL > REREADING") {
            HStack(spacing: 14) {
                Image(systemName: store.nextReview == nil ? "checkmark.seal.fill" : "brain.fill")
                    .font(.title)
                    .foregroundStyle(store.nextReview == nil ? CoffeeTheme.sage : CoffeeTheme.caramel)
                    .frame(width: 48, height: 48)
                    .background(.thinMaterial, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.nextReview == nil ? "Memory is caught up" : "\(store.dashboard.dueCards.count) quick recalls ready")
                        .font(.headline)
                    Text("Short, spaced prompts strengthen the details you actually tasted.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct DiscoverView: View {
    @EnvironmentObject private var store: CoffeeStore
    @State private var loggingCandidate: CoffeeCandidate?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    Text("A recommendation should sometimes surprise you—and always explain itself.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(Array(store.dashboard.recommendations.enumerated()), id: \.element.id) { index, recommendation in
                        RecommendationCard(recommendation: recommendation, rank: index + 1) {
                            Task { await store.recordRecommendation(recommendation, opened: true) }
                            loggingCandidate = recommendation.candidate
                        } onSkip: {
                            Task { await store.recordRecommendation(recommendation, opened: false) }
                        }
                    }
                }
                .padding()
            }
            .background(CoffeeTheme.canvas)
            .navigationTitle("Discover")
            .task(id: store.recommendationExposureID) {
                await store.exposeRecommendations()
            }
            .sheet(item: $loggingCandidate) { candidate in
                LogTastingView(candidate: candidate)
            }
        }
    }
}

struct LearningLabView: View {
    @EnvironmentObject private var store: CoffeeStore
    @State private var isRevealed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    learningHeader
                    if let card = store.nextReview {
                        reviewCard(card)
                    } else {
                        completedState
                    }
                    scienceNote
                }
                .padding()
            }
            .background(CoffeeTheme.canvas)
            .navigationTitle("Taste Lab")
            .onChange(of: store.nextReview?.id) { _, _ in isRevealed = false }
        }
    }

    private var learningHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("ACTIVE RECALL")
                    .font(.caption2.bold())
                    .tracking(1.2)
                    .foregroundStyle(CoffeeTheme.caramel)
                Text("Train your palate's memory")
                    .font(.title2.bold())
            }
            Spacer()
            Text("\(store.dashboard.dueCards.count) due")
                .font(.subheadline.monospacedDigit().bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(CoffeeTheme.caramel.opacity(0.14), in: Capsule())
        }
    }

    private func reviewCard(_ card: ReviewCard) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Label(card.concept.rawValue.capitalized, systemImage: conceptIcon(card.concept))
                .font(.caption.bold())
                .foregroundStyle(CoffeeTheme.caramel)
            Text(card.prompt)
                .font(.system(.title, design: .rounded, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)

            if isRevealed {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ANSWER")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    Text(card.answer)
                        .font(.title3.weight(.medium))
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CoffeeTheme.sage.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))

                Text("How effortful was that recall?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(ReviewGrade.allCases, id: \.self) { grade in
                        Button(grade.title) {
                            Task { await store.gradeNextReview(grade) }
                        }
                        .buttonStyle(GradeButtonStyle(grade: grade))
                    }
                }
            } else {
                Button {
                    withAnimation(.snappy) { isRevealed = true }
                } label: {
                    Text("Recall first, then reveal")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(CoffeeTheme.roast)
            }
        }
        .padding(22)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26))
    }

    private var completedState: some View {
        ContentUnavailableView(
            "You're caught up",
            systemImage: "checkmark.seal.fill",
            description: Text("The scheduler will bring a memory back just before it becomes fragile.")
        )
        .frame(minHeight: 300)
    }

    private var scienceNote: some View {
        Label(
            "Reviews are spaced from your own recall feedback and interleaved across origin, roast, brew, and flavor.",
            systemImage: "lightbulb.max.fill"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func conceptIcon(_ concept: CoffeeConcept) -> String {
        switch concept {
        case .origin: "globe.americas.fill"
        case .flavor: "mouth.fill"
        case .brew: "drop.fill"
        case .roast: "flame.fill"
        }
    }
}

struct CoffeeJournalView: View {
    @EnvironmentObject private var store: CoffeeStore
    @State private var showingLog = false
    @State private var visualQuery: AnalyzedCoffee?

    var body: some View {
        NavigationStack {
            List {
                if store.filteredCoffees.isEmpty {
                    ContentUnavailableView {
                        Label("Your journal is empty", systemImage: "cup.and.saucer")
                    } description: {
                        Text("Log a real cup and CoffeeSnap will learn from your own palate—not demo data.")
                    } actions: {
                        Button("Log my first cup") { showingLog = true }
                            .buttonStyle(.borderedProminent)
                            .tint(CoffeeTheme.roast)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(store.filteredCoffees) { coffee in
                        JournalRow(
                            coffee: coffee,
                            onFindSimilar: coffee.imageData == nil ? nil : {
                                visualQuery = coffee
                            }
                        )
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    Task { await store.delete(coffee.id) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .listStyle(.plain)
            .background(CoffeeTheme.canvas)
            .searchable(text: $store.searchText, prompt: "Type, origin, note…")
            .navigationTitle("Taste journal")
            .toolbar {
                Button { showingLog = true } label: {
                    Label("Log cup", systemImage: "plus")
                }
            }
            .sheet(isPresented: $showingLog) { LogTastingView() }
            .sheet(item: $visualQuery) { coffee in
                VisualSimilarityView(query: coffee)
            }
        }
    }
}

private struct JournalRow: View {
    @EnvironmentObject private var store: CoffeeStore
    let coffee: AnalyzedCoffee
    let onFindSimilar: (() -> Void)?

    var body: some View {
        HStack(spacing: 14) {
            if let onFindSimilar, let imageData = coffee.imageData {
                Button(action: onFindSimilar) {
                    CoffeeMemoryThumbnail(imageData: imageData, size: 50)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "viewfinder")
                                .font(.caption2.bold())
                                .padding(4)
                                .foregroundStyle(.white)
                                .background(CoffeeTheme.roast, in: Circle())
                                .offset(x: 4, y: 4)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Find visually similar coffee memories")
            } else {
                CoffeeGlyph(type: coffee.coffeeType, size: 50)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(coffee.coffeeType.rawValue)
                    .font(.headline)
                Text([coffee.origin, coffee.brewMethod].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 3) {
                    ForEach(1...5, id: \.self) { star in
                        Button {
                            Task { await store.rate(coffee.id, rating: Double(star)) }
                        } label: {
                            Image(systemName: star <= Int(coffee.rating ?? 0) ? "star.fill" : "star")
                                .font(.caption)
                                .foregroundStyle(star <= Int(coffee.rating ?? 0) ? CoffeeTheme.caramel : Color.secondary.opacity(0.45))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer()
            Button {
                Task { await store.toggleFavorite(coffee.id) }
            } label: {
                Image(systemName: store.favorites.contains(coffee.id) ? "heart.fill" : "heart")
                    .foregroundStyle(store.favorites.contains(coffee.id) ? .red : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(CoffeeTheme.card, in: RoundedRectangle(cornerRadius: 18))
        .padding(.vertical, 4)
    }
}

private struct VisualSimilarityView: View {
    @EnvironmentObject private var store: CoffeeStore
    @Environment(\.dismiss) private var dismiss
    let query: AnalyzedCoffee

    @State private var results: [VisualSearchResult] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            List {
                Section("Visual query") {
                    HStack(spacing: 14) {
                        if let imageData = query.imageData {
                            CoffeeMemoryThumbnail(imageData: imageData, size: 72)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(query.coffeeType.rawValue).font(.headline)
                            Text("Compared privately using an on-device Vision embedding—not filenames or cloud labels.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Closest visual memories") {
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView("Searching visual memory…")
                            Spacer()
                        }
                    } else if results.isEmpty {
                        ContentUnavailableView(
                            "No visual neighbor yet",
                            systemImage: "photo.stack",
                            description: Text("Add photos to more tastings and this memory space will become useful.")
                        )
                    } else {
                        ForEach(results, id: \.coffee.id) { result in
                            HStack(spacing: 12) {
                                if let imageData = result.coffee.imageData {
                                    CoffeeMemoryThumbnail(imageData: imageData, size: 52)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(result.coffee.coffeeType.rawValue).font(.headline)
                                    Text([result.coffee.origin, result.coffee.brewMethod].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(Int(result.similarity * 100))")
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(CoffeeTheme.caramel)
                                    .accessibilityLabel("Similarity \(Int(result.similarity * 100)) percent")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Visual memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .task {
                isLoading = true
                results = await store.visualMatches(for: query)
                isLoading = false
            }
        }
    }
}

struct LogTastingView: View {
    @EnvironmentObject private var store: CoffeeStore
    @Environment(\.dismiss) private var dismiss
    private let sourceCandidateID: UUID?

    @State private var type: CoffeeType
    @State private var roast: RoastLevel
    @State private var brewMethod: String
    @State private var origin: String
    @State private var notes: String
    @State private var flavorNotes: String
    @State private var acidity: Double
    @State private var bodyValue: Double
    @State private var sweetness: Double
    @State private var bitterness: Double
    @State private var rating: Double
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var showingCamera = false
    @State private var isLoadingPhoto = false
    @State private var photoError: String?

    init(candidate: CoffeeCandidate? = nil) {
        sourceCandidateID = candidate?.id
        _type = State(initialValue: candidate?.coffeeType ?? .flatWhite)
        _roast = State(initialValue: candidate?.roastLevel ?? .medium)
        _brewMethod = State(initialValue: candidate?.brewMethod ?? "")
        _origin = State(initialValue: candidate?.origin ?? "")
        _notes = State(initialValue: candidate?.story ?? "")
        _flavorNotes = State(initialValue: candidate?.flavorProfile.flavorNotes.joined(separator: ", ") ?? "")
        _acidity = State(initialValue: candidate?.flavorProfile.acidity ?? 0.5)
        _bodyValue = State(initialValue: candidate?.flavorProfile.body ?? 0.5)
        _sweetness = State(initialValue: candidate?.flavorProfile.sweetness ?? 0.5)
        _bitterness = State(initialValue: candidate?.flavorProfile.bitterness ?? 0.5)
        _rating = State(initialValue: 4)
        _imageData = State(initialValue: nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let imageData {
                        CoffeeMemoryThumbnail(imageData: imageData, size: 180)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }

                    HStack {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label(imageData == nil ? "Choose photo" : "Replace photo", systemImage: "photo.on.rectangle")
                        }
                        Spacer()
                        Button {
                            showingCamera = true
                        } label: {
                            Label("Take photo", systemImage: "camera.fill")
                        }
                        .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                    }

                    if isLoadingPhoto {
                        ProgressView("Preparing visual memory…")
                    }
                    if let photoError {
                        Text(photoError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if imageData != nil {
                        Button("Remove photo", role: .destructive) {
                            imageData = nil
                            selectedPhoto = nil
                        }
                    }
                } header: {
                    Text("Visual memory · optional")
                } footer: {
                    Text("The photo is encoded on-device for private visual similarity. CoffeeSnap does not invent flavor or origin from appearance.")
                }

                Section("Cup") {
                    Picker("Style", selection: $type) {
                        ForEach(CoffeeType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Roast", selection: $roast) {
                        ForEach(RoastLevel.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    TextField("Brew method", text: $brewMethod)
                    TextField("Origin", text: $origin)
                }

                Section {
                    TastingSlider(title: "Acidity", value: $acidity)
                    TastingSlider(title: "Body", value: $bodyValue)
                    TastingSlider(title: "Sweetness", value: $sweetness)
                    TastingSlider(title: "Bitterness", value: $bitterness)
                    TextField("Flavor notes, comma separated", text: $flavorNotes, axis: .vertical)
                } header: {
                    Text("Sensory fingerprint")
                } footer: {
                    if sourceCandidateID != nil {
                        Text("This starts from the catalog prediction. Adjust it to what you actually perceive—those differences calibrate future matches to your palate.")
                    }
                }

                Section("Your feedback") {
                    HStack {
                        Text("Rating")
                        Spacer()
                        ForEach(1...5, id: \.self) { star in
                            Button { rating = Double(star) } label: {
                                Image(systemName: star <= Int(rating) ? "star.fill" : "star")
                                    .foregroundStyle(CoffeeTheme.caramel)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    TextField("What stood out?", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle(sourceCandidateID == nil ? "Log a tasting" : "Try this cup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Remember") {
                        let coffee = AnalyzedCoffee(
                            id: UUID(),
                            imageData: imageData,
                            coffeeType: type,
                            confidence: 1,
                            brewMethod: brewMethod.nilIfBlank,
                            roastLevel: roast,
                            notes: notes,
                            recommendations: [],
                            flavorProfile: FlavorProfile(
                                acidity: acidity,
                                body: bodyValue,
                                sweetness: sweetness,
                                bitterness: bitterness,
                                flavorNotes: flavorNotes.split(separator: ",").map {
                                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                                }.filter { !$0.isEmpty }
                            ),
                            origin: origin.nilIfBlank,
                            rating: rating,
                            sourceCandidateID: sourceCandidateID
                        )
                        Task {
                            await store.addCoffee(coffee)
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task { await loadPhoto(item) }
            }
            .sheet(isPresented: $showingCamera) {
                CoffeeCameraCapture(imageData: $imageData)
                    .ignoresSafeArea()
            }
        }
    }

    @MainActor
    private func loadPhoto(_ item: PhotosPickerItem) async {
        isLoadingPhoto = true
        photoError = nil
        defer { isLoadingPhoto = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let normalized = normalizedCoffeePhotoData(data) else {
                photoError = "That image format could not be prepared."
                return
            }
            imageData = normalized
        } catch {
            photoError = error.localizedDescription
        }
    }
}

struct TasteCalibrationView: View {
    @EnvironmentObject private var store: CoffeeStore
    @Environment(\.dismiss) private var dismiss
    let isOnboarding: Bool

    @State private var flavorDirection: CalibrationFlavor?
    @State private var textureDirection: CalibrationTexture?
    @State private var discoveryDirection: CalibrationDiscovery?
    @State private var selectedNotes: Set<String> = []

    private let noteOptions = ["Caramel", "Chocolate", "Nuts", "Citrus", "Berries", "Floral"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("60-SECOND PALATE CALIBRATION")
                            .font(.caption.bold())
                            .tracking(1.1)
                            .foregroundStyle(CoffeeTheme.caramel)
                        Text(isOnboarding ? "Start with your taste—not fake history" : "Tune your taste anchor")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text("Choose what sounds more appealing today. Your real tastings will continuously overrule this starting point.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    CalibrationQuestion(title: "Which cup calls to you?", symbol: "sparkles") {
                        CalibrationOption(
                            title: "Bright & aromatic",
                            subtitle: "Fruit, flowers, lively acidity",
                            isSelected: flavorDirection == .bright
                        ) { flavorDirection = .bright }
                        CalibrationOption(
                            title: "Deep & comforting",
                            subtitle: "Chocolate, nuts, roasted depth",
                            isSelected: flavorDirection == .deep
                        ) { flavorDirection = .deep }
                    }

                    CalibrationQuestion(title: "What texture feels best?", symbol: "water.waves") {
                        CalibrationOption(
                            title: "Clean & delicate",
                            subtitle: "Tea-like clarity and a light finish",
                            isSelected: textureDirection == .clean
                        ) { textureDirection = .clean }
                        CalibrationOption(
                            title: "Creamy & full",
                            subtitle: "Silky weight and a lingering finish",
                            isSelected: textureDirection == .creamy
                        ) { textureDirection = .creamy }
                    }

                    CalibrationQuestion(title: "How should CoffeeSnap challenge you?", symbol: "scope") {
                        CalibrationOption(
                            title: "Keep it familiar",
                            subtitle: "Prioritise reliable matches",
                            isSelected: discoveryDirection == .familiar
                        ) { discoveryDirection = .familiar }
                        CalibrationOption(
                            title: "Surprise me",
                            subtitle: "Make room for high-information discoveries",
                            isSelected: discoveryDirection == .adventurous
                        ) { discoveryDirection = .adventurous }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Notes you already enjoy · optional")
                            .font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92))], spacing: 10) {
                            ForEach(noteOptions, id: \.self) { note in
                                Button {
                                    if selectedNotes.contains(note) {
                                        selectedNotes.remove(note)
                                    } else {
                                        selectedNotes.insert(note)
                                    }
                                } label: {
                                    Text(note)
                                        .font(.subheadline.weight(.medium))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(
                                            selectedNotes.contains(note) ? CoffeeTheme.caramel.opacity(0.18) : Color.secondary.opacity(0.08),
                                            in: Capsule()
                                        )
                                        .foregroundStyle(selectedNotes.contains(note) ? CoffeeTheme.roast : .primary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(selectedNotes.contains(note) ? .isSelected : [])
                            }
                        }
                    }

                    Button {
                        save()
                    } label: {
                        Text(isOnboarding ? "Build my private taste model" : "Update taste model")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(CoffeeTheme.roast)
                    .disabled(!isComplete)
                }
                .padding(20)
            }
            .background(CoffeeTheme.canvas)
            .toolbar {
                if !isOnboarding {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
    }

    private var isComplete: Bool {
        flavorDirection != nil && textureDirection != nil && discoveryDirection != nil
    }

    private func save() {
        guard let flavorDirection, let textureDirection, let discoveryDirection else { return }
        let deep = flavorDirection == .deep
        let creamy = textureDirection == .creamy
        var notes = selectedNotes.map { $0.lowercased() }
        if notes.isEmpty {
            notes = deep ? ["chocolate", "caramel", "nuts"] : ["citrus", "berries", "floral"]
        }
        let calibration = TasteCalibration(
            acidity: deep ? 0.28 : 0.78,
            body: creamy ? 0.82 : 0.34,
            sweetness: deep ? 0.58 : 0.68,
            bitterness: deep ? 0.62 : 0.18,
            adventure: discoveryDirection == .adventurous ? 0.82 : 0.24,
            flavorNotes: notes
        )
        Task {
            await store.saveCalibration(calibration)
            dismiss()
        }
    }
}

private enum CalibrationFlavor { case bright, deep }
private enum CalibrationTexture { case clean, creamy }
private enum CalibrationDiscovery { case familiar, adventurous }

private struct CalibrationQuestion<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.headline)
            HStack(spacing: 10) { content }
        }
    }
}

private struct CalibrationOption: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(title).font(.subheadline.bold())
                    Spacer(minLength: 2)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? CoffeeTheme.caramel : .secondary)
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
            .padding(13)
            .background(
                isSelected ? CoffeeTheme.caramel.opacity(0.14) : CoffeeTheme.card,
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? CoffeeTheme.caramel : .clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct MemoryArchitectureView: View {
    @EnvironmentObject private var store: CoffeeStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingCalibration = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ArchitectureRow(icon: "iphone.gen3.radiowaves.left.and.right", title: "On-device first", detail: "Your journal, vectors, and learning signals live in a private SQLite WAL database and work offline.")
                    ArchitectureRow(icon: "point.3.connected.trianglepath.dotted", title: "Hybrid embedding", detail: "Taste dimensions combine with Apple's sentence embedding, versioned so future models can re-index safely.")
                    ArchitectureRow(icon: "photo.stack.fill", title: "Multimodal memory", detail: "Photos use a separate versioned Apple Vision feature space for private visual recall and similarity. Appearance never fabricates flavor or origin.")
                    ArchitectureRow(icon: "arrow.triangle.2.circlepath", title: "Learns continuously", detail: "Ratings, favorites, recency, skips, and opens update recommendations without a batch retraining job.")
                    ArchitectureRow(icon: "scale.3d", title: "Exploration with guardrails", detail: "Uncertainty and novelty prevent a filter bubble; diversity reranking keeps the list useful.")
                    ArchitectureRow(icon: "chart.bar.xaxis.ascending", title: "Auditable learning", detail: policyDetail)
                } header: {
                    Text("Taste memory architecture")
                } footer: {
                    Text("The repository boundary is cloud-ready. Pinecone or Weaviate becomes useful for shared catalogs and millions of vectors; it is unnecessary overhead for a private personal journal.")
                }
                Section("Your controls") {
                    Button {
                        showingCalibration = true
                    } label: {
                        Label("Recalibrate my palate", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .navigationTitle("How memory works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .sheet(isPresented: $showingCalibration) {
                TasteCalibrationView(isOnboarding: false)
            }
        }
    }

    private var policyDetail: String {
        let diagnostics = store.policyDiagnostics
        guard diagnostics.auditedSessions > 0 else {
            return "Every displayed choice records its exact local selection probability and alternatives, enabling honest future policy evaluation."
        }
        let spread = Int((diagnostics.meanNormalizedEntropy * 100).rounded())
        return "\(diagnostics.auditedSessions) recommendation sessions are locally auditable. Choice-distribution spread is \(spread)%, balancing reliable matches with measurable exploration."
    }
}

private struct RecommendationCard: View {
    let recommendation: MemoryRecommendation
    let rank: Int
    let onTry: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                CoffeeGlyph(type: recommendation.candidate.coffeeType, size: 62)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("#\(rank)")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        if recommendation.isExploration {
                            Label("Explore", systemImage: "sparkle")
                                .font(.caption2.bold())
                                .foregroundStyle(CoffeeTheme.caramel)
                        }
                    }
                    Text(recommendation.candidate.name)
                        .font(.title3.bold())
                    Text("\(recommendation.candidate.origin) · \(recommendation.candidate.roastLevel.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack {
                    Text("\(Int(recommendation.match * 100))")
                        .font(.title2.monospacedDigit().bold())
                    Text("fit")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(recommendation.reason)
                .font(.subheadline)
            Text(recommendation.candidate.story)
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Button("Not now", action: onSkip)
                    .buttonStyle(.bordered)
                Spacer()
                Button("Taste & teach the model", action: onTry)
                    .buttonStyle(.borderedProminent)
                    .tint(CoffeeTheme.roast)
            }
        }
        .padding(18)
        .background(CoffeeTheme.card, in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct MemoryCard<Content: View>: View {
    let title: String
    let eyebrow: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                Text(eyebrow)
                    .font(.caption2.bold())
                    .tracking(0.7)
                    .foregroundStyle(CoffeeTheme.caramel)
            }
            content
        }
        .padding(18)
        .background(CoffeeTheme.card, in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct TasteAxis: View {
    let label: String
    let value: Double
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.subheadline)
                .frame(width: 74, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.12))
                    Capsule().fill(tint.gradient).frame(width: geometry.size.width * value.clamped(to: 0...1))
                }
            }
            .frame(height: 9)
            Text("\(Int(value * 100))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
        }
    }
}

private struct ConfidenceRing: View {
    let value: Double

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.16), lineWidth: 7)
            Circle()
                .trim(from: 0, to: value.clamped(to: 0...1))
                .stroke(CoffeeTheme.crema, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(value * 100))%")
                .font(.caption.monospacedDigit().bold())
                .foregroundStyle(.white)
        }
        .frame(width: 64, height: 64)
        .accessibilityLabel("Profile confidence \(Int(value * 100)) percent")
    }
}

private struct HeroMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(.white)
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.62)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct CoffeeGlyph: View {
    let type: CoffeeType
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3)
                .fill(LinearGradient(colors: [CoffeeTheme.crema, CoffeeTheme.caramel.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: glyph)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(CoffeeTheme.roast)
        }
        .frame(width: size, height: size)
    }

    private var glyph: String {
        switch type {
        case .coldBrew, .nitroColdbrew, .vietnamese: "snowflake"
        case .pourOver, .aeropress, .frenchPress: "drop.triangle.fill"
        default: "cup.and.saucer.fill"
        }
    }
}

private struct CoffeeMemoryThumbnail: View {
    let imageData: Data
    let size: CGFloat

    var body: some View {
        Group {
            if let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.secondary.opacity(0.08))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

private struct CoffeeCameraCapture: UIViewControllerRepresentable {
    @Binding var imageData: Data?

    func makeCoordinator() -> Coordinator {
        Coordinator(imageData: $imageData)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.cameraCaptureMode = .photo
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let imageData: Binding<Data?>

        init(imageData: Binding<Data?>) {
            self.imageData = imageData
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.82) {
                imageData.wrappedValue = normalizedCoffeePhotoData(data)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

private func normalizedCoffeePhotoData(_ data: Data) -> Data? {
    guard let image = UIImage(data: data) else { return nil }
    let maximumDimension: CGFloat = 1_600
    let pixelWidth = image.size.width * image.scale
    let pixelHeight = image.size.height * image.scale
    let longest = max(pixelWidth, pixelHeight)
    guard longest > maximumDimension else {
        return image.jpegData(compressionQuality: 0.82)
    }

    let scale = maximumDimension / longest
    let targetSize = CGSize(
        width: max(1, pixelWidth * scale),
        height: max(1, pixelHeight * scale)
    )
    let renderer = UIGraphicsImageRenderer(size: targetSize)
    let resized = renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: targetSize))
    }
    return resized.jpegData(compressionQuality: 0.82)
}

private struct TastingSlider: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        HStack {
            Text(title).frame(width: 78, alignment: .leading)
            Slider(value: $value, in: 0...1)
            Text("\(Int(value * 100))")
                .font(.caption.monospacedDigit())
                .frame(width: 28, alignment: .trailing)
        }
    }
}

private struct ArchitectureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(CoffeeTheme.caramel)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct GradeButtonStyle: ButtonStyle {
    let grade: ReviewGrade

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.bold())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(color.opacity(configuration.isPressed ? 0.3 : 0.14), in: RoundedRectangle(cornerRadius: 11))
            .foregroundStyle(color)
    }

    private var color: Color {
        switch grade {
        case .again: .red
        case .hard: .orange
        case .good: CoffeeTheme.sage
        case .easy: .blue
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
