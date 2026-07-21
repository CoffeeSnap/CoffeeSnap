import CoreGraphics
import Foundation
import ImageIO
import Vision

enum VisualEmbeddingError: Error, LocalizedError {
    case invalidImage
    case noFeaturePrint
    case unsupportedElementType

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            "The selected photo could not be decoded."
        case .noFeaturePrint:
            "Vision could not create a visual memory for this photo."
        case .unsupportedElementType:
            "Vision returned an unsupported visual feature format."
        }
    }
}

/// On-device visual encoder for multimodal coffee memories.
///
/// Vision revision 2 is pinned deliberately. Stored vectors carry this model
/// version so a future OS/model change can be re-indexed without silently
/// comparing incompatible feature spaces.
struct VisualEmbeddingService: Sendable {
    static let modelVersion = "apple-vision-featureprint-r2"

    func embed(_ imageData: Data) throws -> [Float] {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [
                kCGImageSourceShouldCache: false
              ] as CFDictionary) else {
            throw VisualEmbeddingError.invalidImage
        }

        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision2
        request.imageCropAndScaleOption = .scaleFit
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first else {
            throw VisualEmbeddingError.noFeaturePrint
        }

        switch observation.elementType {
        case .float:
            return observation.data.withUnsafeBytes { bytes in
                Array(bytes.bindMemory(to: Float.self).prefix(observation.elementCount))
            }
        case .double:
            return observation.data.withUnsafeBytes { bytes in
                bytes.bindMemory(to: Double.self).prefix(observation.elementCount).map(Float.init)
            }
        default:
            throw VisualEmbeddingError.unsupportedElementType
        }
    }

    func similarity(_ left: [Float], _ right: [Float]) -> Double {
        guard left.count == right.count, !left.isEmpty else { return 0 }
        var squaredDistance = 0.0
        for index in left.indices {
            let delta = Double(left[index] - right[index])
            squaredDistance += delta * delta
        }
        // A bounded, monotonic transformation of feature-print distance.
        return 1 / (1 + sqrt(squaredDistance))
    }
}
