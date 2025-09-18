import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@available(iOS 17.0, *)
struct ContentView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            Text("Home")
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("Home")
                }
                .tag(0)
            
            Text("Camera")
                .tabItem {
                    Image(systemName: "camera.fill")
                    Text("Snap")
                }
                .tag(1)
            
            Text("History")
                .tabItem {
                    Image(systemName: "clock.fill")
                    Text("History")
                }
                .tag(2)
            
            Text("Profile")
                .tabItem {
                    Image(systemName: "person.fill")
                    Text("Profile")
                }
                .tag(3)
        }
        .onAppear {
            setupTabBarAppearance()
        }
    }
    
    #if canImport(UIKit)
    private func setupTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.systemBackground
        
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
    #else
    private func setupTabBarAppearance() {
        // macOS fallback - no implementation needed
    }
    #endif
}

#if DEBUG
@available(iOS 17.0, *)
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif

#Preview {
    ContentView()
}
