import Foundation
import UIKit
import Vision
import CoreImage

enum ImagePreprocessorError: Error {
    case detectionFailed
    case invalidImage
    case cgImageCreationFailed
    case pixelBufferCreationFailed
}

class ImagePreprocessor {
    
    /// Target image size for MobileCLIP-S1 (256×256, not the standard CLIP 224×224)
    static let targetSize = CGSize(width: 256, height: 256)
    
    private let context = CIContext(options: nil)

    /// Processes an input image to extract regions containing handwriting/text
    /// and formats them into 224x224 CVPixelBuffers suitable for MobileCLIP inference.
    ///
    /// Falls back to tiling the entire page when Vision detects no text regions,
    /// so every note gets at least one embedding regardless of content type.
    ///
    /// - Parameter image: The source `UIImage` to process.
    /// - Returns: An array of `CVPixelBuffer` containing the extracted and resized regions.
    func processAnnotations(from image: UIImage) async throws -> [CVPixelBuffer] {
        guard let cgImage = image.cgImage else {
            throw ImagePreprocessorError.invalidImage
        }
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        return try await withCheckedThrowingContinuation { continuation in
            let textRequest = VNDetectTextRectanglesRequest { [weak self] request, error in
                guard let self = self else { return }
                
                if let error = error {
                    // Vision failed outright — fall back to full page
                    do {
                        let buffers = try self.tileFullPage(cgImage: cgImage)
                        continuation.resume(returning: buffers)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                
                let observations = request.results as? [VNTextObservation] ?? []
                
                do {
                    if observations.isEmpty {
                        // No text detected — tile the full page so we still store embeddings
                        let buffers = try self.tileFullPage(cgImage: cgImage)
                        continuation.resume(returning: buffers)
                    } else {
                        let buffers = try self.extractAndProcessRegions(from: cgImage, observations: observations)
                        // If extraction somehow produced nothing, fall back too
                        if buffers.isEmpty {
                            continuation.resume(returning: try self.tileFullPage(cgImage: cgImage))
                        } else {
                            continuation.resume(returning: buffers)
                        }
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            
            textRequest.reportCharacterBoxes = false
            
            do {
                try requestHandler.perform([textRequest])
            } catch {
                // If Vision can't even start, fall back to full-page tiling
                do {
                    continuation.resume(returning: try self.tileFullPage(cgImage: cgImage))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Tiles the full image into up to 4 non-overlapping quadrant crops, each resized to 224×224.
    /// Used as a fallback when Vision detects no text regions.
    private func tileFullPage(cgImage: CGImage) throws -> [CVPixelBuffer] {
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        
        // Use up to 4 quadrant tiles: TL, TR, BL, BR
        let hw = w / 2, hh = h / 2
        let rects: [CGRect] = [
            CGRect(x: 0,  y: 0,  width: hw, height: hh),  // top-left
            CGRect(x: hw, y: 0,  width: hw, height: hh),  // top-right
            CGRect(x: 0,  y: hh, width: hw, height: hh),  // bottom-left
            CGRect(x: hw, y: hh, width: hw, height: hh),  // bottom-right
        ]
        
        return try rects.compactMap { rect -> CVPixelBuffer? in
            guard let cropped = cgImage.cropping(to: rect) else { return nil }
            let resized = try resizeAndSquare(image: cropped, targetSize: ImagePreprocessor.targetSize)
            return try convertToPixelBuffer(cgImage: resized)
        }
    }


    private func extractAndProcessRegions(from cgImage: CGImage, observations: [VNTextObservation]) throws -> [CVPixelBuffer] {
        var pixelBuffers: [CVPixelBuffer] = []
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        
        // MobileCLIP needs inputs to be somewhat cohesive. We can either:
        // A. Crop exactly to the text bounding box and resize to 224x224.
        // B. Define a fixed aspect ratio window and crop.
        // For simplicity and to avoid excessive distortion, we extract the bounding box of the text,
        // scale it to fit within a 224x224 square, and pad the rest.
        
        for observation in observations {
            let boundingBox = observation.boundingBox
            
            // Vision uses normalized coordinates (0.0 to 1.0) with origin at bottom-left.
            // Convert to image coordinates (CoreGraphics).
            let rect = VNImageRectForNormalizedRect(boundingBox, Int(imageSize.width), Int(imageSize.height))
            
            // CoreGraphics origin is top-left, but VNImageRectForNormalizedRect handles this if flipped
            // If not, we might need: bounds = CGRect(x: rect.minX, y: imageSize.height - rect.maxY, width: rect.width, height: rect.height)
            // Actually, `VNImageRectForNormalizedRect` assumes bottom-left origin for normalized,
            // returning a rect in the original image's coordinate space (which is usually top-left for CGImage).
            // Let's standardise the crop:
            let flippedRect = CGRect(
                x: rect.minX,
                y: imageSize.height - rect.maxY,
                width: rect.width,
                height: rect.height
            )
            
            guard let croppedCGImage = cgImage.cropping(to: flippedRect) else {
                continue
            }
            
            let resizedCGImage = try resizeAndSquare(image: croppedCGImage, targetSize: ImagePreprocessor.targetSize)
            let pixelBuffer = try convertToPixelBuffer(cgImage: resizedCGImage)
            pixelBuffers.append(pixelBuffer)
        }
        
        return pixelBuffers
    }
    
    private func resizeAndSquare(image: CGImage, targetSize: CGSize) throws -> CGImage {
        let ciImage = CIImage(cgImage: image)
        
        // Calculate the scale to fit the image within the target size while maintaining aspect ratio
        let scaleX = targetSize.width / CGFloat(image.width)
        let scaleY = targetSize.height / CGFloat(image.height)
        let scale = min(scaleX, scaleY)
        
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        // Create an empty square 224x224 white or transparent background
        // For text, a white background is typically better for normalization
        let background = CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: targetSize))
        
        // Center the scaled image
        let dx = (targetSize.width - scaledImage.extent.width) / 2
        let dy = (targetSize.height - scaledImage.extent.height) / 2
        
        let translatedImage = scaledImage.transformed(by: CGAffineTransform(translationX: dx, y: dy))
        
        let composedImage = translatedImage.composited(over: background)
        
        guard let finalCGImage = context.createCGImage(composedImage, from: composedImage.extent) else {
            throw ImagePreprocessorError.cgImageCreationFailed
        }
        
        return finalCGImage
    }
    
    private func convertToPixelBuffer(cgImage: CGImage) throws -> CVPixelBuffer {
        let options: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        
        var buffer: CVPixelBuffer?
        let width = cgImage.width
        let height = cgImage.height
        
        // kCVPixelFormatType_32BGRA or kCVPixelFormatType_32ARGB depending on what the MobileCLIP model expects.
        // Standard Core ML image models usually expect 32BGRA or 32ARGB, CoreMLTools handles conversion,
        // but 32BGRA is safest fallback for standard CV / CI contexts.
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         width,
                                         height,
                                         kCVPixelFormatType_32BGRA,
                                         options as CFDictionary,
                                         &buffer)
        
        guard status == kCVReturnSuccess, let pixelBuffer = buffer else {
            throw ImagePreprocessorError.pixelBufferCreationFailed
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let data = CVPixelBufferGetBaseAddress(pixelBuffer)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        
        guard let context = CGContext(data: data,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                      space: rgbColorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            throw ImagePreprocessorError.pixelBufferCreationFailed
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        
        return pixelBuffer
    }
}
