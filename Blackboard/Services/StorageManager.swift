import Foundation

class StorageManager {
    static let shared = StorageManager()
    private let fileManager = FileManager.default
    
    private init() {}
    
    private func getDocumentsDirectory() -> URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    private func getFileURL(for id: UUID) -> URL {
        getDocumentsDirectory().appendingPathComponent("\(id.uuidString).json")
    }
    
    func saveCanvas(id: UUID, data: CanvasData) throws {
        let url = getFileURL(for: id)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(data)
        try jsonData.write(to: url)
        print("Saved canvas to \(url.path)")
    }
    
    func loadCanvas(id: UUID) throws -> CanvasData {
        let url = getFileURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else {
            // Return empty canvas if file doesn't exist
            return CanvasData(elements: [])
        }
        
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CanvasData.self, from: data)
    }
    
    func deleteCanvas(id: UUID) {
        let url = getFileURL(for: id)
        try? fileManager.removeItem(at: url)
    }
}
