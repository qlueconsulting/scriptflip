import Foundation
import Security

/// Persistent, anonymous device-bound identity stored securely in iOS Keychain.
/// - Survives app deletion and reinstallation (preventing uninstall/reinstall quota cheat).
/// - Completely anonymous: zero PII (no Apple ID, no name, no email, no IP address).
/// - Cryptographically random UUID.
public final class KeychainService: @unchecked Sendable {
    public static let shared = KeychainService()
    
    private let service = "com.scriptflip.app"
    private let account = "anonymous_device_user_id"
    private let lock = NSLock()
    private var cachedId: String? = nil
    
    private init() {}
    
    /// Stable, persistent anonymous UUID for quota enforcement and audit logging.
    public var anonymousUserId: String {
        lock.lock()
        defer { lock.unlock() }
        
        if let cached = cachedId {
            return cached
        }
        
        if let existing = readFromKeychain() {
            self.cachedId = existing
            return existing
        }
        
        // Generate new cryptographically random UUID
        let newId = UUID().uuidString.lowercased()
        saveToKeychain(value: newId)
        self.cachedId = newId
        return newId
    }
    
    // MARK: - Keychain CRUD
    
    private func readFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8),
              !string.isEmpty else {
            return nil
        }
        
        return string
    }
    
    private func saveToKeychain(value: String) {
        guard let data = value.data(using: .utf8) else { return }
        
        // Try deleting any existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // Add new item with kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            print("[KeychainService] Warning: Failed to save anonymous user ID to Keychain (status: \(status))")
        }
    }
}
