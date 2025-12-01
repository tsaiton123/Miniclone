import SwiftUI

struct GraphShape: Shape {
    let data: GraphData
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let width = rect.width
        let height = rect.height
        
        let xRange = data.xMax - data.xMin
        // Default yRange if not specified
        let yMin = data.yMin ?? -10
        let yMax = data.yMax ?? 10
        let yRange = yMax - yMin
        
        // Scale factors
        let xScale = width / CGFloat(xRange)
        let yScale = height / CGFloat(yRange)
        
        // Origin in view coordinates
        let originX = -CGFloat(data.xMin) * xScale
        let originY = height - (-CGFloat(yMin) * yScale) // Invert Y
        
        // Draw axes
        path.move(to: CGPoint(x: 0, y: originY))
        path.addLine(to: CGPoint(x: width, y: originY))
        path.move(to: CGPoint(x: originX, y: 0))
        path.addLine(to: CGPoint(x: originX, y: height))
        
        // Plot function
        // Step size: 1 pixel
        let step = 1.0
        var firstPoint = true
        
        for pixelX in stride(from: 0.0, to: width, by: step) {
            // Convert pixelX to graphX
            let graphX = data.xMin + Double(pixelX / width) * xRange
            
            // Evaluate
            if let graphY = MathParser.evaluate(data.expression, at: graphX) {
                // Convert graphY to pixelY
                // Note: Canvas Y is down, Graph Y is up
                let pixelY = height - (CGFloat(graphY - yMin) * yScale)
                
                // Clip values to avoid drawing way off screen
                if pixelY >= -height && pixelY <= height * 2 {
                    if firstPoint {
                        path.move(to: CGPoint(x: pixelX, y: pixelY))
                        firstPoint = false
                    } else {
                        path.addLine(to: CGPoint(x: pixelX, y: pixelY))
                    }
                } else {
                    firstPoint = true // Break line if out of bounds (asymptotes etc)
                }
            } else {
                firstPoint = true
            }
        }
        
        return path
    }
}
