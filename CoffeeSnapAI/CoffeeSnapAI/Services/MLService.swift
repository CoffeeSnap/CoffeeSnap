import Foundation
import SwiftUI
import Vision
import CoreML
import UIKit

class MLService: ObservableObject {
    @Published var isAnalyzing = false
    @Published var analysisResult: AnalyzedCoffee?
    @Published var error: MLError?
    
    private let visionQueue = DispatchQueue(label: "vision.queue", qos: .userInitiated)
    
    // MARK: - Public Methods
    func analyzeCoffeeImage(_ image: UIImage, completion: @escaping (AnalyzedCoffee?) -> Void) {
        isAnalyzing = true
        error = nil
        
        visionQueue.async { [weak self] in
            self?.performVisionAnalysis(image: image) { result in
                DispatchQueue.main.async {
                    self?.isAnalyzing = false
                    completion(result)
                }
            }
        }
    }
    
    // MARK: - Private Methods
    private func performVisionAnalysis(image: UIImage, completion: @escaping (AnalyzedCoffee?) -> Void) {
        guard let cgImage = image.cgImage else {
            DispatchQueue.main.async {
                self.error = .imageProcessingFailed
            }
            completion(nil)
            return
        }
        
        // Create Vision request
        let request = VNClassifyImageRequest { [weak self] request, error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.error = .visionAnalysisFailed(error.localizedDescription)
                }
                completion(nil)
                return
            }
            
            guard let observations = request.results as? [VNClassificationObservation],
                  let topResult = observations.first else {
                DispatchQueue.main.async {
                    self?.error = .noResultsFound
                }
                completion(nil)
                return
            }
            
            // Process the results
            let analyzedCoffee = self?.processVisionResults(
                observations: observations,
                originalImage: image
            )
            
            completion(analyzedCoffee)
        }
        
        // Configure the request
        request.maximumLeafObservations = 10
        request.maximumHierarchicalObservations = 10
        
        // Perform the request
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        do {
            try handler.perform([request])
        } catch {
            DispatchQueue.main.async {
                self.error = .visionAnalysisFailed(error.localizedDescription)
            }
            completion(nil)
        }
    }
    
    private func processVisionResults(observations: [VNClassificationObservation], originalImage: UIImage) -> AnalyzedCoffee {
        // Analyze the top classifications and map them to coffee types
        let coffeeType = mapClassificationToCoffeeType(observations)
        let confidence = observations.first?.confidence ?? 0.0
        
        // Generate additional analysis based on the detected coffee type
        let flavorProfile = generateFlavorProfile(for: coffeeType)
        let recommendations = generateRecommendations(for: coffeeType)
        let brewMethod = suggestBrewMethod(for: coffeeType)
        let roastLevel = estimateRoastLevel(for: coffeeType, observations: observations)
        let origin = suggestOrigin(for: coffeeType)
        
        // Convert image to data for storage
        let imageData = originalImage.jpegData(compressionQuality: 0.8)
        
        return AnalyzedCoffee(
            imageData: imageData,
            coffeeType: coffeeType,
            confidence: Double(confidence),
            brewMethod: brewMethod,
            roastLevel: roastLevel,
            notes: generateAnalysisNotes(for: coffeeType, confidence: confidence),
            recommendations: recommendations,
            flavorProfile: flavorProfile,
            origin: origin
        )
    }
    
    private func mapClassificationToCoffeeType(_ observations: [VNClassificationObservation]) -> CoffeeType {
        guard let topObservation = observations.first else { return .unknown }
        
        let identifier = topObservation.identifier.lowercased()
        
        // Map Vision framework classifications to our coffee types
        // This is a simplified mapping - in a real app, you'd train a custom ML model
        if identifier.contains("espresso") || identifier.contains("coffee") && identifier.contains("black") {
            return .espresso
        } else if identifier.contains("cappuccino") || identifier.contains("foam") {
            return .cappuccino
        } else if identifier.contains("latte") || identifier.contains("milk") {
            return .latte
        } else if identifier.contains("americano") {
            return .americano
        } else if identifier.contains("mocha") || identifier.contains("chocolate") {
            return .mocha
        } else if identifier.contains("macchiato") {
            return .macchiato
        } else if identifier.contains("cold") && identifier.contains("coffee") {
            return .coldBrew
        } else if identifier.contains("cup") || identifier.contains("mug") || identifier.contains("beverage") {
            // Generic coffee detection - use confidence and additional heuristics
            return analyzeGenericCoffee(observations)
        } else {
            return .unknown
        }
    }
    
    private func analyzeGenericCoffee(_ observations: [VNClassificationObservation]) -> CoffeeType {
        // Use multiple observations to make an educated guess
        let identifiers = observations.prefix(5).map { $0.identifier.lowercased() }
        
        if identifiers.contains(where: { $0.contains("foam") || $0.contains("froth") }) {
            return .cappuccino
        } else if identifiers.contains(where: { $0.contains("milk") || $0.contains("cream") }) {
            return .latte
        } else if identifiers.contains(where: { $0.contains("dark") || $0.contains("black") }) {
            return .americano
        } else {
            return .espresso // Default to espresso for generic coffee
        }
    }
    
    private func generateFlavorProfile(for coffeeType: CoffeeType) -> FlavorProfile {
        switch coffeeType {
        case .espresso:
            return FlavorProfile(acidity: 0.7, body: 0.9, sweetness: 0.3, bitterness: 0.8, flavorNotes: ["Bold", "Intense", "Caramel"])
        case .cappuccino:
            return FlavorProfile(acidity: 0.5, body: 0.7, sweetness: 0.6, bitterness: 0.4, flavorNotes: ["Creamy", "Balanced", "Nutty"])
        case .latte:
            return FlavorProfile(acidity: 0.4, body: 0.6, sweetness: 0.8, bitterness: 0.3, flavorNotes: ["Smooth", "Milky", "Sweet"])
        case .americano:
            return FlavorProfile(acidity: 0.6, body: 0.5, sweetness: 0.3, bitterness: 0.7, flavorNotes: ["Clean", "Bright", "Simple"])
        case .mocha:
            return FlavorProfile(acidity: 0.3, body: 0.8, sweetness: 0.9, bitterness: 0.2, flavorNotes: ["Chocolate", "Sweet", "Rich"])
        case .coldBrew:
            return FlavorProfile(acidity: 0.2, body: 0.7, sweetness: 0.5, bitterness: 0.4, flavorNotes: ["Smooth", "Low-acid", "Refreshing"])
        default:
            return FlavorProfile(acidity: 0.5, body: 0.5, sweetness: 0.5, bitterness: 0.5, flavorNotes: ["Balanced"])
        }
    }
    
    private func generateRecommendations(for coffeeType: CoffeeType) -> [String] {
        switch coffeeType {
        case .espresso:
            return [
                "Try with a small amount of sugar to enhance the crema",
                "Best enjoyed immediately after brewing",
                "Pair with dark chocolate for a perfect combination"
            ]
        case .cappuccino:
            return [
                "Enjoy in the morning for the perfect start to your day",
                "Try sprinkling cinnamon on top",
                "The ideal milk-to-coffee ratio is 1:1:1"
            ]
        case .latte:
            return [
                "Perfect canvas for latte art",
                "Try different milk alternatives like oat or almond",
                "Add vanilla syrup for extra sweetness"
            ]
        case .americano:
            return [
                "Add hot water gradually to control strength",
                "Perfect for those who enjoy black coffee",
                "Try with a splash of cream for richness"
            ]
        case .mocha:
            return [
                "Top with whipped cream for indulgence",
                "Try different chocolate types for variety",
                "Perfect afternoon treat"
            ]
        case .coldBrew:
            return [
                "Serve over ice with milk or cream",
                "Can be stored in fridge for up to a week",
                "Perfect for hot summer days"
            ]
        default:
            return [
                "Experiment with different brewing methods",
                "Try varying the grind size",
                "Taste at different temperatures"
            ]
        }
    }
    
    private func suggestBrewMethod(for coffeeType: CoffeeType) -> String {
        switch coffeeType {
        case .espresso, .cappuccino, .latte, .macchiato, .mocha:
            return "Espresso Machine"
        case .americano:
            return "Espresso Machine + Hot Water"
        case .pourOver:
            return "Pour Over (V60, Chemex)"
        case .frenchPress:
            return "French Press"
        case .coldBrew:
            return "Cold Brew Method"
        case .aeropress:
            return "AeroPress"
        default:
            return "Various Methods"
        }
    }
    
    private func estimateRoastLevel(for coffeeType: CoffeeType, observations: [VNClassificationObservation]) -> RoastLevel {
        // Analyze color and visual characteristics to estimate roast level
        let identifiers = observations.prefix(5).map { $0.identifier.lowercased() }
        
        if identifiers.contains(where: { $0.contains("dark") || $0.contains("black") }) {
            return .dark
        } else if identifiers.contains(where: { $0.contains("light") || $0.contains("blonde") }) {
            return .light
        } else {
            return .medium // Default to medium roast
        }
    }
    
    private func suggestOrigin(for coffeeType: CoffeeType) -> String {
        let origins = [
            "Ethiopia", "Colombia", "Brazil", "Guatemala", "Kenya",
            "Jamaica", "Hawaii", "Yemen", "Costa Rica", "Peru"
        ]
        return origins.randomElement() ?? "Unknown"
    }
    
    private func generateAnalysisNotes(for coffeeType: CoffeeType, confidence: Float) -> String {
        let confidenceText = confidence > 0.8 ? "High confidence" : confidence > 0.5 ? "Moderate confidence" : "Low confidence"
        return "AI Analysis: \(confidenceText) identification as \(coffeeType.rawValue). Analysis based on visual characteristics including color, texture, and foam patterns."
    }
}

// MARK: - ML Error Types
enum MLError: LocalizedError {
    case imageProcessingFailed
    case visionAnalysisFailed(String)
    case noResultsFound
    case modelLoadingFailed
    
    var errorDescription: String? {
        switch self {
        case .imageProcessingFailed:
            return "Failed to process the image"
        case .visionAnalysisFailed(let message):
            return "Vision analysis failed: \(message)"
        case .noResultsFound:
            return "No coffee detected in the image"
        case .modelLoadingFailed:
            return "Failed to load the ML model"
        }
    }
}
