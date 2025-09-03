import SwiftUI

struct CoffeeDetailsView: View {
    let coffee: AnalyzedCoffee
    @EnvironmentObject var coffeeStore: CoffeeStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingShareSheet = false
    @State private var animateDetails = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Hero image and basic info
                heroSection
                
                // Analysis summary card
                analysisSummaryCard
                
                // Detailed information
                detailedInfoSection
                
                // Flavor profile visualization
                flavorProfileSection
                
                // Recommendations
                recommendationsSection
                
                // Additional insights
                insightsSection
                
                // Coffee description
                descriptionSection
            }
            .padding()
        }
        .navigationTitle(coffee.coffeeType.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showingShareSheet = true
                    } label: {
                        Label("Share Analysis", systemImage: "square.and.arrow.up")
                    }
                    
                    Button {
                        // Add to favorites functionality
                    } label: {
                        Label("Add to Favorites", systemImage: "heart")
                    }
                    
                    Button(role: .destructive) {
                        deleteAnalysis()
                    } label: {
                        Label("Delete Analysis", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(activityItems: [generateShareText()])
        }
        .onAppear {
            animateDetails = true
        }
    }
    
    // MARK: - Hero Section
    private var heroSection: some View {
        VStack(spacing: 16) {
            // Coffee image
            if let imageData = coffee.imageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 250)
                    .cornerRadius(20)
                    .clipped()
                    .shadow(color: AppColor.shadowColor, radius: 10, x: 0, y: 5)
                    .scaleEffect(animateDetails ? 1.0 : 0.9)
                    .animation(.spring(response: 0.8), value: animateDetails)
            } else {
                RoundedRectangle(cornerRadius: 20)
                    .fill(AppColor.secondaryBackground)
                    .frame(height: 250)
                    .overlay(
                        VStack {
                            Image(systemName: "cup.and.saucer.fill")
                                .font(.system(size: 60))
                                .foregroundColor(AppColor.tertiaryText)
                            
                            Text("No Image Available")
                                .font(.subheadline)
                                .foregroundColor(AppColor.tertiaryText)
                        }
                    )
            }
            
            // Coffee type with emoji and analysis date
            VStack(spacing: 8) {
                HStack {
                    Text(coffee.coffeeType.emoji)
                        .font(.system(size: 40))
                    
                    VStack(alignment: .leading) {
                        Text(coffee.coffeeType.rawValue)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(AppColor.primaryText)
                        
                        Text("Analyzed \(coffee.analysisDate, formatter: relativeDateFormatter)")
                            .font(.caption)
                            .foregroundColor(AppColor.secondaryText)
                    }
                    
                    Spacer()
                }
                .opacity(animateDetails ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.6).delay(0.3), value: animateDetails)
            }
        }
    }
    
    // MARK: - Analysis Summary Card
    private var analysisSummaryCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "brain.head.profile.fill")
                    .font(.title2)
                    .foregroundColor(AppColor.caramel)
                
                Text("AI Analysis Summary")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColor.primaryText)
                
                Spacer()
            }
            
            VStack(spacing: 12) {
                // Confidence meter
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Confidence Level")
                            .font(.subheadline)
                            .foregroundColor(AppColor.primaryText)
                        
                        Spacer()
                        
                        Text("\(Int(coffee.confidence * 100))%")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(confidenceColor)
                    }
                    
                    ProgressView(value: coffee.confidence)
                        .progressViewStyle(LinearProgressViewStyle(tint: confidenceColor))
                        .scaleEffect(y: 1.5)
                }
                
                // Key characteristics
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    CharacteristicChip(title: "Roast", value: coffee.roastLevel.rawValue, color: AppColor.roastColor(for: coffee.roastLevel))
                    
                    if let brewMethod = coffee.brewMethod {
                        CharacteristicChip(title: "Brew", value: brewMethod, color: AppColor.caramel)
                    }
                    
                    if let origin = coffee.origin {
                        CharacteristicChip(title: "Origin", value: origin, color: AppColor.cappuccino)
                    }
                    
                    if let rating = coffee.rating, rating > 0 {
                        CharacteristicChip(title: "Rating", value: "\(Int(rating))★", color: .yellow)
                    }
                }
            }
        }
        .padding()
        .background(AppColor.cardBackground)
        .cornerRadius(16)
        .shadow(color: AppColor.shadowColor, radius: 4, x: 0, y: 2)
        .opacity(animateDetails ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.6).delay(0.4), value: animateDetails)
    }
    
    // MARK: - Detailed Info Section
    private var detailedInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Coffee Details")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(AppColor.primaryText)
            
            VStack(spacing: 12) {
                DetailInfoRow(
                    icon: "cup.and.saucer.fill",
                    title: "Coffee Type",
                    value: coffee.coffeeType.rawValue,
                    description: coffee.coffeeType.description
                )
                
                DetailInfoRow(
                    icon: "flame.fill",
                    title: "Roast Level",
                    value: coffee.roastLevel.rawValue,
                    description: roastDescription
                )
                
                if let brewMethod = coffee.brewMethod {
                    DetailInfoRow(
                        icon: "drop.fill",
                        title: "Recommended Brew Method",
                        value: brewMethod,
                        description: "Based on coffee type characteristics"
                    )
                }
                
                if let origin = coffee.origin {
                    DetailInfoRow(
                        icon: "globe",
                        title: "Suggested Origin",
                        value: origin,
                        description: "AI-estimated origin based on visual characteristics"
                    )
                }
            }
        }
        .padding()
        .background(AppColor.cardBackground)
        .cornerRadius(16)
        .shadow(color: AppColor.shadowColor, radius: 4, x: 0, y: 2)
        .opacity(animateDetails ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.6).delay(0.5), value: animateDetails)
    }
    
    // MARK: - Flavor Profile Section
    private var flavorProfileSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Flavor Profile")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(AppColor.primaryText)
            
            // Flavor radar chart simulation
            VStack(spacing: 16) {
                // Flavor bars
                VStack(spacing: 12) {
                    FlavorProfileBar(
                        label: "Acidity",
                        value: coffee.flavorProfile.acidity,
                        color: .yellow,
                        icon: "bolt.fill"
                    )
                    
                    FlavorProfileBar(
                        label: "Body",
                        value: coffee.flavorProfile.body,
                        color: AppColor.coffeeBean,
                        icon: "drop.fill"
                    )
                    
                    FlavorProfileBar(
                        label: "Sweetness",
                        value: coffee.flavorProfile.sweetness,
                        color: .orange,
                        icon: "heart.fill"
                    )
                    
                    FlavorProfileBar(
                        label: "Bitterness",
                        value: coffee.flavorProfile.bitterness,
                        color: AppColor.espresso,
                        icon: "minus.circle.fill"
                    )
                }
                
                // Flavor notes
                if !coffee.flavorProfile.flavorNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "nose.fill")
                                .font(.subheadline)
                                .foregroundColor(AppColor.caramel)
                            
                            Text("Flavor Notes")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(AppColor.primaryText)
                        }
                        
                        FlowLayout(spacing: 8) {
                            ForEach(coffee.flavorProfile.flavorNotes, id: \.self) { note in
                                FlavorNoteChip(note: note)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(AppColor.cardBackground)
        .cornerRadius(16)
        .shadow(color: AppColor.shadowColor, radius: 4, x: 0, y: 2)
        .opacity(animateDetails ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.6).delay(0.6), value: animateDetails)
    }
    
    // MARK: - Recommendations Section
    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .font(.title2)
                    .foregroundColor(AppColor.caramel)
                
                Text("AI Recommendations")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColor.primaryText)
            }
            
            VStack(spacing: 12) {
                ForEach(Array(coffee.recommendations.enumerated()), id: \.offset) { index, recommendation in
                    RecommendationCard(
                        index: index + 1,
                        recommendation: recommendation
                    )
                }
            }
        }
        .padding()
        .background(AppColor.cardBackground)
        .cornerRadius(16)
        .shadow(color: AppColor.shadowColor, radius: 4, x: 0, y: 2)
        .opacity(animateDetails ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.6).delay(0.7), value: animateDetails)
    }
    
    // MARK: - Insights Section
    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title2)
                    .foregroundColor(AppColor.caramel)
                
                Text("Coffee Insights")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColor.primaryText)
            }
            
            VStack(spacing: 12) {
                InsightCard(
                    icon: "thermometer.medium",
                    title: "Optimal Brewing Temperature",
                    value: getOptimalTemperature(),
                    description: "Based on coffee type and roast level"
                )
                
                InsightCard(
                    icon: "timer",
                    title: "Recommended Brew Time",
                    value: getBrewTime(),
                    description: "For \(coffee.brewMethod ?? "standard brewing")"
                )
                
                InsightCard(
                    icon: "scalemass.fill",
                    title: "Coffee-to-Water Ratio",
                    value: "1:15 to 1:17",
                    description: "Optimal ratio for this coffee type"
                )
            }
        }
        .padding()
        .background(AppColor.cardBackground)
        .cornerRadius(16)
        .shadow(color: AppColor.shadowColor, radius: 4, x: 0, y: 2)
        .opacity(animateDetails ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.6).delay(0.8), value: animateDetails)
    }
    
    // MARK: - Description Section
    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("About This Coffee")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(AppColor.primaryText)
            
            Text(coffee.coffeeType.description)
                .font(.body)
                .foregroundColor(AppColor.primaryText)
                .lineLimit(nil)
            
            if !coffee.notes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Notes")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(AppColor.primaryText)
                    
                    Text(coffee.notes)
                        .font(.body)
                        .foregroundColor(AppColor.secondaryText)
                        .padding()
                        .background(AppColor.secondaryBackground)
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(AppColor.cardBackground)
        .cornerRadius(16)
        .shadow(color: AppColor.shadowColor, radius: 4, x: 0, y: 2)
        .opacity(animateDetails ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.6).delay(0.9), value: animateDetails)
    }
    
    // MARK: - Computed Properties
    private var confidenceColor: Color {
        if coffee.confidence > 0.8 {
            return .green
        } else if coffee.confidence > 0.5 {
            return .orange
        } else {
            return .red
        }
    }
    
    private var roastDescription: String {
        switch coffee.roastLevel {
        case .light:
            return "Bright, acidic, with original bean flavors preserved"
        case .medium:
            return "Balanced acidity and body, well-rounded flavor"
        case .mediumDark:
            return "Reduced acidity, fuller body, slight bittersweet aftertaste"
        case .dark:
            return "Low acidity, heavy body, pronounced bitterness and roast flavors"
        }
    }
    
    private var relativeDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .none
        formatter.dateStyle = .medium
        formatter.doesRelativeDateFormatting = true
        return formatter
    }
    
    // MARK: - Helper Methods
    private func getOptimalTemperature() -> String {
        switch coffee.roastLevel {
        case .light:
            return "200-205°F"
        case .medium:
            return "195-200°F"
        case .mediumDark:
            return "190-195°F"
        case .dark:
            return "185-190°F"
        }
    }
    
    private func getBrewTime() -> String {
        switch coffee.coffeeType {
        case .espresso:
            return "25-30 seconds"
        case .pourOver:
            return "3-4 minutes"
        case .frenchPress:
            return "4 minutes"
        case .aeropress:
            return "1-2 minutes"
        case .coldBrew:
            return "12-24 hours"
        default:
            return "2-4 minutes"
        }
    }
    
    private func deleteAnalysis() {
        // Implementation would remove from coffeeStore
        dismiss()
    }
    
    private func generateShareText() -> String {
        return """
        I just analyzed my \(coffee.coffeeType.rawValue) with CoffeeSnap AI! 
        
        AI Confidence: \(Int(coffee.confidence * 100))%
        Roast Level: \(coffee.roastLevel.rawValue)
        
        Download CoffeeSnap AI to analyze your coffee too!
        """
    }
}

// MARK: - Supporting Views
struct CharacteristicChip: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(AppColor.secondaryText)
                .textCase(.uppercase)
            
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.opacity(0.1))
                .cornerRadius(6)
        }
    }
}

struct DetailInfoRow: View {
    let icon: String
    let title: String
    let value: String
    let description: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundColor(AppColor.caramel)
                    .frame(width: 20)
                
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(AppColor.primaryText)
                
                Spacer()
                
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColor.caramel)
            }
            
            Text(description)
                .font(.caption)
                .foregroundColor(AppColor.secondaryText)
                .padding(.leading, 28)
        }
        .padding(.vertical, 4)
    }
}

struct FlavorProfileBar: View {
    let label: String
    let value: Double
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(color)
                    .frame(width: 16)
                
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(AppColor.primaryText)
                
                Spacer()
                
                Text("\(Int(value * 100))%")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColor.secondaryText)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(AppColor.secondaryBackground)
                        .frame(height: 6)
                        .cornerRadius(3)
                    
                    Rectangle()
                        .fill(color)
                        .frame(width: geometry.size.width * value, height: 6)
                        .cornerRadius(3)
                }
            }
            .frame(height: 6)
        }
    }
}

struct FlavorNoteChip: View {
    let note: String
    
    var body: some View {
        Text(note)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppColor.caramel.opacity(0.15))
            .foregroundColor(AppColor.caramel)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppColor.caramel.opacity(0.3), lineWidth: 1)
            )
    }
}

struct RecommendationCard: View {
    let index: Int
    let recommendation: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppColor.caramel)
                    .frame(width: 24, height: 24)
                
                Text("\(index)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            
            Text(recommendation)
                .font(.subheadline)
                .foregroundColor(AppColor.primaryText)
                .lineLimit(nil)
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct InsightCard: View {
    let icon: String
    let title: String
    let value: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(AppColor.caramel)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(AppColor.secondaryText)
                    .textCase(.uppercase)
                
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColor.primaryText)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(AppColor.tertiaryText)
            }
            
            Spacer()
        }
        .padding()
        .background(AppColor.secondaryBackground)
        .cornerRadius(10)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationView {
        CoffeeDetailsView(coffee: AnalyzedCoffee(
            imageData: nil,
            coffeeType: .cappuccino,
            confidence: 0.85,
            brewMethod: "Espresso Machine",
            roastLevel: .medium,
            notes: "Great morning coffee with perfect foam",
            recommendations: [
                "Try with a dash of cinnamon",
                "Perfect temperature for this roast level",
                "Excellent milk-to-coffee ratio"
            ],
            flavorProfile: FlavorProfile(
                acidity: 0.6,
                body: 0.8,
                sweetness: 0.7,
                bitterness: 0.4,
                flavorNotes: ["Nutty", "Caramel", "Smooth"]
            ),
            origin: "Colombia",
            rating: 4.0
        ))
    }
    .environmentObject(CoffeeStore())
}
