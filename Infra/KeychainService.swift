import Foundation
import Security

enum KeychainError: Error {
    case itemNotFound
    case duplicateItem
    case invalidStatus(OSStatus)
    case encodingFailed
}

final class KeychainService: Sendable {
    static let shared = KeychainService()
    private let lock = NSLock()
    private init() {}

    func save(key: String, for provider: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let data = key.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        let service = "\(Constants.bundleID).apikey.\(provider)"

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "default",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

        if addStatus == errSecDuplicateItem {
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: "default"
            ]
            let updateAttributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.invalidStatus(updateStatus)
            }
        } else if addStatus != errSecSuccess {
            throw KeychainError.invalidStatus(addStatus)
        }
    }

    func load(for provider: String) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        let service = "\(Constants.bundleID).apikey.\(provider)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "default",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.invalidStatus(status)
        }

        guard let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.encodingFailed
        }

        return string
    }

    func delete(for provider: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let service = "\(Constants.bundleID).apikey.\(provider)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "default"
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.invalidStatus(status)
        }
    }

    func update(key: String, for provider: String) throws {
        // save() tries SecItemAdd first; on duplicate, uses SecItemUpdate.
        // No need for explicit delete — avoids non-atomic delete-then-save race.
        try save(key: key, for: provider)
    }
}
