import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var coffeeStore: CoffeeStore
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentPage = 0
    @State private var animateGradient = false
    
    private let pages = OnboardingPage.allPages
    
    var body: some View {
        ZStack {
            // Animated background gradient
            AppColor.primaryGradient
                .opacity(animateGradient ? 0.8 : 0.6)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: animateGradient)
            
            VStack(spacing: 0) {
                // Page content
                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        OnboardingPageView(page: page)
                            .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.5), value: currentPage)
                
                // Bottom section
                VStack(spacing: 20) {
                    // Page indicator
                    HStack(spacing: 8) {
                        ForEach(0..<pages.count, id: \.self) { index in
                            Circle()
                                .fill(index == currentPage ? AppColor.cream : AppColor.cream.opacity(0.3))
                                .frame(width: 8, height: 8)
                                .scaleEffect(index == currentPage ? 1.2 : 1.0)
                                .animation(.spring(response: 0.3), value: currentPage)
                        }
                    }
                    .padding(.top, 20)
                    
                    // Action buttons
                    VStack(spacing: 16) {
                        if currentPage < pages.count - 1 {
                            // Next button
                            Button {
                                withAnimation(.spring(response: 0.5)) {
                                    currentPage += 1
                                }
                            } label: {
                                HStack {
                                    Text("Next")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Image(systemName: "arrow.right")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(AppColor.cream.opacity(0.2))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(AppColor.cream.opacity(0.3), lineWidth: 1)
                                )
                            }
                            
                            // Skip button
                            Button {
                                completeOnboarding()
                            } label: {
                                Text("Skip")
                                    .font(.subheadline)
                                    .foregroundColor(AppColor.cream.opacity(0.8))
                            }
                        } else {
                            // Get Started button
                            Button {
                                completeOnboarding()
                            } label: {
                                HStack {
                                    Image(systemName: "camera.fill")
                                        .font(.headline)
                                    
                                    Text("Start Snapping Coffee!")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                }
                                .foregroundColor(AppColor.espresso)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(AppColor.cream)
                                .cornerRadius(12)
                                .shadow(color: AppColor.shadowColor, radius: 4, x: 0, y: 2)
                            }
                            .scaleEffect(animateGradient ? 1.05 : 1.0)
                            .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: animateGradient)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            animateGradient = true
        }
    }
    
    private func completeOnboarding() {
        hasCompletedOnboarding = true
    }
}

// MARK: - Onboarding Page View
struct OnboardingPageView: View {
    let page: OnboardingPage
    @State private var animateIcon = false
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // Icon
            ZStack {
                Circle()
                    .fill(AppColor.cream.opacity(0.2))
                    .frame(width: 120, height: 120)
                
                Image(systemName: page.icon)
                    .font(.system(size: 50, weight: .light))
                    .foregroundColor(AppColor.cream)
                    .scaleEffect(animateIcon ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: animateIcon)
            }
            
            // Content
            VStack(spacing: 20) {
                Text(page.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(AppColor.cream)
                    .multilineTextAlignment(.center)
                
                Text(page.description)
                    .font(.body)
                    .foregroundColor(AppColor.cream.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .padding(.horizontal, 20)
            }
            
            Spacer()
        }
        .padding()
        .onAppear {
            animateIcon = true
        }
    }
}

// MARK: - Onboarding Page Model
struct OnboardingPage {
    let title: String
    let description: String
    let icon: String
    
    static let allPages: [OnboardingPage] = [
        OnboardingPage(
            title: "Welcome to CoffeeSnap AI",
            description: "Your personal AI-powered coffee companion. Discover, analyze, and perfect your coffee experience with the latest machine learning technology.",
            icon: "cup.and.saucer.fill"
        ),
        OnboardingPage(
            title: "Smart Coffee Recognition",
            description: "Simply snap a photo of your coffee and let our advanced AI identify the type, analyze the flavor profile, and provide personalized recommendations.",
            icon: "camera.viewfinder"
        ),
        OnboardingPage(
            title: "Personalized Recommendations",
            description: "Get tailored brewing tips, flavor insights, and coffee facts based on your preferences and coffee history.",
            icon: "brain.head.profile"
        ),
        OnboardingPage(
            title: "Track Your Journey",
            description: "Build your personal coffee diary, track your favorites, and discover new brewing methods with detailed analytics.",
            icon: "chart.line.uptrend.xyaxis"
        ),
        OnboardingPage(
            title: "Ready to Begin?",
            description: "Start your coffee adventure today! Take your first photo and let CoffeeSnap AI guide you to the perfect cup.",
            icon: "sparkles"
        )
    ]
}

#Preview {
    OnboardingView()
        .environmentObject(CoffeeStore())
}
