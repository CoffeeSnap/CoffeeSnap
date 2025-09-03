import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var coffeeStore: CoffeeStore
    @State private var searchText = ""
    @State private var selectedFilter: FilterOption = .all
    @State private var sortOption: SortOption = .newest
    @State private var showingFilterSheet = false
    
    private var filteredCoffees: [AnalyzedCoffee] {
        var coffees = coffeeStore.analyzedCoffees
        
        // Apply search filter
        if !searchText.isEmpty {
            coffees = coffees.filter { coffee in
                coffee.coffeeType.rawValue.localizedCaseInsensitiveContains(searchText) ||
                coffee.notes.localizedCaseInsensitiveContains(searchText) ||
                (coffee.origin?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        
        // Apply type filter
        switch selectedFilter {
        case .all:
            break
        case .espressoBased:
            coffees = coffees.filter { [.espresso, .cappuccino, .latte, .macchiato, .mocha, .cortado, .flatWhite].contains($0.coffeeType) }
        case .brewedCoffee:
            coffees = coffees.filter { [.americano, .pourOver, .frenchPress, .aeropress, .turkish].contains($0.coffeeType) }
        case .coldCoffee:
            coffees = coffees.filter { [.coldBrew, .nitroColdbrew, .vietnamese].contains($0.coffeeType) }
        case .highConfidence:
            coffees = coffees.filter { $0.confidence > 0.8 }
        case .favorites:
            coffees = coffees.filter { $0.rating ?? 0 >= 4.0 }
        }
        
        // Apply sorting
        switch sortOption {
        case .newest:
            coffees.sort { $0.analysisDate > $1.analysisDate }
        case .oldest:
            coffees.sort { $0.analysisDate < $1.analysisDate }
        case .highestRated:
            coffees.sort { ($0.rating ?? 0) > ($1.rating ?? 0) }
        case .confidence:
            coffees.sort { $0.confidence > $1.confidence }
        case .alphabetical:
            coffees.sort { $0.coffeeType.rawValue < $1.coffeeType.rawValue }
        }
        
        return coffees
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search and filter bar
                searchAndFilterBar
                
                // Content
                if filteredCoffees.isEmpty {
                    emptyStateView
                } else {
                    coffeeGridView
                }
            }
            .navigationTitle("Coffee History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingFilterSheet = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
            }
            .sheet(isPresented: $showingFilterSheet) {
                FilterSheet(
                    selectedFilter: $selectedFilter,
                    sortOption: $sortOption
                )
            }
        }
    }
    
    // MARK: - Search and Filter Bar
    private var searchAndFilterBar: some View {
        VStack(spacing: 12) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppColor.secondaryText)
                
                TextField("Search coffee history...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppColor.secondaryText)
                    }
                }
            }
            .padding()
            .background(AppColor.secondaryBackground)
            .cornerRadius(10)
            
            // Active filters indicator
            if selectedFilter != .all || sortOption != .newest {
                HStack {
                    if selectedFilter != .all {
                        FilterChip(text: selectedFilter.displayName) {
                            selectedFilter = .all
                        }
                    }
                    
                    if sortOption != .newest {
                        FilterChip(text: "Sort: \(sortOption.displayName)") {
                            sortOption = .newest
                        }
                    }
                    
                    Spacer()
                }
            }
            
            // Stats summary
            if !filteredCoffees.isEmpty {
                HStack {
                    Text("\(filteredCoffees.count) coffee\(filteredCoffees.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(AppColor.secondaryText)
                    
                    Spacer()
                    
                    if let averageConfidence = averageConfidence {
                        Text("Avg confidence: \(Int(averageConfidence * 100))%")
                            .font(.caption)
                            .foregroundColor(AppColor.secondaryText)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .background(AppColor.background)
    }
    
    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: searchText.isEmpty ? "cup.and.saucer" : "magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(AppColor.tertiaryText)
            
            VStack(spacing: 8) {
                Text(searchText.isEmpty ? "No Coffee History" : "No Results Found")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColor.primaryText)
                
                Text(searchText.isEmpty ?
                     "Start analyzing your coffee to build your personal coffee journey!" :
                     "Try adjusting your search or filters")
                    .font(.body)
                    .foregroundColor(AppColor.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            if searchText.isEmpty {
                NavigationLink {
                    CameraView()
                } label: {
                    HStack {
                        Image(systemName: "camera.fill")
                        Text("Take Your First Photo")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(AppColor.primaryGradient)
                    .cornerRadius(12)
                }
                .padding(.top)
            }
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Coffee Grid View
    private var coffeeGridView: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 16) {
                ForEach(filteredCoffees) { coffee in
                    NavigationLink {
                        CoffeeDetailsView(coffee: coffee)
                    } label: {
                        CoffeeHistoryCard(coffee: coffee)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding()
        }
    }
    
    // MARK: - Computed Properties
    private var averageConfidence: Double? {
        guard !filteredCoffees.isEmpty else { return nil }
        let total = filteredCoffees.reduce(0) { $0 + $1.confidence }
        return total / Double(filteredCoffees.count)
    }
}

// MARK: - Filter Options
enum FilterOption: CaseIterable {
    case all
    case espressoBased
    case brewedCoffee
    case coldCoffee
    case highConfidence
    case favorites
    
    var displayName: String {
        switch self {
        case .all: return "All Coffee"
        case .espressoBased: return "Espresso-Based"
        case .brewedCoffee: return "Brewed Coffee"
        case .coldCoffee: return "Cold Coffee"
        case .highConfidence: return "High Confidence"
        case .favorites: return "Favorites"
        }
    }
    
    var icon: String {
        switch self {
        case .all: return "cup.and.saucer.fill"
        case .espressoBased: return "cup.and.saucer.fill"
        case .brewedCoffee: return "drop.fill"
        case .coldCoffee: return "snowflake"
        case .highConfidence: return "checkmark.seal.fill"
        case .favorites: return "heart.fill"
        }
    }
}

enum SortOption: CaseIterable {
    case newest
    case oldest
    case highestRated
    case confidence
    case alphabetical
    
    var displayName: String {
        switch self {
        case .newest: return "Newest"
        case .oldest: return "Oldest"
        case .highestRated: return "Highest Rated"
        case .confidence: return "Confidence"
        case .alphabetical: return "A-Z"
        }
    }
}

// MARK: - Coffee History Card
struct CoffeeHistoryCard: View {
    let coffee: AnalyzedCoffee
    @State private var animateCard = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Coffee image
            ZStack(alignment: .topTrailing) {
                if let imageData = coffee.imageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 120)
                        .cornerRadius(12)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(AppColor.secondaryBackground)
                        .frame(height: 120)
                        .cornerRadius(12)
                        .overlay(
                            VStack {
                                Text(coffee.coffeeType.emoji)
                                    .font(.title)
                                
                                Text("No Image")
                                    .font(.caption2)
                                    .foregroundColor(AppColor.tertiaryText)
                            }
                        )
                }
                
                // Confidence badge
                ConfidenceBadge(confidence: coffee.confidence)
                    .padding(8)
            }
            
            // Coffee info
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(coffee.coffeeType.rawValue)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(AppColor.primaryText)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if let rating = coffee.rating, rating > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundColor(.yellow)
                            
                            Text("\(Int(rating))")
                                .font(.caption2)
                                .foregroundColor(AppColor.secondaryText)
                        }
                    }
                }
                
                Text(coffee.analysisDate, formatter: historyDateFormatter)
                    .font(.caption)
                    .foregroundColor(AppColor.secondaryText)
                
                if let origin = coffee.origin {
                    HStack {
                        Image(systemName: "globe")
                            .font(.caption2)
                            .foregroundColor(AppColor.caramel)
                        
                        Text(origin)
                            .font(.caption)
                            .foregroundColor(AppColor.caramel)
                    }
                }
                
                // Flavor notes preview
                if !coffee.flavorProfile.flavorNotes.isEmpty {
                    Text(coffee.flavorProfile.flavorNotes.prefix(2).joined(separator: ", "))
                        .font(.caption2)
                        .foregroundColor(AppColor.tertiaryText)
                        .lineLimit(1)
                }
            }
        }
        .padding()
        .background(AppColor.cardBackground)
        .cornerRadius(16)
        .shadow(color: AppColor.shadowColor, radius: 4, x: 0, y: 2)
        .scaleEffect(animateCard ? 1.0 : 0.95)
        .opacity(animateCard ? 1.0 : 0.8)
        .onAppear {
            withAnimation(.spring(response: 0.6).delay(Double.random(in: 0...0.3))) {
                animateCard = true
            }
        }
    }
}

// MARK: - Confidence Badge
struct ConfidenceBadge: View {
    let confidence: Double
    
    private var badgeColor: Color {
        if confidence > 0.8 {
            return .green
        } else if confidence > 0.5 {
            return .orange
        } else {
            return .red
        }
    }
    
    var body: some View {
        Text("\(Int(confidence * 100))%")
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(badgeColor)
            .cornerRadius(8)
    }
}

// MARK: - Filter Chip
struct FilterChip: View {
    let text: String
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption)
                .foregroundColor(AppColor.caramel)
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(AppColor.caramel)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(AppColor.caramel.opacity(0.1))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColor.caramel.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Filter Sheet
struct FilterSheet: View {
    @Binding var selectedFilter: FilterOption
    @Binding var sortOption: SortOption
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Filter section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Filter by Type")
                        .font(.headline)
                        .foregroundColor(AppColor.primaryText)
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        ForEach(FilterOption.allCases, id: \.self) { filter in
                            FilterOptionCard(
                                filter: filter,
                                isSelected: selectedFilter == filter
                            ) {
                                selectedFilter = filter
                            }
                        }
                    }
                }
                
                // Sort section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Sort by")
                        .font(.headline)
                        .foregroundColor(AppColor.primaryText)
                    
                    VStack(spacing: 8) {
                        ForEach(SortOption.allCases, id: \.self) { sort in
                            SortOptionRow(
                                option: sort,
                                isSelected: sortOption == sort
                            ) {
                                sortOption = sort
                            }
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Filter & Sort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Reset") {
                        selectedFilter = .all
                        sortOption = .newest
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Filter Option Card
struct FilterOptionCard: View {
    let filter: FilterOption
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: filter.icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : AppColor.caramel)
                
                Text(filter.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white : AppColor.primaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isSelected ? AppColor.caramel : AppColor.cardBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppColor.caramel.opacity(0.3), lineWidth: isSelected ? 0 : 1)
            )
        }
    }
}

// MARK: - Sort Option Row
struct SortOptionRow: View {
    let option: SortOption
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(option.displayName)
                    .font(.subheadline)
                    .foregroundColor(AppColor.primaryText)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.subheadline)
                        .foregroundColor(AppColor.caramel)
                }
            }
            .padding()
            .background(isSelected ? AppColor.caramel.opacity(0.1) : AppColor.cardBackground)
            .cornerRadius(10)
        }
    }
}

// MARK: - Date Formatter
private let historyDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    formatter.doesRelativeDateFormatting = true
    return formatter
}()

#Preview {
    HistoryView()
        .environmentObject(CoffeeStore())
}
