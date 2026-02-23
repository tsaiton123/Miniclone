import Foundation
import CoreML
import UIKit
import Vision

class CLIPService {
    static let shared = CLIPService()
    
    private let imageEncoder: mobileclip_s1_image?
    private let textEncoder: mobileclip_s1_text?
    private let tokenizer: CLIPTokenizer?
    
    private init() {
        let config = MLModelConfiguration()
        config.computeUnits = .all
        
        var imageEnc: mobileclip_s1_image? = nil
        var textEnc: mobileclip_s1_text? = nil
        var tok: CLIPTokenizer? = nil
        
        do {
            imageEnc = try mobileclip_s1_image(configuration: config)
            textEnc = try mobileclip_s1_text(configuration: config)
            tok = try CLIPTokenizer()
            print("MobileCLIP Models loaded successfully")
        } catch {
            print("Error loading MobileCLIP models: \(error)")
        }
        
        self.imageEncoder = imageEnc
        self.textEncoder = textEnc
        self.tokenizer = tok
    }
    
    /// Generates embedding for a 224x224 CVPixelBuffer (L2-normalised)
    func encode(image: CVPixelBuffer) async throws -> [Float] {
        guard let encoder = imageEncoder else {
            throw CLIPError.modelNotLoaded
        }
        let output = try encoder.prediction(image: image)
        return output.final_emb_1.toArray().l2Normalized()
    }
    
    /// Preprocesses a UIImage, detects text regions and returns L2-normalised embeddings for each tile.
    /// When `pageId` is supplied the embeddings are automatically stored in VectorStoreService.
    func encode(uiImage: UIImage, pageId: String? = nil, tileRects: [CGRect]? = nil) async throws -> [[Float]] {
        let preprocessor = ImagePreprocessor()
        let buffers = try await preprocessor.processAnnotations(from: uiImage)
        
        var results: [[Float]] = []
        for (index, buffer) in buffers.enumerated() {
            let embedding = try await encode(image: buffer)
            results.append(embedding)
            
            // Auto-store in ObjectBox if a pageId was provided
            if let pageId = pageId {
                let rect = tileRects?.indices.contains(index) == true ? tileRects![index] : .zero
                try? VectorStoreService.shared.insert(embedding: embedding, pageId: pageId, tileRect: rect)
            }
        }
        return results
    }
    
    /// Tokenises `text` with CLIPTokenizer and returns an L2-normalised 512-d embedding.
    func encode(text: String) async throws -> [Float] {
        guard let encoder = textEncoder else { throw CLIPError.modelNotLoaded }
        guard let tokenizer = tokenizer else { throw CLIPError.tokenizerNotLoaded }
        
        let tokenIds = tokenizer.encode(text: text) // [Int32], length 77
        
        // Build 1×77 MLMultiArray of Int32
        let array = try MLMultiArray(shape: [1, 77], dataType: .int32)
        for (i, id) in tokenIds.enumerated() {
            array[[0, i] as [NSNumber]] = NSNumber(value: id)
        }
        
        let output = try encoder.prediction(text: array)
        return output.final_emb_1.toArray().l2Normalized()
    }
}

enum CLIPError: Error {
    case modelNotLoaded
    case tokenizerNotLoaded
}

extension MLMultiArray {
    func toArray() -> [Float] {
        let ptr = self.dataPointer.assumingMemoryBound(to: Float.self)
        return Array(UnsafeBufferPointer(start: ptr, count: self.count))
    }
}

extension Array where Element == Float {
    /// Returns a unit-length copy of this vector (L2 normalisation).
    /// Makes Cosine Similarity equivalent to a simple Dot Product.
    func l2Normalized() -> [Float] {
        let magnitude = sqrt(self.reduce(0) { $0 + $1 * $1 })
        guard magnitude > 1e-8 else { return self }
        return self.map { $0 / magnitude }
    }
}
