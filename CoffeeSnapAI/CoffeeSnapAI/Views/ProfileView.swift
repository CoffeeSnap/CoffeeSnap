import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var coffeeStore: CoffeeStore
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @State private var showingPreferences = false
    @State private var showingAbout = false
    @State private var animateStats = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Profile header
                    profileHeader
                    
                    // Coffee stats
                    coffeeStatsSection
                    
                    // Achievements
                    achievementsSection
                    
                    // Coffee insights
                    insightsSection
                    
                    // Settings and actions
                    settingsSection
                }
                .padding()
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                animateStats = true
            }
        }
        .sheet(isPresented: $showingPreferences) {
            CoffeePreferencesView()
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
    }
    
    // MARK: - Profile Header
    private var profileHeader: some View {
        VStack(spacing: 16) {
            // Avatar
            ZStack {
                Circle()
                    .fill(AppColor.primaryGradient)
                    .frame(width: 100, height: 100)
                
                Image(systemName: "person.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.white)
            }
            .shadow(color: AppColor.shadowColor, radius: 8, x: 0, y: 4)
            
            VStack(spacing: 8) {
                Text("Coffee Enthusiast")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(AppColor.primaryText)
                
                Text("Member since \(memberSinceDate)")
                    .font(.subheadline)
                    .foregroundColor(AppColor.secondaryText)
                
                // Coffee streak
                if coffeeStore.analyzedCoffees.count > 0 {
                    HStack {
                        Image(systemName: "flame.fill")
                            .foregroundColor(.orange)
                        
                        Text("\(coffeeStore.analyzedCoffees.count) coffee\(coffeeStore.analyzedCoffees.count == 1 ? "" : "s") analyzed")
                            .font(.subheadline)
                            .foregroundColor(AppColor.secondaryText)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppColor.caramel.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(AppColor.cardBackground)
        .cornerRadius(20)
        .shadow(color: AppColor.shadowColor, radius: 4, x: 0, y: 2)
    }
    
    // MARK: - Coffee Stats Section
    private var coffeeStatsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your Coffee Journey")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(AppColor.primaryText)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                StatCard(
                    title: "Total Analyzed",
                    value: "\(coffeeStore.analyzedCoffees.count)",
                    icon: "chart.bar.fill",
                    color: AppColor.caramel,
                    animate: animateStats
                )
                
                StatCard(
                    title: "This Week",
                    value: "\(coffeeThisWeek)",
                    icon: "calendar.badge.plus",
                    color: AppColor.cappuccino,
                    animate: animateStats
                )
                
                StatCard(
                    title: "Favorite Type",
                    value: mostCommonCoffeeType,
                    icon: "heart.fill",
                    color: .red,
                    animate: animateStats
                )
                
                StatCard(
                    title: "Avg Confidence",
                    value: "\(Int(averageConfidence * 100))%",
                    icon: "brain.head.profile.fill",
                    color: AppColor.coffeeBean,
                    animate: animateStats
                )
            }
        }
    }
    
    // MARK: - Achievements Section
    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Achievements")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(AppColor.primaryText)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(achievements, id: \.title) { achievement in
                        AchievementCard(achievement: achievement)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.horizontal, -16)
        }
    }
    
    // MARK: - Insights Section
    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Coffee Insights")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(AppColor.primaryText)
            
            VStack(spacing: 12) {
                InsightRow(
                    icon: "chart.pie.fill",
                    title: "Coffee Distribution",
                    value: coffeeTypeDistribution,
                    color: AppColor.caramel
                )
                
                InsightRow(
                    icon: "star.fill",
                    title: "Average Rating",
                    value: "\(String(format: "%.1f", averageRating)) stars",
                    color: .yellow
                )
                
                InsightRow(
                    icon: "clock.fill",
                    title: "Most Active Time",
                    value: mostActiveTime,
                    color: AppColor.cappuccino
                )
                
                InsightRow(
                    icon: "location.fill",
                    title: "Top Origin",
                    value: topOrigin,
                    color: AppColor.coffeeBean
                )
            }
        }
        .padding()
        .background(AppColor.cardBackground)
        .cornerRadius(16)
        .shadow(color: AppColor.shadowColor, radius: 4, x: 0, y: 2)
    }
    
    // MARK: - Settings Section
    private var settingsSection: some View {
        VStack(spacing: 0) {
            SettingsRow(
                icon: "slider.horizontal.3",
                title: "Coffee Preferences",
                subtitle: "Customize your coffee profile",
                color: AppColor.caramel
            ) {
                showingPreferences = true
            }
            
            Divider()
                .padding(.leading, 50)
            
            SettingsRow(
                icon: "square.and.arrow.up",
                title: "Share App",
                subtitle: "Tell your friends about CoffeeSnap AI",
                color: .blue
            ) {
                shareApp()
            }
            
            Divider()
                .padding(.leading, 50)
            
            SettingsRow(
                icon: "star.fill",
                title: "Rate App",
                subtitle: "Help us improve with your feedback",
                color: .yellow
            ) {
                rateApp()
            }
            
            Divider()
                .padding(.leading, 50)
            
            SettingsRow(
                icon: "info.circle.fill",
                title: "About",
                subtitle: "Learn more about CoffeeSnap AI",
                color: AppColor.cappuccino
            ) {
                showingAbout = true
            }
            
            Divider()
                .padding(.leading, 50)
            
            SettingsRow(
                icon: "arrow.clockwise",
                title: "Reset Onboarding",
                subtitle: "See the welcome flow again",
                color: .orange
            ) {
                resetOnboarding()
            }
        }
        .background(AppColor.cardBackground)
        .cornerRadius(16)
        .shadow(color: AppColor.shadowColor, radius: 4, x: 0, y: 2)
    }
    
    // MARK: - Computed Properties
    private var memberSinceDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        
        if let firstCoffee = coffeeStore.analyzedCoffees.last {
            return formatter.string(from: firstCoffee.analysisDate)
        } else {
            return formatter.string(from: Date())
        }
    }
    
    private var coffeeThisWeek: Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return coffeeStore.analyzedCoffees.filter { $0.analysisDate >= weekAgo }.count
    }
    
    private var mostCommonCoffeeType: String {
        guard !coffeeStore.analyzedCoffees.isEmpty else { return "None" }
        
        let types = coffeeStore.analyzedCoffees.map { $0.coffeeType.rawValue }
        let counts = Dictionary(grouping: types, by: { $0 }).mapValues { $0.count }
        return counts.max(by: { $0.value < $1.value })?.key ?? "Unknown"
    }
    
    private var averageConfidence: Double {
        guard !coffeeStore.analyzedCoffees.isEmpty else { return 0 }
        
        let total = coffeeStore.analyzedCoffees.reduce(0) { $0 + $1.confidence }
        return total / Double(coffeeStore.analyzedCoffees.count)
    }
    
    private var coffeeTypeDistribution: String {
        guard !coffeeStore.analyzedCoffees.isEmpty else { return "No data" }
        
        let types = coffeeStore.analyzedCoffees.map { $0.coffeeType.rawValue }
        let counts = Dictionary(grouping: types, by: { $0 }).mapValues { $0.count }
        let sortedTypes = counts.sorted { $0.value > $1.value }
        
        if let topType = sortedTypes.first {
            let percentage = (Double(topType.value) / Double(coffeeStore.analyzedCoffees.count)) * 100
            return "\(Int(percentage))% \(topType.key)"
        }
        
        return "No data"
    }
    
    private var averageRating: Double {
        let ratingsOnly = coffeeStore.analyzedCoffees.compactMap { $0.rating }.filter { $0 > 0 }
        guard !ratingsOnly.isEmpty else { return 0 }
        
        let total = ratingsOnly.reduce(0, +)
        return total / Double(ratingsOnly.count)
    }
    
    private var mostActiveTime: String {
        guard !coffeeStore.analyzedCoffees.isEmpty else { return "No data" }
        
        let hours = coffeeStore.analyzedCoffees.map { Calendar.current.component(.hour, from: $0.analysisDate) }
        let counts = Dictionary(grouping: hours, by: { $0 }).mapValues { $0.count }
        
        if let mostActiveHour = counts.max(by: { $0.value < $1.value })?.key {
            switch mostActiveHour {
            case 5..<12: return "Morning"
            case 12..<17: return "Afternoon"
            case 17..<21: return "Evening"
            default: return "Night"
            }
        }
        
        return "No data"
    }
    
    private var topOrigin: String {
        let origins = coffeeStore.analyzedCoffees.compactMap { $0.origin }
        guard !origins.isEmpty else { return "No data" }
        
        let counts = Dictionary(grouping: origins, by: { $0 }).mapValues { $0.count }
        return counts.max(by: { $0.value < $1.value })?.key ?? "No data"
    }
    
    private var achievements: [Achievement] {
        var unlocked: [Achievement] = []
        
        // First Coffee
        if coffeeStore.analyzedCoffees.count >= 1 {
            unlocked.append(Achievement(
                title: "First Snap",
                description: "Analyzed your first coffee",
                icon: "camera.fill",
                color: AppColor.caramel
            ))
        }
        
        // Coffee Explorer
        if coffeeStore.analyzedCoffees.count >= 10 {
            unlocked.append(Achievement(
                title: "Coffee Explorer",
                description: "Analyzed 10 different coffees",
                icon: "map.fill",
                color: AppColor.cappuccino
            ))
        }
        
        // High Confidence
        if coffeeStore.analyzedCoffees.contains(where: { $0.confidence > 0.95 }) {
            unlocked.append(Achievement(
                title: "Perfect Shot",
                description: "Got 95%+ confidence analysis",
                icon: "target",
                color: .green
            ))
        }
        
        // Coffee Connoisseur
        let uniqueTypes = Set(coffeeStore.analyzedCoffees.map { $0.coffeeType })
        if uniqueTypes.count >= 5 {
            unlocked.append(Achievement(
                title: "Coffee Connoisseur",
                description: "Tried 5 different coffee types",
                icon: "star.fill",
                color: .yellow
            ))
        }
        
        // Weekly Habit
        if coffeeThisWeek >= 7 {
            unlocked.append(Achievement(
                title: "Weekly Habit",
                description: "Analyzed coffee 7 days in a row",
                icon: "calendar.badge.checkmark",
                color: AppColor.coffeeBean
            ))
        }
        
        return unlocked
    }
    
    // MARK: - Helper Methods
    private func shareApp() {
        let shareText = "Check out CoffeeSnap AI - the ultimate app for coffee lovers! It uses AI to analyze your coffee and provide personalized recommendations. Download it now!"
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return }
        
        let activityVC = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
        
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = window
            popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
        }
        
        window.rootViewController?.present(activityVC, animated: true)
    }
    
    private func rateApp() {
        // In a real app, this would open the App Store rating page
        print("Rate app requested")
    }
    
    private func resetOnboarding() {
        hasCompletedOnboarding = false
    }
}

// MARK: - Stat Card
struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let animate: Bool
    
    @State private var animateValue = false
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .scaleEffect(animateValue ? 1.2 : 1.0)
                .animation(.spring(response: 0.6).delay(0.3), value: animateValue)
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(AppColor.primaryText)
                .opacity(animateValue ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.6).delay(0.2), value: animateValue)
            
            Text(title)
                .font(.caption)
                .foregroundColor(AppColor.secondaryText)
                .multilineTextAlignment(.center)
                .opacity(animateValue ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.6).delay(0.4), value: animateValue)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(AppColor.cardBackground)
        .cornerRadius(12)
        .shadow(color: AppColor.shadowColor, radius: 2, x: 0, y: 1)
        .onAppear {
            if animate {
                animateValue = true
            }
        }
        .onChange(of: animate) { newValue in
            if newValue {
                animateValue = true
            }
        }
    }
}

// MARK: - Achievement Card
struct AchievementCard: View {
    let achievement: Achievement
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(achievement.color.opacity(0.2))
                    .frame(width: 50, height: 50)
                
                Image(systemName: achievement.icon)
                    .font(.title3)
                    .foregroundColor(achievement.color)
            }
            
            VStack(spacing: 4) {
                Text(achievement.title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColor.primaryText)
                    .multilineTextAlignment(.center)
                
                Text(achievement.description)
                    .font(.caption2)
                    .foregroundColor(AppColor.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(width: 100)
        .padding()
        .background(AppColor.cardBackground)
        .cornerRadius(12)
        .shadow(color: AppColor.shadowColor, radius: 2, x: 0, y: 1)
    }
}

// MARK: - Insight Row
struct InsightRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(color)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(AppColor.secondaryText)
                    .textCase(.uppercase)
                
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(AppColor.primaryText)
            }
            
            Spacer()
        }
    }
}

// MARK: - Settings Row
struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(AppColor.primaryText)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(AppColor.secondaryText)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(AppColor.tertiaryText)
            }
            .padding()
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Achievement Model
struct Achievement {
    let title: String
    let description: String
    let icon: String
    let color: Color
}

// MARK: - Coffee Preferences View
struct CoffeePreferencesView: View {
    @EnvironmentObject var coffeeStore: CoffeeStore
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("Preferred Strength") {
                    Picker("Strength", selection: $coffeeStore.coffeePreferences.preferredStrength) {
                        ForEach(CoffeeStrength.allCases, id: \.self) { strength in
                            Text(strength.rawValue).tag(strength)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                Section("Preferred Roast") {
                    Picker("Roast Level", selection: $coffeeStore.coffeePreferences.preferredRoast) {
                        ForEach(RoastLevel.allCases, id: \.self) { roast in
                            Text(roast.rawValue).tag(roast)
                        }
                    }
                    .pickerStyle(WheelPickerStyle())
                }
                
                Section("Daily Goal") {
                    Stepper("Coffee cups per day: \(coffeeStore.coffeePreferences.dailyCoffeeGoal)", 
                           value: $coffeeStore.coffeePreferences.dailyCoffeeGoal, 
                           in: 1...10)
                }
                
                Section("Preferred Brew Time") {
                    Picker("Time", selection: $coffeeStore.coffeePreferences.preferredBrewTime) {
                        Text("Morning").tag("Morning")
                        Text("Afternoon").tag("Afternoon")
                        Text("Evening").tag("Evening")
                        Text("Anytime").tag("Anytime")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
            }
            .navigationTitle("Coffee Preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - About View
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // App icon and info
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(AppColor.primaryGradient)
                                .frame(width: 100, height: 100)
                            
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 40))
                                .foregroundColor(.white)
                        }
                        
                        VStack(spacing: 8) {
                            Text("CoffeeSnap AI")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(AppColor.primaryText)
                            
                            Text("Version 1.0.0")
                                .font(.subheadline)
                                .foregroundColor(AppColor.secondaryText)
                        }
                    }
                    .padding()
                    
                    // Description
                    VStack(alignment: .leading, spacing: 16) {
                        Text("About CoffeeSnap AI")
                            .font(.headline)
                            .foregroundColor(AppColor.primaryText)
                        
                        Text("CoffeeSnap AI is your personal coffee companion, powered by advanced machine learning to help you discover, analyze, and perfect your coffee experience. Simply snap a photo of your coffee and let our AI provide detailed insights and personalized recommendations.")
                            .font(.body)
                            .foregroundColor(AppColor.primaryText)
                            .lineLimit(nil)
                    }
                    .padding()
                    .background(AppColor.cardBackground)
                    .cornerRadius(12)
                    
                    // Features
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Features")
                            .font(.headline)
                            .foregroundColor(AppColor.primaryText)
                        
                        VStack(spacing: 12) {
                            FeatureRow(icon: "camera.viewfinder", title: "AI Coffee Recognition", description: "Advanced computer vision to identify coffee types")
                            FeatureRow(icon: "brain.head.profile", title: "Smart Analysis", description: "Detailed flavor profiles and characteristics")
                            FeatureRow(icon: "lightbulb", title: "Personalized Tips", description: "Brewing recommendations based on your coffee")
                            FeatureRow(icon: "chart.line.uptrend.xyaxis", title: "Coffee Journey", description: "Track your coffee exploration over time")
                        }
                    }
                    .padding()
                    .background(AppColor.cardBackground)
                    .cornerRadius(12)
                    
                    // Credits
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Made with ❤️ for Coffee Lovers")
                            .font(.headline)
                            .foregroundColor(AppColor.primaryText)
                        
                        Text("CoffeeSnap AI was built using the latest iOS technologies including SwiftUI, Core ML, and Vision Framework to provide the best possible coffee analysis experience.")
                            .font(.body)
                            .foregroundColor(AppColor.secondaryText)
                            .lineLimit(nil)
                    }
                    .padding()
                    .background(AppColor.cardBackground)
                    .cornerRadius(12)
                }
                .padding()
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(AppColor.caramel)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(AppColor.primaryText)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(AppColor.secondaryText)
            }
            
            Spacer()
        }
    }
}

#Preview {
    ProfileView()
        .environmentObject(CoffeeStore())
}
