import Foundation
import JavaScriptCore

struct MathParser {
    private static let context: JSContext? = {
        let ctx = JSContext()
        return ctx
    }()
    
    private static let lock = NSLock()
    
    static func evaluate(_ expression: String, at x: Double) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        
        guard let context = context else { return nil }
        
        // Set variable x
        context.setObject(x, forKeyedSubscript: "x" as NSString)
        
        // Preprocess expression to use Math.func
        // We replace common functions with Math.func
        var jsExpr = expression.lowercased()
        
        // Replace ^ with ** (JS exponentiation)
        jsExpr = jsExpr.replacingOccurrences(of: "^", with: "**")
        
        // List of functions to prefix with Math.
        let functions = ["sin", "cos", "tan", "sqrt", "abs", "log", "exp", "asin", "acos", "atan", "pow", "max", "min", "floor", "ceil", "round"]
        
        for funcName in functions {
            // Replace "func(" with "Math.func("
            // We use a simple replacement. Note: this might replace "asin" as "aMath.sin" if we are not careful.
            // So we should check for word boundaries or just be careful with order.
            // "asin" should be replaced before "sin".
            
            // Actually, regex is better: \bfunc\(
            if let regex = try? NSRegularExpression(pattern: "\\b\(funcName)\\(", options: .caseInsensitive) {
                let range = NSRange(location: 0, length: jsExpr.utf16.count)
                jsExpr = regex.stringByReplacingMatches(in: jsExpr, options: [], range: range, withTemplate: "Math.\(funcName)(")
            }
        }
        
        // Constants
        jsExpr = jsExpr.replacingOccurrences(of: "\\bpi\\b", with: "Math.PI", options: .regularExpression)
        jsExpr = jsExpr.replacingOccurrences(of: "\\be\\b", with: "Math.E", options: .regularExpression)
        
        // Evaluate
        if let result = context.evaluateScript(jsExpr) {
            if result.isNumber {
                return result.toDouble()
            }
        }
        
        return nil
    }
}
