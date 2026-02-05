import Foundation

/// CloudStorageManager handles iCloud Drive file storage for canvas data
/// Falls back to local Documents directory when iCloud is unavailable
class CloudStorageManager {
    static let shared = CloudStorageManager()
    private let fileManager = FileManager.default
    
    /// The iCloud container identifier - matches the one in Xcode Signing & Capabilities
    private let containerIdentifier = "iCloud.Tsai.Cognote"
    
    private init() {}
    
    // MARK: - iCloud Availability
    
    /// Check if iCloud is available for the current user
    var isCloudAvailable: Bool {
        return fileManager.ubiquityIdentityToken != nil
    }
    
    /// Get the iCloud container URL, or nil if unavailable
    private var cloudContainerURL: URL? {
        return fileManager.url(forUbiquityContainerIdentifier: nil)
    }
    
    /// Get the Documents directory within the iCloud container
    private var cloudDocumentsURL: URL? {
        guard let containerURL = cloudContainerURL else { return nil }
        let documentsURL = containerURL.appendingPathComponent("Documents")
        
        // Create the Documents directory if it doesn't exist
        if !fileManager.fileExists(atPath: documentsURL.path) {
            try? fileManager.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        }
        
        return documentsURL
    }
    
    /// Get the local Documents directory (fallback)
    private var localDocumentsURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    // MARK: - Storage Location
    
    /// Get the appropriate storage directory (iCloud if available, local otherwise)
    func getStorageDirectory() -> URL {
        if isCloudAvailable, let cloudDocs = cloudDocumentsURL {
            return cloudDocs
        } else {
            return localDocumentsURL
        }
    }
    
    /// Get the file URL for a canvas with the given ID
    func getFileURL(for id: UUID) -> URL {
        return getStorageDirectory().appendingPathComponent("\(id.uuidString).json")
    }
    
    // MARK: - File Operations with Coordination
    
    /// Save data to file with proper file coordination for iCloud
    func saveData(_ data: Data, to url: URL) throws {
        if isCloudAvailable {
            // Use file coordination for iCloud files
            var coordinationError: NSError?
            var saveError: Error?
            
            let coordinator = NSFileCoordinator()
            coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
                do {
                    try data.write(to: coordinatedURL, options: .atomic)
                } catch {
                    saveError = error
                }
            }
            
            if let error = coordinationError ?? saveError {
                throw error
            }
        } else {
            // Direct write for local storage
            try data.write(to: url, options: .atomic)
        }
    }
    
    /// Load data from file with proper file coordination
    func loadData(from url: URL) throws -> Data {
        if isCloudAvailable {
            var coordinationError: NSError?
            var loadError: Error?
            var result: Data?
            
            let coordinator = NSFileCoordinator()
            coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
                do {
                    result = try Data(contentsOf: coordinatedURL)
                } catch {
                    loadError = error
                }
            }
            
            if let error = coordinationError ?? loadError {
                throw error
            }
            
            return result ?? Data()
        } else {
            return try Data(contentsOf: url)
        }
    }
    
    /// Delete a file with proper coordination
    func deleteFile(at url: URL) throws {
        if isCloudAvailable {
            var coordinationError: NSError?
            var deleteError: Error?
            
            let coordinator = NSFileCoordinator()
            coordinator.coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { coordinatedURL in
                do {
                    try fileManager.removeItem(at: coordinatedURL)
                } catch {
                    deleteError = error
                }
            }
            
            if let error = coordinationError ?? deleteError {
                throw error
            }
        } else {
            try fileManager.removeItem(at: url)
        }
    }
    
    // MARK: - Migration
    
    /// Migrate existing local files to iCloud when becoming available
    func migrateLocalFilesToCloud() {
        guard isCloudAvailable, let cloudDocs = cloudDocumentsURL else { return }
        
        do {
            let localFiles = try fileManager.contentsOfDirectory(at: localDocumentsURL, includingPropertiesForKeys: nil)
            let jsonFiles = localFiles.filter { $0.pathExtension == "json" }
            
            for localFile in jsonFiles {
                let cloudDestination = cloudDocs.appendingPathComponent(localFile.lastPathComponent)
                
                // Only migrate if file doesn't exist in cloud
                if !fileManager.fileExists(atPath: cloudDestination.path) {
                    try fileManager.copyItem(at: localFile, to: cloudDestination)
                }
            }
        } catch {
            // Migration failed silently - files remain local
        }
    }
    
    /// Check if file exists at the given URL
    func fileExists(at url: URL) -> Bool {
        return fileManager.fileExists(atPath: url.path)
    }
    
    /// Get all canvas files in storage
    func getAllCanvasFiles() -> [URL] {
        let storageDir = getStorageDirectory()
        do {
            let files = try fileManager.contentsOfDirectory(at: storageDir, includingPropertiesForKeys: nil)
            return files.filter { $0.pathExtension == "json" }
        } catch {
            return []
        }
    }
    
    /// Delete all canvas files (for account deletion)
    func deleteAllCanvasFiles() {
        let files = getAllCanvasFiles()
        for file in files {
            try? deleteFile(at: file)
        }
    }
}
