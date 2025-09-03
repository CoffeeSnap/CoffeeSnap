import Foundation
import SwiftUI

// MARK: - Analyzed Coffee
struct AnalyzedCoffee: Identifiable, Codable {
    let id = UUID()
    let imageData: Data?
    let coffeeType: CoffeeType
    let confidence: Double
    let analysisDate: Date
    let brewMethod: String?
    let roastLevel: RoastLevel
    let notes: String
    let recommendations: [String]
    let flavorProfile: FlavorProfile
    let origin: String?
    let rating: Double?
    
    init(imageData: Data?, coffeeType: CoffeeType, confidence: Double, brewMethod: String? = nil, roastLevel: RoastLevel = .medium, notes: String = "", recommendations: [String] = [], flavorProfile: FlavorProfile = FlavorProfile(), origin: String? = nil, rating: Double? = nil) {
        self.imageData = imageData
        self.coffeeType = coffeeType
        self.confidence = confidence
        self.analysisDate = Date()
        self.brewMethod = brewMethod
        self.roastLevel = roastLevel
        self.notes = notes
        self.recommendations = recommendations
        self.flavorProfile = flavorProfile
        self.origin = origin
        self.rating = rating
    }
}

// MARK: - Coffee Type
enum CoffeeType: String, CaseIterable, Codable {
    case espresso = "Espresso"
    case cappuccino = "Cappuccino"
    case latte = "Latte"
    case americano = "Americano"
    case macchiato = "Macchiato"
    case mocha = "Mocha"
    case flatWhite = "Flat White"
    case cortado = "Cortado"
    case pourOver = "Pour Over"
    case frenchPress = "French Press"
    case coldBrew = "Cold Brew"
    case nitroColdbrew = "Nitro Cold Brew"
    case aeropress = "AeroPress"
    case turkish = "Turkish Coffee"
    case vietnamese = "Vietnamese Coffee"
    case affogato = "Affogato"
    case gibraltar = "Gibraltar"
    case breve = "Breve"
    case redEye = "Red Eye"
    case blackEye = "Black Eye"
    case unknown = "Unknown"
    
    var description: String {
        switch self {
        case .espresso:
            return "A concentrated coffee served in small shots with a rich crema on top."
        case .cappuccino:
            return "Equal parts espresso, steamed milk, and milk foam, often with a dusting of cocoa."
        case .latte:
            return "Espresso with steamed milk and a light layer of foam, perfect for latte art."
        case .americano:
            return "Espresso diluted with hot water, similar to drip coffee but with a different flavor profile."
        case .macchiato:
            return "Espresso 'marked' with a dollop of steamed milk foam."
        case .mocha:
            return "A chocolate-flavored variant of a latte, combining espresso, chocolate, and steamed milk."
        case .flatWhite:
            return "Similar to a latte but with a stronger coffee flavor and velvety microfoam."
        case .cortado:
            return "Equal parts espresso and warm milk, served in a small glass."
        case .pourOver:
            return "Coffee brewed by pouring hot water over ground coffee in a filter."
        case .frenchPress:
            return "Coffee brewed by steeping coarse grounds in hot water and pressing with a plunger."
        case .coldBrew:
            return "Coffee brewed with cold water over an extended period, resulting in a smooth, less acidic taste."
        case .nitroColdbrew:
            return "Cold brew coffee infused with nitrogen for a creamy, smooth texture."
        case .aeropress:
            return "Coffee brewed using an AeroPress device, combining immersion and pressure brewing."
        case .turkish:
            return "Finely ground coffee simmered in a pot and served unfiltered."
        case .vietnamese:
            return "Strong coffee brewed with a special drip filter, often served with condensed milk."
        case .affogato:
            return "A shot of espresso poured over vanilla gelato or ice cream."
        case .gibraltar:
            return "Similar to a cortado, served in a Gibraltar glass with equal parts espresso and milk."
        case .breve:
            return "Espresso with steamed half-and-half instead of milk, creating a rich, creamy texture."
        case .redEye:
            return "Regular drip coffee with a shot of espresso added for extra caffeine."
        case .blackEye:
            return "Regular drip coffee with two shots of espresso for maximum caffeine."
        case .unknown:
            return "Coffee type could not be determined from the image."
        }
    }
    
    var emoji: String {
        switch self {
        case .espresso: return "☕️"
        case .cappuccino: return "🥛"
        case .latte: return "🍼"
        case .americano: return "☕️"
        case .macchiato: return "🥛"
        case .mocha: return "🍫"
        case .flatWhite: return "🥛"
        case .cortado: return "🥛"
        case .pourOver: return "☕️"
        case .frenchPress: return "☕️"
        case .coldBrew: return "🧊"
        case .nitroColdbrew: return "🧊"
        case .aeropress: return "☕️"
        case .turkish: return "☕️"
        case .vietnamese: return "☕️"
        case .affogato: return "🍨"
        case .gibraltar: return "🥛"
        case .breve: return "🥛"
        case .redEye: return "👁️"
        case .blackEye: return "👁️"
        case .unknown: return "❓"
        }
    }
}

// MARK: - Flavor Profile
struct FlavorProfile: Codable {
    var acidity: Double = 0.5
    var body: Double = 0.5
    var sweetness: Double = 0.5
    var bitterness: Double = 0.5
    var flavorNotes: [String] = []
    
    init(acidity: Double = 0.5, body: Double = 0.5, sweetness: Double = 0.5, bitterness: Double = 0.5, flavorNotes: [String] = []) {
        self.acidity = acidity
        self.body = body
        self.sweetness = sweetness
        self.bitterness = bitterness
        self.flavorNotes = flavorNotes
    }
}

// MARK: - Coffee Facts
struct CoffeeFact {
    let title: String
    let description: String
    let category: FactCategory
    
    enum FactCategory: String, CaseIterable {
        case brewing = "Brewing"
        case history = "History"
        case health = "Health"
        case culture = "Culture"
        case trivia = "Trivia"
    }
}

extension CoffeeFact {
    static let allFacts: [CoffeeFact] = [
        CoffeeFact(title: "Perfect Water Temperature", description: "The ideal water temperature for brewing coffee is between 195°F and 205°F (90°C to 96°C).", category: .brewing),
        CoffeeFact(title: "Coffee Belt", description: "Most coffee grows in the 'Coffee Belt' between 25° North and 30° South latitude.", category: .trivia),
        CoffeeFact(title: "Ethiopian Origins", description: "Coffee was first discovered in Ethiopia, and legend says a goat herder named Kaldi found it.", category: .history),
        CoffeeFact(title: "Antioxidant Powerhouse", description: "Coffee is one of the largest sources of antioxidants in the Western diet.", category: .health),
        CoffeeFact(title: "Second Most Traded Commodity", description: "Coffee is the second most traded commodity in the world after oil.", category: .trivia),
        CoffeeFact(title: "Espresso vs Drip", description: "Espresso actually contains less caffeine per serving than drip coffee, but it's more concentrated.", category: .brewing),
        CoffeeFact(title: "Coffee Plant Varieties", description: "There are over 120 species of coffee plants, but only two are commercially important: Arabica and Robusta.", category: .trivia),
        CoffeeFact(title: "Grind Size Matters", description: "The grind size affects extraction time and flavor. Finer grinds extract faster than coarser grinds.", category: .brewing),
        CoffeeFact(title: "Coffee and Productivity", description: "Studies show that moderate coffee consumption can improve focus, alertness, and cognitive performance.", category: .health),
        CoffeeFact(title: "Turkish Coffee Tradition", description: "Turkish coffee preparation was added to UNESCO's list of Intangible Cultural Heritage in 2013.", category: .culture),
        CoffeeFact(title: "Golden Ratio", description: "The golden ratio for coffee brewing is typically 1:15 to 1:17 (coffee to water by weight).", category: .brewing),
        CoffeeFact(title: "Coffee Cherry", description: "Coffee beans are actually seeds inside coffee cherries, which are typically red when ripe.", category: .trivia),
        CoffeeFact(title: "Decaf Process", description: "Decaffeinated coffee still contains about 3% of the original caffeine content.", category: .brewing),
        CoffeeFact(title: "Coffee Tasting", description: "Professional coffee tasters can distinguish over 800 different flavor notes in coffee.", category: .culture),
        CoffeeFact(title: "Storage Tips", description: "Coffee beans stay fresh longer when stored in an airtight container away from light and heat.", category: .brewing)
    ]
    
    static func randomFact() -> CoffeeFact {
        return allFacts.randomElement() ?? allFacts[0]
    }
    
    static func facts(for category: FactCategory) -> [CoffeeFact] {
        return allFacts.filter { $0.category == category }
    }
}
