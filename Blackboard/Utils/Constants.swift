import Foundation
import CoreGraphics

struct CanvasConstants {
    /// A4 paper size in points at 72 PPI (standard for iOS/macOS)
    /// Width: 210mm = 595.27 points
    /// Height: 297mm = 841.89 points
    static let a4Width: CGFloat = 595.27
    static let a4Height: CGFloat = 841.89
    
    static let paperColor = "#FFFFFF"
    static let workspaceColor = "#12151d" // Slightly darker than the paper for contrast
}
