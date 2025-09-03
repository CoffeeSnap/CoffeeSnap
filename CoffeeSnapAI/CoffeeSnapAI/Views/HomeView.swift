import SwiftUI

struct HomeView: View {
    @EnvironmentObject var coffeeStore: CoffeeStore
    @State private var currentFact = CoffeeFact.randomFact()
    @State private var showingCameraView = false
    @State private var animateWelcome = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Welcome Header
                    welcomeHeader
                    
                    // Quick Actions
                    quickActions
                    
                    // Daily Fact Card
                    dailyFactCard
                    
                    // Recent Coffee Analysis
                    recentAnalysisSection
                    
                    // Coffee Stats
                    coffeeStatsSection
                    
                    // Coffee Tips
                    coffeeTipsSection
                }
                .padding()
            }
            .background(AppColor.background)
            .navigationBarHidden(true)
            .refreshable {
                refreshContent()
            }
        }
        .sheet(isPresented: $showingCameraView) {
            CameraView()
        }
        .onAppear {
            animateWelcome = true
        }
    }
    
    // MARK: - Welcome Header
    private var welcomeHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Good \(timeOfDay)!")
                        .font(.title2)
                        .foregroundColor(AppColor.secondaryText)
                    
                    Text("Ready for your coffee?")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(AppColor.primaryText)
                }
                
                Spacer()
                
                // Profile icon
                Button {
                    // Navigate to profile
                } label: {
                    Circle()
                        .fill(AppColor.primaryGradient)
                        .frame(width: 50, height: 50)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                        )
                }
            }
            
            // Coffee streak indicator
            if coffeeStore.analyzedCoffees.count > 0 {
                HStack {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.orange)
                    
                    Text("\(coffeeStore.analyzedCoffees.count) coffee\(coffeeStore.analyzedCoffees.count == 1 ? "" : "s") analyzed")
                        .font(.subheadline)
                        .foregroundColor(AppColor.secondaryText)
                }
                .scaleEffect(animateWelcome ? 1.0 : 0.8)
                .animation(.spring(response: 0.6).delay(0.2), value: animateWelcome)
            }
        }
        .padding()
        .background(AppColor.cardBackground)
        .cornerRadius(16)
        .shadow(color: AppColor.shadowColor, radius: 4, x: 0, y: 2)
    }
    
    // MARK: - Quick Actions
    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Actions")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(AppColor.primaryText)
            
            HStack(spacing: 16) {
                // Snap Coffee Button
                QuickActionButton(
                    title: "Snap Coffee",
                    subtitle: "AI Analysis",
                    icon: "camera.fill",
                    gradient: AppColor.primaryGradient
                ) {
                    showingCameraView = true
                }
                
                // Random Fact Button
                QuickActionButton(
                    title: "Coffee Fact",
                    subtitle: "Learn Something",
                    icon: "lightbulb.fill",
                    gradient: AppColor.warmGradient
                ) {
                    currentFact = CoffeeFact.randomFact()
                }
            }
        }
    }
    
    // MARK: - Daily Fact Card
    private var dailyFactCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "brain.head.profile.fill")
                    .font(.title2)
                    .foregroundColor(AppColor.caramel)
                
                Text("Did You Know?")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColor.primaryText)
                
                Spacer()
                
                Text(currentFact.category.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppColor.caramel.opacity(0.2))
                    .foregroundColor(AppColor.caramel)
                    .cornerRadius(8)
            }
            
            Text(currentFact.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(AppColor.primaryText)
            
            Text(currentFact.description)
                .font(.body)
                .foregroundColor(AppColor.secondaryText)
                .lineLimit(nil)
        }
        .padding()
        .background(AppColor.cardBackground)
        .cornerRadius(16)
        .shadow(color: AppColor.shadowColor, radius: 4, x: 0, y: 2)
        .transition(.slide)
        .animation(.easeInOut(duration: 0.3), value: currentFact.id)
    }
    
    // MARK: - Recent Analysis Section
    private var recentAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recent Analysis")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColor.primaryText)
                
                Spacer()
                
                if !coffeeStore.analyzedCoffees.isEmpty {
                    NavigationLink("See All") {
                        HistoryView()
                    }
                    .font(.subheadline)
                    .foregroundColor(AppColor.caramel)
                }
            }
            
            if coffeeStore.analyzedCoffees.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "camera.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(AppColor.tertiaryText)
                    
                    Text("No coffee analyzed yet")
                        .font(.subheadline)
                        .foregroundColor(AppColor.tertiaryText)
                    
                    Text("Take your first photo to get started!")
                        .font(.caption)
                        .foregroundColor(AppColor.tertiaryText)
                    
                    Button("Start Now") {
                        showingCameraView = true
                    }
                    .font(.subheadline)
                    .foregroundColor(AppColor.caramel)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(AppColor.caramel.opacity(0.1))
                    .cornerRadius(8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .background(AppColor.secondaryBackground)
                .cornerRadius(12)
            } else {
                // Recent coffee cards
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(coffeeStore.analyzedCoffees.prefix(5))) { coffee in
                            NavigationLink {
                                CoffeeDetailsView(coffee: coffee)
                            } label: {
                                RecentCoffeeCard(coffee: coffee)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.horizontal, -16)
            }
        }
    }
    
    // MARK: - Coffee Stats Section
    private var coffeeStatsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your Coffee Journey")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(AppColor.primaryText)
            
            HStack(spacing: 12) {
                StatsCard(
                    title: "Total Analyzed",
                    value: "\(coffeeStore.analyzedCoffees.count)",
                    icon: "chart.bar.fill",
                    color: AppColor.caramel
                )
                
                StatsCard(
                    title: "Favorite Type",
                    value: mostCommonCoffeeType,
                    icon: "heart.fill",
                    color: AppColor.cappuccino
                )
                
                StatsCard(
                    title: "This Week",
                    value: "\(coffeeThisWeek)",
                    icon: "calendar.badge.plus",
                    color: AppColor.coffeeBean
                )
            }
        }
    }
    
    // MARK: - Coffee Tips Section
    private var coffeeTipsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Brewing Tips")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(AppColor.primaryText)
            
            VStack(spacing: 12) {
                TipCard(
                    tip: "The ideal water temperature for brewing coffee is 195-205°F (90-96°C)",
                    icon: "thermometer.medium"
                )
                
                TipCard(
                    tip: "Use a 1:15 to 1:17 coffee-to-water ratio for optimal extraction",
                    icon: "drop.fill"
                )
                
                TipCard(
                    tip: "Grind your coffee beans just before brewing for maximum freshness",
                    icon: "timer"
                )
            }
        }
    }
    
    // MARK: - Computed Properties
    private var timeOfDay: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Morning"
        case 12..<17: return "Afternoon"
        case 17..<21: return "Evening"
        default: return "Night"
        }
    }
    
    private var mostCommonCoffeeType: String {
        guard !coffeeStore.analyzedCoffees.isEmpty else { return "None" }
        
        let types = coffeeStore.analyzedCoffees.map { $0.coffeeType.rawValue }
        let counts = Dictionary(grouping: types, by: { $0 }).mapValues { $0.count }
        return counts.max(by: { $0.value < $1.value })?.key ?? "Unknown"
    }
    
    private var coffeeThisWeek: Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return coffeeStore.analyzedCoffees.filter { $0.analysisDate >= weekAgo }.count
    }
    
    // MARK: - Helper Methods
    private func refreshContent() {
        currentFact = CoffeeFact.randomFact()
    }
}

// MARK: - Quick Action Button
struct QuickActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let gradient: LinearGradient
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.white)
                
                VStack(spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(gradient)
            .cornerRadius(12)
            .shadow(color: AppColor.shadowColor, radius: 4, x: 0, y: 2)
        }
    }
}

// MARK: - Recent Coffee Card
struct RecentCoffeeCard: View {
    let coffee: AnalyzedCoffee
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Coffee image
            if let imageData = coffee.imageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 120, height: 80)
                    .cornerRadius(8)
                    .clipped()
            } else {
                Rectangle()
                    .fill(AppColor.secondaryBackground)
                    .frame(width: 120, height: 80)
                    .cornerRadius(8)
                    .overlay(
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.title2)
                            .foregroundColor(AppColor.tertiaryText)
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(coffee.coffeeType.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(AppColor.primaryText)
                    .lineLimit(1)
                
                Text("\(Int(coffee.confidence * 100))% confident")
                    .font(.caption2)
                    .foregroundColor(AppColor.secondaryText)
            }
        }
        .frame(width: 120)
        .padding(8)
        .background(AppColor.cardBackground)
        .cornerRadius(12)
        .shadow(color: AppColor.shadowColor, radius: 2, x: 0, y: 1)
    }
}

// MARK: - Stats Card
struct StatsCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(AppColor.primaryText)
            
            Text(title)
                .font(.caption)
                .foregroundColor(AppColor.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(AppColor.cardBackground)
        .cornerRadius(12)
        .shadow(color: AppColor.shadowColor, radius: 2, x: 0, y: 1)
    }
}

// MARK: - Tip Card
struct TipCard: View {
    let tip: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(AppColor.caramel)
                .frame(width: 24)
            
            Text(tip)
                .font(.subheadline)
                .foregroundColor(AppColor.primaryText)
                .lineLimit(nil)
            
            Spacer()
        }
        .padding()
        .background(AppColor.cardBackground)
        .cornerRadius(10)
        .shadow(color: AppColor.shadowColor, radius: 1, x: 0, y: 1)
    }
}

#Preview {
    HomeView()
        .environmentObject(CoffeeStore())
}
