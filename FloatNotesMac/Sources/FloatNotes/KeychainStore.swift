import Foundation
import Security

enum KeychainStore {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "local.floatnotes.api",
        kSecAttrAccount as String: "openai"
    ]

    static func load(allowInteraction: Bool = false) throws -> String {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        if !allowInteraction { request[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail }
        var value: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &value)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = value as? Data else {
            throw AppError.message("Saved API key is locked or not authorized for this build (Keychain \(status)). Open Settings and click Unlock saved key, or paste your API key again.")
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func save(_ key: String) throws {
        let attributes = [kSecValueData as String: Data(key.utf8)]
        let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if update == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = Data(key.utf8)
            let status = SecItemAdd(item as CFDictionary, nil)
            guard status == errSecSuccess else { throw AppError.message("Keychain save failed (\(status)).") }
        } else if update != errSecSuccess { throw AppError.message("Keychain update failed (\(update)).") }
    }

    static func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError.message("Keychain delete failed (\(status)).")
        }
    }
}
