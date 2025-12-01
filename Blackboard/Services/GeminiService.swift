import Foundation
import Combine
import GoogleGenerativeAI
import UIKit

class GeminiService: ObservableObject {
    private var model: GenerativeModel?
    private let apiKeyKey = "gemini_api_key"
    
    @Published var apiKey: String = "" {
        didSet {
            UserDefaults.standard.set(apiKey, forKey: apiKeyKey)
            configureModel()
        }
    }
    
    init() {
        self.apiKey = UserDefaults.standard.string(forKey: apiKeyKey) ?? ""
        configureModel()
    }
    
    private func configureModel() {
        guard !apiKey.isEmpty else {
            model = nil
            return
        }
        
        let config = GenerationConfig(
            temperature: 0.7,
            topP: 0.95,
            topK: 40,
            maxOutputTokens: 2048
        )
        
        model = GenerativeModel(
            name: "gemini-2.0-flash-exp",
            apiKey: apiKey,
            generationConfig: config,
            systemInstruction: ModelContent(role: "system", parts: [.text(systemPrompt)])
        )
    }
    
    private var systemPrompt: String {
        """
        You are an AI assistant that writes on a digital blackboard. Your responses will be rendered in beautiful handwriting.

        IMPORTANT: Be concise and minimal. Only provide exactly what the user asks for.

        When the user asks you to plot a mathematical function, respond with ONLY the JSON tool call - no extra text:

        ```json
        {
          "tool": "plot_function",
          "expression": "x^2",
          "xMin": -10,
          "xMax": 10
        }
        ```

        Do NOT add explanatory text before or after the JSON when plotting.

        Supported mathematical expressions:
        - Polynomials: x^2, x^3 - 3*x^2 + 2*x
        - Trigonometric: sin(x), cos(x), tan(x)
        - Exponential: exp(x), exp(-x^2/10)
        - Math functions: sqrt(x), abs(x), log(x)
        - Compound: sin(x) + cos(x), 2*sin(x) - cos(2*x)
        - Rational: 1/x, 1/(x^2 + 1)

        For other questions, be direct and concise - write as if teaching on a blackboard.
        """
    }
    
    func sendMessage(_ text: String, image: UIImage? = nil) async throws -> String {
        guard let model = model else {
            throw NSError(domain: "GeminiService", code: 1, userInfo: [NSLocalizedDescriptionKey: "API Key not configured"])
        }
        
        var parts: [ModelContent.Part] = [.text(text)]
        
        if let image = image, let data = image.jpegData(compressionQuality: 0.8) {
            parts.append(.jpeg(data))
        }
        
        let content = ModelContent(role: "user", parts: parts)
        let response = try await model.generateContent([content])
        return response.text ?? ""
    }
    
    func sendSelectionContext(_ context: String, image: UIImage? = nil, query: String = "Explain this") async throws -> String {
        let prompt = """
        Context from Blackboard Selection:
        \(context)
        
        User Question: \(query)
        """
        return try await sendMessage(prompt, image: image)
    }
    
    struct GraphCommand: Codable {
        let tool: String
        let expression: String
        let xMin: Double?
        let xMax: Double?
    }
    
    func parseResponse(_ response: String) -> (text: String, graph: GraphCommand?) {
        // Check for JSON block
        let pattern = "```(?:json)?\\s*\\n?([\\s\\S]*?)\\n?```"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return (response, nil)
        }
        
        let nsString = response as NSString
        let results = regex.matches(in: response, options: [], range: NSRange(location: 0, length: nsString.length))
        
        for result in results {
            if result.numberOfRanges > 1 {
                let jsonString = nsString.substring(with: result.range(at: 1))
                if let data = jsonString.data(using: .utf8),
                   let command = try? JSONDecoder().decode(GraphCommand.self, from: data),
                   command.tool == "plot_function" {
                    
                    // Remove the JSON block from the text
                    let cleanText = regex.stringByReplacingMatches(in: response, options: [], range: NSRange(location: 0, length: nsString.length), withTemplate: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    return (cleanText, command)
                }
            }
        }
        
        return (response, nil)
    }
}
