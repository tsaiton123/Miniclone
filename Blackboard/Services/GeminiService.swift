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
        config.timeoutIntervalForRequest = 180  // Thinking models need more time
        config.timeoutIntervalForResource = 300
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
    
    func sendBoardScan(images: [UIImage]) async throws -> String {
        let endpoint = "\(serverBaseURL)/v1/chat"
        
        // Combine multiple images into a single composite image
        let compositeImage = Self.createCompositeImage(from: images)
        
        let scanPrompt = """
        Convert these lecture board/slide photos into clean, organized study notes.
        
        Rules:
        - Extract ALL visible text, equations, and key points
        - Organize into clear notes with headers and bullet points
        - Use LaTeX for math: $x^2 + y^2 = r^2$
        - Be thorough - capture everything important
        - If multiple sections visible, use short headers to organize
        - For diagrams, describe what they show in [brackets]
        """
        
        var body: [String: Any] = [
            "message": scanPrompt
        ]
        
        // Add composite image
        if let data = compositeImage.jpegData(compressionQuality: 0.8) {
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
    
    /// Combine multiple images into a single vertical grid image
    private static func createCompositeImage(from images: [UIImage]) -> UIImage {
        guard images.count > 1 else { return images.first ?? UIImage() }
        
        let maxWidth: CGFloat = 1200
        var yOffset: CGFloat = 0
        let padding: CGFloat = 10
        
        // Calculate scaled sizes
        var scaledSizes: [CGSize] = []
        for image in images {
            let scale = min(maxWidth / image.size.width, 1.0)
            let scaledSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            scaledSizes.append(scaledSize)
            yOffset += scaledSize.height + padding
        }
        yOffset -= padding // Remove last padding
        
        let totalSize = CGSize(width: maxWidth, height: yOffset)
        
        let renderer = UIGraphicsImageRenderer(size: totalSize)
        return renderer.image { context in
            var currentY: CGFloat = 0
            for (index, image) in images.enumerated() {
                let size = scaledSizes[index]
                let x = (maxWidth - size.width) / 2
                image.draw(in: CGRect(x: x, y: currentY, width: size.width, height: size.height))
                currentY += size.height + padding
            }
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
    
    // MARK: - Streaming Methods
    
    /// Stream a chat message response, calling onChunk with each text chunk as it arrives.
    /// Returns the full accumulated response text after streaming completes.
    func streamMessage(_ text: String, image: UIImage? = nil, onChunk: @escaping (String) -> Void) async throws -> String {
        let endpoint = "\(serverBaseURL)/v1/chat/stream"
        
        var body: [String: Any] = ["message": text]
        
        if let image = image, let data = image.jpegData(compressionQuality: 0.8) {
            body["image_base64"] = data.base64EncodedString()
        }
        if let deviceID = UIDevice.current.identifierForVendor?.uuidString {
            body["device_id"] = deviceID
        }
        
        return try await streamSSE(to: endpoint, body: body, onChunk: onChunk)
    }
    
    /// Stream an analyze/selection context response.
    func streamSelectionContext(_ context: String, image: UIImage? = nil, mode: AIMode, onChunk: @escaping (String) -> Void) async throws -> String {
        let endpoint = "\(serverBaseURL)/v1/analyze/stream"
        
        var body: [String: Any] = [
            "context": context,
            "mode": mode.stringValue
        ]
        
        if let image = image, let data = image.jpegData(compressionQuality: 0.8) {
            body["image_base64"] = data.base64EncodedString()
        }
        if let deviceID = UIDevice.current.identifierForVendor?.uuidString {
            body["device_id"] = deviceID
        }
        
        return try await streamSSE(to: endpoint, body: body, onChunk: onChunk)
    }
    
    /// Stream a board scan response.
    func streamBoardScan(images: [UIImage], onChunk: @escaping (String) -> Void) async throws -> String {
        let endpoint = "\(serverBaseURL)/v1/chat/stream"
        
        let compositeImage = Self.createCompositeImage(from: images)
        
        let scanPrompt = """
        Convert these lecture board/slide photos into clean, organized study notes.
        
        Rules:
        - Extract ALL visible text, equations, and key points
        - Organize into clear notes with headers and bullet points
        - Use LaTeX for math: $x^2 + y^2 = r^2$
        - Be thorough - capture everything important
        - If multiple sections visible, use short headers to organize
        - For diagrams, describe what they show in [brackets]
        """
        
        var body: [String: Any] = ["message": scanPrompt]
        
        if let data = compositeImage.jpegData(compressionQuality: 0.8) {
            body["image_base64"] = data.base64EncodedString()
        }
        if let deviceID = UIDevice.current.identifierForVendor?.uuidString {
            body["device_id"] = deviceID
        }
        
        return try await streamSSE(to: endpoint, body: body, onChunk: onChunk)
    }
    
    /// Parse SSE stream from server, calling onChunk for each text chunk.
    /// Returns the full accumulated response.
    /// Falls back to non-streaming endpoint if streaming returns 404 (not deployed yet).
    private func streamSSE(to endpoint: String, body: [String: Any], onChunk: @escaping (String) -> Void) async throws -> String {
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
        
        let (bytes, response) = try await session.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }
        
        // Fallback: if streaming endpoint doesn't exist (404), use non-streaming
        if httpResponse.statusCode == 404 {
            let fallbackEndpoint = endpoint.replacingOccurrences(of: "/stream", with: "")
            let fallbackResponse: ChatResponse = try await makeRequest(to: fallbackEndpoint, body: body)
            if fallbackResponse.success {
                await MainActor.run {
                    onChunk(fallbackResponse.response)
                }
                return fallbackResponse.response
            } else {
                throw GeminiError.serverError(fallbackResponse.error ?? "Unknown error")
            }
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw GeminiError.httpError(statusCode: httpResponse.statusCode)
        }
        
        var accumulated = ""
        
        for try await line in bytes.lines {
            // SSE format: "data: {json}" or "data: [DONE]"
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            
            if payload == "[DONE]" {
                break
            }
            
            // Parse JSON chunk
            if let data = payload.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let text = json["text"] as? String {
                    accumulated += text
                    await MainActor.run {
                        onChunk(text)
                    }
                } else if let error = json["error"] as? String {
                    throw GeminiError.serverError(error)
                }
            }
        }
        
        return accumulated
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
