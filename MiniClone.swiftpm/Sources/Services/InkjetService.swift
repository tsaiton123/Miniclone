import UIKit
import CoreImage
import CoreGraphics

class InkjetService {
    
    struct InkElement {
        var rect: CGRect
        var label: Int
    }
    
    // Main entry point
    static func process(image: UIImage) -> [(BitmapInkData, CGRect)] {
        guard let cgImage = image.cgImage else { return [] }
        
        // 1. Get raw pixel data
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let totalBytes = height * bytesPerRow
        
        var rawData = [UInt8](repeating: 0, count: totalBytes)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        
        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return [] }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // 2. Process Pixels (Background Removal Only - No Segmentation)
        // We now treat the entire captured area as a single stamp to preserve layout.
        
        var processedData = [UInt8](repeating: 0, count: totalBytes)
        
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                
                let r = rawData[offset]
                let g = rawData[offset + 1]
                let b = rawData[offset + 2]
                let a = rawData[offset + 3]
                
                // Background Removal Logic
                // If pixel is "White" (Background), make it transparent
                // Threshold: > 240 for R, G, and B
                if r > 240 && g > 240 && b > 240 {
                    processedData[offset] = 0     // R
                    processedData[offset + 1] = 0 // G
                    processedData[offset + 2] = 0 // B
                    processedData[offset + 3] = 0 // Alpha -> 0
                } else {
                    // Copy original pixel
                    processedData[offset] = r
                    processedData[offset + 1] = g
                    processedData[offset + 2] = b
                    processedData[offset + 3] = a
                }
            }
        }
        
        // 3. Create Result Image
        guard let provider = CGDataProvider(data: Data(processedData) as CFData),
              let processedCGImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else { return [] }
        
        let processedUIImage = UIImage(cgImage: processedCGImage)
        
        if let pngData = processedUIImage.pngData() {
            let base64 = pngData.base64EncodedString()
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            
            let data = BitmapInkData(
                src: base64,
                originalWidth: Double(width),
                originalHeight: Double(height)
            )
            
            // Return single element
            return [(data, rect)]
        }
        
        return []
    }
}
