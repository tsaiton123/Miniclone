import Foundation
import Combine
import UIKit

class GeminiService: ObservableObject {
    // MARK: - Configuration
    
    /// The base URL for the Gemini API proxy server
    private let serverBaseURL = "https://gemini-proxy-147061267626.us-central1.run.app"
    
    // For local development, use:
    // private let serverBaseURL = "http://localhost:8080"
    
    private let session: URLSession
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Public Methods
    
    func sendMessage(_ text: String, image: UIImage? = nil) async throws -> String {
        let endpoint = "\(serverBaseURL)/v1/chat"
        
        var body: [String: Any] = [
            "message": text
        ]
        
        // Add image if provided
        if let image = image, let data = image.jpegData(compressionQuality: 0.8) {
            body["image_base64"] = data.base64EncodedString()
        }
        
        // Add device ID for potential rate limiting
        if let deviceID = UIDevice.current.identifierForVendor?.uuidString {
            body["device_id"] = deviceID
        }
        
        let response: ChatResponse = try await makeRequest(to: endpoint, body: body)
        
        if response.success {
            return response.response
        } else {
            throw GeminiError.serverError(response.error ?? "Unknown error")
        }
    }
    
    enum AIMode {
        case explain
        case solve
        case plot
        
        var stringValue: String {
            switch self {
            case .explain: return "explain"
            case .solve: return "solve"
            case .plot: return "plot"
            }
        }
    }
    
    func sendSelectionContext(_ context: String, image: UIImage? = nil, mode: AIMode) async throws -> String {
        let endpoint = "\(serverBaseURL)/v1/analyze"
        
        var body: [String: Any] = [
            "context": context,
            "mode": mode.stringValue
        ]
        
        // Add image if provided
        if let image = image, let data = image.jpegData(compressionQuality: 0.8) {
            body["image_base64"] = data.base64EncodedString()
        }
        
        // Add device ID for potential rate limiting
        if let deviceID = UIDevice.current.identifierForVendor?.uuidString {
            body["device_id"] = deviceID
        }
        
        let response: ChatResponse = try await makeRequest(to: endpoint, body: body)
        
        if response.success {
            return response.response
        } else {
            throw GeminiError.serverError(response.error ?? "Unknown error")
        }
    }
    
    // MARK: - Response Parsing
    
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
    
    // MARK: - Private Helpers
    
    private struct ChatResponse: Codable {
        let response: String
        let success: Bool
        let error: String?
    }
    
    private func makeRequest<T: Codable>(to endpoint: String, body: [String: Any]) async throws -> T {
        guard let url = URL(string: endpoint) else {
            throw GeminiError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw GeminiError.encodingError
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw GeminiError.httpError(statusCode: httpResponse.statusCode)
        }
        
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            throw GeminiError.decodingError
        }
    }
}

// MARK: - Error Types

enum GeminiError: LocalizedError {
    case invalidURL
    case encodingError
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError
    case serverError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .encodingError:
            return "Failed to encode request"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode):
            return "Server error (HTTP \(statusCode))"
        case .decodingError:
            return "Failed to decode response"
        case .serverError(let message):
            return message
        }
    }
}
