import Foundation

class StorageManager {
    static let shared = StorageManager()
    private let fileManager = FileManager.default
    private let cloudStorage = CloudStorageManager.shared
    
    private init() {
        // Attempt migration on initialization
        migrateToCloudIfNeeded()
    }
    
    // MARK: - Migration
    
    private var hasMigrated: Bool {
        get { UserDefaults.standard.bool(forKey: "hasAttemptedCloudMigration") }
        set { UserDefaults.standard.set(newValue, forKey: "hasAttemptedCloudMigration") }
    }
    
    private func migrateToCloudIfNeeded() {
        // Only attempt migration once
        guard !hasMigrated else { return }
        
        if cloudStorage.isCloudAvailable {
            cloudStorage.migrateLocalFilesToCloud()
            hasMigrated = true
        }
    }
    
    // MARK: - Canvas Storage (now uses CloudStorageManager)
    
    private func getFileURL(for id: UUID) -> URL {
        return cloudStorage.getFileURL(for: id)
    }
    
    func saveCanvas(id: UUID, data: CanvasData) throws {
        let url = getFileURL(for: id)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(data)
        try cloudStorage.saveData(jsonData, to: url)
    }
    
    func loadCanvas(id: UUID) throws -> CanvasData {
        let url = getFileURL(for: id)
        
        do {
            let data = try cloudStorage.loadData(from: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(CanvasData.self, from: data)
        } catch {
            // Check local fallback for non-migrated files or if cloud load fails
            let localURL = getLocalDocumentsDirectory().appendingPathComponent("\(id.uuidString).json")
            if fileManager.fileExists(atPath: localURL.path) {
                let data = try Data(contentsOf: localURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let canvas = try decoder.decode(CanvasData.self, from: data)
                
                // Migrate this file to cloud
                if cloudStorage.isCloudAvailable {
                    try? saveCanvas(id: id, data: canvas)
                    try? fileManager.removeItem(at: localURL)
                }
                
                return canvas
            }
            
            // Return empty canvas if file doesn't exist anywhere
            return CanvasData(elements: [])
        }
    }
    
    func deleteCanvas(id: UUID) {
        let url = getFileURL(for: id)
        try? cloudStorage.deleteFile(at: url)
        
        // Also delete local copy if exists
        let localURL = getLocalDocumentsDirectory().appendingPathComponent("\(id.uuidString).json")
        try? fileManager.removeItem(at: localURL)
    }
    
    // MARK: - Private Helpers
    
    private func getLocalDocumentsDirectory() -> URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    /// Deletes all canvas files from both cloud and local storage
    /// Used when deleting user account
    func deleteAllCanvases() {
        // Delete from cloud storage
        cloudStorage.deleteAllCanvasFiles()
        
        // Also clean up any remaining local files
        let documentsDirectory = getLocalDocumentsDirectory()
        do {
            let files = try fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "json" {
                try? fileManager.removeItem(at: file)
            }
        } catch {
            // Silently handle errors
        }
    }
    
    /// Deletes the SwiftData store (SQLite database) containing NoteItem objects
    /// This removes all notes and folders
    func deleteSwiftDataStore() {
        // SwiftData stores its data in the Application Support directory by default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        
        // SwiftData uses default.store as the database name
        let storeURL = appSupportURL.appendingPathComponent("default.store")
        
        // SwiftData/SQLite creates multiple files: .store, .store-shm, .store-wal
        let extensions = ["", "-shm", "-wal"]
        
        for ext in extensions {
            let fileURL = URL(fileURLWithPath: storeURL.path + ext)
            if fileManager.fileExists(atPath: fileURL.path) {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }
    
    // MARK: - Sync Status
    
    /// Returns true if iCloud sync is available
    var isCloudSyncEnabled: Bool {
        return cloudStorage.isCloudAvailable
    }
}
