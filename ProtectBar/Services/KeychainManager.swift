import Foundation
import CryptoKit

/// Manages secure credential storage using encrypted file
/// (Avoids Keychain permission prompts for unsigned apps)
enum KeychainManager {

    enum KeychainError: Error, LocalizedError {
        case encodingError
        case decodingError
        case fileError

        var errorDescription: String? {
            switch self {
            case .encodingError: return "Failed to encode credentials"
            case .decodingError: return "Failed to decode credentials"
            case .fileError: return "Failed to access credentials file"
            }
        }
    }
    
    // MARK: - File Path
    
    private static var credentialsURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("ProtectBar", isDirectory: true)
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        
        return appFolder.appendingPathComponent(".credentials")
    }
    
    // MARK: - Encryption Key (device-specific)
    
    private static var encryptionKey: SymmetricKey {
        // Use hardware UUID as base for key derivation
        let hardwareUUID = getHardwareUUID() ?? "ProtectBarDefaultKey"
        let keyData = SHA256.hash(data: Data(hardwareUUID.utf8))
        return SymmetricKey(data: keyData)
    }
    
    private static func getHardwareUUID() -> String? {
        let platformExpert = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(platformExpert) }
        
        guard platformExpert != 0,
              let uuid = IORegistryEntryCreateCFProperty(platformExpert, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String else {
            return nil
        }
        return uuid
    }
    
    // MARK: - Storage Model
    
    private struct StoredCredentials: Codable {
        var username: String?
        var password: String?
    }
    
    // MARK: - Read/Write
    
    private static func loadCredentialsFile() -> StoredCredentials {
        guard let encryptedData = try? Data(contentsOf: credentialsURL),
              let sealedBox = try? ChaChaPoly.SealedBox(combined: encryptedData),
              let decryptedData = try? ChaChaPoly.open(sealedBox, using: encryptionKey),
              let credentials = try? JSONDecoder().decode(StoredCredentials.self, from: decryptedData) else {
            return StoredCredentials()
        }
        return credentials
    }
    
    private static func saveCredentialsFile(_ credentials: StoredCredentials) throws {
        guard let data = try? JSONEncoder().encode(credentials),
              let sealedBox = try? ChaChaPoly.seal(data, using: encryptionKey) else {
            throw KeychainError.encodingError
        }
        try sealedBox.combined.write(to: credentialsURL)
    }

    // MARK: - Convenience

    static func saveCredentials(username: String, password: String) throws {
        var credentials = StoredCredentials()
        credentials.username = username
        credentials.password = password
        try saveCredentialsFile(credentials)
    }

    static func loadCredentials() -> (username: String, password: String)? {
        let credentials = loadCredentialsFile()
        guard let username = credentials.username,
              let password = credentials.password else {
            return nil
        }
        return (username, password)
    }

    static func deleteCredentials() {
        try? FileManager.default.removeItem(at: credentialsURL)
    }
}
