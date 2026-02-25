import Foundation
import UIKit

/// Lightweight on-device image matching service using downscaled pixel comparison.
/// Works on both real devices and the iOS Simulator (no Neural Engine required).
@MainActor
final class ImageMatchingService {
    static let shared = ImageMatchingService()
    
    /// Thumbnail size for comparison (small = fast, but enough detail for shape matching)
    private let thumbSize = 64
    
    // pageId -> raw grayscale pixel bytes (thumbSize x thumbSize = 1024 bytes)
    private var index: [String: [UInt8]] = [:]
    private let indexURL: URL
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        indexURL = appSupport.appendingPathComponent("image_pixel_index.json")
        loadFromDisk()
    }
    
    // MARK: - Persistence
    
    private func loadFromDisk() {
        print("[DEBUG-IMS] Loading index from: \(indexURL.path)")
        if let data = try? Data(contentsOf: indexURL),
           let raw = try? JSONDecoder().decode([String: [UInt8]].self, from: data) {
            index = raw
            print("[DEBUG-IMS] ✅ Loaded \(index.count) page(s) from disk")
            for key in index.keys {
                print("[DEBUG-IMS]   - stored pageId: \(key)")
            }
        } else {
            print("[DEBUG-IMS] ⚠️ No existing index file found or failed to decode")
        }
    }
    
    private func saveToDisk() {
        if let data = try? JSONEncoder().encode(index) {
            do {
                try data.write(to: indexURL, options: .atomic)
                print("[DEBUG-IMS] ✅ Saved \(index.count) page(s) to disk (\(data.count) bytes)")
            } catch {
                print("[DEBUG-IMS] ⚠️ Failed to write index to disk: \(error)")
            }
        } else {
            print("[DEBUG-IMS] ⚠️ Failed to encode index to JSON")
        }
    }
    
    // MARK: - Thumbnail Generation
    
    /// Downscales an image to a small grayscale thumbnail and returns raw pixel bytes.
    /// Crops to the content bounding box first so drawings fill the thumbnail.
    private func generateThumbnail(from image: UIImage) -> [UInt8]? {
        let size = CGSize(width: thumbSize, height: thumbSize)
        
        // 1. First render UIImage to a standard CGImage on white background
        UIGraphicsBeginImageContextWithOptions(image.size, true, 1.0)
        UIColor.white.setFill()
        UIRectFill(CGRect(origin: .zero, size: image.size))
        image.draw(at: .zero)
        let flatImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        guard let cgImage = flatImage?.cgImage else {
            print("[DEBUG-IMS] ⚠️ Failed to get CGImage from flattened image")
            return nil
        }
        
        // 2. Crop to content bounding box to make the drawing fill the thumbnail
        let croppedCG = cropToContent(cgImage) ?? cgImage
        print("[DEBUG-IMS] Cropped content: \(croppedCG.width)x\(croppedCG.height) (from \(cgImage.width)x\(cgImage.height))")
        
        // 3. Create grayscale thumbnail context
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil,
            width: thumbSize,
            height: thumbSize,
            bitsPerComponent: 8,
            bytesPerRow: thumbSize,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            print("[DEBUG-IMS] ⚠️ Failed to create grayscale CGContext")
            return nil
        }
        
        // Fill with white first, then draw cropped content
        context.setFillColor(gray: 1.0, alpha: 1.0)
        context.fill(CGRect(origin: .zero, size: size))
        context.draw(croppedCG, in: CGRect(origin: .zero, size: size))
        
        guard let data = context.data else {
            print("[DEBUG-IMS] ⚠️ CGContext data is nil")
            return nil
        }
        
        let pixelCount = thumbSize * thumbSize
        let buffer = data.bindMemory(to: UInt8.self, capacity: pixelCount)
        var pixels = [UInt8](repeating: 0, count: pixelCount)
        for i in 0..<pixelCount {
            pixels[i] = buffer[i]
        }
        
        print("[DEBUG-IMS] ✅ Generated \(thumbSize)x\(thumbSize) grayscale thumbnail (\(pixels.count) bytes)")
        return pixels
    }
    
    /// Finds the bounding box of non-white content in a CGImage and crops to it with padding.
    private func cropToContent(_ cgImage: CGImage) -> CGImage? {
        let width = cgImage.width
        let height = cgImage.height
        
        // Render to grayscale to scan pixels
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height)
        
        // Threshold: pixels darker than 240 are considered "content"
        let threshold: UInt8 = 240
        var minX = width, minY = height, maxX = 0, maxY = 0
        
        for y in 0..<height {
            for x in 0..<width {
                let pixel = buffer[y * width + x]
                if pixel < threshold {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }
        
        // No content found — return nil to use original
        guard minX < maxX && minY < maxY else { return nil }
        
        // Add 10% padding
        let contentWidth = maxX - minX
        let contentHeight = maxY - minY
        let padX = max(10, contentWidth / 10)
        let padY = max(10, contentHeight / 10)
        
        let cropRect = CGRect(
            x: max(0, minX - padX),
            y: max(0, minY - padY),
            width: min(width - max(0, minX - padX), contentWidth + 2 * padX),
            height: min(height - max(0, minY - padY), contentHeight + 2 * padY)
        )
        
        return cgImage.cropping(to: cropRect)
    }
    
    /// Compares two pixel arrays using spatial histogram + cosine similarity.
    /// Divides each image into an 8x8 grid and compares ink density per cell.
    /// This is tolerant to small position differences between drawings.
    /// Returns distance: 0 = identical shapes, 1 = completely different.
    private func comparePixels(_ a: [UInt8], _ b: [UInt8]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return Float.greatestFiniteMagnitude }
        
        let side = thumbSize  // 64
        let gridSize = 8      // 8x8 grid
        let cellSize = side / gridSize  // 8 pixels per cell
        
        // Build ink density histogram for each image
        let histA = buildHistogram(a, side: side, gridSize: gridSize, cellSize: cellSize)
        let histB = buildHistogram(b, side: side, gridSize: gridSize, cellSize: cellSize)
        
        // Compute cosine similarity between histograms
        let similarity = cosineSimilarity(histA, histB)
        
        print("[DEBUG-IMS] Histogram cosine similarity: \(similarity)")
        
        // Convert to distance (0 = identical, 1 = completely different)
        return 1.0 - similarity
    }
    
    /// Builds an ink density histogram from pixel data.
    /// Returns array of float densities (0-1) for each grid cell.
    private func buildHistogram(_ pixels: [UInt8], side: Int, gridSize: Int, cellSize: Int) -> [Float] {
        let inkThreshold: UInt8 = 200  // Darker than this = ink
        var histogram = [Float](repeating: 0, count: gridSize * gridSize)
        let pixelsPerCell = Float(cellSize * cellSize)
        
        for cellY in 0..<gridSize {
            for cellX in 0..<gridSize {
                var inkCount = 0
                for dy in 0..<cellSize {
                    for dx in 0..<cellSize {
                        let px = cellX * cellSize + dx
                        let py = cellY * cellSize + dy
                        let idx = py * side + px
                        if idx < pixels.count && pixels[idx] < inkThreshold {
                            inkCount += 1
                        }
                    }
                }
                histogram[cellY * gridSize + cellX] = Float(inkCount) / pixelsPerCell
            }
        }
        return histogram
    }
    
    /// Cosine similarity between two vectors. Returns 0-1 (1 = identical direction).
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        
        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }
        
        return max(0, min(1, dotProduct / denominator))
    }
    
    // MARK: - Indexing
    
    /// Generates and stores a pixel thumbnail for a given canvas page image.
    func index(image: UIImage, pageId: String) async {
        print("[DEBUG-IMS] index() called for pageId=\(pageId), image=\(image.size.width)x\(image.size.height)")
        
        guard let thumbnail = generateThumbnail(from: image) else {
            print("[DEBUG-IMS] ⚠️ FAILED to generate thumbnail for indexing")
            return
        }
        
        index[pageId] = thumbnail
        print("[DEBUG-IMS] ✅ Stored thumbnail for pageId=\(pageId) (\(thumbnail.count) bytes). Total index size: \(index.count)")
        saveToDisk()
    }
    
    /// Call when a note is deleted to remove all its page thumbnails.
    func delete(pageId: String) {
        let keysToRemove = index.keys.filter { $0.hasPrefix(pageId) }
        for key in keysToRemove {
            index.removeValue(forKey: key)
        }
        saveToDisk()
    }
    
    /// Clears all page indices for a note (call before re-indexing all pages).
    func reset(pageId: String) {
        let keysToRemove = index.keys.filter { $0.hasPrefix(pageId) }
        print("[DEBUG-IMS] reset() for pageId prefix=\(pageId.prefix(8))… removing \(keysToRemove.count) key(s)")
        for key in keysToRemove {
            index.removeValue(forKey: key)
        }
    }
    
    // MARK: - Search
    
    struct SearchResult {
        let pageId: String
        let distance: Float
    }
    
    /// Compares a query image against all stored thumbnails and returns ranked results.
    /// Lower distance means higher similarity. Distance is normalized 0-1.
    func search(queryImage: UIImage) async throws -> [SearchResult] {
        print("[DEBUG-SEARCH] search() called. Query image: \(queryImage.size.width)x\(queryImage.size.height)")
        print("[DEBUG-SEARCH] Current index has \(index.count) stored page(s)")
        for key in index.keys {
            print("[DEBUG-SEARCH]   - stored: \(key)")
        }
        
        guard let queryThumb = generateThumbnail(from: queryImage) else {
            print("[DEBUG-SEARCH] ⚠️ FAILED to generate thumbnail from query")
            throw NSError(domain: "ImageMatchingError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid query image"])
        }
        
        print("[DEBUG-SEARCH] ✅ Query thumbnail generated")
        
        var results: [SearchResult] = []
        
        for (pageId, storedThumb) in index {
            let distance = comparePixels(queryThumb, storedThumb)
            print("[DEBUG-SEARCH] Distance to \(pageId): \(distance)")
            results.append(SearchResult(pageId: pageId, distance: distance))
        }
        
        print("[DEBUG-SEARCH] Total results: \(results.count)")
        return results.sorted { $0.distance < $1.distance }
    }
}
